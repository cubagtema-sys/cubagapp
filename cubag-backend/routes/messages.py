import logging

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from config.rate_limit import rate_limit

logger = logging.getLogger(__name__)
messages_bp = Blueprint('messages', __name__)

MAX_MESSAGE_LENGTH = 2000
REPORT_REASONS = ('spam', 'harassment', 'abusive', 'fraud', 'inappropriate', 'other')


def _ensure_safety_tables(cursor):
    """Store-compliance tables for user-generated content (Apple 1.2 /
    Google Play UGC): blocks and reports. Idempotent."""
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS member_blocks (
            blocker_id INT NOT NULL,
            blocked_id INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (blocker_id, blocked_id)
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS message_reports (
            id SERIAL PRIMARY KEY,
            reporter_id INT NOT NULL,
            reported_member_id INT NOT NULL,
            message_id INT,
            reason VARCHAR(40) NOT NULL,
            details TEXT,
            status VARCHAR(20) DEFAULT 'open',
            reviewed_by INT,
            reviewed_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)


def _is_blocked_either_way(cursor, a, b):
    cursor.execute(
        "SELECT 1 FROM member_blocks WHERE (blocker_id = %s AND blocked_id = %s) "
        "OR (blocker_id = %s AND blocked_id = %s) LIMIT 1",
        (a, b, b, a),
    )
    return cursor.fetchone() is not None

@messages_bp.route('/conversations', methods=['GET'])
@jwt_required()
def get_conversations():
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                WITH latest AS (
                    SELECT DISTINCT ON (
                        CASE WHEN m.sender_id = %s THEN m.receiver_id ELSE m.sender_id END
                    )
                        CASE WHEN m.sender_id = %s THEN m.receiver_id ELSE m.sender_id END AS other_id,
                        m.message AS last_msg,
                        m.created_at
                    FROM messages m
                    WHERE m.sender_id = %s OR m.receiver_id = %s
                    ORDER BY CASE WHEN m.sender_id = %s THEN m.receiver_id ELSE m.sender_id END, m.created_at DESC
                ), unread AS (
                    SELECT sender_id AS other_id, COUNT(*) AS unread
                    FROM messages
                    WHERE receiver_id = %s AND read_at IS NULL
                    GROUP BY sender_id
                )
                SELECT u.id AS other_id, u.name, u.company, latest.last_msg, latest.created_at, COALESCE(unread.unread, 0) AS unread
                FROM latest
                JOIN members u ON u.id = latest.other_id
                LEFT JOIN unread ON unread.other_id = latest.other_id
                ORDER BY latest.created_at DESC
            """, (user_id, user_id, user_id, user_id, user_id, user_id))
            
            rows = cursor.fetchall()
            conversations = []
            for r in rows:
                name_str = r['name'] or 'Member'
                initials = ''.join([n[0] for n in name_str.split() if n]).upper()[:2]
                if not initials:
                    initials = 'M'
                time_str = r['created_at'].strftime('%b %d, %I:%M %p') if r['created_at'] else ''
                
                conversations.append({
                    'id': r['other_id'],
                    'name': name_str,
                    'company': r['company'] or 'CUBAG Member',
                    'initials': initials,
                    'lastMsg': r['last_msg'] or '',
                    'time': time_str,
                    'unread': int(r['unread'] or 0)
                })
            
            return jsonify({'items': conversations, 'total': len(conversations)}), 200
    except Exception as e:
        logger.exception('get_conversations error')
        logger.exception('[messages] %s', e)
        return jsonify({'message': 'Messaging is temporarily unavailable'}), 500
    finally:
        conn.close()

@messages_bp.route('/<int:other_id>', methods=['GET'])
@jwt_required()
def get_messages(other_id):
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE messages
                SET read_at = CURRENT_TIMESTAMP
                WHERE receiver_id = %s AND sender_id = %s AND read_at IS NULL
            """, (user_id, other_id))
            conn.commit()

            cursor.execute("""
                SELECT id, sender_id, receiver_id, message, created_at, read_at
                FROM messages
                WHERE (sender_id = %s AND receiver_id = %s)
                   OR (sender_id = %s AND receiver_id = %s)
                ORDER BY created_at ASC
            """, (user_id, other_id, other_id, user_id))
            msgs = cursor.fetchall()
            
            formatted = []
            for m in msgs:
                formatted.append({
                    'id': m['id'],
                    'from': 'me' if int(m['sender_id']) == user_id else 'them',
                    'text': m['message'],
                    'time': m['created_at'].strftime('%b %d, %I:%M %p') if m['created_at'] else '',
                    'read_at': m['read_at'].strftime('%b %d, %I:%M %p') if m.get('read_at') else None,
                })
            
            return jsonify({'items': formatted, 'total': len(formatted)}), 200
    except Exception as e:
        logger.exception('[messages] %s', e)
        return jsonify({'message': 'Messaging is temporarily unavailable'}), 500
    finally:
        conn.close()

