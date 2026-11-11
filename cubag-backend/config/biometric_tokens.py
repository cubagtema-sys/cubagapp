"""
SEC-14: revocable, per-device credentials for biometric sign-in.

The phone used to keep the member's real password for Face ID / fingerprint
sign-in. It now keeps a random credential issued here. The server stores only a
SHA-256 hash of it, can expire and revoke it, and rotates it on every use.

No biometric data is involved on the server: the credential proves possession
of an enrolled device; the biometric check itself stays on the phone.

Design and residual risks: docs/CUBAG_SEC14_DESIGN.md
"""
import hashlib
import hmac
import os
import re
import secrets
from datetime import datetime, timedelta, timezone

def _utcnow():
    """Naive UTC, matching the TIMESTAMP columns."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


INVALID_CODE = 'BIOMETRIC_TOKEN_INVALID'
INVALID_MESSAGE = 'Biometric sign-in is no longer valid on this device. Please sign in with your password.'
MAX_DEVICES_PER_MEMBER = 5
MAX_WRONG_ATTEMPTS = 5
ADMIN_ROLES = ('admin', 'sub_admin', 'super_admin')

_DEVICE_ID_RE = re.compile(r'^[A-Za-z0-9_-]{16,64}$')

DDL = """
    CREATE TABLE IF NOT EXISTS biometric_tokens (
        id SERIAL PRIMARY KEY,
        member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
        device_id VARCHAR(64) NOT NULL,
        device_name VARCHAR(120),
        platform VARCHAR(20),
        token_hash CHAR(64) NOT NULL,
        prev_token_hash CHAR(64),
        token_version INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_used_at TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        revoked_at TIMESTAMP,
        revoked_reason VARCHAR(40)
    )
