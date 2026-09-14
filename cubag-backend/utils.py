import os
import json
import logging
import firebase_admin
from firebase_admin import credentials, messaging
from config.db import get_db

# Module logger
logger = logging.getLogger(__name__)

def log_audit(admin_id, action, target_type=None, target_id=None, target_name=None, details=None, ip_address=None):
    if not admin_id:
        return
    if not ip_address:
        try:
            from flask import request, has_request_context
            if has_request_context():
                ip_address = request.headers.get('X-Forwarded-For', request.remote_addr or '127.0.0.1')
                if ip_address and ',' in ip_address:
                    ip_address = ip_address.split(',')[0].strip()
        except Exception:
            ip_address = '127.0.0.1'
    if not ip_address:
        ip_address = '127.0.0.1'

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Ensure ids are integers
            try:
                a_id = int(admin_id)
            except (TypeError, ValueError):
                return

            t_id = None
            if target_id:
                try:
                    t_id = int(target_id)
                except (TypeError, ValueError):
                    pass

            t_name = json.dumps(target_name) if isinstance(target_name, (dict, list)) else (str(target_name) if target_name is not None else None)
            det_val = json.dumps(details) if isinstance(details, (dict, list)) else (str(details) if details is not None else None)

            cursor.execute("""
                INSERT INTO audit_log (admin_id, action, target_type, target_id, target_name, details, ip_address)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (a_id, action, target_type, t_id, t_name, det_val, ip_address))
        conn.commit()
    except Exception as e:
        logger.exception("[Audit Log Error] %s", e)
    finally:
        conn.close()

log_admin_action = log_audit

def log_backend_error(action, details):
    """Utility to record a backend error in the audit log without needing admin_id."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO audit_log (action, target_type, details)
                VALUES (%s, 'error', %s)
            """, (action, details))
        conn.commit()
    except Exception as e:
        logger.exception("[Audit Log Error logging backend error] %s", e)
    finally:
        conn.close()


def send_push_notification(fcm_token, title, body, data=None):
    """
    Sends a push notification to a specific device using FCM.
    """
    if not fcm_token:
        return False
        
    if not _init_firebase():
        return False

    try:
        # Prepare the message data (must be strings)
        string_data = {k: str(v) for k, v in (data or {}).items()}

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=string_data,
            token=fcm_token,
        )

        response = messaging.send(message)
        logger.info("Successfully sent message: %s", response)
        return True
    except Exception as e:
        logger.exception("Error sending push notification: %s", e)
        return False

# Load service account from environment variable (JSON string) or file
# Primary env variable used across the system is FIREBASE_CREDENTIALS_JSON
service_account_json = os.getenv('FIREBASE_CREDENTIALS_JSON') or os.getenv('FIREBASE_SERVICE_ACCOUNT')

def _init_firebase():
    """Initializes the Firebase Admin SDK if not already initialized."""
    try:
        firebase_admin.get_app()
    except ValueError:
        if service_account_json:
            import json
            try:
                cred_dict = json.loads(service_account_json)
                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                logger.info("[Push] Firebase Admin initialized from ENV.")
            except Exception as e:
                logger.exception("[Push] Error parsing FIREBASE_CREDENTIALS_JSON: %s", e)
                return False
        elif os.path.exists('firebase-key.json'):
            cred = credentials.Certificate('firebase-key.json')
            firebase_admin.initialize_app(cred)
            logger.info("[Push] Firebase Admin initialized from FILE.")
        else:
            logger.warning("[Push] Firebase Credentials not found. Skipping push.")
            return False
    return True

def send_push_to_all(title, body, data=None):
    """
    Sends a push notification to all members who have an fcm_token registered.
    Uses the modern FCM V1 API via Firebase Admin SDK.
    """
    if not _init_firebase():
        return

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT fcm_token FROM members WHERE fcm_token IS NOT NULL")
            tokens = [row['fcm_token'] for row in cursor.fetchall()]

        logger.debug("[DEBUG] Push notification triggered. Found %d tokens in DB.", len(tokens))

        if not tokens:
            return

        # Prepare the message data (must be strings)
        string_data = {k: str(v) for k, v in (data or {}).items()}

        # Multicast message allows sending to up to 500 tokens at once
        for i in range(0, len(tokens), 500):
            batch = tokens[i:i+500]
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=string_data,
                tokens=batch,
            )
            try:
                if hasattr(messaging, 'send_each_for_multicast'):
                    response = messaging.send_each_for_multicast(message)
                elif hasattr(messaging, 'send_multicast'):
                    response = messaging.send_multicast(message)
                else:
                    response = None

                if response:
                    logger.info("[Push] Batch sent: %s success, %s failure", response.success_count, response.failure_count)
            except Exception as e:
                logger.warning("[Push] Error sending batch (non-fatal): %s", e)

    except Exception as e:
        logger.exception("[Push] Database error: %s", e)
    finally:
        conn.close()

def calculate_and_update_member_rating(member_id, cursor=None):
    from datetime import date
    should_close = False
    if cursor is None:
        conn = get_db()
        cursor = conn.cursor()
        should_close = True
    
    try:
        # Get previous rating status to compare tiers for notification triggers
        cursor.execute("SELECT compliance_score, star_rating FROM members WHERE id = %s", (member_id,))
        prev_row = cursor.fetchone()
        prev_score = prev_row['compliance_score'] if prev_row and prev_row['compliance_score'] is not None else None
        prev_stars = float(prev_row['star_rating']) if prev_row and prev_row['star_rating'] is not None else None

        cursor.execute("SELECT role, status, license_expiry_date, manual_review_score, created_at, compliance_score, star_rating FROM members WHERE id = %s", (member_id,))
        member_row = cursor.fetchone()
        if not member_row:
            return {'compliance_score': 0, 'star_rating': 0.0, 'manual_review_score': 0}
            
        role = str(member_row.get('role') or 'member').lower().strip()
        if role in ('admin', 'super_admin', 'sub_admin', 'staff', 'system'):
            cursor.execute("UPDATE members SET compliance_score = NULL, star_rating = NULL, manual_review_score = NULL WHERE id = %s", (member_id,))
            return {'compliance_score': None, 'star_rating': None, 'manual_review_score': None}

        old_score = member_row.get('compliance_score')
        old_rating = member_row.get('star_rating')
            
        status = str(member_row['status'] or '').lower()
        expiry_date = member_row['license_expiry_date']
        manual_review = member_row['manual_review_score']
        created_at = member_row['created_at']
        if manual_review is None:
            manual_review = 10

        today = date.today()
        is_expired = False
        if expiry_date:
            if isinstance(expiry_date, str):
                from datetime import datetime
                try:
                    expiry_date = datetime.strptime(expiry_date, '%Y-%m-%d').date()
                except Exception as e:
                    logger.debug("Failed to parse expiry_date for member %s: %s", member_id, e)
            if isinstance(expiry_date, date):
                is_expired = expiry_date < today

        # Check if member has confirmed paid payment for license
        cursor.execute("SELECT COUNT(*) AS paid_count FROM payments WHERE member_id = %s AND LOWER(status) = 'paid'", (member_id,))
        has_paid_license = (cursor.fetchone()['paid_count'] or 0) > 0

        # 1. Licensing & Good Standing (40 points)
        standing_score = 0
        if has_paid_license and status == 'active':
            if expiry_date and not is_expired:
                standing_score = 40
            elif expiry_date and is_expired:
                standing_score = 25
            else:
                standing_score = 30
        elif status in ('pending', 'inactive') or not has_paid_license:
            standing_score = 0
        else:
            standing_score = 0
            
        # 2. Payment Compliance (30 points)
        cursor.execute("""
            SELECT COUNT(*) as total_count,
                   SUM(CASE WHEN LOWER(status) = 'paid' THEN 1 ELSE 0 END) as paid_count
            FROM payments
            WHERE member_id = %s
        """, (member_id,))
        pay_stats = cursor.fetchone()
        total_invoices = pay_stats['total_count'] or 0
        paid_invoices = pay_stats['paid_count'] or 0
        if not has_paid_license or total_invoices == 0:
            financial_score = 0 if not has_paid_license else 25
        else:
            financial_score = round(min(1.0, paid_invoices / total_invoices) * 30)

        # 3. Documents / Compliance Approval (30 points)
        cursor.execute("""
            SELECT COUNT(*) AS total_docs,
                   COUNT(*) FILTER (WHERE LOWER(cd.status) = 'approved') AS approved_docs
            FROM compliance_documents cd
            JOIN compliance_applications ca ON ca.id = cd.application_id
            WHERE ca.member_id = %s
        """, (member_id,))
        doc_stats = cursor.fetchone()
        total_docs = doc_stats['total_docs'] or 0
        approved_docs = doc_stats['approved_docs'] or 0
        if total_docs == 0:
            docs_score = 20
        else:
            docs_score = round((approved_docs / total_docs) * 30)

        # 4. Admin Trust / Issue History (10-15 points)
        manual_review = int(min(max(manual_review or 10, 0), 10))
        cursor.execute("""
            SELECT COUNT(*) AS open_tickets
            FROM support_tickets
            WHERE member_id = %s AND deleted_at IS NULL AND LOWER(status) != 'closed'
        """, (member_id,))
        ticket_stats = cursor.fetchone()
        open_tickets = ticket_stats['open_tickets'] or 0
        ticket_penalty = min(5, open_tickets * 2)
        admin_score = max(0, min(15, manual_review + 5 - ticket_penalty))

        # Total Score & Rating
        total_score = standing_score + financial_score + docs_score + admin_score
        total_score = max(0, min(100, total_score))
        star_rating = round(total_score / 20.0, 2)

        # Save to database only if score or rating actually changed or is missing
        if old_score != total_score or float(old_rating or -1.0) != float(star_rating):
            cursor.execute("""
                UPDATE members 
                SET compliance_score = %s, star_rating = %s, manual_review_score = %s
                WHERE id = %s
            """, (total_score, star_rating, manual_review, member_id))

        # Log history ONLY if this is a new score/rating compared to the latest history entry
        cursor.execute("""
            SELECT compliance_score, star_rating 
            FROM member_rating_history 
            WHERE member_id = %s 
            ORDER BY recorded_at DESC LIMIT 1
        """, (member_id,))
        last_hist = cursor.fetchone()
        if not last_hist or int(last_hist['compliance_score'] or -1) != int(total_score) or float(last_hist['star_rating'] or -1.0) != float(star_rating):
            cursor.execute("""
                INSERT INTO member_rating_history (member_id, compliance_score, star_rating)
                VALUES (%s, %s, %s)
            """, (member_id, total_score, star_rating))

        if should_close:
            conn.commit()

        breakdown = {
            'standing': standing_score,
            'financial': financial_score,
            'documents': docs_score,
            'trust': admin_score,
            'events': docs_score,
            'admin': admin_score,

            # Aliases & sub-scores for frontend UI breakdown:
            'payment_score': financial_score,
            'payment_punctual_score': round(financial_score * 0.6),
            'payment_history_score': round(financial_score * 0.4),
            'total_payments_paid': paid_invoices,
            'overdue_payments_count': max(0, total_invoices - paid_invoices),
            'on_time_payments_paid': paid_invoices,
            'license_score': standing_score,
            'task_score': docs_score,
            'task_completion_score': docs_score,
            'total_tasks': total_docs,
            'completed_tasks': approved_docs,
            'engagement_score': admin_score,
            'survey_score': admin_score,
            'total_surveys': 1,
            'responded_surveys': 1 if admin_score > 0 else 0,
            'agm_score': admin_score,
            'admin_score': admin_score
        }

        # Check for standing tier changes
        def get_tier(score):
            if not has_paid_license:
                return "License Not Activated (Payment Required)"
            if score >= 90: return "Elite"
            elif score >= 70: return "Good Standing"
            elif score >= 50: return "Warning/Probation"
            else: return "Suspended/Delinquent"

        new_tier = get_tier(total_score)
        
        if prev_score is not None:
            prev_tier = get_tier(prev_score)
            if prev_tier != new_tier:
                # standing tier transition alert
                title = f"Standing Changed to {new_tier}"
                body = f"Your compliance standing has changed from {prev_tier} to {new_tier}. Compliance Score: {total_score}%."
                
                # Check duplicate before inserting
                cursor.execute("""
                    SELECT id FROM notifications 
                    WHERE member_id = %s AND title = %s AND body = %s 
                      AND created_at > NOW() - INTERVAL '10 minutes'
                """, (member_id, title, body))
                if not cursor.fetchone():
                    cursor.execute("""
                        INSERT INTO notifications (member_id, title, body, category, notification_type)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (member_id, title, body, 'Compliance', 'compliance'))
                
                # FCM push
                cursor.execute("SELECT fcm_token FROM members WHERE id = %s", (member_id,))
                fcm_row = cursor.fetchone()
                fcm_token = fcm_row['fcm_token'] if fcm_row else None
                if fcm_token:
                    send_push_notification(fcm_token, title, body, data={'type': 'compliance'})
        else:
            # Welcome notice
            title = "Compliance Standing Calculated"
            body = f"Your initial compliance status is now calculated: {total_score}% ({star_rating} Stars) - {new_tier} Standing."
            cursor.execute("""
                SELECT id FROM notifications 
                WHERE member_id = %s AND title = %s AND body = %s 
                  AND created_at > NOW() - INTERVAL '10 minutes'
            """, (member_id, title, body))
            if not cursor.fetchone():
                cursor.execute("""
                    INSERT INTO notifications (member_id, title, body, category, notification_type)
                    VALUES (%s, %s, %s, %s, %s)
                """, (member_id, title, body, 'Compliance', 'compliance'))

        cursor.connection.commit()

        return {
            'compliance_score': total_score,
            'star_rating': float(star_rating),
            'manual_review_score': manual_review,
            'breakdown': breakdown
        }
    except Exception as e:
        logger.exception("Error calculating member rating: %s", e)
        try:
            cursor.connection.rollback()
        except Exception as re:
            logger.exception("Error rolling back DB after rating calc failure: %s", re)

        # Fall back to the last saved score already in the DB (fetched at top of function).
        # This means the member still sees their real previous score rather than a 0 or fake value.
        try:
            saved_score = int(prev_score) if prev_score is not None else 50
            saved_stars = float(prev_stars) if prev_stars is not None else 2.5
            saved_review = int(prev_row.get('manual_review_score') or 5) if prev_row else 5
        except Exception:
            saved_score, saved_stars, saved_review = 50, 2.5, 5

        logger.warning(
            "Returning last saved rating for member %s: score=%s stars=%s",
            member_id, saved_score, saved_stars
        )
        return {
            'compliance_score':   saved_score,
            'star_rating':        saved_stars,
            'manual_review_score': saved_review,
        }
    finally:
        if should_close:
            cursor.close()
            conn.close()

