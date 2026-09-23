import os
import uuid
import random
import logging
import resend

from flask import Blueprint, request, jsonify, make_response
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity, verify_jwt_in_request
from werkzeug.security import generate_password_hash, check_password_hash
from flask_cors import cross_origin
from config.db import get_db
from config.cache import cache
from config.rate_limit import (
    rate_limit,
    otp_attempt_limited,
    record_otp_failure,
    clear_otp_failures,
)
from utils import admin_required
import requests as http_req

auth_bp = Blueprint('auth', __name__)
logger = logging.getLogger(__name__)

# Initialize Resend
resend.api_key = os.getenv('RESEND_API_KEY')

import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# ─── Shared Email Sender (Resend + SMTP Fallback) ───────────────────────────
def _send_email(to_email: str, subject: str, body_text: str, body_html: str = None):
    """Send an email using Resend API or fallback to standard SMTP. Returns True on success."""
    sender_email = os.getenv('SMTP_USER', 'support@winningedgeinvestment.com')
    sender_name = os.getenv('SMTP_SENDER_NAME', 'CUBAG Support')

    # 1. Try Resend API
    if resend.api_key:
        try:
            params = {
                "from": f"{sender_name} <{sender_email}>",
                "to": [to_email],
                "subject": subject,
                "text": body_text,
            }
            if body_html:
                params["html"] = body_html

            resend.Emails.send(params)
            logger.info(f'[Resend] Email sent to {to_email} — {subject}')
            return True
        except Exception as e:
            logger.error(f'[Resend] Failed to send email: {e}. Falling back to SMTP if available.')

    # 2. Try Standard SMTP Fallback
    smtp_host = os.getenv('SMTP_HOST')
    if smtp_host:
        try:
            smtp_port = int(os.getenv('SMTP_PORT', '587'))
            smtp_pass = os.getenv('SMTP_PASS') or os.getenv('SMTP_PASSWORD')
            
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = f"{sender_name} <{sender_email}>"
            msg['To'] = to_email
            
            msg.attach(MIMEText(body_text, 'plain'))
            if body_html:
                msg.attach(MIMEText(body_html, 'html'))
                
            if smtp_port == 465 or os.getenv('SMTP_SECURE', '').lower() == 'true':
                server = smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=10)
            else:
                server = smtplib.SMTP(smtp_host, smtp_port, timeout=10)
                server.starttls()
            if smtp_pass:
                server.login(sender_email, smtp_pass)
            server.sendmail(sender_email, to_email, msg.as_string())
            server.quit()
                
            logger.info(f'[SMTP] Email sent to {to_email} — {subject}')
            return True
        except Exception as e:
            logger.error(f'[SMTP] Failed to send email to {to_email}: {e}')
            return False

    logger.error('[Email] No valid email configuration found or all methods failed.')
    return False


@auth_bp.route('/debug-smtp', methods=['GET'])
@admin_required
def debug_smtp():
    """Admin-only: check email configuration status. Does NOT send a live email."""
    sender_email = os.getenv('SMTP_USER', '')
    debug_info = {
        'resend_api_key_configured': bool(os.getenv('RESEND_API_KEY')),
        'smtp_user_configured': bool(sender_email),
        'supabase_configured': bool(os.getenv('SUPABASE_URL') and os.getenv('SUPABASE_SERVICE_KEY')),
        'firebase_configured': bool(os.getenv('FIREBASE_CREDENTIALS_JSON') or os.getenv('FIREBASE_SERVICE_ACCOUNT')),
        'whitsunpay_configured': bool(os.getenv('WHITSUNPAY_API_KEY') or os.getenv('x-api-key')),
        'whitsunpay_webhook_secret_set': bool(os.getenv('WHITSUNPAY_WEBHOOK_SECRET')),
        'whitsunpay_callback_url_set': bool(os.getenv('WHITSUNPAY_CALLBACK_URL') or os.getenv('x-callback-url')),
    }
    return jsonify(debug_info)

# ─── Supabase config ──────────────────────────────────────────────────────────
SUPABASE_URL  = os.getenv('SUPABASE_URL', '')
SUPABASE_KEY  = os.getenv('SUPABASE_SERVICE_KEY', '')
PHOTO_BUCKET  = os.getenv('SUPABASE_BUCKET', 'uploads')

def send_verification_email(to_email, token):
    subject   = 'Your CUBAG Verification Code'
    body_text = (
        f'Hello,\n\n'
        f'Your CUBAG email verification code is:\n\n'
        f'  {token}\n\n'
        f'Enter this 6-digit code in the app to complete your registration.\n'
        f'This code expires in 15 minutes.\n\n'
        f'If you did not request this, please ignore this email.\n\n'
        f'Thanks,\nCUBAG Secretariat'
    )
    body_html = (
        f'<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:32px;border:1px solid #e2e8f0;border-radius:12px;">'
        f'<h2 style="color:#FF5000;margin-bottom:8px;">CUBAG Email Verification</h2>'
        f'<p style="color:#475569;">Enter the code below in the app to verify your email address:</p>'
        f'<div style="font-size:36px;font-weight:900;letter-spacing:12px;text-align:center;'
        f'background:#f8fafc;border:2px solid #FF5000;border-radius:10px;padding:20px 0;margin:24px 0;color:#0f172a;">'
        f'{token}</div>'
        f'<p style="color:#94a3b8;font-size:12px;">This code expires in 15 minutes. If you did not register on CUBAG, ignore this email.</p>'
        f'</div>'
    )
    return _send_email(to_email, subject, body_text, body_html)