@messages_bp.route('/<int:other_id>', methods=['POST'])
@jwt_required()
@rate_limit('send_message', max_requests=30, window_seconds=60)
def send_message(other_id):
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    data = request.get_json() or {}
    message_text = str(data.get('text') or '').strip()

    if not message_text:
        return jsonify({'message': 'Message text is required'}), 400
    # BUG-12: bound message size and validate the recipient.
    if len(message_text) > MAX_MESSAGE_LENGTH:
        return jsonify({'message': f'Messages are limited to {MAX_MESSAGE_LENGTH} characters'}), 400
    if other_id == user_id:
        return jsonify({'message': 'You cannot message yourself'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT status, role FROM members WHERE id = %s", (other_id,))
            recipient = cursor.fetchone()
            if not recipient or str(recipient.get('status') or '').lower() in ('deleted', 'suspended', 'inactive'):
                return jsonify({'message': 'This member cannot receive messages'}), 404
            _ensure_safety_tables(cursor)
            if _is_blocked_either_way(cursor, user_id, other_id):
                return jsonify({'message': 'You cannot message this member', 'error_code': 'BLOCKED'}), 403

            # 1. Save to DB
            cursor.execute("""
                INSERT INTO messages (sender_id, receiver_id, message)
                VALUES (%s, %s, %s) RETURNING id, created_at
            """, (user_id, other_id, message_text))
            new_msg = cursor.fetchone()

            # 2. Get sender name and receiver FCM token
            cursor.execute("SELECT name FROM members WHERE id = %s", (user_id,))
            sender = cursor.fetchone()
            sender_name = sender['name'] if sender else "A member"

            cursor.execute("SELECT fcm_token FROM members WHERE id = %s", (other_id,))
            receiver = cursor.fetchone()
            receiver_token = receiver['fcm_token'] if receiver else None

            conn.commit()

            # 3. Send Push Notification
            if receiver_token:
                try:
                    from utils import send_push_notification
                    send_push_notification(
                        fcm_token=receiver_token,
                        title=f"Message from {sender_name}",
                        body=message_text[:100] + ("..." if len(message_text) > 100 else ""),
                        data={
                            'type': 'message',
                            'id': str(user_id),
                            'name': str(sender_name)
                        }
                    )
                except Exception as p_err:
                    pass

            return jsonify({
                'id': new_msg['id'],
                'from': 'me',
                'text': message_text,
                'time': new_msg['created_at'].strftime('%b %d, %I:%M %p') if new_msg.get('created_at') else ''
            }), 201
    except Exception as e:
        logger.exception('[messages] %s', e)
        return jsonify({'message': 'Messaging is temporarily unavailable'}), 500
    finally:
        conn.close()


# ── UGC safety: block / unblock / report (Apple 1.2, Google Play UGC policy) ──

@messages_bp.route('/blocks', methods=['GET'])
@jwt_required()
def list_blocks():
    user_id = int(get_jwt_identity())
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_safety_tables(cursor)
            cursor.execute("""
                SELECT b.blocked_id AS id, m.name, b.created_at
                FROM member_blocks b LEFT JOIN members m ON m.id = b.blocked_id
                WHERE b.blocker_id = %s ORDER BY b.created_at DESC
            """, (user_id,))
            rows = [dict(r) for r in cursor.fetchall()]
            conn.commit()
        for r in rows:
            if hasattr(r.get('created_at'), 'isoformat'):
                r['created_at'] = r['created_at'].isoformat()
        return jsonify({'items': rows, 'total': len(rows)}), 200
    finally:
        conn.close()


@messages_bp.route('/<int:other_id>/block', methods=['POST'])
@jwt_required()
def block_member(other_id):
    user_id = int(get_jwt_identity())
    if other_id == user_id:
        return jsonify({'message': 'You cannot block yourself'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_safety_tables(cursor)
            cursor.execute(
                "INSERT INTO member_blocks (blocker_id, blocked_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (user_id, other_id),
            )
            conn.commit()
        return jsonify({'message': 'Member blocked. They can no longer message you.', 'blocked': True}), 200
    finally:
        conn.close()


@messages_bp.route('/<int:other_id>/block', methods=['DELETE'])
@jwt_required()
def unblock_member(other_id):
    user_id = int(get_jwt_identity())
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_safety_tables(cursor)
            cursor.execute("DELETE FROM member_blocks WHERE blocker_id = %s AND blocked_id = %s", (user_id, other_id))
            conn.commit()
        return jsonify({'message': 'Member unblocked.', 'blocked': False}), 200
    finally:
        conn.close()


@messages_bp.route('/<int:other_id>/report', methods=['POST'])
@jwt_required()
@rate_limit('report_message', max_requests=10, window_seconds=3600)
def report_member(other_id):
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    reason = str(data.get('reason') or 'other').strip().lower()
    if reason not in REPORT_REASONS:
        reason = 'other'
    details = str(data.get('details') or '').strip()[:1000]
    message_id = data.get('message_id')
    try:
        message_id = int(message_id) if message_id is not None else None
    except (TypeError, ValueError):
        message_id = None
    if other_id == user_id:
        return jsonify({'message': 'You cannot report yourself'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_safety_tables(cursor)
            cursor.execute("""
                INSERT INTO message_reports (reporter_id, reported_member_id, message_id, reason, details)
                VALUES (%s, %s, %s, %s, %s) RETURNING id
            """, (user_id, other_id, message_id, reason, details))
            report = cursor.fetchone() or {}
            if data.get('block', True):
                cursor.execute(
                    "INSERT INTO member_blocks (blocker_id, blocked_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (user_id, other_id),
                )
            conn.commit()
        try:
            from socket_instance import socketio
            socketio.emit('message_report_created', {'report_id': report.get('id')}, room='admins')
        except Exception:
            pass
        return jsonify({
            'message': 'Thank you. The Secretariat will review this report.',
            'report_id': report.get('id'),
        }), 201
    finally:
        conn.close()


@messages_bp.route('/admin/reports', methods=['GET'])
def admin_list_reports():
    from utils import sub_admin_required

    @sub_admin_required('messaging')
    def _inner():
        status = (request.args.get('status') or 'open').lower()
        conn = get_db()
        try:
            with conn.cursor() as cursor:
                _ensure_safety_tables(cursor)
                cursor.execute("""
                    SELECT r.id, r.reason, r.details, r.status, r.created_at, r.message_id,
                           r.reporter_id, rp.name AS reporter_name,
                           r.reported_member_id, rm.name AS reported_name,
                           msg.message AS message_text
                    FROM message_reports r
                    LEFT JOIN members rp ON rp.id = r.reporter_id
                    LEFT JOIN members rm ON rm.id = r.reported_member_id
                    LEFT JOIN messages msg ON msg.id = r.message_id
                    WHERE (%s = 'all' OR r.status = %s)
                    ORDER BY r.created_at DESC LIMIT 200
                """, (status, status))
                rows = [dict(r) for r in cursor.fetchall()]
                conn.commit()
            for r in rows:
                if hasattr(r.get('created_at'), 'isoformat'):
                    r['created_at'] = r['created_at'].isoformat()
            return jsonify({'items': rows, 'total': len(rows)}), 200
        finally:
            conn.close()
    return _inner()


@messages_bp.route('/admin/reports/<int:report_id>', methods=['PUT'])
def admin_resolve_report(report_id):
    from utils import sub_admin_required, log_admin_action

    @sub_admin_required('messaging')
    def _inner():
        data = request.get_json(silent=True) or {}
        status = str(data.get('status') or 'resolved').lower()
        if status not in ('open', 'resolved', 'dismissed'):
            return jsonify({'message': 'Invalid status'}), 400
        admin_id = get_jwt_identity()
        conn = get_db()
        try:
            with conn.cursor() as cursor:
                _ensure_safety_tables(cursor)
                cursor.execute(
                    "UPDATE message_reports SET status = %s, reviewed_by = %s, reviewed_at = NOW() WHERE id = %s RETURNING id",
                    (status, admin_id, report_id),
                )
                if not cursor.fetchone():
                    return jsonify({'message': 'Report not found'}), 404
                conn.commit()
            log_admin_action(admin_id, 'Reviewed message report', 'message_report', report_id, None, f'Status: {status}')
            return jsonify({'message': 'Report updated', 'status': status}), 200
        finally:
            conn.close()
    return _inner()
