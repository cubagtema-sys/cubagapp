"""
SEC-12: second factor for administrator sign-in (email one-time code).

A correct password for an admin / sub_admin / super_admin no longer returns a
session token. Instead the server emails a 6-digit code to the account's
address and returns a short-lived challenge credential ('<id>.<secret>').
POST /auth/login/mfa with that credential and the code completes sign-in.

Only hashes are stored. A challenge is single-use, expires after
CODE_TTL_MINUTES, and is burnt after MAX_WRONG_ATTEMPTS wrong codes. Starting a
new challenge cancels any earlier unused one for the same account.

Emergency switch: ADMIN_MFA_REQUIRED=false turns the step off (e.g. if email
delivery is broken and no admin can sign in). Leave it on in production.
"""
import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone

ADMIN_ROLES = ('admin', 'sub_admin', 'super_admin')
CODE_TTL_MINUTES = 10
MAX_WRONG_ATTEMPTS = 5
INVALID_MESSAGE = 'This sign-in code is invalid or has expired. Please sign in again.'

DDL = """
    CREATE TABLE IF NOT EXISTS admin_mfa_challenges (
        id SERIAL PRIMARY KEY,
        member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
        token_hash CHAR(64) NOT NULL,
        code_hash CHAR(64) NOT NULL,
        attempts INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        used_at TIMESTAMP
    )
"""
INDEX_DDL = (
    "CREATE INDEX IF NOT EXISTS idx_admin_mfa_challenges_member "
    "ON admin_mfa_challenges(member_id, used_at)"
)


def _utcnow():
    """Naive UTC, matching the TIMESTAMP columns."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def required() -> bool:
    return os.getenv('ADMIN_MFA_REQUIRED', 'true').strip().lower() not in ('0', 'false', 'no', 'off')


def applies_to(member) -> bool:
    return required() and (member.get('role') or 'member') in ADMIN_ROLES


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def _code_hash(row_id: int, code: str) -> str:
    # Bound to the challenge id so equal codes never share a hash.
    return _hash(f'{row_id}:{code}')


def mask_email(email: str) -> str:
    local, _, domain = (email or '').partition('@')
    if not domain:
        return ''
    return f'{local[:1]}***@{domain}'


def parse_credential(credential):
    """'<id>.<secret>' -> (id, secret) or (None, None)."""
    if not isinstance(credential, str) or len(credential) > 200:
        return None, None
    head, sep, secret = credential.partition('.')
    if not sep or not head.isdigit() or len(secret) < 32:
        return None, None
    return int(head), secret


def start(cursor, member_id):
    """Create a challenge. Returns (credential, code). Caller commits and emails."""
    cursor.execute(
        "UPDATE admin_mfa_challenges SET used_at = %s WHERE member_id = %s AND used_at IS NULL",
        (_utcnow(), member_id),
    )
    secret = secrets.token_urlsafe(32)
    code = f'{secrets.randbelow(1_000_000):06d}'
    cursor.execute(
        """
        INSERT INTO admin_mfa_challenges (member_id, token_hash, code_hash, expires_at)
        VALUES (%s, %s, %s, %s) RETURNING id
        """,
        (member_id, _hash(secret), '0' * 64, _utcnow() + timedelta(minutes=CODE_TTL_MINUTES)),
    )
    row_id = cursor.fetchone()['id']
    cursor.execute(
        "UPDATE admin_mfa_challenges SET code_hash = %s WHERE id = %s",
        (_code_hash(row_id, code), row_id),
    )
    return f'{row_id}.{secret}', code


def verify(cursor, credential, code):
    """Returns (member_id, None) on success, else (None, reason). Caller commits
    in both cases, so attempt counts and burnt challenges persist."""
    row_id, secret = parse_credential(credential)
    if row_id is None:
        return None, 'malformed'
    code = str(code or '').strip()
    cursor.execute(
        "SELECT id, member_id, token_hash, code_hash, attempts, expires_at, used_at "
        "FROM admin_mfa_challenges WHERE id = %s FOR UPDATE",
        (row_id,),
    )
    row = cursor.fetchone()
    if not row or not hmac.compare_digest(str(row['token_hash']), _hash(secret)):
        return None, 'unknown'
    if row.get('used_at') is not None:
        return None, 'used'
    if row['expires_at'] <= _utcnow():
        return None, 'expired'
    if not (code.isdigit() and len(code) == 6 and
            hmac.compare_digest(str(row['code_hash']), _code_hash(row_id, code))):
        attempts = int(row.get('attempts') or 0) + 1
        burnt = attempts >= MAX_WRONG_ATTEMPTS
        cursor.execute(
            "UPDATE admin_mfa_challenges SET attempts = %s, used_at = %s WHERE id = %s",
            (attempts, _utcnow() if burnt else None, row_id),
        )
        return None, 'burnt' if burnt else 'wrong_code'
    cursor.execute("UPDATE admin_mfa_challenges SET used_at = %s WHERE id = %s", (_utcnow(), row_id))
    return row['member_id'], None