@auth_bp.route('/send-otp', methods=['POST'])
@rate_limit('send_otp', max_requests=5, window_seconds=300)
def send_otp():
    data  = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()

    if not email:
        return jsonify({'message': 'Email is required'}), 400

    # B-01 fix: proper regex email validation
    import re
    if not re.match(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$', email):
        return jsonify({'message': 'Invalid email format'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Check if email is already registered
            cursor.execute("SELECT id FROM members WHERE LOWER(email) = %s", (email,))
            if cursor.fetchone():
                return jsonify({'message': 'Email already registered'}), 409

            import secrets
            token = str(secrets.randbelow(900000) + 100000)  # cryptographically secure 6-digit OTP

            # Upsert — include 'type' column required by otp_codes schema
            cursor.execute("""
                INSERT INTO otp_codes (email, code, type)
                VALUES (%s, %s, 'email_verification')
                ON CONFLICT (email, type) DO UPDATE
                  SET code = EXCLUDED.code,
                      created_at = CURRENT_TIMESTAMP
            """, (email, token))
            conn.commit()

        # Send email synchronously (threads are unreliable under eventlet/gevent)
        if not send_verification_email(email, token):
            return jsonify({'message': 'Failed to send verification email. Please check your SMTP/Resend configuration, or ensure your SMTP_USER is verified.'}), 500

        clear_otp_failures('email', email)
        return jsonify({'message': 'OTP sent to email.'}), 200

    except Exception as e:
        logger.error(f'[send-otp] Error: {e}')
        conn.rollback()
        return jsonify({'message': 'Failed to generate OTP. Please try again.'}), 500
    finally:
        conn.close()

@auth_bp.route('/verify-email', methods=['POST'])
@rate_limit('verify_otp', max_requests=10, window_seconds=300)
def verify_email():
    data = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()
    token = (data.get('token') or data.get('otp') or data.get('code') or '').strip()
    if not email or not token:
        return jsonify({'message': 'Email and Token/OTP are required'}), 400

    if otp_attempt_limited('email', email):
        return jsonify({'message': 'Too many incorrect codes. Please request a new one.'}), 429

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT * FROM otp_codes
                WHERE LOWER(email) = LOWER(%s) AND code = %s
                  AND type = 'email_verification'
                  AND created_at > NOW() - INTERVAL '15 minutes'
            """, (email, token))
            if not cursor.fetchone():
                record_otp_failure('email', email)
                return jsonify({'message': 'Invalid or expired verification code'}), 400

            clear_otp_failures('email', email)
            cursor.execute("DELETE FROM otp_codes WHERE LOWER(email) = LOWER(%s)", (email,))
            cursor.execute(
                "INSERT INTO otp_codes (email, code, type) VALUES (%s, %s, 'email_verified')",
                (email, token)
            )
            conn.commit()
            return jsonify({'message': 'Email verified successfully.'}), 200
    finally:
        conn.close()

# BUG-F31 fix: alias used by otp_verification_page.dart
@auth_bp.route('/verify-otp', methods=['POST'])
def verify_otp_alias():
    """Alias for /verify-email — Flutter OTP page calls this endpoint."""
    return verify_email()

# BUG-F32 fix: resend-otp route (skips 'already registered' guard)
@auth_bp.route('/resend-otp', methods=['POST'])
@rate_limit('resend_otp', max_requests=5, window_seconds=300)
def resend_otp():
    data  = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()
    if not email:
        return jsonify({'message': 'Email is required'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            import secrets
            token = str(secrets.randbelow(900000) + 100000)
            cursor.execute("""
                INSERT INTO otp_codes (email, code, type)
                VALUES (%s, %s, 'email_verification')
                ON CONFLICT (email, type) DO UPDATE
                  SET code = EXCLUDED.code,
                      created_at = CURRENT_TIMESTAMP
            """, (email, token))
            conn.commit()
        # Send email synchronously (threads are unreliable under eventlet/gevent)
        if not send_verification_email(email, token):
            return jsonify({'message': 'Failed to send verification email. Please check your SMTP/Resend configuration, or ensure your SMTP_USER is verified.'}), 500

        clear_otp_failures('email', email)
        return jsonify({'message': 'New OTP sent to email.'}), 200
    except Exception as e:
        conn.rollback()
        logger.error(f'[resend-otp] {e}')
        return jsonify({'message': 'Failed to resend OTP. Please try again.'}), 500
    finally:
        conn.close()

@auth_bp.route('/register', methods=['POST'])
@rate_limit('register', max_requests=8, window_seconds=600)
def register():
    data = request.get_json() or {}
    # licenseNumber and agencyCode are now OPTIONAL
    required = ['name', 'email', 'phone', 'company', 'location', 'digitalAddress', 'tin', 'memberType', 'portOfOperation', 'password']
    for field in required:
        if not data.get(field):
            return jsonify({'message': f'{field} is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            email = (data.get('email') or '').strip().lower()
            otp = (data.get('otp') or data.get('email_otp') or data.get('token') or '').strip()
            if not otp:
                return jsonify({'message': 'Please verify your email with the OTP before registering.'}), 400

            cursor.execute("""
                SELECT id FROM otp_codes
                WHERE LOWER(email) = LOWER(%s) AND code = %s
                  AND type = 'email_verified'
                  AND created_at > NOW() - INTERVAL '30 minutes'
            """, (email, otp))
            if not cursor.fetchone():
                return jsonify({'message': 'Email is not verified or the verification code has expired. Please request a new code.'}), 400

            cursor.execute("SELECT id FROM members WHERE LOWER(email) = LOWER(%s)", (email,))
            if cursor.fetchone():
                return jsonify({'message': 'Email already registered'}), 409

            # BUG-M02: enforce minimum password length server-side
            password = data.get('password', '')
            if len(password) < 8:
                return jsonify({'message': 'Password must be at least 8 characters'}), 400

            pw_hash = generate_password_hash(password, method='pbkdf2:sha256')
            is_corp = (data.get('memberType') or '').strip().lower() == 'corporate'
            member_scale = (data.get('memberScale') or data.get('companyScale') or 'sme') if is_corp else None
            fee_category = (data.get('feeCategory') or data.get('fee_category') or 'cf_only') if is_corp else None
            consolidation_scope = ('with_consolidation' if fee_category in ('consolidation', 'cf_consolidation') else 'without_consolidation') if is_corp else None
            tin = (data.get('tin') or '').strip().upper()[:11]
            cursor.execute("""
                INSERT INTO members (name, email, phone, company, license_number, agency_code,
                                     location, digital_address, tin,
                                     port_of_operation, member_type, member_scale, fee_category, consolidation_scope,
                                     password_hash, email_verified, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, TRUE, 'pending')
                RETURNING id
            """, (
                data['name'], email, data['phone'], data['company'],
                data.get('licenseNumber'), data.get('agencyCode'),
                data.get('location'), data.get('digitalAddress'), tin,
                data.get('portOfOperation'), data['memberType'], member_scale, fee_category, consolidation_scope, pw_hash
            ))
            new_id = cursor.fetchone()['id']
            cursor.execute("DELETE FROM otp_codes WHERE LOWER(email) = LOWER(%s)", (email,))
            conn.commit()

            from datetime import timedelta
            token = create_access_token(
                identity=str(new_id),
                additional_claims={'role': 'member'},
                expires_delta=timedelta(hours=48),
            )

            return jsonify({
                'message': 'Registration successful. Welcome to CUBAG!',
                'token': token,
                'user': {
                    'id': new_id,
                    'name': data['name'],
                    'email': email,
                    'phone': data['phone'],
                    'company': data['company'],
                    'memberType': data['memberType'],
                    'licenseNumber': 'PENDING',
                    'portOfOperation': data.get('portOfOperation'),
                    'status': 'pending',
                    'role': 'member',
                    'memberScale': member_scale,
                    'feeCategory': fee_category,
                    'permissions': [],
                    'profile_photo': None,
                    'compliance_score': 100,
                    'star_rating': 5.0,
                    'manual_review_score': 10,
                    'breakdown': {}
                }
            }), 201
    except Exception as e:
        conn.rollback()  # BUG-B04 fix
        logger.error(f'[register] {e}')  # BUG-B03 fix
        return jsonify({'message': 'Registration failed. Please try again.'}), 500
    finally:
        conn.close()


@auth_bp.route('/login', methods=['POST'])
@rate_limit('login', max_requests=12, window_seconds=300)
def login():
    data = request.get_json(silent=True) or {}
    identifier = (data.get('email') or data.get('identifier') or data.get('memberId') or '').strip()
    password = data.get('password')

    if not identifier or not password:
        return jsonify({'message': 'Email or phone number and password are required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # First, check by email address (case-insensitive)
            cursor.execute("SELECT * FROM members WHERE LOWER(email) = LOWER(%s)", (identifier,))
            member = cursor.fetchone()

            # If not found by email, check phone number if it contains at least 7 digits
            if not member:
                import re
                digits_only = re.sub(r'\D', '', identifier)
                if len(digits_only) >= 7:
                    cursor.execute(
                        "SELECT * FROM members WHERE regexp_replace(phone, '[^0-9]', '', 'g') = %s",
                        (digits_only,)
                    )
                    member = cursor.fetchone()

            # If still not found, check agency_code or license_number
            if not member:
                cursor.execute(
                    "SELECT * FROM members WHERE LOWER(agency_code) = LOWER(%s) OR LOWER(license_number) = LOWER(%s)",
                    (identifier, identifier)
                )
                member = cursor.fetchone()

            if not member:
                return jsonify({'message': 'Invalid credentials'}), 401

            # Check password (both exact and stripped of mobile/autofill accidental whitespace)
            raw_pw = str(password or '')
            stripped_pw = raw_pw.strip()
            
            def _verify_password(hash_val, candidate):
                try:
                    return check_password_hash(hash_val, candidate)
                except Exception as ex:
                    logger.warning(f'[auth] Password verification fallback error: {ex}')
                    return False

            if not (_verify_password(member['password_hash'], raw_pw) or _verify_password(member['password_hash'], stripped_pw)):
                return jsonify({'message': 'Invalid credentials'}), 401

            # ── Block suspended / inactive accounts ───────────────────────────
            member_status = str(member.get('status') or 'active').lower()
            if member_status == 'suspended':
                return jsonify({
                    'message': 'Your account has been suspended. Please contact the CUBAG Secretariat for assistance.'
                }), 403
            if member_status == 'inactive':
                return jsonify({
                    'message': 'Your account is inactive. Please contact the CUBAG Secretariat to reactivate.'
                }), 403

            # BUG-B05 fix: default False so missing column never silently bypasses verification
            if not member.get('email_verified', False):
                return jsonify({'message': 'Please check your email to verify your account before logging in.'}), 403

            from utils import calculate_and_update_member_rating
            comp_score = member.get('compliance_score')
            if comp_score is None: comp_score = 100
            s_rating = member.get('star_rating')
            if s_rating is None: s_rating = 5.0
            m_score = member.get('manual_review_score')
            if m_score is None: m_score = 10

            # Trigger asynchronous background rating update so login returns instantly
            member_id_val = member['id']
            def _async_rating_update(m_id):
                c = None
                try:
                    c = get_db()
                    with c.cursor() as cur:
                        calculate_and_update_member_rating(m_id, cur)
                except Exception as ex:
                    logger.debug(f"[auth] Async rating update error: {ex}")
                finally:
                    if c:
                        try:
                            c.close()
                        except Exception:
                            pass

            import threading
            threading.Thread(target=_async_rating_update, args=(member_id_val,), daemon=True).start()

            # Generate JWT with identity and role. Admins get a shorter token.
            role = member.get('role', 'member')
            from datetime import timedelta
            token_ttl = timedelta(hours=8) if role in ('admin', 'sub_admin', 'super_admin') else timedelta(hours=48)
            token = create_access_token(
                identity=str(member['id']),
                additional_claims={'role': role},
                expires_delta=token_ttl,
            )

            # Expiry date serialization
            expiry = str(member['license_expiry_date']) if member.get('license_expiry_date') else None

            # Audit log for admin & sub_admin logins
            if role in ('admin', 'sub_admin', 'super_admin'):
                from utils import log_admin_action
                
                # Fetch actual IP, falling back to remote_addr if no proxy header exists
                forwarded_for = request.headers.get('X-Forwarded-For')
                actual_ip = forwarded_for.split(',')[0].strip() if forwarded_for else request.remote_addr
                
                log_admin_action(
                    member['id'],
                    f'{role.replace("_", " ").title()} Login',
                    role, member['id'], member['name'],
                    f'IP: {actual_ip}'
                )

            sub_perms = []
            if role == 'sub_admin':
                cursor.execute(
                    "SELECT permission_key FROM sub_admin_permissions WHERE sub_admin_id = %s AND granted = true",
                    (member['id'],)
                )
                sub_perms = [r['permission_key'] for r in cursor.fetchall()]

            user_status = member.get('status') or 'pending'
            is_admin_role = role in ('admin', 'sub_admin', 'super_admin')
            user_license = None if is_admin_role else member.get('license_number')
            has_paid_fee = False
            is_pkg_paid = False
            is_good_standing = False
            mem_no = None
            is_ren_paid = False

            if role == 'member':
                # Check for any registration/application fee payment
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%registration%%'
                          OR LOWER(description) LIKE '%%application%%'
                          OR LOWER(description) LIKE '%%reg form%%'
                      )
                """, (member['id'],))
                reg_row = cursor.fetchone()
                has_any_reg_payment = (reg_row['cnt'] > 0) if reg_row else False

                # Check specifically for package fee payment
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%new member%%'
                          OR LOWER(description) LIKE '%%entrance%%'
                          OR LOWER(description) LIKE '%%package%%'
                          OR LOWER(description) LIKE '%%clearing & forwarding only%%'
                          OR LOWER(description) LIKE '%%consolidation only%%'
                          OR LOWER(description) LIKE '%%licentiate membership%%'
                          OR LOWER(description) LIKE '%%associate membership%%'
                      )
                      AND LOWER(description) NOT LIKE '%%registration%%'
                      AND LOWER(description) NOT LIKE '%%application%%'
                      AND LOWER(description) NOT LIKE '%%renewal%%'
                """, (member['id'],))
                pkg_row = cursor.fetchone()
                has_pkg_payment = (pkg_row['cnt'] > 0) if pkg_row else False

                # Check specifically for annual renewal payment
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%renewal%%'
                          OR LOWER(description) LIKE '%%annual renewal%%'
                      )
                """, (member['id'],))
                ren_row = cursor.fetchone()
                has_renewal_payment = (ren_row['cnt'] > 0) if ren_row else False

                is_pkg_paid = (member.get('package_fee_paid') is True) or has_pkg_payment
                has_paid_fee = has_any_reg_payment or (member.get('registration_fee_paid') is True) or (member.get('application_fee_paid') is True)
                is_good_standing = is_pkg_paid
                is_ren_paid = has_renewal_payment

                raw_status = str(user_status).lower().strip()
                is_docs_approved = raw_status in ('active', 'approved')

                if is_docs_approved and has_paid_fee:
                    user_status = 'active'
                else:
                    user_status = raw_status

                if not is_pkg_paid:
                    mem_no = 'PENDING SETTLEMENT'
                    user_license = 'PENDING SETTLEMENT'
                else:
                    mem_no = member.get('membership_number') or member.get('license_number') or f"CUBAG-{member['id']:04d}"
                    if 'pending' in str(mem_no).lower():
                        mem_no = f"CUBAG-{member['id']:04d}"
                    user_license = mem_no
            elif is_admin_role:
                has_paid_fee = True
                is_pkg_paid = True
                is_good_standing = True
                user_status = 'active'

            return jsonify({
                'token': token,
                'permissions': sub_perms,
                'user': {
                    'id': member['id'],
                    'name': member['name'],
                    'email': member['email'],
                    'company': member['company'],
                    'memberType': member['member_type'],
                    'member_type': member['member_type'],
                    'fee_category': member.get('fee_category'),
                    'member_scale': member.get('member_scale'),
                    'licenseNumber': user_license,
                    'license_number': user_license,
                    'membershipNumber': mem_no,
                    'membership_number': mem_no,
                    'licenseExpiryDate': None if is_admin_role else expiry,
                    'license_expiry_date': None if is_admin_role else expiry,
                    'portOfOperation': member['port_of_operation'],
                    'status': user_status,
                    'registration_fee_paid': has_paid_fee,
                    'application_fee_paid': has_paid_fee,
                    'package_fee_paid': is_pkg_paid,
                    'good_standing': is_good_standing,
                    'is_good_standing': is_good_standing,
                    'is_renewal_paid': is_ren_paid,
                    'renewal_paid': is_ren_paid,
                    'role': role,
                    'permissions': sub_perms,
                    'profile_photo': member.get('profile_photo') or None,
                    'compliance_score': None if is_admin_role else comp_score,
                    'star_rating': None if is_admin_role else s_rating,
                    'manual_review_score': None if is_admin_role else m_score,
                    'breakdown': {}
                }
            }), 200
    except Exception as e:
        logger.error(f'[login] {e}')
        return jsonify({'message': 'An unexpected error occurred. Please try again.'}), 500
    finally:
        conn.close()


