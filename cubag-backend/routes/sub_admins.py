"""
Sub-admin management routes.
Full admins can:
  - Create a sub_admin account (promote an existing member OR create fresh)
  - View all sub_admins
  - Grant / revoke individual permissions
  - Demote / remove a sub_admin
"""
import logging
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required
from config.db import get_db
from utils import admin_required, log_admin_action
from werkzeug.security import generate_password_hash

logger = logging.getLogger(__name__)
sub_admins_bp = Blueprint('sub_admins', __name__)

# All permission keys the system understands
ALL_PERMISSIONS = [
    'members', 'payments', 'tickets', 'announcements',
    'schedules', 'events', 'surveys', 'intelligence', 'audit_log',
    'fees', 'settings', 'compliance', 'documents', 'messaging', 'notifications',
]


def _get_caller_role(cursor, caller_id):
    """B-22/23 fix: null-safe helper that fetches the caller's role.
    Returns the role string, or None if the caller is not found.
    """
    cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
    row = cursor.fetchone()
    return row['role'] if row else None


# ─── GET /sub-admins — list all sub-admins with their permissions ─────────────
@sub_admins_bp.route('/', methods=['GET'])
@admin_required
def list_sub_admins():
    """Only full admins can view this."""
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            role = _get_caller_role(cursor, caller_id)
            if role not in ('admin', 'super_admin'):
                return jsonify({'message': 'Full admin access required'}), 403

            cursor.execute("""
                SELECT m.id, m.name, m.email, m.status, m.created_at,
                       COALESCE(
                           json_agg(p.permission_key ORDER BY p.permission_key)
                           FILTER (WHERE p.permission_key IS NOT NULL AND p.granted = TRUE),
                           '[]'
                       ) as permissions
                FROM members m
                LEFT JOIN sub_admin_permissions p ON p.sub_admin_id = m.id
                WHERE m.role = 'sub_admin'
                GROUP BY m.id
                ORDER BY m.name
            """)
            sub_admins = cursor.fetchall()
            for s in sub_admins:
                if hasattr(s.get('created_at'), 'isoformat'):
                    s['created_at'] = s['created_at'].isoformat()
        return jsonify({'sub_admins': sub_admins, 'all_permissions': ALL_PERMISSIONS}), 200
    except Exception as e:
        logger.error(f'[list_sub_admins] {e}')
        return jsonify({'message': 'Failed to load sub-admins'}), 500
    finally:
        conn.close()


