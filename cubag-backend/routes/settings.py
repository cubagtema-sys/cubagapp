from flask import Blueprint, jsonify, request
from config.db import get_db
import json
from utils import admin_required, sub_admin_required
from config.cache import cache

settings_bp = Blueprint('settings', __name__)

@settings_bp.route('/<key>', methods=['GET'])
def get_setting(key):
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = %s", (key,))
            result = cursor.fetchone()
            if result:
                return jsonify(result['config_value']), 200
            else:
                return jsonify({}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@settings_bp.route('/<key>', methods=['POST'])
@sub_admin_required('settings')
def update_setting(key):
    data = request.get_json()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Upsert
            cursor.execute("""
                INSERT INTO platform_settings (config_key, config_value)
                VALUES (%s, %s)
                ON CONFLICT (config_key) 
                DO UPDATE SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP
            """, (key, json.dumps(data)))

            if key == 'cubag_fees_v2' and isinstance(data, list):
                customs_fee = None
                renewal_fee = None
                for item in data:
                    lbl = str(item.get('label', '')).lower()
                    amt_str = str(item.get('amount', '0')).replace(',', '')
                    try:
                        amt_val = float(amt_str)
                    except ValueError:
                        amt_val = 0.0

                    if ('custom' in lbl and 'licence' in lbl) or ('customs' in lbl and 'application' in lbl) or 'application' in lbl:
                        customs_fee = amt_val
                    elif 'renewal' in lbl:
                        renewal_fee = amt_val

                if customs_fee is not None or renewal_fee is not None:
                    cursor.execute("CREATE TABLE IF NOT EXISTS compliance_settings (id SERIAL PRIMARY KEY)")
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
                    cursor.execute("SELECT COUNT(*) FROM compliance_settings")
                    if cursor.fetchone()['count'] == 0:
                        cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")

                    cursor.execute("SELECT id FROM compliance_settings ORDER BY id DESC, updated_at DESC NULLS LAST LIMIT 1")
                    row = cursor.fetchone()
                    target_id = row['id'] if row else None

                    updates = []
                    params = []
                    if customs_fee is not None:
                        updates.append("customs_licence_fee = %s")
                        params.append(customs_fee)
                    if renewal_fee is not None:
                        updates.append("renewal_fee = %s")
                        params.append(renewal_fee)
                    updates.append("updated_at = CURRENT_TIMESTAMP")
                    params.append(target_id)

                cursor.execute("CREATE TABLE IF NOT EXISTS fee_schedules (key VARCHAR(100) PRIMARY KEY, amount NUMERIC(10,2) DEFAULT 0.00, is_active BOOLEAN DEFAULT TRUE, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
                for item in data:
                    f_id = str(item.get('id', '')).strip()
                    if not f_id:
                        continue
                    lbl = str(item.get('label', ''))
                    sec = str(item.get('section', 'new_membership'))
                    desc = str(item.get('description', ''))
                    amt_str = str(item.get('amount', '0')).replace(',', '').strip()
                    try:
                        amt_val = float(amt_str)
                    except ValueError:
                        amt_val = 0.0
                    cursor.execute("""
                        INSERT INTO fee_schedules (key, fee_type, name, amount, description, is_active)
                        VALUES (%s, %s, %s, %s, %s, TRUE)
                        ON CONFLICT (key) 
                        DO UPDATE SET fee_type = EXCLUDED.fee_type, name = EXCLUDED.name, 
                                      amount = EXCLUDED.amount, description = EXCLUDED.description, 
                                      is_active = TRUE
                    """, (f_id, sec, lbl, amt_val, desc))

            conn.commit()
            cache.delete_memoized(get_setting)  # Invalidate stale cache on update
            cache.clear()  # Clear all cached settings
            try:
                from socket_instance import socketio
                socketio.emit('fees_updated', {'key': key})
                socketio.emit('tasks_updated', {})
            except Exception:
                pass
            return jsonify({'message': 'Settings updated'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