def get_member_renewal_breakdown(member_scale, fee_category, cursor, member_type='corporate'):
    raw_m = str(member_type or 'corporate').lower().strip()
    is_licentiate = 'licentiate' in raw_m or 'individual' in raw_m
    is_associate = 'associate' in raw_m or 'affiliate' in raw_m

    fee_map = {}
    if cursor:
        try:
            cursor.execute("SELECT key, amount FROM fee_schedules WHERE is_active = TRUE")
            for r in cursor.fetchall():
                if r.get('key') and r.get('amount') is not None:
                    fee_map[r['key']] = float(r['amount'])
        except Exception as ex:
            logger.debug(f'Error fetching fee_schedules: {ex}')

    if is_licentiate:
        sub_fee = fee_map.get('licentiate_sub_fee', 0.0)
        vet_fee = fee_map.get('licentiate_vetting_fee', 0.0)
        dist_fee = fee_map.get('licentiate_district_fee', 0.0)
        welfare = fee_map.get('licentiate_welfare_dues', 0.0)
        legal_fee = fee_map.get('licentiate_legal_audit_fee', 0.0)
        agm_levy = fee_map.get('licentiate_agm_levy', 0.0)

        breakdown = [
            {'label': 'Subscription Fee – Licentiate', 'amount': f'{sub_fee:.2f}'},
            {'label': 'Vetting Fee – Licentiate', 'amount': f'{vet_fee:.2f}'},
            {'label': 'District Dues – Licentiate', 'amount': f'{dist_fee:.2f}'},
            {'label': 'Welfare Dues – Licentiate', 'amount': f'{welfare:.2f}'},
            {'label': 'Legal & Audit Fee – Licentiate', 'amount': f'{legal_fee:.2f}'},
            {'label': 'AGM Levy – Licentiate', 'amount': f'{agm_levy:.2f}'},
        ]
        computed_total = sum(float(b['amount']) for b in breakdown)
        return {
            'schedule_key': 'renewal_licentiate',
            'scale': 'licentiate',
            'scale_label': 'Licentiate Member',
            'has_consolidation': False,
            'scope_label': 'Customs House Agent',
            'renewal_fee_title': 'Licentiate Annual Renewal Dues',
            'renewal_fee_amount': computed_total,
            'renewal_fee_breakdown': breakdown
        }
    elif is_associate:
        sub_fee = fee_map.get('associate_sub_fee', 0.0)
        vet_fee = fee_map.get('associate_vetting_fee', 0.0)
        dist_fee = fee_map.get('associate_district_fee', 0.0)
        welfare = fee_map.get('associate_welfare_dues', 0.0)
        legal_fee = fee_map.get('associate_legal_audit_fee', 0.0)
        agm_levy = fee_map.get('associate_agm_levy', 0.0)

        breakdown = [
            {'label': 'Subscription Fee – Associate', 'amount': f'{sub_fee:.2f}'},
            {'label': 'Vetting Fee – Associate', 'amount': f'{vet_fee:.2f}'},
            {'label': 'District Dues – Associate', 'amount': f'{dist_fee:.2f}'},
            {'label': 'Welfare Dues – Associate', 'amount': f'{welfare:.2f}'},
            {'label': 'Legal & Audit Fee – Associate', 'amount': f'{legal_fee:.2f}'},
            {'label': 'AGM Levy – Associate', 'amount': f'{agm_levy:.2f}'},
        ]
        computed_total = sum(float(b['amount']) for b in breakdown)
        return {
            'schedule_key': 'renewal_associate',
            'scale': 'associate',
            'scale_label': 'Associate Member',
            'has_consolidation': False,
            'scope_label': 'Allied Logistics Partner',
            'renewal_fee_title': 'Associate Annual Renewal Dues',
            'renewal_fee_amount': computed_total,
            'renewal_fee_breakdown': breakdown
        }

    scale = str(member_scale or 'sme').lower().strip()
    is_large = scale in ('large_corporate', 'large', 'corporate')
    cat = str(fee_category or 'cf_only').lower().strip()
    has_consolidation = cat in ('consolidation', 'cf_consolidation')

    if is_large:
        sched_key = 'renewal_large_corporate_with_consolidation' if has_consolidation else 'renewal_large_corporate_without_consolidation'
        scale_title = 'Large Corporate'
        sub_fee = fee_map.get('renewal_sub_large', 0.0)
        welfare = fee_map.get('renewal_welfare_large', 0.0)
        admin_fee = fee_map.get('renewal_admin_large', 0.0)
        legal_fee = fee_map.get('renewal_legal_large', 0.0)
        cti_fee = fee_map.get('renewal_cti_large', 0.0)
    else:
        sched_key = 'renewal_sme_with_consolidation' if has_consolidation else 'renewal_sme_without_consolidation'
        scale_title = "SME's"
        sub_fee = fee_map.get('renewal_sub_sme', 0.0)
        welfare = fee_map.get('renewal_welfare_sme', 0.0)
        admin_fee = fee_map.get('renewal_admin_sme', 0.0)
        legal_fee = fee_map.get('renewal_legal_sme', 0.0)
        cti_fee = fee_map.get('renewal_cti_sme', 0.0)

    agm_levy = fee_map.get('renewal_agm', 0.0)
    customs_bond = fee_map.get('renewal_bond', 0.0)
    consolidation_fee = fee_map.get('renewal_consolidation', fee_map.get('renewal_consolidation_item', 0.0)) if has_consolidation else 0.0

    breakdown = [
        {'label': f'Subscription Fee ({scale_title})', 'amount': f'{sub_fee:.2f}'},
        {'label': f'Welfare Dues ({scale_title})', 'amount': f'{welfare:.2f}'},
    ]
    if has_consolidation:
        breakdown.append({'label': 'Consolidation Fee', 'amount': f'{consolidation_fee:.2f}'})

    breakdown.extend([
        {'label': f'Administrative Fee ({scale_title})', 'amount': f'{admin_fee:.2f}'},
        {'label': f'Legal & Audit Fee ({scale_title})', 'amount': f'{legal_fee:.2f}'},
        {'label': 'AGM Levy', 'amount': f'{agm_levy:.2f}'},
        {'label': 'Customs Bond Fee (SIC)', 'amount': f'{customs_bond:.2f}'},
        {'label': f'CTI Training ({scale_title})', 'amount': f'{cti_fee:.2f}'},
    ])

    computed_total = sum(float(b['amount']) for b in breakdown)
    expected_total = fee_map.get(sched_key, computed_total)

    title = f"{scale_title} ({'Consolidation' if has_consolidation else 'Without Consolidation'})"

    return {
        'schedule_key': sched_key,
        'scale': 'large_corporate' if is_large else 'sme',
        'scale_label': scale_title,
        'has_consolidation': has_consolidation,
        'scope_label': 'Consolidation' if has_consolidation else 'Without Consolidation',
        'renewal_fee_title': title,
        'renewal_fee_amount': expected_total,
        'renewal_fee_breakdown': breakdown
    }


