import logging
from flask import Blueprint, jsonify, request
from config.db import get_db
from utils import admin_required

logger = logging.getLogger(__name__)
compliance_settings_bp = Blueprint('compliance_settings', __name__)


def _ensure_schema(cursor):
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS payment_punctual INT DEFAULT 25")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS payment_history INT DEFAULT 15")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS license_active INT DEFAULT 15")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS license_inactive INT DEFAULT 5")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS task_completion INT DEFAULT 15")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS survey_completion INT DEFAULT 10")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS agm_active INT DEFAULT 10")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS agm_inactive INT DEFAULT 5")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")


@compliance_settings_bp.route('/', methods=['GET'])
@admin_required
def get_settings():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_schema(cursor)
            cursor.execute("SELECT COUNT(*) FROM compliance_settings")
            if cursor.fetchone()['count'] == 0:
                cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")
            cursor.execute("SELECT * FROM compliance_settings ORDER BY id DESC, updated_at DESC NULLS LAST LIMIT 1")
            settings = cursor.fetchone()
            if not settings:
                settings = {
                    'payment_punctual': 25, 'payment_history': 15,
                    'license_active': 15, 'license_inactive': 5,
                    'task_completion': 15, 'survey_completion': 10,
                    'agm_active': 10, 'agm_inactive': 5,
                    'renewal_fee': 500.00,
                    'customs_licence_fee': 750.00,
                }
            else:
                settings = dict(settings)
                settings.setdefault('payment_punctual', 25)
                settings.setdefault('payment_history', 15)
                settings.setdefault('license_active', 15)
                settings.setdefault('license_inactive', 5)
                settings.setdefault('task_completion', 15)
                settings.setdefault('survey_completion', 10)
                settings.setdefault('agm_active', 10)
                settings.setdefault('agm_inactive', 5)
                settings.setdefault('renewal_fee', 500.00)
                settings.setdefault('customs_licence_fee', 750.00)
        return jsonify(settings), 200
    except Exception as e:
        logger.exception("Error fetching compliance settings: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@compliance_settings_bp.route('/', methods=['PUT'])
@admin_required
def update_settings():
    data = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_schema(cursor)
            # Check if exists
            cursor.execute("SELECT COUNT(*) FROM compliance_settings")
            count = cursor.fetchone()['count']
            if count == 0:
                cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")

            cursor.execute("SELECT id FROM compliance_settings ORDER BY id DESC, updated_at DESC NULLS LAST LIMIT 1")
            latest_row = cursor.fetchone()
            if not latest_row:
                cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")
                cursor.execute("SELECT id FROM compliance_settings ORDER BY id DESC, updated_at DESC NULLS LAST LIMIT 1")
                latest_row = cursor.fetchone()

            target_id = latest_row['id']
            cursor.execute("""
                UPDATE compliance_settings SET 
                    payment_punctual = %s,
                    payment_history = %s,
                    license_active = %s,
                    license_inactive = %s,
                    task_completion = %s,
                    survey_completion = %s,
                    agm_active = %s,
                    agm_inactive = %s,
                    renewal_fee = %s,
                    customs_licence_fee = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """, (
                int(data.get('payment_punctual', 25)),
                int(data.get('payment_history', 15)),
                int(data.get('license_active', 15)),
                int(data.get('license_inactive', 5)),
                int(data.get('task_completion', 15)),
                int(data.get('survey_completion', 10)),
                int(data.get('agm_active', 10)),
                int(data.get('agm_inactive', 5)),
                float(data.get('renewal_fee', 500.00)),
                float(data.get('customs_licence_fee', 750.00)),
                target_id,
            ))
            conn.commit()
            
            # Recalculate for all members
            cursor.execute("SELECT id FROM members WHERE status IN ('active', 'pending')")
            members = cursor.fetchall()
            
        # Re-fetch cursor to prevent holding lock during recalculation
        from utils import calculate_and_update_member_rating
        for m in members:
            calculate_and_update_member_rating(m['id'])
            
        return jsonify({'message': 'Settings updated and all member scores recalculated.'}), 200
    except Exception as e:
        logger.exception("Error updating compliance settings: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
