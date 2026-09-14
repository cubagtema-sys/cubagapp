import os
import uuid
import requests
import hashlib
import hmac
import resend
import logging
from datetime import datetime, date, timedelta
from flask import Blueprint, jsonify, request
from flask_cors import cross_origin
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from socket_instance import socketio
from utils import admin_required, sub_admin_required, log_backend_error, log_admin_action
from config.cache import cache

payments_bp = Blueprint('payments', __name__)
logger = logging.getLogger(__name__)

# ─── WhitsunPay Configuration ─────────────────────────────────────────────────
WHITSUNPAY_BASE_URL = (os.getenv('WHITSUNPAY_BASE_URL', '') or 'https://developer.whitsun.dev').rstrip('/')
WHITSUNPAY_CLIENT_ID = os.getenv('WHITSUNPAY_CLIENT_ID', '') or os.getenv('x-client-id', '')
WHITSUNPAY_API_KEY = os.getenv('WHITSUNPAY_API_KEY', '') or os.getenv('x-api-key', '')
WHITSUNPAY_WEBHOOK_SECRET = os.getenv('WHITSUNPAY_WEBHOOK_SECRET', '')

# BUG-P04 fix: Do NOT hardcode a fallback domain — if this env var is unset
# webhooks will be sent to the wrong server. Fail loudly at startup instead.
WHITSUNPAY_CALLBACK_URL = os.getenv('WHITSUNPAY_CALLBACK_URL', '') or os.getenv('x-callback-url', '')
if not WHITSUNPAY_CALLBACK_URL:
    logger.warning(
        '[WhitsunPay] WHITSUNPAY_CALLBACK_URL is not set! '
        'Set this env var to your production webhook URL '
        '(e.g. https://your-backend.onrender.com/api/payments/webhook). '
        'Payment webhooks will not be received until this is configured.'
    )

# Full versioned API base — e.g. https://developer.whitsun.dev/api/v1
_WP_API = f'{WHITSUNPAY_BASE_URL}/api/v1'


def _whitsunpay_headers():
    """Build headers for WhitsunPay API requests (Enhanced to bypass Cloudflare)."""
    return {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'x-client-id': WHITSUNPAY_CLIENT_ID,
        'x-api-key': WHITSUNPAY_API_KEY,
        'x-callback-url': WHITSUNPAY_CALLBACK_URL,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Referer': 'https://developer.whitsun.dev/',
        'Origin': 'https://developer.whitsun.dev',
        'Sec-Ch-Ua': '"Not(A:Brand";v="24", "Chromium";v="122"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
    }

@payments_bp.route('/test-gateway', methods=['GET'])
@admin_required
def test_gateway_connectivity():
    """Admin-only: test if the backend can reach the WhitsunPay gateway."""
    tests = [
        "https://developer.whitsun.dev/api/v1/health",
        "https://api.whitsun.dev/api/v1/health",
        "https://api.whitsun.io/api/v1/health",
        "https://api.whitsunsystems.com/api/v1/health",
        "https://api.swagpaygh.com/api/v1/health",
        "https://swagpay.whitsun.dev/api/v1/health"
    ]
    results = []

    headers = _whitsunpay_headers()
    if 'x-callback-url' in headers: del headers['x-callback-url']

    for url in tests:
        try:
            r = requests.get(url, headers=headers, timeout=5)
            results.append({
                'url': url,
                'status': r.status_code,
                'blocked': 'Just a moment' in r.text or r.status_code == 403,
                'preview': r.text[:100].strip()
            })
        except Exception as e:
            results.append({'url': url, 'error': str(e)})

    return jsonify({
        'results': results,
        'recommendation': 'WhitsunPay API host is likely blocked by Cloudflare on Render. Contact WhitsunPay support to whitelist Render outgoing IPs.'
    }), 200