@auth_bp.route('/renewal-details', methods=['GET'])
@jwt_required()
def get_my_renewal_details():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT member_scale, fee_category, member_type FROM members WHERE id = %s", (member_id,))
            row = cursor.fetchone()
            if not row:
                return jsonify({'message': 'Member not found'}), 404
            details = get_member_renewal_breakdown(row.get('member_scale'), row.get('fee_category'), cursor, row.get('member_type'))
            return jsonify(details), 200
    finally:
        conn.close()


@auth_bp.route('/me', methods=['GET'])
@jwt_required()
def get_me():
    member_id = get_jwt_identity()
    cache_key = f'me_{member_id}'
    cached_res = cache.get(cache_key)
    if cached_res is not None:
        return jsonify(cached_res), 200
    
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            try:
                cursor.execute("SELECT * FROM members WHERE id = %s", (member_id,))
            except Exception:
                conn.rollback()
                cursor.execute("""
                    SELECT id, name, email, phone, company, license_number, agency_code,
                           member_type, member_scale, fee_category, consolidation_scope,
                           port_of_operation, status, profile_photo,
                           license_expiry_date, role, compliance_score, star_rating, manual_review_score
                    FROM members WHERE id = %s
                """, (member_id,))
            member = cursor.fetchone()
            if not member:
                return jsonify({'message': 'Member not found'}), 404
                
            from utils import calculate_and_update_member_rating
            rating_data = calculate_and_update_member_rating(member_id, cursor)

            # Fetch rating history (capped to last 30 entries for speed)
            cursor.execute("""
                SELECT compliance_score, star_rating, recorded_at
                FROM member_rating_history
                WHERE member_id = %s
                ORDER BY recorded_at DESC LIMIT 30
            """, (member_id,))
            history_rows = cursor.fetchall()
            history_rows.reverse()
            history = []
            for h in history_rows:
                history.append({
                    'compliance_score': h['compliance_score'],
                    'star_rating': float(h['star_rating']),
                    'recorded_at': str(h['recorded_at'])
                })

            # Return fresh data
            result = dict(member)
            for secret_key in ('password_hash', 'fcm_token', 'reset_token', 'otp', 'otp_code'):
                result.pop(secret_key, None)
            result['compliance_score'] = rating_data['compliance_score']
            result['star_rating'] = rating_data['star_rating']
            result['manual_review_score'] = rating_data['manual_review_score']
            result['breakdown'] = rating_data.get('breakdown', {})
            result['rating_history'] = history
            days_left = None
            if result.get('license_expiry_date'):
                from datetime import datetime, date
                exp = result['license_expiry_date']
                if isinstance(exp, str):
                    try: exp = datetime.strptime(exp, '%Y-%m-%d').date()
                    except ValueError as date_err:
                        logger.debug(f'[/me] Could not parse license_expiry_date: {date_err}')
                if isinstance(exp, date):
                    days_left = (exp - date.today()).days
                result['license_expiry_date'] = str(result['license_expiry_date'])
            result['license_days_left'] = days_left
            
            if result.get('role') == 'member':
                mem_no = result.get('membership_number') or result.get('license_number') or f"CUBAG-{result['id']:04d}"
                result['membership_number'] = mem_no
                result['license_number'] = mem_no
                result['company_scale'] = result.get('member_scale') or 'sme'
                result['fee_category'] = result.get('fee_category') or 'cf_only'

                # Check if there is a custom profile-specific bill issued by Admin in Compliance Centre or saved on member profile
                cursor.execute("""
                    SELECT id, type, status, payment_amount, payment_deadline, fee_breakdown, bill_title, admin_note
                    FROM compliance_applications
                    WHERE member_id = %s AND type = 'renewal'
                    ORDER BY (fee_breakdown IS NOT NULL AND fee_breakdown != '[]' AND fee_breakdown != 'null') DESC, updated_at DESC LIMIT 1
                """, (member_id,))
                latest_comp_app = cursor.fetchone()
                if not latest_comp_app:
                    cursor.execute("""
                        SELECT id, type, status, payment_amount, payment_deadline, fee_breakdown, bill_title, admin_note
                        FROM compliance_applications
                        WHERE member_id = %s
                        ORDER BY updated_at DESC LIMIT 1
                    """, (member_id,))
                    latest_comp_app = cursor.fetchone()

                import json
                has_custom_bill = False
                custom_fb = None
                custom_title = None
                custom_amt = None

                # 1. Inspect compliance_applications
                if latest_comp_app and latest_comp_app.get('fee_breakdown'):
                    raw_fb = latest_comp_app['fee_breakdown']
                    if isinstance(raw_fb, str):
                        try:
                            raw_fb = json.loads(raw_fb)
                        except Exception:
                            raw_fb = []
                    if isinstance(raw_fb, list) and len(raw_fb) > 0:
                        custom_fb = raw_fb
                        custom_title = latest_comp_app.get('bill_title')
                        if latest_comp_app.get('payment_amount') is not None:
                            try:
                                custom_amt = float(latest_comp_app['payment_amount'])
                            except (TypeError, ValueError):
                                pass

                # 2. Inspect members table if not found on application
                if not custom_fb and result.get('renewal_fee_breakdown'):
                    raw_m_fb = result['renewal_fee_breakdown']
                    if isinstance(raw_m_fb, str):
                        try:
                            raw_m_fb = json.loads(raw_m_fb)
                        except Exception:
                            raw_m_fb = []
                    if isinstance(raw_m_fb, list) and len(raw_m_fb) > 0:
                        custom_fb = raw_m_fb
                        custom_title = result.get('renewal_fee_title')
                        if result.get('renewal_fee_amount') is not None:
                            try:
                                custom_amt = float(result['renewal_fee_amount'])
                            except (TypeError, ValueError):
                                pass

                # 3. If no breakdown list is present, but an application has an explicit payment_amount
                if not custom_fb and latest_comp_app and latest_comp_app.get('payment_amount') is not None:
                    try:
                        p_amt = float(latest_comp_app['payment_amount'])
                        if p_amt > 0:
                            custom_amt = p_amt
                            custom_title = latest_comp_app.get('bill_title') or result.get('renewal_fee_title') or 'Annual Renewal Dues'
                            custom_fb = [{'label': custom_title, 'amount': f'{p_amt:.2f}'}]
                    except (TypeError, ValueError):
                        pass

                if custom_fb:
                    if custom_amt is None or custom_amt <= 0:
                        custom_amt = sum(float(str(x.get('amount', 0)).replace(',', '')) for x in custom_fb)
                    bill_lbl = custom_title or result.get('renewal_fee_title') or 'Annual Renewal Dues'
                    result['renewal_fee_breakdown'] = custom_fb
                    result['renewal_fee_amount'] = custom_amt
                    result['renewal_fee_title'] = bill_lbl
                    if latest_comp_app:
                        result['compliance_app_id'] = latest_comp_app['id']
                        result['compliance_app_status'] = latest_comp_app['status']
                        result['payment_deadline'] = str(latest_comp_app.get('payment_deadline') or '')
                    result['renewal_details'] = {
                        'renewal_fee_amount': custom_amt,
                        'renewal_fee_title': bill_lbl,
                        'renewal_fee_breakdown': custom_fb
                    }
                    has_custom_bill = True

                if not has_custom_bill:
                    renewal_info = get_member_renewal_breakdown(result.get('member_scale'), result.get('fee_category'), cursor, result.get('member_type'))
                    result['renewal_details'] = renewal_info
                    result['renewal_fee_amount'] = renewal_info['renewal_fee_amount']
                    result['renewal_fee_title'] = renewal_info['renewal_fee_title']
                    result['renewal_fee_breakdown'] = renewal_info['renewal_fee_breakdown']

                # Calculate installment financials and retrieve any linked payments
                app_target_id = latest_comp_app['id'] if latest_comp_app else 0
                cursor.execute("""
                    SELECT id, amount, status, payment_method, receipt_url, description, is_installment, installment_number, created_at, paid_at
                    FROM payments
                    WHERE (application_id = %s OR (member_id = %s AND (LOWER(description) LIKE '%%renewal%%' OR LOWER(description) LIKE '%%annual dues%%')))
                      AND LOWER(status) IN ('paid', 'completed', 'success', 'successful', 'pending', 'submitted', 'processing')
                    ORDER BY created_at ASC
                """, (app_target_id, member_id))
                renewal_installments = [dict(r) for r in cursor.fetchall()]
                for inst in renewal_installments:
                    if inst.get('created_at'):
                        inst['date'] = inst['created_at'].isoformat()
                    if inst.get('paid_at'):
                        inst['paid_at'] = inst['paid_at'].isoformat()

                confirmed_paid = sum(float(p['amount']) for p in renewal_installments if str(p.get('status', '')).lower() in ('paid', 'completed', 'success', 'successful'))
                comp_amt_paid = float(latest_comp_app.get('amount_paid') or 0.0) if latest_comp_app else 0.0
                actual_paid = confirmed_paid if confirmed_paid > 0 else comp_amt_paid
                total_billed = float(result.get('renewal_fee_amount') or 0.0)
                bal_due = max(0.0, total_billed - actual_paid)
                is_part_paid = (actual_paid > 0.01 and bal_due > 0.01)

                result['renewal_amount_paid'] = actual_paid
                result['renewal_balance_due'] = bal_due
                result['renewal_allow_installments'] = bool(latest_comp_app.get('allow_installments', True)) if latest_comp_app else True
                result['renewal_min_installment_amount'] = float(latest_comp_app.get('min_installment_amount') or 0.0) if latest_comp_app else 0.0
                result['renewal_is_partially_paid'] = is_part_paid
                result['renewal_installments'] = renewal_installments

                # Check if member has an active or completed renewal payment
                cursor.execute("""
                    SELECT id, amount, status, payment_method, receipt_url, description FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('pending', 'paid', 'completed', 'success', 'successful', 'processing', 'submitted')
                      AND (
                          LOWER(description) LIKE '%%renewal%%'
                          OR LOWER(description) LIKE '%%annual dues%%'
                          OR LOWER(description) LIKE '%%license renewal%%'
                      )
                    ORDER BY id DESC LIMIT 1
                """, (member_id,))
                renewal_pay_row = cursor.fetchone()
                result['renewal_payment_submitted'] = bool(renewal_pay_row)
                result['renewal_payment_status'] = renewal_pay_row['status'] if renewal_pay_row else None
                if renewal_pay_row and latest_comp_app and latest_comp_app.get('status') == 'payment_pending':
                    cursor.execute("""
                        UPDATE compliance_applications
                        SET status = 'payment_submitted', updated_at = NOW()
                        WHERE id = %s
                    """, (latest_comp_app['id'],))
                    conn.commit()
                    result['compliance_app_status'] = 'payment_submitted'

                # Check if registration fee and package fee were already paid
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%registration%%'
                          OR LOWER(description) LIKE '%%new member%%'
                          OR LOWER(description) LIKE '%%clearing & forwarding%%'
                          OR LOWER(description) LIKE '%%consolidation%%'
                          OR LOWER(description) LIKE '%%entrance%%'
                          OR LOWER(description) LIKE '%%package%%'
                          OR LOWER(description) LIKE '%%application%%'
                      )
                """, (member_id,))
                p_row = cursor.fetchone()
                has_any_reg_payment = (p_row['cnt'] > 0) if p_row else False

                # Check specifically for entrance package payment
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%new member%%'
                          OR LOWER(description) LIKE '%%entrance%%'
                          OR LOWER(description) LIKE '%%package%%'
                          OR LOWER(description) LIKE '%%clearing & forwarding only%%'
                          OR LOWER(description) LIKE '%%consolidation only%%'
                          OR LOWER(description) LIKE '%%licentiate membership%%'
                          OR LOWER(description) LIKE '%%associate membership%%'
                      )
                      AND LOWER(description) NOT LIKE '%%registration%%'
                      AND LOWER(description) NOT LIKE '%%application%%'
                      AND LOWER(description) NOT LIKE '%%renewal%%'
                """, (member_id,))
                pkg_row = cursor.fetchone()
                has_pkg_payment = (pkg_row['cnt'] > 0) if pkg_row else False

                # Check specifically for annual renewal payment
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM payments
                    WHERE member_id = %s
                      AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                      AND (
                          LOWER(description) LIKE '%%renewal%%'
                          OR LOWER(description) LIKE '%%annual renewal%%'
                      )
                """, (member_id,))
                ren_row = cursor.fetchone()
                has_renewal_payment = (ren_row['cnt'] > 0) if ren_row else False

                is_pkg_paid = (result.get('package_fee_paid') is True) or has_pkg_payment
                result['registration_fee_paid'] = has_any_reg_payment or (result.get('registration_fee_paid') is True)
                result['package_fee_paid'] = is_pkg_paid
                result['is_renewal_paid'] = has_renewal_payment
                result['renewal_paid'] = has_renewal_payment
                result['good_standing'] = is_pkg_paid
                result['is_good_standing'] = is_pkg_paid

                if not is_pkg_paid:
                    result['membership_number'] = 'PENDING SETTLEMENT'
                    result['license_number'] = 'PENDING SETTLEMENT'
                else:
                    mem_no = result.get('membership_number') or result.get('license_number') or f"CUBAG-{result['id']:04d}"
                    if 'pending' in str(mem_no).lower():
                        mem_no = f"CUBAG-{result['id']:04d}"
                    result['membership_number'] = mem_no
                    result['license_number'] = mem_no

            if result.get('role') in ('admin', 'sub_admin', 'super_admin'):
                result['license_number'] = None
                result['membership_number'] = None
                result['agency_code'] = None
                result['compliance_score'] = None
                result['star_rating'] = None
                result['manual_review_score'] = None
                result['good_standing'] = None
                result['is_good_standing'] = None

            if result.get('role') == 'sub_admin':
                cursor.execute(
                    "SELECT permission_key FROM sub_admin_permissions WHERE sub_admin_id = %s AND granted = true",
                    (member_id,)
                )
                result['permissions'] = [r['permission_key'] for r in cursor.fetchall()]

            for secret_key in ('password_hash', 'fcm_token', 'reset_token', 'otp', 'otp_code'):
                result.pop(secret_key, None)
            # Store in cache — 60 second TTL per member (never cache secrets)
            cache.set(cache_key, result, timeout=60)
            return jsonify(result), 200
    finally:
        conn.close()


@auth_bp.route('/update-preferences', methods=['POST'])
@jwt_required()
def update_preferences():
    """F-47 fix: Persist user preferences (e.g. push_notifications) to DB."""
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    push_enabled = data.get('push_notifications')
    if push_enabled is None:
        return jsonify({'message': 'No preferences provided'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "UPDATE members SET push_notifications_enabled = %s WHERE id = %s",
                (bool(push_enabled), member_id)
            )
            conn.commit()
        return jsonify({'message': 'Preferences updated'}), 200
    except Exception as e:
        conn.rollback()
        logger.error(f'[update-preferences] {e}')
        return jsonify({'message': 'Preferences noted'}), 200  # non-critical
    finally:
        conn.close()


@auth_bp.route('/upload-photo', methods=['POST'])
@jwt_required()
def upload_photo():
    """Upload profile photo to Supabase Storage and save URL in DB."""
    member_id = get_jwt_identity()

    file = request.files.get('photo') or request.files.get('file') or request.files.get('image')
    if not file or not file.filename:
        return jsonify({'message': 'No photo provided'}), 400

    ext = file.filename.rsplit('.', 1)[-1].lower()
    if ext not in ('jpg', 'jpeg', 'png', 'webp'):
        return jsonify({'message': 'Only JPG, PNG, or WebP allowed'}), 400

    # Size check (max 5MB)
    file.seek(0, 2)
    if file.tell() > 5 * 1024 * 1024:
        return jsonify({'message': 'Photo too large. Max 5MB.'}), 413
    file.seek(0)

    safe_name = f"profile_{member_id}_{uuid.uuid4().hex[:8]}.{ext}"
    file_bytes = file.read()
    content_type = file.content_type or 'image/jpeg'

    # Read Supabase config at request time (not module load time)
    supabase_url = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
    supabase_key = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
    photo_bucket = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

    public_url = None
    if supabase_url and supabase_key:
        storage_url = f"{supabase_url}/storage/v1/object/{photo_bucket}/{safe_name}"
        headers = {
            "apikey": supabase_key,
            "Authorization": f"Bearer {supabase_key}",
            "Content-Type": content_type,
            "x-upsert": "true",
        }
        try:
            resp = http_req.post(storage_url, data=file_bytes, headers=headers, timeout=10)
            if resp.status_code in (200, 201):
                public_url = f"{supabase_url}/storage/v1/object/public/{photo_bucket}/{safe_name}"
            else:
                logger.warning(f"[upload-photo] Supabase upload returned {resp.status_code}: {resp.text}")
        except Exception as e:
            logger.warning(f"[upload-photo] Request to Supabase failed: {e}")

    # Fallback to local persistent storage if Supabase failed or unconfigured
    if not public_url:
        local_filename = safe_name
        # 1. Permanent storage outside web build directories
        backend_dir = os.path.dirname(os.path.dirname(__file__))
        perm_dir = os.path.join(backend_dir, 'uploads', 'avatars')
        os.makedirs(perm_dir, exist_ok=True)
        with open(os.path.join(perm_dir, local_filename), 'wb') as f:
            f.write(file_bytes)

        # 2. Also mirror to static and dist so static file handlers find it
        for folder in ['static', 'dist']:
            sub_dir = os.path.join(backend_dir, folder, 'uploads', 'avatars')
            os.makedirs(sub_dir, exist_ok=True)
            try:
                with open(os.path.join(sub_dir, local_filename), 'wb') as f:
                    f.write(file_bytes)
            except Exception:
                pass

        public_url = f"/static/uploads/avatars/{local_filename}"

    # Save URL to DB
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE members SET profile_photo = %s WHERE id = %s", (public_url, member_id))
            conn.commit()

        # Invalidate profile cache so fresh photo is always returned immediately
        cache.delete(f'me_{member_id}')

        try:
            from socket_instance import socketio
            socketio.emit('member_updated', {'id': member_id, 'profile_photo': public_url})
        except Exception:
            pass

        return jsonify({'message': 'Photo uploaded successfully', 'photo_url': public_url, 'profile_photo': public_url}), 200
    except Exception as e:
        logger.error(f"[upload-photo] DB update failed: {e}")
        return jsonify({'message': 'Failed to save profile photo to database.'}), 500
    finally:
        conn.close()


@auth_bp.route('/change-password', methods=['POST', 'OPTIONS'])
@cross_origin(supports_credentials=True)
def change_password():
    if request.method == 'OPTIONS':
        res = make_response('', 200)
        # BUG-B08 fix: never echo arbitrary Origin — use explicit allowlist
        allowed_origins = os.getenv('ALLOWED_ORIGINS', 'https://cubag.web.app').split(',')
        request_origin = request.headers.get('Origin', '')
        if request_origin in allowed_origins:
            res.headers['Access-Control-Allow-Origin'] = request_origin
        res.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
        res.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
        res.headers['Access-Control-Allow-Credentials'] = 'true'
        return res

    try:
        # Manually verify JWT so it doesn't block the preflight
        verify_jwt_in_request()
        member_id = get_jwt_identity()
    except Exception as e:
        logger.debug(f"[change-password] JWT verification failed: {str(e)}")
        return jsonify({'message': 'Authentication required'}), 401

    data = request.get_json()
    current_password = data.get('current_password')
    new_password = data.get('new_password')

    if not current_password or not new_password:
        return jsonify({'message': 'Current and new passwords are required'}), 400

    # BUG-M03: enforce minimum password length server-side
    if len(new_password) < 8:
        return jsonify({'message': 'New password must be at least 8 characters'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT password_hash FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            if not member or not check_password_hash(member['password_hash'], current_password):
                return jsonify({'message': 'Incorrect current password'}), 401

            hashed_pw = generate_password_hash(new_password)
            cursor.execute("UPDATE members SET password_hash = %s WHERE id = %s", (hashed_pw, member_id))
            conn.commit()
            return jsonify({'message': 'Password changed successfully'}), 200
    except Exception as e:
        logger.error(f'[change-password] {e}')
        return jsonify({'message': 'Password change failed. Please try again.'}), 500
    finally:
        conn.close()


@auth_bp.route('/update-fcm-token', methods=['POST', 'PUT', 'OPTIONS'])
@auth_bp.route('/fcm-token', methods=['POST', 'PUT', 'OPTIONS'])
def update_fcm_token():
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    # Properly verify JWT on the route function (inner-function decorator pattern doesn't work)
    try:
        verify_jwt_in_request()
        member_id = get_jwt_identity()
    except Exception:
        return jsonify({'message': 'Authentication required'}), 401

    data = request.get_json() or {}
    token = data.get('fcm_token') or data.get('token')

    if not token:
        return jsonify({'message': 'Token is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE members SET fcm_token = %s WHERE id = %s", (token, member_id))
            conn.commit()
        return jsonify({'message': 'FCM token updated'}), 200
    except Exception as e:
        logger.error(f'[update-fcm-token] {e}')
        return jsonify({'message': 'Failed to update token'}), 500
    finally:
        conn.close()


@auth_bp.route('/delete-account', methods=['DELETE', 'POST', 'OPTIONS'])
@cross_origin()
def delete_account():
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    try:
        verify_jwt_in_request()
        member_id = get_jwt_identity()
    except Exception:
        return jsonify({'message': 'Authentication required'}), 401

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE members 
                SET status = 'deleted',
                    email = CONCAT('deleted_', id, '_', email),
                    phone = NULL,
                    fcm_token = NULL,
                    updated_at = NOW()
                WHERE id = %s
            """, (member_id,))
            conn.commit()
        return jsonify({'message': 'Account deleted successfully', 'status': 'deleted'}), 200
    except Exception as e:
        logger.error(f'[delete-account] {e}')
        return jsonify({'message': 'Failed to delete account'}), 500
    finally:
        conn.close()


