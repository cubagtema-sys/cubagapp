"""
SEC-04: private member documents.

Stored file URLs look like either
  https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>
  /static/uploads/<path>            (local-disk fallback)

Sensitive paths (receipts, compliance & member documents) must only be served
to their owner or to an admin with the matching permission, through a
short-lived signed URL. Public assets (gallery, avatars, logos) are untouched.

This works BEFORE and AFTER the Supabase bucket is switched to private, so the
backend can be deployed first and the bucket flipped afterwards.
"""
import logging
import os
import re
from urllib.parse import unquote, urlparse

import requests

logger = logging.getLogger(__name__)

SIGNED_URL_TTL_SECONDS = 300

SENSITIVE_PREFIXES = (
    'receipts/', 'compliance/', 'compliance_docs/', 'documents/',
    'member_documents/', 'member_docs/', 'private/', 'bank/',
)

# Which admin permission grants access to which kind of document.
_ADMIN_PERMISSION_FOR = {
    'receipts/': 'payments',
    'bank/': 'payments',
    'compliance/': 'compliance',
    'compliance_docs/': 'compliance',
    'member_docs/': 'documents',
    'member_documents/': 'documents',
    'documents/': 'documents',
    'private/': 'documents',
}

_SUPABASE_PATH_RE = re.compile(r'/storage/v1/object/(?:public|sign|authenticated)/([^/]+)/(.+)$')


def _supabase_cfg():
    return (
        os.getenv('SUPABASE_URL', '').strip().strip('\'"').rstrip('/'),
        os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"'),
        os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"'),
    )


def parse_storage_url(raw: str):
    """Return (kind, bucket, path) — kind is 'supabase' | 'local' | None."""
    raw = (raw or '').strip()
    if not raw:
        return None, None, None
    parsed = urlparse(raw)
    m = _SUPABASE_PATH_RE.search(parsed.path or '')
    if m:
        return 'supabase', m.group(1), unquote(m.group(2))
    path = parsed.path if parsed.scheme else raw.split('?', 1)[0]
    for marker in ('/static/uploads/', '/uploads/'):
        if marker in path:
            return 'local', None, unquote(path.split(marker, 1)[1])
    return None, None, None


def normalize_rel_path(path: str) -> str:
    norm = os.path.normpath(path or '').replace('\\', '/').lstrip('/')
    if norm.startswith('..') or '/../' in f'/{norm}/':
        raise ValueError('invalid path')
    return norm


def is_sensitive(path: str) -> bool:
    try:
        p = normalize_rel_path(path)
    except ValueError:
        return True
    return p.startswith(SENSITIVE_PREFIXES)


def _prefix_of(path: str):
    for pre in SENSITIVE_PREFIXES:
        if path.startswith(pre):
            return pre
    return None


def owner_member_id(cursor, path: str):
    """Best-effort: which member owns this document? None if unknown."""
    parts = path.split('/')
    try:
        if parts[0] in ('member_docs', 'member_documents') and len(parts) > 2:
            return int(parts[1])
        if parts[0] in ('compliance_docs', 'compliance') and len(parts) > 2:
            cursor.execute("SELECT member_id FROM compliance_applications WHERE id = %s", (int(parts[1]),))
            row = cursor.fetchone()
            return int(row['member_id']) if row and row.get('member_id') is not None else None
        if parts[0] == 'receipts':
            fname = parts[-1]
            cursor.execute(
                "SELECT member_id FROM payments WHERE receipt_url LIKE %s ORDER BY id DESC LIMIT 1",
                (f'%{fname}',),
            )
            row = cursor.fetchone()
            return int(row['member_id']) if row and row.get('member_id') is not None else None
    except (ValueError, TypeError, KeyError):
        return None
    return None


def can_access(cursor, caller_id, path: str) -> bool:
    from config.authz import has_admin_permission
    path = normalize_rel_path(path)
    if not is_sensitive(path):
        return True
    owner = owner_member_id(cursor, path)
    if owner is not None and str(owner) == str(caller_id):
        return True
    perm = _ADMIN_PERMISSION_FOR.get(_prefix_of(path) or '', 'documents')
    return has_admin_permission(cursor, caller_id, perm)


# ── signing ──────────────────────────────────────────────────────────────────

def _serializer():
    from itsdangerous import URLSafeTimedSerializer
    secret = os.getenv('SECRET_KEY') or 'cubag-secret-placeholder-insecure'
    return URLSafeTimedSerializer(secret, salt='cubag-file-access-v1')


def make_local_file_token(path: str) -> str:
    return _serializer().dumps({'p': normalize_rel_path(path)})


def verify_local_file_token(token: str, path: str) -> bool:
    try:
        data = _serializer().loads(token, max_age=SIGNED_URL_TTL_SECONDS)
        return data.get('p') == normalize_rel_path(path)
    except Exception:
        return False


def signed_url_for(raw_url: str, api_base: str = '') -> str:
    """Return a short-lived URL for ``raw_url`` (caller must already be authorised)."""
    kind, bucket, path = parse_storage_url(raw_url)
    if kind == 'supabase':
        sb_url, sb_key, default_bucket = _supabase_cfg()
        if not sb_url or not sb_key:
            raise RuntimeError('storage not configured')
        r = requests.post(
            f'{sb_url}/storage/v1/object/sign/{bucket or default_bucket}/{path}',
            json={'expiresIn': SIGNED_URL_TTL_SECONDS},
            headers={'apikey': sb_key, 'Authorization': f'Bearer {sb_key}'},
            timeout=10,
        )
        if r.status_code >= 400:
            raise RuntimeError(f'sign failed: {r.status_code}')
        signed = (r.json() or {}).get('signedURL') or (r.json() or {}).get('signedUrl')
        if not signed:
            raise RuntimeError('sign failed: empty response')
        return f'{sb_url}/storage/v1{signed}' if signed.startswith('/') else signed
    if kind == 'local':
        token = make_local_file_token(path)
        return f"{api_base.rstrip('/')}/static/uploads/{normalize_rel_path(path)}?t={token}"
    return raw_url
