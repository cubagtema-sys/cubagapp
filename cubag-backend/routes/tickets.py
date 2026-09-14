from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import admin_required, log_admin_action, sub_admin_required
from config.cache import cache

tickets_bp = Blueprint('tickets', __name__)

@tickets_bp.route('/', methods=['GET'])
@jwt_required()
def get_user_tickets():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Join with members to ensure we only get valid tickets and potentially add more info
            cursor.execute("""
                SELECT id, subject, message, status, created_at, updated_at
                FROM support_tickets
                WHERE member_id = %s AND deleted_at IS NULL
                ORDER BY updated_at DESC
            """, (member_id,))
            tickets = cursor.fetchall()
            
            # Helper to safely format dates
            def format_date(dt, fmt):
                return dt.strftime(fmt) if dt else 'N/A'

            # Get replies for each ticket
            for t in tickets:
                cursor.execute("""
                    SELECT author, message, created_at
                    FROM ticket_replies
                    WHERE ticket_id = %s
                    ORDER BY created_at ASC
                """, (t['id'],))
                replies = cursor.fetchall()
                t['replies'] = [{
                    'author': r['author'],
                    'message': r['message'],
                    'date': format_date(r['created_at'], '%Y-%m-%d %H:%M')
                } for r in replies]
                
                t['date'] = format_date(t['created_at'], '%Y-%m-%d')
                t['lastUpdate'] = format_date(t['updated_at'], '%Y-%m-%d %H:%M')
                
            return jsonify(tickets), 200
    except Exception as e:
        import traceback
        print(f"[Tickets Error] {str(e)}")
        print(traceback.format_exc())
        return jsonify({'message': 'Failed to load tickets', 'details': str(e)}), 500
    finally:
        conn.close()

@tickets_bp.route('/', methods=['POST'])
@jwt_required()
def create_ticket():
    member_id = get_jwt_identity()
    data = request.get_json()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Generate a unique ticket ID
            import random
            attempts = 0
            while True:
                # 6 digits for better collision avoidance
                ticket_id = f"TKT-{random.randint(100000, 999999)}"
                cursor.execute("SELECT 1 FROM support_tickets WHERE id = %s", (ticket_id,))
                if not cursor.fetchone():
                    break
                attempts += 1
                if attempts > 50:
                    import uuid
                    ticket_id = f"TKT-{uuid.uuid4().hex[:8].upper()}"
                    break

            cursor.execute("""
                INSERT INTO support_tickets (id, member_id, subject, message)
                VALUES (%s, %s, %s, %s)
            """, (ticket_id, member_id, data.get('subject'), data.get('message')))
            conn.commit()
            
        return jsonify({'id': ticket_id, 'message': 'Ticket created'}), 201
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# --- ADMIN ENDPOINTS ---

@tickets_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('tickets')
def get_all_tickets_admin():
    page = max(1, int(request.args.get('page', 1)))
    per_page = int(request.args.get('per_page', 20))
    per_page = max(1, min(per_page, 200))
    status_filter = request.args.get('status', 'inbox').lower()

    # 20-second cache keyed by page+status
    cache_key = f'admin_tickets_{status_filter}_p{page}_pp{per_page}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200

    conn = get_db()
    try:
        offset = (page - 1) * per_page

        where_clause = "WHERE t.deleted_at IS NULL"
        if status_filter == 'inbox':
            where_clause += " AND t.status != 'archived'"
        elif status_filter == 'archived':
            where_clause += " AND t.status = 'archived'"

        with conn.cursor() as cursor:
            cursor.execute(f"""
                SELECT t.id, t.subject, t.message, t.status, t.created_at, t.updated_at, 
                       COALESCE(m.name, 'Unknown Member') as member_name,
                       m.company, m.email as member_email, m.phone as member_phone,
                       m.membership_number
                FROM support_tickets t
                LEFT JOIN members m ON t.member_id = m.id
                {where_clause}
                ORDER BY t.updated_at DESC
                LIMIT %s OFFSET %s
            """, (per_page, offset))
            tickets = cursor.fetchall()

            cursor.execute(f"""
                SELECT COUNT(*) as total
                FROM support_tickets t
                {where_clause}
            """)
            total = cursor.fetchone().get('total', 0)
            
            def format_date(dt, fmt):
                return dt.strftime(fmt) if dt else 'N/A'

            # Batch fetch all replies for this page of tickets
            ticket_ids = [t['id'] for t in tickets if t.get('id')]
            replies_by_ticket = {}
            if ticket_ids:
                cursor.execute("""
                    SELECT ticket_id, author, message, created_at
                    FROM ticket_replies
                    WHERE ticket_id = ANY(%s)
                    ORDER BY created_at ASC
                """, (ticket_ids,))
                all_replies = cursor.fetchall()
                for r in all_replies:
                    tid = r['ticket_id']
                    if tid not in replies_by_ticket:
                        replies_by_ticket[tid] = []
                    replies_by_ticket[tid].append({
                        'author': r['author'],
                        'message': r['message'],
                        'date': format_date(r['created_at'], '%Y-%m-%d %H:%M')
                    })

            for t in tickets:
                t['replies'] = replies_by_ticket.get(t['id'], [])
                t['date'] = format_date(t['created_at'], '%Y-%m-%d')
                t['lastUpdate'] = format_date(t['updated_at'], '%Y-%m-%d %H:%M')

        response = {'data': tickets, 'page': page, 'per_page': per_page, 'total': total}
        cache.set(cache_key, response, timeout=20)
        return jsonify(response), 200
    except Exception as e:
        import traceback
        print(f"[Admin Tickets Error] {str(e)}")
        print(traceback.format_exc())
        return jsonify({'message': 'Failed to load tickets', 'details': str(e)}), 500
    finally:
        conn.close()