def send_reset_email(to_email, token):
    client_url = os.getenv('CLIENT_URL', '')
    if not client_url or 'localhost' in client_url or '127.0.0.1' in client_url:
        client_url = 'https://cubag-web-app.onrender.com'
    
    client_url = client_url.rstrip('/#')
    reset_link = f'{client_url}/#/reset-password?token={token}&email={to_email}'
    subject   = 'Reset your CUBAG Password'
    body_text = (
        f'Hello,\n\n'
        f'You requested a password reset for your CUBAG account.\n\n'
        f'Click the link below to reset your password:\n\n'
        f'  {reset_link}\n\n'
        f'If you did not request this, please ignore this email.\n\n'
        f'Thanks,\nCUBAG Secretariat'
    )
    body_html = (
        f'<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:32px;border:1px solid #e2e8f0;border-radius:12px;">'
        f'<h2 style="color:#FF5000;margin-bottom:8px;">CUBAG Password Reset</h2>'
        f'<p style="color:#475569;">You requested a password reset. Click the button below:</p>'
        f'<a href="{reset_link}" style="display:block;text-align:center;background:#FF5000;color:#fff;'
        f'font-weight:bold;padding:14px 24px;border-radius:10px;text-decoration:none;margin:24px 0;">'
        f'Reset My Password</a>'
        f'<p style="color:#94a3b8;font-size:12px;">If you did not request this, ignore this email. This link expires shortly.</p>'
        f'</div>'
    )
    return _send_email(to_email, subject, body_text, body_html)


