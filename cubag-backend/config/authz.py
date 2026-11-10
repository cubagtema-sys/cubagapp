"""
Shared authorisation helpers (security hardening batch, Nov 2026).

Keep these small and dependency-free so routes can reuse one implementation
instead of re-deriving role/permission checks inline.
"""
import logging

from flask import request
from flask_jwt_extended import decode_token, get_jwt_identity, verify_jwt_in_request

logger = logging.getLogger(__name__)

ADMIN_ROLES = ('admin', 'sub_admin', 'super_admin')
FULL_ADMIN_ROLES = ('admin', 'super_admin')

# Account statuses that must never be able to authenticate or use a token.
BLOCKED_STATUSES = ('suspended', 'inactive', 'deleted')

BLOCKED_STATUS_MESSAGES = {
    'suspended': 'Your account has been suspended. Please contact the CUBAG Secretariat.',
    'inactive': 'Your account is inactive. Please contact the CUBAG Secretariat.',
    'deleted': 'This account has been deleted.',
}


def caller_id_from_request(allow_query_token: bool = False):
    """Return the authenticated member id (str) or None.

    Prefers the Authorization header. When ``allow_query_token`` is True a
    ``?token=`` query parameter is also accepted — only for endpoints opened in
    a WebView/browser where headers cannot be attached (PDF viewers).
    """
    try:
        verify_jwt_in_request(optional=True)
        ident = get_jwt_identity()
        if ident:
            return str(ident)
    except Exception:
        # Invalid/expired header token: fall through to query token (if allowed)
        pass
    if allow_query_token:
        token = (request.args.get('token') or '').strip()
        if token:
            try:
                decoded = decode_token(token)
                sub = decoded.get('sub')
                return str(sub) if sub else None
            except Exception:
                return None
    return None


def get_role(cursor, member_id):
    cursor.execute("SELECT role FROM members WHERE id = %s", (member_id,))
    row = cursor.fetchone()
    return (row.get('role') if row else None) or None


def has_admin_permission(cursor, member_id, permission: str) -> bool:
    """True for full admins, or sub-admins holding ``permission``."""
    role = get_role(cursor, member_id)
    if role in FULL_ADMIN_ROLES:
        return True
    if role == 'sub_admin':
        cursor.execute(
            "SELECT 1 FROM sub_admin_permissions "
            "WHERE sub_admin_id = %s AND permission_key = %s AND granted = TRUE",
            (member_id, permission),
        )
        return cursor.fetchone() is not None
    return False
