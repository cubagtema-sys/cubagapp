import logging
import time
from datetime import date, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from config.db import get_db
from utils import send_push_notification, calculate_and_update_member_rating

logger = logging.getLogger(__name__)

def check_expired_licenses():
    logger.info("[Jobs] Running expired license check...")
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            today = date.today()
            window_30d = today + timedelta(days=30)

            # Find active members whose license expires within the next 30 days
            cursor.execute("""
                SELECT id, name, fcm_token, license_expiry_date 
                FROM members 
                WHERE status = 'active' 
                  AND license_expiry_date IS NOT NULL
                  AND license_expiry_date > %s 
                  AND license_expiry_date <= %s
            """, (today, window_30d))
            expiring_members = cursor.fetchall()

            for m in expiring_members:
                exp_date = m['license_expiry_date']
                days_left = (exp_date - today).days

                # Prevent duplicate notification spam: only send if no renewal notification sent in last 24h
                cursor.execute("""
                    SELECT COUNT(*) as cnt FROM notifications 
                    WHERE member_id = %s 
                      AND (title LIKE '%%Renewal%%' OR title LIKE '%%License Expiring%%')
                      AND created_at > NOW() - INTERVAL '24 hours'
                """, (m['id'],))
                already_notified = (cursor.fetchone()['cnt'] > 0)

                if not already_notified:
                    if days_left <= 7:
                        title = f"🔴 Urgent Renewal Notice: {days_left} Days Remaining"
                    else:
                        title = f"Urgent Renewal Reminder: {days_left} Days Remaining"

                    body = (
                        f"Hello {m['name']}, your CUBAG membership expires in {days_left} days on {exp_date}. "
                        f"Renew today — all remaining {days_left} days will be preserved and added to your new 365-day validity!"
                    )

                    if m.get('fcm_token'):
                        send_push_notification(m['fcm_token'], title, body, data={'type': 'license_warning'})

                    cursor.execute("""
                        INSERT INTO notifications (member_id, title, body, category, notification_type)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (m['id'], title, body, 'Compliance', 'reminder'))

            # Find active members whose license has already expired
            cursor.execute("""
                SELECT id, name, fcm_token 
                FROM members 
                WHERE status = 'active' 
                  AND license_expiry_date IS NOT NULL
                  AND license_expiry_date < %s
            """, (today,))
            expired_members = cursor.fetchall()

            for m in expired_members:
                # Update status to suspended
                cursor.execute("UPDATE members SET status = 'suspended' WHERE id = %s", (m['id'],))
                
                if m.get('fcm_token'):
                    title = "License Expired - Account Suspended"
                    body = f"Hello {m['name']}, your license has expired and your account is now suspended. Please renew immediately to restore active standing."
                    send_push_notification(m['fcm_token'], title, body, data={'type': 'license_expired'})
                
                cursor.execute("""
                    INSERT INTO notifications (member_id, title, body, category, notification_type)
                    VALUES (%s, %s, %s, %s, %s)
                """, (m['id'], "License Expired", "Account suspended due to license expiration. Please renew immediately.", 'Compliance', 'alert'))

            conn.commit()

            if expired_members:
                logger.info(f"[Jobs] Suspended {len(expired_members)} members due to expired licenses.")
            if expiring_members:
                logger.info(f"[Jobs] Checked {len(expiring_members)} members within 30-day renewal window.")

    except Exception as e:
        logger.exception(f"[Jobs] Error in check_expired_licenses: {e}")
        conn.rollback()
    finally:
        conn.close()


def run_rating_update_cycle():
    logger.info("[Jobs] Starting full compliance update cycle...")
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id FROM members WHERE role NOT IN ('admin', 'super_admin') AND status = 'active'")
            member_ids = [row['id'] for row in cursor.fetchall()]

            for mid in member_ids:
                try:
                    calculate_and_update_member_rating(mid, cursor)
                    conn.commit()
                except Exception as e:
                    logger.error(f"[Jobs] Failed to update member {mid}: {e}")
                    conn.rollback()
    except Exception as e:
        logger.error(f"[Jobs] Critical cycle error: {e}")
    finally:
        conn.close()

from datetime import date, datetime, timedelta

def check_upcoming_cti_courses():
    logger.info("[Jobs] Running upcoming CTI courses reminder check...")
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Query active enrollments with course details and member details
            cursor.execute("""
                SELECT e.id as enrollment_id, e.member_id, e.status as enrollment_status,
                       c.id as course_id, c.title as course_title, c.start_date, c.mode, c.duration,
                       m.name as member_name, m.email as member_email, m.fcm_token
                FROM cti_course_enrollments e
                JOIN cti_courses c ON c.id = e.course_id
                JOIN members m ON m.id = e.member_id
                WHERE c.deleted_at IS NULL AND c.is_active = TRUE AND e.status = 'enrolled'
            """)
            enrollments = cursor.fetchall()
            today = date.today()

            for en in enrollments:
                start_str = (en.get('start_date') or '').strip()
                course_date = None
                for fmt in ('%d %b %Y', '%d %B %Y', '%Y-%m-%d', '%d/%m/%Y'):
                    try:
                        course_date = datetime.strptime(start_str, fmt).date()
                        break
                    except Exception:
                        pass

                if not course_date:
                    continue

                days_diff = (course_date - today).days

                # Notify if 7 days away, 3 days away, 1 day away, or starting today
                if days_diff in (7, 3, 1, 0):
                    time_desc = "starts today!" if days_diff == 0 else f"starts in {days_diff} day{'s' if days_diff > 1 else ''} on {start_str}."
                    title = f"🎓 CTI Course Alert: {en['course_title']}"
                    body = f"Hello {en['member_name']}, your CTI course '{en['course_title']}' ({en['mode']}) {time_desc} Please check your course schedule & materials."

                    # Send push notification
                    if en.get('fcm_token'):
                        send_push_notification(en['fcm_token'], title, body, data={'type': 'cti_course_reminder', 'course_id': str(en['course_id'])})

                    # Insert in-app notification
                    cursor.execute("""
                        INSERT INTO notifications (member_id, title, body, category, notification_type)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (en['member_id'], title, body, 'Training', 'reminder'))

            conn.commit()
    except Exception as e:
        logger.exception(f"[Jobs] Error in check_upcoming_cti_courses: {e}")
        conn.rollback()
    finally:
        conn.close()


def start_scheduler():
    scheduler = BackgroundScheduler(daemon=True)
    
    # Check licenses daily at 12:00 PM
    scheduler.add_job(check_expired_licenses, 'cron', hour=12, minute=0)
    
    # Check upcoming CTI courses daily at 9:00 AM
    scheduler.add_job(check_upcoming_cti_courses, 'cron', hour=9, minute=0)

    # Update ratings daily at 2:00 AM
    scheduler.add_job(run_rating_update_cycle, 'cron', hour=2, minute=0)
    
    scheduler.start()
    logger.info("[Jobs] APScheduler started.")