@auth_bp.route('/forgot-password', methods=['POST', 'OPTIONS'])
@rate_limit('forgot_password', max_requests=5, window_seconds=300)
def forgot_password():
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    data = request.get_json()
    email = data.get('email')
    if not email:
        return jsonify({'message': 'Email is required'}), 400
        
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, email FROM members WHERE LOWER(email) = LOWER(%s)", (email,))
            user = cursor.fetchone()
            if user:
                actual_email = user['email']
                import secrets
                token = str(secrets.randbelow(90000000) + 10000000) # 8-digit code
                # Delete ALL otp entries for this email (PK constraint = one row per email)
                cursor.execute("DELETE FROM otp_codes WHERE LOWER(email) = LOWER(%s)", (actual_email,))
                # Insert the password reset token
                cursor.execute(
                    "INSERT INTO otp_codes (email, code, type) VALUES (%s, %s, 'password_reset')",
                    (actual_email, token)
                )
                conn.commit()
                clear_otp_failures('reset', actual_email)
                # Send synchronously with 10s timeout (threads unreliable with gevent)
                try:
                    send_reset_email(actual_email, token)
                except Exception as mail_err:
                    logger.warning(f'[SMTP] Non-fatal: {mail_err}')  # BUG-B13 fix

        return jsonify({'message': 'If an account exists, a reset link has been sent.'}), 200
    except Exception as e:
        logger.error(f'[forgot-password] {e}')  # BUG-B14 fix
        return jsonify({'message': 'An error occurred. Please try again.'}), 500
    finally:

        conn.close()


