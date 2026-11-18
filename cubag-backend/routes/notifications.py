from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import sub_admin_required

notifications_bp = Blueprint('notifications', __name__)

NOTIFICATION_CATEGORIES = ('Compliance', 'System', 'Payment', 'Meeting', 'Announcement')


@notifications_bp.route('/', methods=['GET'])
@jwt_required()
def get_notifications():
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # 1. Fetch direct notifications for member or broadcast notifications
            cursor.execute("""
                SELECT id, title, body, category, notification_type,
                       read_at, created_at
                FROM notifications
                WHERE deleted_at IS NULL AND (member_id = %s OR member_id IS NULL)
                ORDER BY created_at DESC
            """, (user_id,))
            raw_notes = [dict(r) for r in cursor.fetchall()]

            # Deduplicate notes with identical title & body (keep most recent)
            seen_signatures = set()
            direct_notes = []
            for n in raw_notes:
                sig = (n.get('title', '').strip().lower(), n.get('body', '').strip().lower())
                if sig not in seen_signatures:
                    seen_signatures.add(sig)
                    direct_notes.append(n)

            # 2. Include recent announcements as system notifications
            cursor.execute("""
                SELECT id, title, body, category, created_at
                FROM announcements
                WHERE deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT 25
            """)
            announcements = cursor.fetchall()

            existing_titles = {n['title'].strip().lower() for n in direct_notes if n.get('title')}

            for a in announcements:
                t_lower = (a.get('title') or '').strip().lower()
                if t_lower not in existing_titles:
                    c_at = a.get('created_at')
                    time_str = c_at.isoformat() if hasattr(c_at, 'isoformat') else str(c_at or '')
                    direct_notes.append({
                        'id': f"ann_{a['id']}",
                        'title': a.get('title') or 'Announcement',
                        'body': a.get('body') or '',
                        'category': a.get('category') or 'Announcement',
                        'notification_type': 'announcement',
                        'read_at': None,
                        'created_at': time_str
                    })
                    existing_titles.add(t_lower)

            import re
            emoji_re = re.compile(r'[\U00010000-\U0010ffff\u2600-\u27BF]')
            for item in direct_notes:
                if item.get('title'):
                    item['title'] = emoji_re.sub('', str(item['title'])).strip()
                if item.get('body'):
                    item['body'] = emoji_re.sub('', str(item['body'])).strip()
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
                if item.get('read_at') is not None and hasattr(item['read_at'], 'isoformat'):
                    item['read_at'] = item['read_at'].isoformat()
                elif item.get('read_at') is None:
                    item['read_at'] = None

        return jsonify({'items': direct_notes, 'total': len(direct_notes)}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@notifications_bp.route('/unread-count', methods=['GET'])
@jwt_required()
def get_unread_count():
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, body, notification_type, read_at
                FROM notifications
                WHERE deleted_at IS NULL
                  AND (member_id = %s OR member_id IS NULL)
                  AND read_at IS NULL
                ORDER BY created_at DESC
            """, (user_id,))
            raw_notes = [dict(r) for r in cursor.fetchall()]

            seen_signatures = set()
            unread_count = 0
            for n in raw_notes:
                sig = (n.get('title', '').strip().lower(), n.get('body', '').strip().lower())
                if sig not in seen_signatures:
                    seen_signatures.add(sig)
                    unread_count += 1

            # Also count active announcements included in notifications feed
            cursor.execute("""
                SELECT id, title, body FROM announcements
                WHERE deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT 25
            """)
            announcements = cursor.fetchall()
            for a in announcements:
                sig = ((a.get('title') or '').strip().lower(), (a.get('body') or '').strip().lower())
                if sig not in seen_signatures:
                    seen_signatures.add(sig)
                    unread_count += 1

        return jsonify({'unread': unread_count}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@notifications_bp.route('/mark-read', methods=['POST'])
@jwt_required()
def mark_read():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    notification_id = data.get('notification_id')
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if notification_id:
                cursor.execute("""
                    SELECT id FROM notifications
                    WHERE id = %s AND deleted_at IS NULL AND member_id = %s
                """, (notification_id, user_id))
                if not cursor.fetchone():
                    return jsonify({'message': 'Notification not found'}), 404
                cursor.execute(
                    "UPDATE notifications SET read_at = NOW() WHERE id = %s",
                    (notification_id,)
                )
            else:
                cursor.execute(
                    "UPDATE notifications SET read_at = NOW() WHERE deleted_at IS NULL AND member_id = %s",
                    (user_id,)
                )
            conn.commit()
        return jsonify({'message': 'Marked as read'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@notifications_bp.route('/<int:notification_id>', methods=['DELETE'])
@jwt_required()
def delete_notification(notification_id):
    user_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id FROM notifications
                WHERE id = %s AND deleted_at IS NULL AND member_id = %s
            """, (notification_id, user_id))
            if not cursor.fetchone():
                return jsonify({'message': 'Notification not found'}), 404
            cursor.execute(
                "UPDATE notifications SET deleted_at = NOW() WHERE id = %s",
                (notification_id,)
            )
            conn.commit()
        return jsonify({'message': 'Notification deleted'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ── Admin: message a group of members ────────────────────────────────────────
# Groups are worked out from live data at send time, so "Renewal due" never
# includes someone who has already paid this year's renewal.
MESSAGE_GROUPS = {
    'renewal_due': 'Renewal due or overdue, not paid',
    'expired': 'Licence already ended, not paid',
    'pending': 'Applications not yet approved',
    'all_active': 'All active members',
}


def group_members(cursor, group, today=None):
    """Members (id, name, email, fcm_token) in a message group."""
    from datetime import date, timedelta
    from routes.auth import renewal_paid_this_cycle

    today = today or date.today()
    base = """SELECT id, name, email, fcm_token, license_expiry_date FROM members
              WHERE COALESCE(role, 'member') = 'member'"""
    if group == 'all_active':
        cursor.execute(base + " AND status = 'active' ORDER BY id")
        return cursor.fetchall()
    if group == 'pending':
        cursor.execute(base + " AND status IN ('pending', 'pending_review') ORDER BY id")
        return cursor.fetchall()
    if group in ('renewal_due', 'expired'):
        limit = today + timedelta(days=30) if group == 'renewal_due' else today - timedelta(days=1)
        cursor.execute(base + """ AND status IN ('active', 'suspended')
                                  AND license_expiry_date IS NOT NULL
                                  AND license_expiry_date <= %s ORDER BY id""", (limit,))
        rows = cursor.fetchall()
        return [r for r in rows if not renewal_paid_this_cycle(cursor, r['id'], r['license_expiry_date'])]
    raise ValueError('unknown group')


@notifications_bp.route('/admin/groups', methods=['GET'])
@sub_admin_required('announcements')
def admin_message_groups():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            return jsonify({'groups': [
                {'key': k, 'label': v, 'count': len(group_members(cursor, k))}
                for k, v in MESSAGE_GROUPS.items()
            ]}), 200
    finally:
        conn.close()


@notifications_bp.route('/admin/send-group', methods=['POST'])
@sub_admin_required('announcements')
def admin_send_group():
    from utils import send_push_notification, log_audit
    from routes.auth import _send_email

    data = request.get_json(silent=True) or {}
    group = str(data.get('group') or '')
    title = str(data.get('title') or '').strip()
    message = str(data.get('message') or '').strip()
    also_email = bool(data.get('email'))
    if group not in MESSAGE_GROUPS:
        return jsonify({'message': 'Choose who to send it to.'}), 400
    if not title or not message:
        return jsonify({'message': 'Add a title and a message.'}), 400
    if len(title) > 120 or len(message) > 2000:
        return jsonify({'message': 'The title or message is too long.'}), 400

    conn = get_db()
    sent = emailed = 0
    try:
        with conn.cursor() as cursor:
            members = group_members(cursor, group)
            for m in members:
                cursor.execute(
                    """INSERT INTO notifications (member_id, title, body, category, notification_type)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (m['id'], title, message, 'Announcement', 'admin_message'),
                )
                sent += 1
            conn.commit()
        # Push and email after saving, so a slow provider never loses the in-app copy.
        for m in members:
            if m.get('fcm_token'):
                try:
                    send_push_notification(m['fcm_token'], title, message, data={'type': 'admin_message'})
                except Exception:
                    pass
            if also_email and m.get('email'):
                try:
                    if _send_email(m['email'], title, message):
                        emailed += 1
                except Exception:
                    pass
        log_audit(get_jwt_identity(), 'Sent message', 'notification', None,
                  f"{MESSAGE_GROUPS[group]}: {title}", f'{sent} members, {emailed} emails')
        return jsonify({'sent': sent, 'emailed': emailed}), 200
    except Exception:
        conn.rollback()
        return jsonify({'message': 'Could not send the message.'}), 500
    finally:
        conn.close()