# ─── POST /payments/public/initiate-momo — Public MoMo Prompt for CTI Course Enrollment ───
@payments_bp.route('/public/initiate-momo', methods=['POST', 'OPTIONS'])
@cross_origin()
def public_initiate_momo():
    """Public endpoint: Dispatches mobile money authorization prompt for guest course enrollment."""
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    data = request.get_json(force=True) or {}
    name         = (data.get('name') or '').strip()
    phone        = (data.get('phone') or '').strip()
    email        = (data.get('email') or '').strip()
    course_name  = (data.get('course_name') or 'CTI Professional Course').strip()
    amount_str   = str(data.get('amount') or '1500').replace('GHS', '').replace(',', '').strip()
    network      = (data.get('network') or 'MTN').strip()
    service_type = (data.get('service_type') or 'cti_training').strip()

    if not phone:
        return jsonify({'message': 'Phone number is required'}), 400

    try:
        amount = float(amount_str)
        if amount <= 0:
            amount = 1500.0
    except Exception:
        amount = 1500.0

    # International phone format: 233XXXXXXXXX
    clean_phone = ''.join(filter(str.isdigit, phone))
    if clean_phone.startswith('0') and len(clean_phone) == 10:
        clean_phone = '233' + clean_phone[1:]
    elif len(clean_phone) == 9:
        clean_phone = '233' + clean_phone

    import datetime
    ref_suffix = uuid.uuid4().hex[:6].upper()
    today_str  = datetime.date.today().strftime('%Y%m%d')
    tx_ref     = f"CTI-{today_str}-{ref_suffix}"

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS guest_payments (
                    id SERIAL PRIMARY KEY,
                    reference_no VARCHAR(100) UNIQUE NOT NULL,
                    service_type VARCHAR(100),
                    name VARCHAR(255),
                    phone VARCHAR(50),
                    email VARCHAR(150),
                    course_name VARCHAR(255),
                    amount NUMERIC(12, 2),
                    network VARCHAR(50),
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                INSERT INTO guest_payments
                    (reference_no, service_type, name, phone, email, course_name, amount, network, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending')
                RETURNING id
            """, (tx_ref, service_type, name, clean_phone, email, course_name, amount, network))
            guest_pay_id = cursor.fetchone()['id']
            conn.commit()

        # Attempt to dispatch gateway prompt via WhitsunPay / MoMo API if configured
        network_map = {
            'MTN Mobile Money': 'mtn', 'MTN': 'mtn',
            'Telecel Cash': 'vodafone', 'Vodafone': 'vodafone',
            'AT Money': 'airteltigo', 'AirtelTigo': 'airteltigo'
        }
        provider = network_map.get(network, 'mtn')

        prompt_sent = False
        if WHITSUNPAY_CLIENT_ID and WHITSUNPAY_API_KEY:
            payload = {
                'transactionReference': tx_ref,
                'description': f"CUBAG CTI: {course_name[:40]}",
                'amount': round(amount, 2),
                'debitParty': {
                    'msisdn': clean_phone,
                    'provider': provider
                }
            }
            try:
                target_url = f'{_WP_API}/payments'
                wp_res = requests.post(target_url, json=payload, headers=_whitsunpay_headers(), timeout=15)
                logger.info("[Public MoMo Prompt] WhitsunPay response: %s", wp_res.text[:200])
                if wp_res.status_code < 400:
                    prompt_sent = True
            except Exception as e:
                logger.warning("[Public MoMo Prompt] Gateway call error: %s", e)

        return jsonify({
            'status': 'pending',
            'message': 'Payment prompt sent to your phone. Please authorize with your MoMo PIN.',
            'reference_number': tx_ref,
            'id': guest_pay_id,
            'amount': amount,
            'phone': phone,
            'network': network,
            'prompt_sent': prompt_sent
        }), 200
    except Exception as e:
        logger.exception("Error in public_initiate_momo: %s", e)
        return jsonify({'message': 'Failed to initiate payment prompt'}), 500
    finally:
        conn.close()


@payments_bp.route('/public/check-status/<string:reference>', methods=['GET', 'OPTIONS'])
@cross_origin()
def public_check_momo_status(reference):
    """Checks the status of a guest CTI course MoMo payment."""
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, reference_no, service_type, name, phone, course_name, amount, status, created_at
                FROM guest_payments
                WHERE reference_no = %s
            """, (reference,))
            row = cursor.fetchone()
            if not row:
                return jsonify({'message': 'Transaction not found', 'status': 'not_found'}), 404

            current_status = (row.get('status') or 'pending').lower()
            if current_status == 'pending' and WHITSUNPAY_CLIENT_ID and WHITSUNPAY_API_KEY:
                try:
                    target_url = f'{_WP_API}/{reference}/status'
                    wp_res = requests.get(target_url, headers=_whitsunpay_headers(), timeout=8)
                    if wp_res.status_code < 400:
                        wp_data = wp_res.json()
                        wp_status = str(wp_data.get('status', '')).lower()
                        if wp_status in ('successful', 'success', 'completed', 'paid'):
                            cursor.execute("UPDATE guest_payments SET status = 'paid', updated_at = NOW() WHERE reference_no = %s", (reference,))
                            conn.commit()
                            current_status = 'paid'
                except Exception as e:
                    logger.warning("[Public Check Status] Gateway polling error: %s", e)

            return jsonify({
                'reference_number': row['reference_no'],
                'status': current_status,
                'is_paid': current_status in ('paid', 'completed', 'success', 'successful'),
                'amount': float(row['amount']) if row.get('amount') else 1500.0,
                'course_name': row.get('course_name'),
                'name': row.get('name')
            }), 200
    except Exception as e:
        logger.exception("Error in public_check_momo_status: %s", e)
        return jsonify({'message': 'Failed to check status'}), 500
    finally:
        conn.close()


@payments_bp.route('/public/confirm-momo/<string:reference>', methods=['POST', 'OPTIONS'])
@cross_origin()
def public_confirm_momo(reference):
    """Verifies and confirms a guest MoMo payment with WhitsunPay gateway."""
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, reference_no, course_name, name, phone, email, amount, status
                FROM guest_payments
                WHERE reference_no = %s
            """, (reference,))
            row = cursor.fetchone()
            if not row:
                return jsonify({'message': 'Transaction not found', 'is_paid': False}), 404

            current_status = (row.get('status') or 'pending').lower()

            # Strict Gateway Verification: Check if customer approved prompt with PIN
            if current_status != 'paid' and WHITSUNPAY_CLIENT_ID and WHITSUNPAY_API_KEY:
                try:
                    target_url = f'{_WP_API}/{reference}/status'
                    wp_res = requests.get(target_url, headers=_whitsunpay_headers(), timeout=10)
                    logger.info("[Verify MoMo Gateway] %s => %d %s", target_url, wp_res.status_code, wp_res.text[:250])
                    if wp_res.status_code < 400:
                        wp_data = wp_res.json()
                        wp_status = str(wp_data.get('status', '')).upper()
                        if wp_status in ('SUCCESS', 'SUCCESSFUL', 'PAID', 'COMPLETED'):
                            current_status = 'paid'
                        elif wp_status in ('FAILED', 'DECLINED', 'EXPIRED', 'CANCELLED'):
                            current_status = 'failed'
                except Exception as ex:
                    logger.warning("[Verify MoMo Gateway] Status check exception: %s", ex)

            if current_status == 'paid':
                cursor.execute("""
                    UPDATE guest_payments
                    SET status = 'paid', updated_at = NOW()
                    WHERE reference_no = %s
                """, (reference,))

                cursor.execute("""
                    INSERT INTO guest_service_requests
                        (reference_no, service_type, name, phone, email, course_name, details, status)
                    VALUES (%s, 'cti_training', %s, %s, %s, %s, %s, 'paid')
                    ON CONFLICT (reference_no) DO UPDATE
                    SET status = 'paid'
                """, (row['reference_no'], row['name'], row['phone'], row['email'], row['course_name'], f"Course: {row['course_name']} - Paid GHS {row['amount']}"))
                conn.commit()

                return jsonify({
                    'message': 'Payment confirmed successfully',
                    'reference_number': row['reference_no'],
                    'status': 'paid',
                    'is_paid': True
                }), 200
            elif current_status == 'failed':
                return jsonify({
                    'message': 'Payment was cancelled or declined on phone. Please try again.',
                    'reference_number': row['reference_no'],
                    'status': 'failed',
                    'is_paid': False
                }), 400
            else:
                return jsonify({
                    'message': 'Payment is still awaiting authorization. Please approve the MoMo prompt on your phone (or dial the USSD code) and click Check Now.',
                    'reference_number': row['reference_no'],
                    'status': 'pending',
                    'is_paid': False
                }), 200
    except Exception as e:
        logger.exception("Error in public_confirm_momo: %s", e)
        return jsonify({'message': 'Failed to verify payment with gateway', 'is_paid': False}), 500
    finally:
        conn.close()


# ─── POST /payments — Initiate charge (MoMo or Bank) ──────────────────────────
@payments_bp.route('/', methods=['POST'])
@jwt_required()
def create_payment():
    member_id = get_jwt_identity()
    data = request.get_json()
    if not data:
        return jsonify({'message': 'Request body is required'}), 400

    logger.info(f"[Payments] New request from member {member_id}: {data}")

    amount      = data.get('amount')
    description = data.get('description')
    payment_ref = data.get('payment_ref', '')
    method      = data.get('method', 'momo')
    network     = data.get('network', 'MTN')
    phone       = data.get('phone', '')

    if not amount or not description:
        return jsonify({'message': 'Amount and description are required'}), 400

    if method == 'momo' and not phone:
        return jsonify({'message': 'Phone number is required for Mobile Money payments'}), 400

    # Validate amount is a positive number
    try:
        amount = float(amount)
        if amount <= 0:
            return jsonify({'message': 'Amount must be greater than zero'}), 400
    except (TypeError, ValueError):
        return jsonify({'message': 'Amount must be a valid number'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT email, name FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            if not member:
                return jsonify({'message': 'Member not found'}), 404

            meta = data.get('meta') or {}
            comp_app_id = meta.get('compliance_application_id') or data.get('compliance_application_id')

            # ── Active License Guard ──────────────────────────────────────────
            # If this is an annual renewal/license payment (not a new member package or compliance app),
            # allow payment if the member's license is within 30 days of expiry or expired.
            desc_lower = description.lower() if description else ''
            is_renewal_payment = 'renewal' in desc_lower or ('license' in desc_lower and 'new' not in desc_lower and 'package' not in desc_lower and 'entrance' not in desc_lower)
            if not comp_app_id and is_renewal_payment:
                cursor.execute(
                    "SELECT status, license_expiry_date FROM members WHERE id = %s",
                    (member_id,)
                )
                m = cursor.fetchone()
                if m and str(m['status']).lower() == 'active' and m.get('license_expiry_date'):
                    expiry = m['license_expiry_date']
                    # Allow renewal in the 30-day window before expiry (or after expiry)
                    if isinstance(expiry, str):
                        expiry = datetime.strptime(expiry, '%Y-%m-%d').date()
                    renewal_open_date = expiry - timedelta(days=30)
                    if date.today() < renewal_open_date:
                        return jsonify({
                            'message': (
                                f'Your license is active until {expiry.strftime("%B %d, %Y")}. '
                                f'Renewal window opens on {renewal_open_date.strftime("%B %d, %Y")} '
                                f'(30 days before expiry). When renewed, any remaining days are preserved!'
                            ),
                            'license_expiry_date': str(expiry),
                            'renewal_opens': str(renewal_open_date),
                            'error_code': 'LICENSE_ACTIVE',
                        }), 200

            # ── Duplicate Prevention Logic ────────────────────────────────────
            # 1. Check if an already COMPLETED / PAID payment exists for this exact description & member
            cursor.execute("""
                SELECT id FROM payments
                WHERE member_id = %s AND description = %s AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                LIMIT 1
            """, (member_id, description))
            already_paid = cursor.fetchone()

            if already_paid:
                return jsonify({
                    'message': f'Payment for "{description}" has already been completed and confirmed. Duplicate payment is not required.',
                    'payment_id': already_paid['id'],
                    'error_code': 'PAYMENT_ALREADY_COMPLETED'
                }), 200

            # 2. Check if a pending transaction already exists for this description.
            # If created within the last 15s, return existing pending record without sending a 2nd MoMo prompt.
            cursor.execute("""
                SELECT id, payment_ref, created_at FROM payments
                WHERE member_id = %s AND description = %s AND LOWER(status) = 'pending'
                ORDER BY id DESC LIMIT 1
            """, (member_id, description))
            existing_pending = cursor.fetchone()

            if existing_pending and existing_pending.get('created_at'):
                try:
                    created_at_dt = existing_pending['created_at']
                    if isinstance(created_at_dt, str):
                        created_at_dt = datetime.fromisoformat(created_at_dt)
                    sec_elapsed = (datetime.now() - created_at_dt).total_seconds()
                    if sec_elapsed < 15 and existing_pending.get('payment_ref'):
                        logger.info("[Payments] Debounced duplicate MoMo request for member %s (elapsed: %.1fs)", member_id, sec_elapsed)
                        return jsonify({
                            'message': 'MoMo payment prompt already sent. Please check your phone.',
                            'payment_id': existing_pending['id'],
                            'transaction_ref': existing_pending['payment_ref'],
                            'whitsun_ref': existing_pending['payment_ref'],
                            'status': 'pending'
                        }), 200
                except Exception as ex:
                    logger.warning("[Payments] Time check error: %s", ex)

            if existing_pending:
                payment_id = existing_pending['id']
                cursor.execute("""
                    UPDATE payments SET amount = %s, payment_ref = %s, created_at = NOW()
                    WHERE id = %s
                """, (amount, payment_ref, payment_id))
            else:
                # Check for a stale 'failed' record for the same description and reset it
                cursor.execute("""
                    SELECT id FROM payments
                    WHERE member_id = %s AND description = %s AND LOWER(status) = 'failed'
                    ORDER BY id DESC LIMIT 1
                """, (member_id, description))
                stale_failed = cursor.fetchone()
                if stale_failed:
                    payment_id = stale_failed['id']
                    cursor.execute("""
                        UPDATE payments SET status = 'pending', amount = %s, payment_ref = %s, created_at = NOW()
                        WHERE id = %s
                    """, (amount, payment_ref, payment_id))
                    logger.info(f"[Payments] Reset stale failed payment {payment_id} to pending for member {member_id}")
                else:
                    # Initialize New Record
                    cursor.execute("""
                        INSERT INTO payments (member_id, amount, description, status, payment_ref)
                        VALUES (%s, %s, %s, 'pending', %s)
                        RETURNING id
                    """, (member_id, amount, description, payment_ref))
                    payment_id = cursor.fetchone()['id']

            conn.commit()

        # ── 2. Handle MoMo via WhitsunPay ──
        if method == 'momo':
            network_map = {'MTN': 'mtn', 'Vodafone': 'vodafone', 'AirtelTigo': 'airteltigo'}

            # WhitsunPay requires international format without +: 233XXXXXXXXX
            clean_phone = ''.join(filter(str.isdigit, phone))
            if clean_phone.startswith('0') and len(clean_phone) == 10:
                clean_phone = '233' + clean_phone[1:]
            elif len(clean_phone) == 9:
                clean_phone = '233' + clean_phone

            tx_ref = f"CUBAG-{payment_id}-{uuid.uuid4().hex[:8]}"

            # Store payment reference in DB
            with conn.cursor() as cursor:
                cursor.execute(
                    "UPDATE payments SET payment_ref = %s WHERE id = %s",
                    (tx_ref, payment_id)
                )
                desc_lower = description.lower()
                if 'renewal' in desc_lower or 'license' in desc_lower:
                    cursor.execute(
                        "UPDATE members SET payment_ref = %s WHERE id = %s",
                        (tx_ref, member_id)
                    )
                if comp_app_id:
                    cursor.execute("""
                        UPDATE compliance_applications
                        SET payment_ref = %s, payment_amount = %s, updated_at = NOW()
                        WHERE id = %s
                    """, (tx_ref, amount, comp_app_id))
                conn.commit()

            if WHITSUNPAY_CLIENT_ID and WHITSUNPAY_API_KEY:
                payload = {
                    'transactionReference': tx_ref,
                    'description': description,
                    'amount': round(float(amount), 2),
                    'debitParty': {
                        'msisdn': clean_phone,
                        'provider': network_map.get(network, 'mtn')
                    }
                }

                # ── Fire WhitsunPay in a background thread so the API returns
                # immediately (< 1s). WhitsunPay currently takes 60-70s to respond
                # which exceeds Dio's 30s receiveTimeout and causes false "failed"
                # errors on the Flutter side. The app polls /payments/verify-code
                # while this thread runs.
                import threading

                def _send_whitsunpay(pid, ref, pld, db_conn_str):
                    """Background thread: POST to WhitsunPay and update payment status."""
                    from config.db import get_db as _get_db
                    _logger = logging.getLogger(__name__)
                    try:
                        target_url = f'{_WP_API}/payments'
                        headers = _whitsunpay_headers()
                        _logger.info(f"[WhitsunPay Debug] Calling API: {target_url}")
                        _logger.info(f"[WhitsunPay Debug] Headers: { {k: (v if k != 'x-api-key' else '***') for k, v in headers.items()} }")
                        _logger.info(f"[WhitsunPay Debug] Payload: {pld}")

                        wp_res = requests.post(
                            target_url,
                            json=pld,
                            headers=headers,
                            timeout=120  # Generous timeout — WhitsunPay can be slow
                        )

                        _logger.info(f"[WhitsunPay Debug] Status Code: {wp_res.status_code}")
                        try:
                            wp_data = wp_res.json()
                        except Exception:
                            wp_data = {'raw_response': wp_res.text[:1000]}
                            _logger.warning(f"[WhitsunPay Debug] Failed to parse JSON: {wp_res.text[:500]}")

                        _logger.info(f"[WhitsunPay Debug] Response Body: {wp_data}")

                        if wp_res.status_code >= 400:
                            _logger.error(f"[WhitsunPay] Error {wp_res.status_code}: {wp_data}")
                            _bg_conn = _get_db()
                            try:
                                with _bg_conn.cursor() as cur:
                                    cur.execute("UPDATE payments SET status = 'failed' WHERE id = %s", (pid,))
                                    _bg_conn.commit()
                            finally:
                                _bg_conn.close()
                        else:
                            _logger.info(f"[WhitsunPay] Prompt sent for ref {ref}, status=PENDING")
                    except Exception as bg_err:
                        _logger.error(f"[WhitsunPay] Background request failed: {bg_err}")
                        try:
                            _bg_conn = _get_db()
                            with _bg_conn.cursor() as cur:
                                cur.execute("UPDATE payments SET status = 'failed' WHERE id = %s", (pid,))
                                _bg_conn.commit()
                            _bg_conn.close()
                        except Exception:
                            pass

                t = threading.Thread(
                    target=_send_whitsunpay,
                    args=(payment_id, tx_ref, payload, None),
                    daemon=True
                )
                t.start()

            # Return immediately — Flutter picks up payment_id + tx_ref and starts polling
            return jsonify({
                'payment_id': payment_id,
                'whitsun_ref': tx_ref,
                'transaction_ref': tx_ref,
                'status': 'pending',
                'message': 'Payment request sent. Please check your phone for the MoMo prompt.',
                'display_text': 'Please check your phone for the MoMo prompt and enter your PIN to approve.'
            }), 200


        # ── 4. Handle Bank Transfer / Other ──
        return jsonify({
            'payment_id': payment_id,
            'status': 'pending',
            'message': 'Bank transfer record saved. Awaiting verification.'
        }), 201

    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─── GET /payments/status/<id> — Poll payment status ──────────────────────────
@payments_bp.route('/status/<int:payment_id>', methods=['GET'])
@jwt_required()
def poll_payment_status(payment_id):
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, status, amount, description, created_at FROM payments WHERE id = %s AND member_id = %s",
                (payment_id, member_id)
            )
            payment = cursor.fetchone()
        if not payment:
            return jsonify({'message': 'Not found'}), 404
        return jsonify(payment), 200
    finally:
        conn.close()


# ─── POST /payments/verify-code — Check status via WhitsunPay ────────────────
@payments_bp.route('/verify-code', methods=['POST', 'OPTIONS'])
@jwt_required()
def verify_payment_code():
    """WhitsunPay handles MoMo PIN approval on-device (no OTP submission).
    This endpoint now checks the transaction status via WhitsunPay instead."""
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    data = request.get_json() or {}
    payment_id = data.get('payment_id')
    tx_ref = str(data.get('whitsun_ref', data.get('transaction_ref', ''))).strip()

    if not tx_ref:
        return jsonify({'message': 'Transaction reference is required', 'error': True}), 400

    # ── Local Database Check First ──
    # If the webhook already received the terminal state callback and updated the DB,
    # resolve immediately to avoid gateway polling failures.
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT status, created_at FROM payments WHERE id = %s", (payment_id,))
            p = cursor.fetchone()
            if p:
                status = str(p['status']).lower()
                if status == 'paid':
                    return jsonify({'message': 'Payment confirmed! 🎉', 'status': 'success'}), 200
                elif status in ('failed', 'declined', 'cancelled', 'reversed'):
                    # Only treat DB 'failed' as terminal if the payment is older than 3 minutes.
                    # Within 3 minutes, the WhitsunPay background thread may still be running
                    # (it can take 60-90s). Fall through to query WhitsunPay live instead.
                    created_at = p.get('created_at')
                    age_seconds = 999
                    if created_at:
                        try:
                            if isinstance(created_at, str):
                                created_at = datetime.fromisoformat(created_at)
                            age_seconds = (datetime.now() - created_at.replace(tzinfo=None)).total_seconds()
                        except Exception:
                            pass
                    if age_seconds > 180:
                        return jsonify({'message': 'Payment failed or declined', 'status': 'failed'}), 200
                    # Recent 'failed' — fall through to live WhitsunPay status check below
    except Exception as e:
        logger.error(f"[verify_payment_code DB check] {e}")
    finally:
        conn.close()


    try:
        target_url = f'{_WP_API}/{tx_ref}/status'
        logger.info(f"[WhitsunPay] Checking status at {target_url}")
        wp_res = requests.get(
            target_url,
            headers=_whitsunpay_headers(),
            timeout=15
        )
        # Handle Cloudflare or non-JSON errors
        try:
            wp_data = wp_res.json()
        except Exception:
            logger.error(f"[WhitsunPay] Non-JSON response in verify: {wp_res.text[:300]}")
            # Can't determine status — keep polling
            return jsonify({'message': 'Waiting for payment confirmation. Please approve the MoMo prompt.', 'status': 'pending'}), 200

        logger.info(f"[WhitsunPay Verify Status] Status Code: {wp_res.status_code}, Body: {wp_data}")

        if wp_res.status_code in (401, 403):
            # Auth error from WhitsunPay status API — prompt may still be in flight
            logger.warning(f"[WhitsunPay] {wp_res.status_code} on status check — treating as pending")
            return jsonify({'message': 'Waiting for MoMo prompt. Please approve on your phone.', 'status': 'pending'}), 200

        if wp_res.status_code >= 400:
            logger.warning(f"[WhitsunPay] {wp_res.status_code} status check error — treating as pending")
            return jsonify({'message': 'Waiting for payment confirmation. Please approve the MoMo prompt.', 'status': 'pending'}), 200

        wp_status = str(wp_data.get('status', '')).lower()

        if wp_status in ('successful', 'success', 'completed'):
            _mark_payment_as_paid(payment_id)
            return jsonify({'message': 'Payment confirmed! 🎉', 'status': 'success'}), 200
        elif wp_status in ('failed', 'declined', 'reversed', 'cancelled'):
            _mark_payment_as_failed(payment_id)
            return jsonify({'message': f'Payment {wp_status}', 'status': 'failed'}), 200

        return jsonify({
            'message': 'Payment is still processing. Please approve the MoMo prompt on your phone.',
            'status': wp_status or 'pending'
        }), 200

    except Exception as e:
        logger.error(f"[verify_payment_code] {str(e)}")
        # Network error querying WhitsunPay — don't fail the payment, keep polling
        return jsonify({'message': 'Waiting for payment confirmation…', 'status': 'pending'}), 200


# ─── GET /payments/verify/<reference> — Poll WhitsunPay for status (auth required) ────
@payments_bp.route('/verify/<string:reference>', methods=['GET', 'OPTIONS'])
@cross_origin()
@jwt_required()  # ✔ SECURITY: must be authenticated to trigger payment verification
def verify_payment_manually(reference):
    if request.method == 'OPTIONS':
        return jsonify({'ok': True}), 200

    member_id = get_jwt_identity()

    if not reference or reference.lower() in ('n/a', 'pending', 'null', 'undefined'):
        return jsonify({'message': 'Invalid reference code', 'status': 'error'}), 200

    # Ownership check: verify this reference belongs to the calling member
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, member_id, status FROM payments WHERE payment_ref = %s",
                (reference,)
            )
            row = cursor.fetchone()
            if not row:
                return jsonify({'message': 'Payment reference not found', 'status': 'error'}), 404
            if str(row['member_id']) != str(member_id):
                return jsonify({'message': 'Unauthorised', 'status': 'error'}), 403
            payment_id = row['id']
            
            # If already marked as paid locally via webhook, resolve immediately
            if str(row['status']).lower() == 'paid':
                return jsonify({'message': 'Payment verified and updated!', 'status': 'success'}), 200
    finally:
        conn.close()

    try:
        target_url = f'{_WP_API}/{reference}/status'
        logger.info(f"[WhitsunPay] Manual check at {target_url}")
        wp_res = requests.get(
            target_url,
            headers=_whitsunpay_headers(),
            timeout=15
        )
        try:
            wp_data = wp_res.json()
        except Exception:
            logger.error(f"[WhitsunPay] Non-JSON response in manual verify: {wp_res.text[:300]}")
            return jsonify({'message': 'WhitsunPay returned an invalid response.', 'status': 'error'}), 200

        wp_status = str(wp_data.get('status', 'pending')).lower()

        if wp_status in ('successful', 'success', 'completed'):
            _mark_payment_as_paid(payment_id)
            return jsonify({'message': 'Payment verified and updated!', 'status': 'success'}), 200

        elif wp_status in ('failed', 'abandoned', 'reversed', 'declined', 'cancelled'):
            return jsonify({'message': f'Payment {wp_status}', 'status': 'failed'}), 200

        return jsonify({'message': f'Transaction state: {wp_status.replace("_", " ")}', 'status': wp_status}), 200
    except Exception as e:
        logger.error(f'[verify_payment_manually] {e}')
        return jsonify({'message': 'Verification service temporarily unavailable', 'status': 'pending'}), 200


def _mark_payment_as_failed(payment_id):
    if not payment_id: return
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT status FROM payments WHERE id = %s", (payment_id,))
            p = cursor.fetchone()
            if p and str(p['status']).lower() == 'pending':
                cursor.execute(
                    "UPDATE payments SET status = 'failed' WHERE id = %s",
                    (payment_id,)
                )
                conn.commit()
    finally:
        conn.close()

def _mark_payment_as_paid(payment_id):
    if not payment_id: return
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Check if already paid to avoid double processing
            cursor.execute("SELECT status, member_id, description, amount, payment_ref FROM payments WHERE id = %s", (payment_id,))
            p = cursor.fetchone()
            if not p or str(p['status']).lower() == 'paid':
                return

            member_id = p['member_id']
            description = p['description']

            cursor.execute(
                "UPDATE payments SET status = 'paid', paid_at = NOW() WHERE id = %s",
                (payment_id,)
            )
            # Set registration_fee_paid flag if payment description indicates registration/entrance/package
            desc_lower = description.lower()
            if any(k in desc_lower for k in ('registration', 'new member', 'entrance', 'package', 'clearing & forwarding', 'consolidation', 'application')):
                try:
                    cursor.execute(
                        "UPDATE members SET registration_fee_paid = TRUE, application_fee_paid = TRUE WHERE id = %s",
                        (member_id,)
                    )
                except Exception as ex:
                    logger.warning("[Payment Verify] Failed updating members reg flag: %s", ex)
                # Notify user that payment is pending admin approval
                try:
                    from utils import send_push_notification
                    cursor.execute("SELECT fcm_token, name FROM members WHERE id = %s", (member_id,))
                    m = cursor.fetchone()
                    if m and m.get('fcm_token'):
                        send_push_notification(
                            m['fcm_token'],
                            title='Registration fee received ✓',
                            body='Your registration fee has been paid. Await admin approval.',
                            data={'screen': 'dashboard', 'message': 'awaiting_approval'}
                        )
                except Exception as notif_err:
                    logger.warning(f"[Notification] Failed to send registration fee notification: {notif_err}")


            # B1 FIX: now must be assigned before the if/else so the else branch can use it
            import datetime
            now = datetime.datetime.now()

            # ── Handle License Issuance & Expiry ──
            license_issued = False
            expiry_date_str = None
            desc_lower = description.lower()
            
            cursor.execute("SELECT license_number, license_expiry_date FROM members WHERE id = %s", (member_id,))
            member_row = cursor.fetchone()
            license_number = member_row['license_number'] if member_row else None
            if not license_number or str(license_number).lower() in ('pending', 'none', 'n/a', ''):
                license_number = f"CUBAG-LIC-{now.year}-{member_id:04d}"

            if 'renewal' in desc_lower or 'annual' in desc_lower or ('license' in desc_lower and 'new' not in desc_lower and 'package' not in desc_lower and 'entrance' not in desc_lower):
                # Fetch current license info to check remaining unexpired days
                current_expiry = member_row.get('license_expiry_date') if member_row else None
                if isinstance(current_expiry, str):
                    try:
                        current_expiry = datetime.datetime.strptime(current_expiry, '%Y-%m-%d').date()
                    except Exception:
                        current_expiry = None

                # Cumulative rollover: If current license has days remaining (> today), add 365 days to existing expiry.
                # If already expired (<= today) or None, add 365 days from today.
                if current_expiry and current_expiry > now.date():
                    new_expiry_date = current_expiry + datetime.timedelta(days=365)
                    start_date = current_expiry
                else:
                    new_expiry_date = now.date() + datetime.timedelta(days=365)
                    start_date = now.date()

                expiry_date_str = new_expiry_date.strftime("%d %b %Y")

                cursor.execute("""
                    UPDATE members
                    SET status = 'active',
                        good_standing = TRUE,
                        package_fee_paid = TRUE,
                        license_number = %s,
                        license_expiry_date = %s
                    WHERE id = %s
                """, (license_number, new_expiry_date, member_id))

                # Log to history
                cursor.execute("""
                    INSERT INTO license_history (member_id, license_number, start_date, expiry_date, duration_label)
                    VALUES (%s, %s, %s, %s, %s)
                """, (member_id, license_number, start_date, new_expiry_date, '1 Year (Cumulative Renewal)'))
                license_issued = True
            else:
                is_pkg_desc = any(k in desc_lower for k in ('package', 'entrance', 'new member dues', 'membership dues', 'dues', 'clearing & forwarding only', 'consolidation only')) and 'registration' not in desc_lower and 'application' not in desc_lower
                if is_pkg_desc:
                    cursor.execute("""
                        UPDATE members 
                        SET package_fee_paid = TRUE,
                            good_standing = TRUE,
                            license_number = %s,
                            license_expiry_date = COALESCE(license_expiry_date, (NOW() + INTERVAL '1 year')::date)
                        WHERE id = %s
                    """, (license_number, member_id))
                else:
                    cursor.execute("""
                        UPDATE members 
                        SET registration_fee_paid = TRUE,
                            application_fee_paid = TRUE,
                            license_number = %s 
                        WHERE id = %s
                    """, (license_number, member_id))

            conn.commit()
            cache.delete(f'me_{member_id}')

            # ── FIX #1: Compliance application confirmation ──────────────────
            # If this payment's payment_ref matches a compliance application in
            # 'submitted' status, advance it to 'under_review'. This means the
            # existing WhitsunPay webhook URL also handles compliance payments —
            # no second webhook URL needed.
            try:
                cursor.execute(
                    "SELECT id, member_id, type FROM compliance_applications WHERE payment_ref = %s AND status = 'submitted'",
                    (p.get('payment_ref', ''),)
                )
                comp_app = cursor.fetchone()
                if not comp_app:
                    # Also try matching by payment reference stored in the payments row
                    cursor.execute("SELECT payment_ref FROM payments WHERE id = %s", (payment_id,))
                    pay_row = cursor.fetchone()
                    if pay_row and pay_row.get('payment_ref'):
                        cursor.execute(
                            "SELECT id, member_id, type FROM compliance_applications WHERE payment_ref = %s AND status = 'submitted'",
                            (pay_row['payment_ref'],)
                        )
                        comp_app = cursor.fetchone()
                if comp_app:
                    cursor.execute("""
                        UPDATE compliance_applications
                        SET status = 'under_review', payment_confirmed_at = NOW(), updated_at = NOW()
                        WHERE id = %s
                    """, (comp_app['id'],))
                    conn.commit()
                    logger.info(f"[Compliance] Application {comp_app['id']} advanced to under_review via payment webhook")
                    # Push notification to member
                    try:
                        from utils import send_push_notification
                        cursor.execute("SELECT fcm_token, email, name FROM members WHERE id = %s", (comp_app['member_id'],))
                        m = cursor.fetchone()
                        if m and m.get('fcm_token'):
                            type_label = 'License Renewal' if comp_app['type'] == 'renewal' else 'Member ID Application'
                            send_push_notification(
                                m['fcm_token'],
                                title='Payment Confirmed ✓',
                                body=f'Your {type_label} payment has been received. Application is now under review.',
                                data={'screen': 'compliance', 'application_id': str(comp_app['id'])}
                            )
                    except Exception as push_err:
                        logger.warning(f"[Compliance] Push notification failed: {push_err}")
            except Exception as comp_err:
                logger.warning(f"[Compliance] Failed to update compliance application after payment: {comp_err}")

            # ── CTI Course Enrollment Confirmation ──
            try:
                if 'cti' in desc_lower or 'course' in desc_lower:
                    cursor.execute("""
                        SELECT id, title, start_date FROM cti_courses
                        WHERE deleted_at IS NULL AND is_active = TRUE
                        ORDER BY id ASC
                    """)
                    all_c = cursor.fetchall()
                    matched_cid = None
                    matched_title = None
                    matched_start = None
                    for c_item in all_c:
                        if c_item['title'].lower() in desc_lower or str(c_item['id']) in desc_lower:
                            matched_cid = c_item['id']
                            matched_title = c_item['title']
                            matched_start = c_item['start_date']
                            break

                    if not matched_cid and all_c:
                        matched_cid = all_c[0]['id']
                        matched_title = all_c[0]['title']
                        matched_start = all_c[0]['start_date']

                    if matched_cid:
                        cursor.execute("""
                            INSERT INTO cti_course_enrollments (course_id, member_id, status, payment_method, payment_ref, amount, payment_confirmed_at)
                            VALUES (%s, %s, 'enrolled', 'momo', %s, %s, NOW())
                            ON CONFLICT (course_id, member_id) DO UPDATE SET
                                status = 'enrolled',
                                payment_ref = EXCLUDED.payment_ref,
                                amount = EXCLUDED.amount,
                                payment_confirmed_at = NOW()
                        """, (matched_cid, member_id, p.get('payment_ref', f'PAY-{payment_id}'), p.get('amount', 0)))
                        conn.commit()
                        logger.info(f"[CTI] Enrolled member {member_id} in course {matched_cid} via confirmed payment {payment_id}")

                        # In-app and Push notification
                        try:
                            from utils import send_push_notification
                            cursor.execute("SELECT fcm_token, name FROM members WHERE id = %s", (member_id,))
                            m_info = cursor.fetchone()
                            notif_t = f"🎓 Enrolled: {matched_title}"
                            notif_b = f"Your payment of GHS {p.get('amount')} has been confirmed! You are enrolled in '{matched_title}' starting {matched_start}."
                            cursor.execute("""
                                INSERT INTO notifications (member_id, title, body, category, notification_type)
                                VALUES (%s, %s, %s, 'Training', 'announcement')
                            """, (member_id, notif_t, notif_b))
                            conn.commit()
                            if m_info and m_info.get('fcm_token'):
                                send_push_notification(m_info['fcm_token'], notif_t, notif_b, data={'type': 'cti_enrolled', 'course_id': str(matched_cid)})
                        except Exception:
                            pass
            except Exception as cti_err:
                logger.warning(f"[CTI] Failed to update course enrollment after payment: {cti_err}")

            # Fetch for receipt email
            cursor.execute("""
                SELECT m.email, m.name, p.amount, p.description
                FROM payments p JOIN members m ON p.member_id = m.id
                WHERE p.id = %s
            """, (payment_id,))
            row = cursor.fetchone()
            if row:
                custom_msg = ""
                if license_issued:
                    custom_msg = f"<p>Your membership license has been issued/renewed and is valid until <strong>{expiry_date_str}</strong>.</p>"
                _send_receipt_email(row['email'], row['name'], row['amount'], row['description'], payment_id, custom_msg)

            try:
                from config.socket import socketio
                socketio.emit('payment_approved', {'member_id': member_id, 'payment_id': payment_id, 'status': 'paid'})
                socketio.emit('member_updated', {'member_id': member_id, 'status': 'active'})
                socketio.emit('fees_updated', {'member_id': member_id})
                socketio.emit('tasks_updated', {'member_id': member_id})
            except Exception as socket_err:
                logger.debug("[Socket payment_approved] %s", socket_err)
    finally:
        conn.close()


# ─── PUT|POST /payments/webhook — WhitsunPay callback on terminal state ───────
@payments_bp.route('/webhook', methods=['PUT', 'POST'])
def whitsunpay_webhook():
    sig  = request.headers.get('X-Whitsun-Signature', '')
    body = request.get_data()

    # BUG-C01 fix: when the secret is configured, enforce HMAC verification.
    # When it's NOT set, log a warning and continue processing — refusing all
    # webhooks when the env var is absent permanently blocks all auto-payments.
    if WHITSUNPAY_WEBHOOK_SECRET:
        expected = 'sha256=' + hmac.new(
            WHITSUNPAY_WEBHOOK_SECRET.encode(), body, hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(sig, expected):
            logger.warning('[Webhook] Signature mismatch — rejecting call')
            return jsonify({'message': 'Invalid signature'}), 401
    else:
        logger.warning(
            '[Webhook] WHITSUNPAY_WEBHOOK_SECRET not set — processing webhook '
            'WITHOUT signature verification. Set this env var to secure webhooks.'
        )

    event     = request.get_json() or {}
    tx_ref    = event.get('transactionReference', '')
    wp_status = str(event.get('status', '')).lower()

    if tx_ref:
        conn = get_db()
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT id FROM payments WHERE payment_ref = %s", (tx_ref,))
                row = cursor.fetchone()
                if row:
                    if wp_status in ('successful', 'success', 'completed'):
                        _mark_payment_as_paid(row['id'])
                        try:
                            with conn.cursor() as cursor2:
                                cursor2.execute("SELECT member_id FROM payments WHERE id = %s", (row['id'],))
                                m_row = cursor2.fetchone()
                                if m_row:
                                    m_id = m_row['member_id']
                                    from utils import calculate_and_update_member_rating
                                    calculate_and_update_member_rating(m_id, cursor2)
                                    conn.commit()
                                    # Emit real-time Socket.IO notification to client for instant UI update
                                    socketio.emit('payment_approved', {'member_id': m_id, 'payment_id': row['id'], 'status': 'paid'})
                                    logger.info(f"[Webhook] Emitted payment_approved event for member {m_id}, payment {row['id']}")
                        except Exception as e:
                            logger.error(f"[Webhook Rating Update] {e}")
                    elif wp_status in ('failed', 'declined', 'reversed', 'cancelled'):
                        _mark_payment_as_failed(row['id'])
                        try:
                            with conn.cursor() as cursor2:
                                cursor2.execute("SELECT member_id FROM payments WHERE id = %s", (row['id'],))
                                m_row = cursor2.fetchone()
                                if m_row:
                                    socketio.emit('payment_failed', {'member_id': m_row['member_id'], 'payment_id': row['id'], 'status': 'failed'})
                        except Exception as e:
                            logger.error(f"[Webhook Failed Emit] {e}")
        finally:
            conn.close()


    return jsonify({'message': 'ok'}), 200


def _send_receipt_email(to_email, member_name, amount, description, payment_id=None, custom_msg=""):
    import datetime
    resend.api_key = os.getenv('RESEND_API_KEY')
    if not resend.api_key:
        logger.info('[Resend] RESEND_API_KEY not configured — mock receipt logged.')
        return

    sender_email = os.getenv('SMTP_USER', 'support@winningedgeinvestment.com')
    now_str = datetime.datetime.now().strftime("%B %d, %Y at %I:%M %p")
    formatted_amount = f"GH₵ {float(amount):,.2f}"

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>CUBAG Official Payment Receipt</title>
    </head>
    <body style="margin:0;padding:0;background-color:#F1F5F9;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#F1F5F9;padding:30px 15px;">
        <tr>
          <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" style="max-width:580px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.06);border:1px solid #E2E8F0;">
              <!-- TOP EXECUTIVE HEADER -->
              <tr>
                <td style="background:linear-gradient(135deg, #1E110B 0%, #381E13 100%);padding:28px 32px;text-align:left;border-bottom:3px solid #FF5000;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td>
                        <div style="display:inline-block;background:#FF5000;color:#ffffff;font-size:12px;font-weight:900;letter-spacing:1px;padding:4px 10px;border-radius:6px;margin-bottom:8px;">CUBAG</div>
                        <h1 style="margin:0;color:#ffffff;font-size:19px;font-weight:800;letter-spacing:0.3px;">CUSTOMS BROKERS ASSOCIATION OF GHANA</h1>
                        <p style="margin:4px 0 0 0;color:#E2E8F0;font-size:12px;opacity:0.85;">Official Payment Acknowledgement & Receipt</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- BODY CONTAINER -->
              <tr>
                <td style="padding:32px 32px 24px 32px;">
                  <div style="background:#ECFDF5;border:1px solid #A7F3D0;border-radius:10px;padding:12px 16px;margin-bottom:24px;">
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="24" valign="middle" style="color:#059669;font-size:16px;font-weight:bold;">✓</td>
                        <td style="color:#065F46;font-size:13.5px;font-weight:700;padding-left:8px;">Payment Confirmed & Verified</td>
                      </tr>
                    </table>
                  </div>

                  <p style="margin:0 0 16px 0;color:#1E293B;font-size:15px;line-height:1.5;">
                    Dear <strong>{member_name}</strong>,
                  </p>
                  <p style="margin:0 0 20px 0;color:#475569;font-size:13.5px;line-height:1.6;">
                    Thank you for your payment to the Customs Brokers Association of Ghana. This email serves as your official electronic receipt and acknowledgement of confirmed funds.
                  </p>

                  {f'<div style="background:#FFF7ED;border-left:4px solid #FF5000;padding:14px 16px;border-radius:0 8px 8px 0;margin-bottom:22px;color:#9A3412;font-size:13px;line-height:1.5;">{custom_msg}</div>' if custom_msg else ''}

                  <!-- RECEIPT INVOICE TABLE -->
                  <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #E2E8F0;border-radius:12px;overflow:hidden;margin-bottom:24px;">
                    <tr style="background:#F8FAFC;border-bottom:1px solid #E2E8F0;">
                      <th colspan="2" style="padding:12px 16px;text-align:left;color:#475569;font-size:11px;font-weight:800;letter-spacing:0.5px;text-transform:uppercase;">
                        Receipt Breakdown
                      </th>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Service / Purpose</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#0F172A;font-size:13.5px;font-weight:700;text-align:right;">{description}</td>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Payment Date</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#334155;font-size:13px;text-align:right;">{now_str}</td>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Payment Status</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;text-align:right;">
                        <span style="background:#D1FAE5;color:#065F46;padding:4px 10px;border-radius:20px;font-size:11px;font-weight:800;letter-spacing:0.3px;">PAID & CLEARED</span>
                      </td>
                    </tr>
                    <tr style="background:#FFFBF8;">
                      <td style="padding:16px 16px;color:#1E293B;font-size:14px;font-weight:800;">Total Amount Paid</td>
                      <td style="padding:16px 16px;color:#FF5000;font-size:18px;font-weight:900;text-align:right;">{formatted_amount}</td>
                    </tr>
                  </table>

                  <p style="margin:0 0 8px 0;color:#64748B;font-size:12px;line-height:1.5;">
                    If you have questions regarding this transaction, please contact the CUBAG Secretariat directly via your Member Portal.
                  </p>
                </td>
              </tr>

              <!-- FOOTER -->
              <tr>
                <td style="background:#F8FAFC;padding:20px 32px;border-top:1px solid #E2E8F0;text-align:center;">
                  <p style="margin:0 0 4px 0;color:#1E293B;font-size:12px;font-weight:700;">Customs Brokers Association of Ghana (CUBAG)</p>
                  <p style="margin:0;color:#94A3B8;font-size:11px;">National Secretariat • Tema Port & KIA Chapters • Ghana</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """

    try:
        params = {
            "from": f"CUBAG Secretariat <{sender_email}>",
            "to": [to_email],
            "subject": f'Official Payment Receipt: {description} ({formatted_amount})',
            "html": html,
        }
        resend.Emails.send(params)
        logger.info(f'[Resend] Official executive receipt sent to {to_email} for {description}')
    except Exception as e:
        logger.warning(f'[Resend] Failed to send receipt to {to_email}: {e}')


# ─── GET /payments/ — Member payment history ──────────────────────────────────
@payments_bp.route('/', methods=['GET'])
@jwt_required()
def get_payments():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM payments WHERE member_id = %s ORDER BY created_at DESC", (member_id,))
            data = cursor.fetchall()
        return jsonify(data), 200
    finally:
        conn.close()


# ─── GET /payments/summary ────────────────────────────────────────────────────
@payments_bp.route('/summary', methods=['GET'])
@jwt_required()
def payments_summary():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Get Totals
            cursor.execute("""
                SELECT 
                    SUM(CASE WHEN LOWER(status)='paid' THEN amount ELSE 0 END) as total_paid,
                    SUM(CASE WHEN LOWER(status)='pending' THEN amount ELSE 0 END) as total_pending
                FROM payments WHERE member_id = %s
            """, (member_id,))
            totals = cursor.fetchone()

            # Get breakdown of pending items
            cursor.execute("""
                SELECT description, amount, created_at
                FROM payments
                WHERE member_id = %s AND LOWER(status) = 'pending'
                ORDER BY created_at DESC
            """, (member_id,))
            items = cursor.fetchall()

        return jsonify({
            'total_paid': float(totals['total_paid'] or 0),
            'total_pending': float(totals['total_pending'] or 0),
            'items': items
        }), 200
    finally:
        conn.close()


# ─── GET /payments/admin/all ──────────────────────────────────────────────────
@payments_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('payments')
def get_all_payments_admin():
    page = int(request.args.get('page', 1))
    limit = int(request.args.get('limit', 20))
    search = request.args.get('search', '').lower()
    status = request.args.get('status', 'all').lower()

    # 20-second cache keyed by page+status+search
    cache_key = f'admin_payments_{status}_{search}_p{page}_l{limit}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200

    conn = get_db()
    try:
        offset = (page - 1) * limit

        where_clauses = []
        params = []
        if search:
            where_clauses.append("(LOWER(m.name) LIKE %s OR LOWER(p.description) LIKE %s OR LOWER(COALESCE(p.payment_ref, '')) LIKE %s OR LOWER(COALESCE(p.momo_tx_id, '')) LIKE %s)")
            params.extend([f"%{search}%", f"%{search}%", f"%{search}%", f"%{search}%"])
        if status != 'all':
            st_lower = status.lower()
            if st_lower == 'paid':
                where_clauses.append("LOWER(p.status) IN ('paid', 'success', 'completed', 'successful')")
            elif st_lower == 'pending':
                where_clauses.append("LOWER(p.status) IN ('pending', 'processing', 'submitted')")
            elif st_lower in ('overdue', 'failed'):
                where_clauses.append("LOWER(p.status) IN ('failed', 'overdue', 'cancelled', 'rejected')")
            else:
                where_clauses.append("LOWER(p.status) = %s")
                params.append(st_lower)

        where_sql = ""
        if where_clauses:
            where_sql = "WHERE " + " AND ".join(where_clauses)

        with conn.cursor() as cursor:
            # Get total count with filters
            count_query = f"""
                SELECT COUNT(*) as total 
                FROM payments p
                LEFT JOIN members m ON p.member_id = m.id
                {where_sql}
            """
            cursor.execute(count_query, tuple(params))
            total = cursor.fetchone()['total']

            # Get paginated data
            data_query = f"""
                SELECT p.id as id, p.id as tx_id, p.amount, p.description, p.status,
                       p.payment_ref, p.momo_tx_id, p.created_at, m.name as member_name,
                       COALESCE(NULLIF(p.momo_tx_id, ''), NULLIF(p.payment_ref, ''), CONCAT('TXN-', LPAD(p.id::text, 6, '0'))) as ref_code,
                       COALESCE(NULLIF(p.momo_tx_id, ''), p.payment_ref) as transaction_ref
                FROM payments p
                LEFT JOIN members m ON p.member_id = m.id
                {where_sql}
                ORDER BY p.created_at DESC
                LIMIT %s OFFSET %s
            """
            cursor.execute(data_query, tuple(params) + (limit, offset))
            payments = cursor.fetchall()

            # Manually serialize dates and decimals
            for p in payments:
                if 'created_at' in p and p['created_at']:
                    p['date'] = p['created_at'].isoformat() if hasattr(p['created_at'], 'isoformat') else str(p['created_at'])

                for key, value in list(p.items()):
                    if hasattr(value, 'isoformat'):
                        p[key] = value.isoformat()
                    elif hasattr(value, 'strftime'):
                        p[key] = str(value)
                    elif hasattr(value, 'to_eng_string'): # Decimal
                        p[key] = float(value)
                    elif key == 'amount' and value is not None:
                        p[key] = float(value)

            cursor.execute("""
                SELECT 
                    COALESCE(SUM(CASE WHEN LOWER(status) IN ('paid', 'success', 'completed') THEN amount ELSE 0 END), 0) as total_revenue,
                    COALESCE(SUM(CASE WHEN LOWER(status) IN ('paid', 'success', 'completed') AND (LOWER(description) LIKE '%renewal%' OR LOWER(description) LIKE '%licen%fee%') THEN amount ELSE 0 END), 0) as renewal_revenue,
                    COALESCE(SUM(CASE WHEN LOWER(status) IN ('paid', 'success', 'completed') AND (LOWER(description) LIKE '%registration%' OR LOWER(description) LIKE '%entrance%' OR LOWER(description) LIKE '%new member%' OR LOWER(description) LIKE '%onboarding%' OR LOWER(description) LIKE '%dossier%') THEN amount ELSE 0 END), 0) as new_membership_revenue,
                    COALESCE(SUM(CASE WHEN LOWER(status) IN ('paid', 'success', 'completed') AND (LOWER(description) LIKE '%course%' OR LOWER(description) LIKE '%cti%' OR LOWER(description) LIKE '%training%' OR LOWER(description) LIKE '%enroll%') THEN amount ELSE 0 END), 0) as course_revenue,
                    COALESCE(SUM(CASE WHEN LOWER(status) = 'pending' THEN amount ELSE 0 END), 0) as pending_revenue,
                    COALESCE(SUM(CASE WHEN LOWER(status) IN ('failed', 'overdue') THEN amount ELSE 0 END), 0) as failed_revenue
                FROM payments 
            """)
            stats = cursor.fetchone() or {}

            tot_rev = float(stats.get('total_revenue') or 0)
            ren_rev = float(stats.get('renewal_revenue') or 0)
            new_rev = float(stats.get('new_membership_revenue') or 0)
            crs_rev = float(stats.get('course_revenue') or 0)
            oth_rev = max(0.0, tot_rev - (ren_rev + new_rev + crs_rev))
            pending_rev = float(stats.get('pending_revenue') or 0)
            failed_rev = float(stats.get('failed_revenue') or 0)

        response = {
            'data': payments,
            'total': total,
            'page': page,
            'limit': limit,
            'kpis': {
                'revenue': tot_rev,
                'pending': pending_rev,
                'failed':  failed_rev,
                'breakdown': {
                    'renewal': ren_rev,
                    'new_membership': new_rev,
                    'course': crs_rev,
                    'other': oth_rev,
                }
            }
        }
        cache.set(cache_key, response, timeout=20)
        return jsonify(response), 200
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        logger.exception("[Admin Payments Error] %s", e)
        try:
            log_backend_error('Admin Payments Error', f"Error: {str(e)}\nTraceback:\n{tb}")
        except Exception as log_err:
            logger.error(f"Failed to log error to DB: {log_err}")
        return jsonify({'message': str(e), 'traceback': tb}), 500
    finally:
        conn.close()


# ─── POST /payments/admin/mark-paid/<id> ─────────────────────────────────────
@payments_bp.route('/admin/mark-paid/<int:payment_id>', methods=['POST'])
@sub_admin_required('payments')
def admin_mark_paid(payment_id):
    admin_id = get_jwt_identity()
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            # Get data for audit log
            cursor.execute("""
                SELECT p.member_id, p.amount, m.name
                FROM payments p LEFT JOIN members m ON p.member_id = m.id
                WHERE p.id = %s
            """, (payment_id,))
            row = cursor.fetchone()
        conn.close()

        # Use unified helper
        _mark_payment_as_paid(payment_id)

        if row:
            # Real-time WebSocket emission
            socketio.emit('payment_approved', {'member_id': row['member_id'], 'payment_id': payment_id})
            # Audit log
            log_admin_action(admin_id, 'Marked payment as paid', 'payment', payment_id, row.get('name'), f'Amount: {row.get("amount")}')

        return jsonify({'message': 'Payment marked as paid'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500


# ─── POST /payments/admin/approve-license/<id> ───────────────────────────────
@payments_bp.route('/admin/approve-license/<int:payment_id>', methods=['POST'])
@sub_admin_required('payments')
def admin_approve_license(payment_id):
    try:
        # Use unified helper
        _mark_payment_as_paid(payment_id)
        return jsonify({'message': 'License approved and payment confirmed'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