@auth_bp.route('/reset-password', methods=['POST', 'OPTIONS'])
@rate_limit('reset_password', max_requests=8, window_seconds=300)
def reset_password():
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    data = request.get_json()
    email = data.get('email')
    token = data.get('code')
    new_password = data.get('new_password')
    
    if not email or not token or not new_password:
        return jsonify({'message': 'Email, code, and new password are required'}), 400

    if len(new_password) < 8:
        return jsonify({'message': 'Password must be at least 8 characters'}), 400

    if otp_attempt_limited('reset', email):
        return jsonify({'message': 'Too many incorrect codes. Please request a new one.'}), 429

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Token must exist, match type, AND be less than 1 hour old
            cursor.execute("""
                SELECT * FROM otp_codes
                WHERE LOWER(email) = LOWER(%s)
                  AND code = %s
                  AND type = 'password_reset'
                  AND created_at > NOW() - INTERVAL '1 hour'
            """, (email, token))
            otp_record = cursor.fetchone()

            if not otp_record:
                record_otp_failure('reset', email)
                return jsonify({'message': 'Invalid or expired reset link. Please request a new one.'}), 400

            clear_otp_failures('reset', email)
            # B-15 fix: update by member ID, not email string (avoids multi-row risk)
            actual_email = otp_record['email']
            cursor.execute("SELECT id FROM members WHERE LOWER(email) = LOWER(%s)", (actual_email,))
            member_row = cursor.fetchone()
            if not member_row:
                return jsonify({'message': 'Account not found'}), 400
            hashed_pw = generate_password_hash(new_password)
            cursor.execute("UPDATE members SET password_hash = %s WHERE id = %s", (hashed_pw, member_row['id']))
            cursor.execute("DELETE FROM otp_codes WHERE LOWER(email) = LOWER(%s) AND type = 'password_reset'", (actual_email,))
            conn.commit()
            
            return jsonify({'message': 'Password has been reset successfully. You can now log in.'}), 200
    except Exception as e:
        logger.error(f'[reset-password] {e}')
        return jsonify({'message': 'Password reset failed. Please try again.'}), 500
    finally:
        conn.close()

# SMS OTP routes (send-sms-otp, verify-sms-otp) have been removed.
# No SMS gateway integration exists. Use email OTP via /send-otp and /verify-email.