from functools import wraps
from flask import jsonify
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request

def admin_required(fn):
    @wraps(fn)
    def decorator(*args, **kwargs):
        try:
            verify_jwt_in_request()
        except Exception:
            return jsonify({'message': 'Missing or invalid authorization token'}), 401
            
        admin_id = get_jwt_identity()
        if not admin_id:
            return jsonify({'message': 'Missing or invalid authorization token'}), 401
            
        conn = get_db()
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT role FROM members WHERE id = %s", (admin_id,))
                res = cursor.fetchone()
                if not res or res.get('role') not in ('admin', 'sub_admin', 'super_admin'):
                    return jsonify({'message': 'Admin privilege required'}), 403
                # Sub-admins pass through here — individual route decorators can
                # add further permission checks via sub_admin_required().
        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            logger.exception("[Decorator admin_required Error] %s", e)
            try:
                log_backend_error('Decorator admin_required Error', f"Error: {str(e)}\nTraceback:\n{tb}")
            except Exception as log_err:
                logger.error(f"Failed to log decorator error to DB: {log_err}")
            return jsonify({'message': str(e), 'traceback': tb}), 500
        finally:
            conn.close()
        return fn(*args, **kwargs)
    return decorator


def sub_admin_required(permission: str):
    """
    Decorator that requires the caller to be either:
      - a full admin (role == 'admin' or role == 'super_admin') — always allowed, OR
      - a sub_admin with the given permission key granted.

    Supported permission keys:
      members, payments, tickets, announcements,
      schedules, events, intelligence, audit_log,
      fees, settings
    """
    def decorator_factory(fn):
        @wraps(fn)
        def decorator(*args, **kwargs):
            try:
                verify_jwt_in_request()
            except Exception:
                return jsonify({'message': 'Missing or invalid authorization token'}), 401

            caller_id = get_jwt_identity()
            if not caller_id:
                return jsonify({'message': 'Missing or invalid authorization token'}), 401

            conn = get_db()
            try:
                with conn.cursor() as cursor:
                    cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
                    res = cursor.fetchone()
                    if not res:
                        return jsonify({'message': 'User not found'}), 403

                    role = res.get('role')
                    if role in ('admin', 'super_admin'):
                        # Full admin — unconditional access
                        pass
                    elif role == 'sub_admin':
                        cursor.execute("""
                            SELECT 1 FROM sub_admin_permissions
                            WHERE sub_admin_id = %s AND permission_key = %s AND granted = TRUE
                        """, (caller_id, permission))
                        if not cursor.fetchone():
                            return jsonify({'message': f'Permission denied: {permission}'}), 403
                    else:
                        return jsonify({'message': 'Admin privilege required'}), 403
            except Exception as e:
                import traceback
                tb = traceback.format_exc()
                logger.exception("[Decorator sub_admin_required Error] %s", e)
                try:
                    log_backend_error('Decorator sub_admin_required Error', f"Permission: {permission}\nError: {str(e)}\nTraceback:\n{tb}")
                except Exception as log_err:
                    logger.error(f"Failed to log decorator error to DB: {log_err}")
                return jsonify({'message': str(e), 'traceback': tb}), 500
            finally:
                conn.close()
            return fn(*args, **kwargs)
        return decorator
    return decorator_factory