@tickets_bp.route('/admin/<ticket_id>/status', methods=['PUT'])
@sub_admin_required('tickets')
def update_ticket_status(ticket_id):
    admin_id = get_jwt_identity()
    data = request.get_json(silent=True) or {}
    new_status = (data.get('status') or '').strip().lower()
    if not new_status:
        return jsonify({'message': 'Status is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Fetch ticket subject for audit context
            cursor.execute("SELECT subject, member_id FROM support_tickets WHERE id = %s", (str(ticket_id),))
            ticket = cursor.fetchone()
            if not ticket:
                return jsonify({'message': f'Ticket #{ticket_id} not found'}), 404

            cursor.execute("""
                UPDATE support_tickets 
                SET status = %s, updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """, (new_status, str(ticket_id)))
            conn.commit()

        # Invalidate cache so fresh tickets are fetched immediately
        try:
            cache.clear()
        except Exception:
            pass

        subject = ticket['subject'] if ticket else str(ticket_id)
        try:
            log_admin_action(admin_id, f'Updated ticket status to {new_status}', 'ticket', None, subject, f'Ticket: {ticket_id} → {new_status}')
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': f'Ticket status updated to {new_status}',
            'status': new_status,
            'id': ticket_id
        }), 200
    except Exception as e:
        logger.exception("Error updating ticket status: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@tickets_bp.route('/admin/<ticket_id>/reply', methods=['POST'])
@sub_admin_required('tickets')
def add_ticket_reply(ticket_id):
    admin_id = get_jwt_identity()
    data = request.get_json(silent=True) or {}
    reply_msg = data.get('message')

    if not reply_msg:
        return jsonify({'message': 'Reply message is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # 1. Fetch ticket and member info
            cursor.execute("""
                SELECT t.subject, t.member_id, m.fcm_token
                FROM support_tickets t
                JOIN members m ON t.member_id = m.id
                WHERE t.id = %s
            """, (str(ticket_id),))
            ticket_row = cursor.fetchone()
            if not ticket_row:
                return jsonify({'message': 'Ticket not found'}), 404

            # 2. Fetch the real admin's name
            cursor.execute("SELECT name FROM members WHERE id = %s", (admin_id,))
            admin_row = cursor.fetchone()
            admin_name = admin_row['name'] if admin_row else 'CUBAG Admin'

            # 3. Save reply and update ticket timestamp
            cursor.execute("""
                INSERT INTO ticket_replies (ticket_id, author, message)
                VALUES (%s, %s, %s)
            """, (str(ticket_id), admin_name, reply_msg))
            cursor.execute("""
                UPDATE support_tickets
                SET updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """, (str(ticket_id),))
            conn.commit()

            # 4. Send Push Notification to Member
            fcm_token = ticket_row.get('fcm_token')
            if fcm_token:
                from utils import send_push_notification
                send_push_notification(
                    fcm_token=fcm_token,
                    title=f"New Support Reply: {ticket_id}",
                    body=reply_msg[:100] + ("..." if len(reply_msg) > 100 else ""),
                    data={
                        'type': 'ticket',
                        'id': str(ticket_id)
                    }
                )

        # Invalidate cache
        try:
            cache.clear()
        except Exception:
            pass

        subject = ticket_row['subject']
        try:
            log_admin_action(admin_id, 'Replied to ticket', 'ticket', None, subject, f'Ticket: {ticket_id}')
        except Exception:
            pass

        return jsonify({'message': 'Reply added'}), 201
    except Exception as e:
        logger.exception("Error adding ticket reply: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# ─── DELETE /tickets/admin/<id> — Soft delete (keeps data in DB) ──────────────
@tickets_bp.route('/admin/<ticket_id>', methods=['DELETE'])
@sub_admin_required('tickets')
def soft_delete_ticket(ticket_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT subject FROM support_tickets WHERE id = %s", (str(ticket_id),))
            ticket = cursor.fetchone()
            cursor.execute("""
                UPDATE support_tickets
                SET deleted_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """, (str(ticket_id),))
            conn.commit()

        # Invalidate cache
        try:
            cache.clear()
        except Exception:
            pass

        subject = ticket['subject'] if ticket else str(ticket_id)
        try:
            log_admin_action(admin_id, 'Archived ticket', 'ticket', None, subject, f'Ticket: {ticket_id}')
        except Exception:
            pass

        return jsonify({'message': 'Ticket archived'}), 200
    except Exception as e:
        logger.exception("Error deleting ticket: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