# ─── POST /sub-admins — create a new sub-admin account ───────────────────────
@sub_admins_bp.route('/', methods=['POST'])
@admin_required
def create_sub_admin():
    caller_id = get_jwt_identity()
    data = request.get_json() or {}

    name        = (data.get('name') or '').strip()
    email       = (data.get('email') or '').strip().lower()
    password    = (data.get('password') or '').strip()
    permissions = data.get('permissions', [])  # list of permission_key strings

    if not name or not email or not password:
        return jsonify({'message': 'name, email and password are required'}), 400

    # B-25 fix: enforce minimum password length
    if len(password) < 8:
        return jsonify({'message': 'Password must be at least 8 characters'}), 400

    invalid = [p for p in permissions if p not in ALL_PERMISSIONS]
    if invalid:
        return jsonify({'message': f'Unknown permissions: {invalid}'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            role = _get_caller_role(cursor, caller_id)
            if role not in ('admin', 'super_admin'):
                return jsonify({'message': 'Full admin access required'}), 403

            # Prevent duplicate email (case-insensitive)
            cursor.execute("SELECT id FROM members WHERE LOWER(email) = LOWER(%s)", (email,))
            if cursor.fetchone():
                return jsonify({'message': 'An account with that email already exists'}), 409

            pw_hash = generate_password_hash(password)
            cursor.execute("""
                INSERT INTO members (name, email, password_hash, role, status, email_verified)
                VALUES (%s, %s, %s, 'sub_admin', 'active', TRUE)
                RETURNING id
            """, (name, email, pw_hash))
            new_id = cursor.fetchone()['id']

            # Insert permission rows
            for perm in permissions:
                cursor.execute("""
                    INSERT INTO sub_admin_permissions (sub_admin_id, permission_key, granted)
                    VALUES (%s, %s, TRUE)
                    ON CONFLICT (sub_admin_id, permission_key) DO UPDATE SET granted = TRUE
                """, (new_id, perm))

            conn.commit()

        log_admin_action(
            caller_id, 'Created sub-admin', 'sub_admin', new_id, name,
            f'Permissions: {", ".join(permissions) or "none"}'
        )
        return jsonify({'message': 'Sub-admin created', 'id': new_id}), 201
    except Exception as e:
        conn.rollback()
        logger.error(f'[create_sub_admin] {e}')
        return jsonify({'message': 'Failed to create sub-admin'}), 500
    finally:
        conn.close()


# ─── PUT /sub-admins/<id>/permissions — update permission set ─────────────────
@sub_admins_bp.route('/<int:sub_admin_id>/permissions', methods=['PUT'])
@admin_required
def update_permissions(sub_admin_id):
    caller_id = get_jwt_identity()
    data = request.get_json() or {}
    permissions = data.get('permissions', [])  # full desired list

    invalid = [p for p in permissions if p not in ALL_PERMISSIONS]
    if invalid:
        return jsonify({'message': f'Unknown permissions: {invalid}'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            role = _get_caller_role(cursor, caller_id)
            if role not in ('admin', 'super_admin'):
                return jsonify({'message': 'Full admin access required'}), 403

            cursor.execute("SELECT name, role FROM members WHERE id = %s", (sub_admin_id,))
            target = cursor.fetchone()
            if not target or target['role'] != 'sub_admin':
                return jsonify({'message': 'Sub-admin not found'}), 404

            # Delete all then re-insert the desired set (clean replace)
            cursor.execute("DELETE FROM sub_admin_permissions WHERE sub_admin_id = %s", (sub_admin_id,))
            for perm in permissions:
                cursor.execute("""
                    INSERT INTO sub_admin_permissions (sub_admin_id, permission_key, granted)
                    VALUES (%s, %s, TRUE)
                """, (sub_admin_id, perm))

            conn.commit()

        log_admin_action(
            caller_id, 'Updated sub-admin permissions', 'sub_admin', sub_admin_id, target['name'],
            f'Permissions: {", ".join(permissions) or "none"}'
        )
        return jsonify({'message': 'Permissions updated'}), 200
    except Exception as e:
        conn.rollback()
        logger.error(f'[update_permissions] {e}')
        return jsonify({'message': 'Failed to update permissions'}), 500
    finally:
        conn.close()


# ─── DELETE /sub-admins/<id> — remove sub-admin role (demote to member) ───────
@sub_admins_bp.route('/<int:sub_admin_id>', methods=['DELETE'])
@admin_required
def remove_sub_admin(sub_admin_id):
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            role = _get_caller_role(cursor, caller_id)
            if role not in ('admin', 'super_admin'):
                return jsonify({'message': 'Full admin access required'}), 403

            cursor.execute("SELECT name, role FROM members WHERE id = %s", (sub_admin_id,))
            target = cursor.fetchone()
            if not target or target['role'] != 'sub_admin':
                return jsonify({'message': 'Sub-admin not found'}), 404

            # Demote back to member and remove all permissions
            cursor.execute("UPDATE members SET role = 'member' WHERE id = %s", (sub_admin_id,))
            cursor.execute("DELETE FROM sub_admin_permissions WHERE sub_admin_id = %s", (sub_admin_id,))
            conn.commit()

        log_admin_action(caller_id, 'Removed sub-admin', 'sub_admin', sub_admin_id, target['name'])
        return jsonify({'message': 'Sub-admin demoted to member'}), 200
    except Exception as e:
        conn.rollback()
        logger.error(f'[remove_sub_admin] {e}')
        return jsonify({'message': 'Failed to remove sub-admin'}), 500
    finally:
        conn.close()


# ─── GET /sub-admins/me/permissions — called by Flutter on login ──────────────
@sub_admins_bp.route('/me/permissions', methods=['GET'])
@jwt_required()  # B-24 fix: was @admin_required which blocked sub-admins from calling this
def my_permissions():
    """Returns the permission list for the calling sub-admin (or 'all' for full admin)."""
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            role = _get_caller_role(cursor, caller_id)
            if role is None:
                return jsonify({'message': 'Account not found'}), 404
            if role in ('admin', 'super_admin'):
                return jsonify({'role': role, 'permissions': ALL_PERMISSIONS}), 200
            if role != 'sub_admin':
                return jsonify({'message': 'Not a sub-admin account'}), 403

            cursor.execute("""
                SELECT permission_key FROM sub_admin_permissions
                WHERE sub_admin_id = %s AND granted = TRUE
            """, (caller_id,))
            perms = [r['permission_key'] for r in cursor.fetchall()]
            return jsonify({'role': 'sub_admin', 'permissions': perms}), 200
    except Exception as e:
        logger.error(f'[my_permissions] {e}')
        return jsonify({'message': 'Failed to load permissions'}), 500
    finally:
        conn.close()
