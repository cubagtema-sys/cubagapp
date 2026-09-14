from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db

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

            for item in direct_notes:
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
