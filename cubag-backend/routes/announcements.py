from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import send_push_to_all, admin_required, sub_admin_required
from routes.admin import log_admin_action
from config.cache import cache

announcements_bp = Blueprint('announcements', __name__)

# ─── GET / — Members: only non-deleted announcements ──────────────────────────
@announcements_bp.route('/', methods=['GET'])
@jwt_required()
def get_announcements():
    user_id = get_jwt_identity()
    
    # Per-user 30s cache — announcements are user-specific (is_read flag)
    cache_key = f'announcements_{user_id}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT a.*,
                       (ar.member_id IS NOT NULL) AS is_read
                FROM announcements a
                LEFT JOIN announcement_reads ar ON a.id = ar.announcement_id AND ar.member_id = %s
                WHERE a.deleted_at IS NULL
                ORDER BY a.created_at DESC
            """, (user_id,))
            data = cursor.fetchall()

            # Stringify dates
            for item in data:
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()

        result = {'items': data, 'total': len(data)}
        cache.set(cache_key, result, timeout=30)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# ─── POST /mark-read — Mark specific or all announcements as read ────────────
@announcements_bp.route('/mark-read', methods=['POST'])
@jwt_required()
def mark_read():
    user_id = get_jwt_identity()
    data = request.get_json()
    ann_id = data.get('announcement_id') # single ID or None for "all"

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if ann_id:
                cursor.execute("""
                    INSERT INTO announcement_reads (member_id, announcement_id)
                    VALUES (%s, %s)
                    ON CONFLICT DO NOTHING
                """, (user_id, ann_id))
            else:
                # Mark all as read
                cursor.execute("""
                    INSERT INTO announcement_reads (member_id, announcement_id)
                    SELECT %s, id FROM announcements WHERE deleted_at IS NULL
                    ON CONFLICT DO NOTHING
                """, (user_id,))
            conn.commit()
        # Invalidate this user's announcements cache
        cache.delete(f'announcements_{user_id}')
        return jsonify({'message': 'Marked as read'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# ─── POST / — Create new announcement ─────────────────────────────────────────
@announcements_bp.route('/', methods=['POST'])
@sub_admin_required('announcements')
def create_announcement():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    title    = (data.get('title') or '').strip()
    body     = (data.get('body') or '').strip()
    category = data.get('category', 'General')

    if not title or not body:
        return jsonify({'message': 'Title and body are required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Use the real admin's name as the author
            cursor.execute("SELECT name FROM members WHERE id = %s", (admin_id,))
            admin_row = cursor.fetchone()
            posted_by = admin_row['name'] if admin_row else data.get('posted_by', 'CUBAG Secretariat')

            cursor.execute("""
                INSERT INTO announcements (title, body, category, posted_by)
                VALUES (%s, %s, %s, %s)
            """, (title, body, category, posted_by))
            conn.commit()

        # Trigger Push Notification
        send_push_to_all(
            title=f"New Announcement: {title}",
            body=body[:100] + ('...' if len(body) > 100 else ''),
            data={'type': 'announcement', 'category': category}
        )

        try:
            from socket_instance import socketio
            socketio.emit('announcements_updated', {'category': category})
        except Exception:
            pass

        # Audit log
        log_admin_action(admin_id, 'Created announcement', 'announcement', None, title, f'Category: {category}')

        return jsonify({'message': 'Announcement posted'}), 201
    except Exception as e:
        return jsonify({'message': 'Failed to create announcement'}), 500
    finally:
        conn.close()


# ─── GET /admin/all — Admin: all announcements (including soft-deleted) ────────
@announcements_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('announcements')
def get_all_announcements_admin():
    conn = get_db()
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 20))
        archived = request.args.get('archived', 'false').lower() == 'true'
        offset = (page - 1) * limit

        with conn.cursor() as cursor:
            if archived:
                where_clause = "WHERE deleted_at IS NOT NULL"
            else:
                where_clause = "WHERE deleted_at IS NULL"
                
            cursor.execute(f"SELECT COUNT(*) as total FROM announcements {where_clause}")
            total = cursor.fetchone()['total']

            cursor.execute(f"""
                SELECT *, deleted_at IS NOT NULL AS is_deleted
                FROM announcements
                {where_clause}
                ORDER BY created_at DESC
                LIMIT %s OFFSET %s
            """, (limit, offset))
            data = cursor.fetchall()
            
            for item in data:
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
                if hasattr(item.get('deleted_at'), 'isoformat'):
                    item['deleted_at'] = item['deleted_at'].isoformat()

        return jsonify({
            "data": data,
            "total": total,
            "page": page,
            "limit": limit
        }), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─── PUT /<id> — Update an existing announcement ─────────────────────────────
@announcements_bp.route('/<int:ann_id>', methods=['PUT'])
@sub_admin_required('announcements')
def update_announcement(ann_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    body = (data.get('body') or '').strip()
    category = data.get('category', 'General')

    if not title or not body:
        return jsonify({'message': 'Title and body are required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id FROM announcements WHERE id = %s", (ann_id,))
            ann = cursor.fetchone()
            if not ann:
                return jsonify({'message': 'Announcement not found'}), 404

            cursor.execute("""
                UPDATE announcements 
                SET title = %s, body = %s, category = %s
                WHERE id = %s
            """, (title, body, category, ann_id))
            conn.commit()

        # Invalidate announcements cache
        try:
            from socket_instance import socketio
            socketio.emit('announcements_updated', {'id': ann_id})
        except Exception:
            pass
        log_admin_action(admin_id, 'Updated announcement', 'announcement', ann_id, title, f'Category: {category}')

        return jsonify({'message': 'Announcement updated successfully'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─── DELETE /<id> — Soft-delete: set deleted_at timestamp ─────────────────────
@announcements_bp.route('/<int:ann_id>', methods=['DELETE'])
@sub_admin_required('announcements')
def soft_delete_announcement(ann_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Ensure the announcement exists
            cursor.execute("SELECT id, title FROM announcements WHERE id = %s", (ann_id,))
            ann = cursor.fetchone()
            if not ann:
                return jsonify({'message': 'Announcement not found'}), 404

            # Soft-delete — keep the record, just mark the timestamp
            cursor.execute(
                "UPDATE announcements SET deleted_at = NOW() WHERE id = %s",
                (ann_id,)
            )
            conn.commit()

        try:
            from socket_instance import socketio
            socketio.emit('announcements_updated', {'id': ann_id, 'deleted': True})
        except Exception:
            pass

        # Audit log
        log_admin_action(admin_id, 'Archived announcement', 'announcement', ann_id, ann.get('title', f'#{ann_id}'))

        return jsonify({'message': 'Announcement archived (soft-deleted)'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─── PATCH /<id>/restore — Restore a soft-deleted announcement ────────────────
@announcements_bp.route('/<int:ann_id>/restore', methods=['PATCH'])
@sub_admin_required('announcements')
def restore_announcement(ann_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT title FROM announcements WHERE id = %s", (ann_id,))
            ann = cursor.fetchone()

            cursor.execute(
                "UPDATE announcements SET deleted_at = NULL WHERE id = %s",
                (ann_id,)
            )
            conn.commit()

        try:
            from socket_instance import socketio
            socketio.emit('announcements_updated', {'id': ann_id, 'restored': True})
        except Exception:
            pass

        # Audit log
        log_admin_action(admin_id, 'Restored announcement', 'announcement', ann_id, ann.get('title', f'#{ann_id}') if ann else f'#{ann_id}')

        return jsonify({'message': 'Announcement restored'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