"""
INDEX_DDL = "CREATE INDEX IF NOT EXISTS idx_biometric_tokens_member ON biometric_tokens(member_id, revoked_at)"


def ttl_days() -> int:
    try:
        return max(1, min(365, int(os.getenv('BIOMETRIC_TOKEN_TTL_DAYS', '90'))))
    except (TypeError, ValueError):
        return 90


def valid_device_id(device_id) -> bool:
    return isinstance(device_id, str) and bool(_DEVICE_ID_RE.match(device_id))


def hash_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode('utf-8')).hexdigest()


def _same(a, b) -> bool:
    return hmac.compare_digest(str(a or '').strip(), str(b or '').strip())


def format_credential(row_id: int, secret: str) -> str:
    return f'{row_id}.{secret}'


def parse_credential(credential):
    """'<id>.<secret>' -> (id, secret) or (None, None)."""
    if not isinstance(credential, str) or len(credential) > 200:
        return None, None
    head, sep, secret = credential.partition('.')
    if not sep or not head.isdigit() or len(head) > 12 or len(secret) < 32:
        return None, None
    return int(head), secret


def _clean(text, limit):
    text = re.sub(r'[\x00-\x1f\x7f]', '', str(text or '')).strip()
    return text[:limit] or None


def issue(cursor, member_id, device_id, token_version, device_name=None, platform=None) -> dict:
    """Create a credential for this device, replacing any earlier one for the
    same device and keeping at most MAX_DEVICES_PER_MEMBER active devices."""
    cursor.execute(
        "UPDATE biometric_tokens SET revoked_at = NOW(), revoked_reason = 'replaced' "
        "WHERE member_id = %s AND device_id = %s AND revoked_at IS NULL",
        (member_id, device_id),
    )
    cursor.execute(
        "SELECT id FROM biometric_tokens WHERE member_id = %s AND revoked_at IS NULL "
        "ORDER BY created_at DESC, id DESC",
        (member_id,),
    )
    active = [r['id'] for r in (cursor.fetchall() or [])]
    for old_id in active[MAX_DEVICES_PER_MEMBER - 1:]:
        cursor.execute(
            "UPDATE biometric_tokens SET revoked_at = NOW(), revoked_reason = 'device_limit' WHERE id = %s",
            (old_id,),
        )
    secret = secrets.token_urlsafe(32)
    expires_at = _utcnow() + timedelta(days=ttl_days())
    cursor.execute(
        "INSERT INTO biometric_tokens (member_id, device_id, device_name, platform, token_hash, token_version, expires_at) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (member_id, device_id, _clean(device_name, 120), _clean(platform, 20),
         hash_secret(secret), int(token_version or 0), expires_at),
    )
    row_id = cursor.fetchone()['id']
    return {'biometric_token': format_credential(row_id, secret),
            'device_id': device_id,
            'expires_at': expires_at.isoformat() + 'Z'}


def revoke_row(cursor, row_id, reason) -> None:
    cursor.execute(
        "UPDATE biometric_tokens SET revoked_at = NOW(), revoked_reason = %s "
        "WHERE id = %s AND revoked_at IS NULL",
        (reason, row_id),
    )


def revoke_device(cursor, member_id, device_id, reason='user_revoked') -> None:
    cursor.execute(
        "UPDATE biometric_tokens SET revoked_at = NOW(), revoked_reason = %s "
        "WHERE member_id = %s AND device_id = %s AND revoked_at IS NULL",
        (reason, member_id, device_id),
    )


def revoke_all(cursor, member_id, reason) -> None:
    """Called on password change/reset, email change, account deletion and
    'sign out everywhere'. Isolated with a savepoint so that a database without
    the table yet can never break those flows."""
    try:
        cursor.execute("SAVEPOINT bio_revoke")
        cursor.execute(
            "UPDATE biometric_tokens SET revoked_at = NOW(), revoked_reason = %s "
            "WHERE member_id = %s AND revoked_at IS NULL",
            (reason, member_id),
        )
        cursor.execute("RELEASE SAVEPOINT bio_revoke")
    except Exception:
        try:
            cursor.execute("ROLLBACK TO SAVEPOINT bio_revoke")
        except Exception:
            pass


def check(cursor, credential, device_id):
    """Validate a presented credential under a row lock.

    Returns (row, None) when it is good, or (None, reason) when it is not.
    Revokes the credential when the failure indicates theft or staleness.
    The caller decides what to tell the client (always the same generic text).
    """
    row_id, secret = parse_credential(credential)
    if row_id is None or not valid_device_id(device_id):
        return None, 'malformed'
    cursor.execute("SELECT * FROM biometric_tokens WHERE id = %s FOR UPDATE", (row_id,))
    row = cursor.fetchone()
    if not row:
        return None, 'unknown'
    if row.get('revoked_at') is not None:
        return None, 'revoked'
    presented = hash_secret(secret)
    if row.get('prev_token_hash') and _same(presented, row['prev_token_hash']):
        # An already-rotated credential came back: it was copied. Kill the device.
        revoke_row(cursor, row_id, 'reuse_detected')
        return None, 'reuse_detected'
    if not _same(presented, row.get('token_hash')):
        return None, 'wrong_secret'
    if not _same(device_id, row.get('device_id')):
        revoke_row(cursor, row_id, 'device_mismatch')
        return None, 'device_mismatch'
    expires_at = row.get('expires_at')
    if expires_at is None or expires_at <= _utcnow():
        revoke_row(cursor, row_id, 'expired')
        return None, 'expired'
    return row, None


def rotate(cursor, row_id, current_hash) -> str:
    """Single-use: swap in a new secret and remember the old hash for reuse detection."""
    secret = secrets.token_urlsafe(32)
    cursor.execute(
        "UPDATE biometric_tokens SET prev_token_hash = %s, token_hash = %s, last_used_at = NOW() WHERE id = %s",
        (str(current_hash).strip(), hash_secret(secret), row_id),
    )
    return format_credential(row_id, secret)


def list_devices(cursor, member_id) -> list:
    cursor.execute(
        "SELECT id, device_id, device_name, platform, created_at, last_used_at, expires_at "
        "FROM biometric_tokens WHERE member_id = %s AND revoked_at IS NULL AND expires_at > %s "
        "ORDER BY created_at DESC",
        (member_id, _utcnow()),
    )
    out = []
    for r in cursor.fetchall() or []:
        out.append({
            'id': r['id'], 'device_id': r['device_id'], 'device_name': r.get('device_name'),
            'platform': r.get('platform'),
            'created_at': r['created_at'].isoformat() if r.get('created_at') else None,
            'last_used_at': r['last_used_at'].isoformat() if r.get('last_used_at') else None,
            'expires_at': r['expires_at'].isoformat() if r.get('expires_at') else None,
        })
    return out
