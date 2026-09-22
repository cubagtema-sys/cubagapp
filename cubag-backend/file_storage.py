"""
file_storage.py  —  Centralized persistent file storage for CUBAG backend.

Strategy:
  1. Try Supabase cloud first (if configured and reachable).
  2. Fall back to LOCAL PERMANENT storage under <backend_root>/uploads/
     using ABSOLUTE paths so files survive server restarts, process moves,
     and working-directory changes.

All callers get back a public_url they can store in the DB.
Local URLs are served by the existing serve_uploads() / serve_uploaded_file()
route in server.py.
"""

import os
import uuid
import logging
import requests as http_req
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

# Ensure .env is loaded
load_dotenv()

# ── Backend root (absolute, never changes) ───────────────────────────────────
_BACKEND_ROOT = os.path.dirname(os.path.abspath(__file__))
_UPLOADS_ROOT = os.path.join(_BACKEND_ROOT, 'uploads')

# ── Supabase (optional) ───────────────────────────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

from typing import Optional

# Cached connectivity state — avoids hammering a dead endpoint on every upload.
_supabase_ok: Optional[bool] = None  # None = not yet tested


def _test_supabase() -> bool:
    """Return True if Supabase is reachable right now."""
    global _supabase_ok
    if not SUPABASE_URL or not SUPABASE_KEY:
        _supabase_ok = False
        return False
    try:
        r = http_req.get(
            f"{SUPABASE_URL}/storage/v1/bucket",
            headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"},
            timeout=5
        )
        _supabase_ok = r.status_code < 500
        if not _supabase_ok:
            logger.warning("[FileStorage] Supabase unreachable (status %s) — using local storage.", r.status_code)
    except Exception as e:
        logger.warning("[FileStorage] Supabase DNS/connection failure — using local storage. (%s)", e)
        _supabase_ok = False
    return _supabase_ok


def supabase_available() -> bool:
    """Return (cached) Supabase availability."""
    global _supabase_ok
    if _supabase_ok is None:
        _test_supabase()
    return bool(_supabase_ok)


def _upload_to_supabase(file_bytes: bytes, cloud_path: str, content_type: str) -> Optional[str]:
    """Try uploading to Supabase. Returns public URL on success, None otherwise."""
    if not supabase_available():
        return None
    storage_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{cloud_path}"
    try:
        resp = http_req.post(
            storage_url,
            data=file_bytes,
            headers={
                "apikey": SUPABASE_KEY,
                "Authorization": f"Bearer {SUPABASE_KEY}",
                "Content-Type": content_type,
                "x-upsert": "true",
            },
            timeout=20,
        )
        if resp.status_code in (200, 201):
            return f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{cloud_path}"
        logger.warning("[FileStorage] Supabase upload error %s: %s", resp.status_code, resp.text[:200])
    except Exception as e:
        logger.warning("[FileStorage] Supabase upload exception: %s", e)
        global _supabase_ok
        _supabase_ok = False  # mark as broken so we skip on next call
    return None


def _save_local(file_bytes: bytes, subfolder: str, filename: str) -> str:
    """
    Save file_bytes to <backend_root>/uploads/<subfolder>/<filename> using an
    absolute path that is stable across working directory changes.

    Also mirrors to static/uploads/<subfolder>/ so Flask's static handler can
    serve it immediately without any extra config.

    Returns the relative public URL, e.g. /static/uploads/receipts/receipt_abc.jpg
    """
    # 1. Permanent uploads folder (survives restarts)
    abs_dir = os.path.join(_UPLOADS_ROOT, subfolder)
    os.makedirs(abs_dir, exist_ok=True)
    abs_path = os.path.join(abs_dir, filename)
    with open(abs_path, 'wb') as fh:
        fh.write(file_bytes)
    logger.debug("[FileStorage] Saved to %s", abs_path)

    # 2. Mirror to static/uploads so the /static/uploads/... URL resolves
    static_dir = os.path.join(_BACKEND_ROOT, 'static', 'uploads', subfolder)
    os.makedirs(static_dir, exist_ok=True)
    try:
        with open(os.path.join(static_dir, filename), 'wb') as fh:
            fh.write(file_bytes)
    except Exception as e:
        logger.warning("[FileStorage] Could not mirror to static dir: %s", e)

    return f"/static/uploads/{subfolder}/{filename}"


def save_file(
    file_bytes: bytes,
    original_filename: str,
    subfolder: str,
    prefix: str = '',
    content_type: str = 'image/jpeg',
) -> str:
    """
    Main entry point. Saves a file and returns a stable public URL.

    Args:
        file_bytes:        Raw bytes of the file.
        original_filename: Original filename (used to extract extension).
        subfolder:         Subfolder under uploads/, e.g. 'receipts' or 'member_docs/3'.
        prefix:            Optional filename prefix, e.g. 'receipt_' or 'ghana_card_'.
        content_type:      MIME type for Supabase upload header.

    Returns:
        Public URL string (either Supabase https:// or /static/uploads/... path).
    """
    if hasattr(file_bytes, 'read'):
        file_bytes = file_bytes.read()

    import mimetypes
    guessed, _ = mimetypes.guess_type(original_filename)
    if guessed and (content_type == 'image/jpeg' or not content_type):
        content_type = guessed

    ext = original_filename.rsplit('.', 1)[1].lower() if '.' in original_filename else 'jpg'
    unique_id = uuid.uuid4().hex
    safe_filename = f"{prefix}{unique_id}.{ext}"
    cloud_path = f"{subfolder}/{safe_filename}"

    # Try Supabase first
    url = _upload_to_supabase(file_bytes, cloud_path, content_type)
    if url:
        logger.info("[FileStorage] Saved to Supabase: %s", cloud_path)
        return url

    # Permanent local fallback
    url = _save_local(file_bytes, subfolder, safe_filename)
    logger.info("[FileStorage] Saved locally: %s", url)
    return url
