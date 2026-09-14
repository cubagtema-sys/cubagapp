from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db

messages_bp = Blueprint('messages', __name__)

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
        return jsonify({'message': str(e)}), 500
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
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@messages_bp.route('/<int:other_id>', methods=['POST'])
@jwt_required()
def send_message(other_id):
    raw_uid = get_jwt_identity()
    user_id = int(raw_uid) if raw_uid is not None else 0
    data = request.get_json() or {}
    message_text = data.get('text')

    if not message_text:
        return jsonify({'message': 'Message text is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
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
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
