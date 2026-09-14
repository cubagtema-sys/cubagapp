from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from routes.admin import log_admin_action
from utils import admin_required, sub_admin_required
from config.cache import cache

schedules_bp = Blueprint('schedules', __name__)

@schedules_bp.route('/', methods=['GET'])
@cache.cached(timeout=60, query_string=True)
def get_schedules():
    schedule_type = request.args.get('type')
    return _fetch_schedules(schedule_type)

@schedules_bp.route('/<string:schedule_type>', methods=['GET'])
@cache.cached(timeout=60, query_string=True)
def get_schedules_by_path(schedule_type):
    return _fetch_schedules(schedule_type)

def _fetch_schedules(schedule_type):
    try:
        page = max(1, int(request.args.get('page', 1)))
        per_page = int(request.args.get('per_page', 50))
        per_page = max(1, min(per_page, 200))
        offset = (page - 1) * per_page
        
        status_filter = request.args.get('status', 'All')

        conn = get_db()
        with conn.cursor() as cursor:
            where_clauses = []
            params = []
            
            if schedule_type:
                where_clauses.append("LOWER(type) = LOWER(%s)")
                params.append(schedule_type)
                
            if status_filter != 'All':
                where_clauses.append("status = %s")
                params.append(status_filter)
                
            where_sql = "WHERE " + " AND ".join(where_clauses) if where_clauses else ""
            
            cursor.execute(f"SELECT * FROM schedules {where_sql} ORDER BY created_at DESC LIMIT %s OFFSET %s", (*params, per_page, offset))
            data = cursor.fetchall()
            
            cursor.execute(f"SELECT COUNT(*) as total FROM schedules {where_sql}", params)
            total = cursor.fetchone().get('total', 0)

            # Ensure dates and numbers are JSON serializable
            for item in data:
                for key, value in list(item.items()):
                    if hasattr(value, 'isoformat'):
                        item[key] = value.isoformat()
                    elif hasattr(value, 'strftime'):
                        item[key] = str(value)

        return jsonify({'data': data, 'total': total, 'page': page, 'per_page': per_page}), 200
    except Exception as e:
        import traceback
        print(f"[Schedules Error] {e}")
        print(traceback.format_exc())
        return jsonify({'message': str(e)}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@schedules_bp.route('/', methods=['POST'])
@sub_admin_required('schedules')
def create_schedule():
    admin_id = get_jwt_identity()
    data = request.get_json()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO schedules (type, container, vessel, cargo, date, port, status, origin, destination, progress)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                data.get('type'), data.get('container'), data.get('vessel'),
                data.get('cargo'), data.get('date'), data.get('port'),
                data.get('status', 'Scheduled'),
                data.get('origin'),       # vessel movement: departure port
                data.get('destination'),  # vessel movement: arrival port
                data.get('progress', 0)   # 0–100 percent along route
            ))
            conn.commit()

        # Audit log
        log_admin_action(admin_id, 'Created schedule', 'schedule', None, data.get('vessel') or data.get('container'), f'Type: {data.get("type")}, Port: {data.get("port")}')
        try:
            from socket_instance import socketio
            socketio.emit('schedules_updated', {'type': data.get('type')})
        except Exception:
            pass
        return jsonify({'message': 'Schedule added successfully'}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# ─── PATCH /schedules/<id> — Update status ────────────────────────────────────
@schedules_bp.route('/<int:schedule_id>', methods=['PATCH'])
@sub_admin_required('schedules')
def update_schedule_status(schedule_id):
    admin_id = get_jwt_identity()
    data = request.get_json()
    new_status = data.get('status')
    if not new_status:
        return jsonify({'message': 'status is required'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT vessel, container FROM schedules WHERE id = %s", (schedule_id,))
            sched = cursor.fetchone()

            cursor.execute(
                "UPDATE schedules SET status = %s WHERE id = %s",
                (new_status, schedule_id)
            )
            conn.commit()

        # Audit log
        label = sched.get('vessel') or sched.get('container') or f'#{schedule_id}' if sched else f'#{schedule_id}'
        log_admin_action(admin_id, 'Updated schedule status', 'schedule', schedule_id, label, f'Status → {new_status}')
        try:
            from socket_instance import socketio
            socketio.emit('schedules_updated', {'id': schedule_id, 'status': new_status})
        except Exception:
            pass
        return jsonify({'message': 'Status updated'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

# ─── DELETE /schedules/<id> ───────────────────────────────────────────────
@schedules_bp.route('/<int:schedule_id>', methods=['DELETE'])
@sub_admin_required('schedules')
def delete_schedule(schedule_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT vessel, container FROM schedules WHERE id = %s", (schedule_id,))
            sched = cursor.fetchone()

            cursor.execute("UPDATE schedules SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s", (schedule_id,))
            conn.commit()

        # Audit log
        label = sched.get('vessel') or sched.get('container') or f'#{schedule_id}' if sched else f'#{schedule_id}'
        log_admin_action(admin_id, 'Archived schedule', 'schedule', schedule_id, label)
        try:
            from socket_instance import socketio
            socketio.emit('schedules_updated', {'id': schedule_id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Schedule archived'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