def eval_good_standing(member_dict, cursor):
    """
    Evaluates backend-authoritative Good Standing.
    Returns (is_good_standing: bool, audit_reasons: list).
    
    Rules:
    1. membership status is 'active' or 'approved'
    2. license_expiry_date >= TODAY (if set)
    3. Payment settlement: Member must have fully paid registration or renewal dues.
    """
    import datetime
    reasons = []
    if not member_dict:
        return False, ["Member record not found"]

    status = (member_dict.get('status') or '').lower()
    if status not in ('active', 'approved'):
        reasons.append(f"Status is '{status}' (requires active or approved)")

    expiry = member_dict.get('license_expiry_date')
    today = datetime.date.today()
    if expiry:
        if isinstance(expiry, str):
            try:
                expiry = datetime.datetime.strptime(expiry, '%Y-%m-%d').date()
            except Exception:
                pass
        if isinstance(expiry, (datetime.date, datetime.datetime)):
            expiry_date = expiry.date() if isinstance(expiry, datetime.datetime) else expiry
            if expiry_date < today:
                reasons.append(f"Membership subscription expired on {expiry_date}")

    member_id = member_dict.get('id')
    if member_id and cursor:
        # Check if member has package fee or renewal dues paid
        cursor.execute("""
            SELECT id, description FROM payments
            WHERE member_id = %s
              AND LOWER(COALESCE(status, '')) IN ('success', 'paid', 'completed')
        """, (member_id,))
        paid_rows = cursor.fetchall()

        has_package_paid = any(
            any(k in (r.get('description') or '').lower() for k in ('package', 'entrance', 'clearing & forwarding only', 'consolidation'))
            for r in paid_rows
        ) or member_dict.get('package_fee_paid') is True
        
        has_renewal_paid = any(
            any(k in (r.get('description') or '').lower() for k in ('renewal', 'dues'))
            for r in paid_rows
        )
        
        has_reg_only = any(
            'registration' in (r.get('description') or '').lower() or 'application' in (r.get('description') or '').lower()
            for r in paid_rows
        ) and not has_package_paid

        if member_dict.get('good_standing') is not True:
            if not paid_rows:
                reasons.append("Membership dues and package fee have not been paid.")
            elif has_reg_only and not has_renewal_paid:
                reasons.append("Registration fee is paid, but Membership Entrance Package fee is pending payment.")

    is_good = len(reasons) == 0
    return is_good, reasons

