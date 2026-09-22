import os
import uuid
import requests
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from urllib.parse import urlparse

uploads_bp = Blueprint('uploads', __name__)

# ─── Supabase Configuration ──────────────────────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

try:
    from file_storage import save_file as _save_file
except ImportError:
    _save_file = None

ALLOWED = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'avif'}
MAX_SIZE_MB = 10

def allowed(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED

import logging
logger = logging.getLogger(__name__)

@uploads_bp.route('/image', methods=['POST'])
@jwt_required()
def upload_image():
    """
    Uploads an image to Supabase Storage and returns the public URL.
    This ensures images are permanent in production (Railway).
    """
    try:
        file = request.files.get('image') or request.files.get('file')
        if not file or not file.filename:
            return jsonify({'message': 'No file provided'}), 400

        if not allowed(file.filename):
            return jsonify({'message': 'File type not allowed. Use PNG, JPG, JPEG, GIF, WEBP or AVIF.'}), 400

        # Size check
        file.seek(0, 2)
        size_mb = file.tell() / (1024 * 1024)
        file.seek(0)
        if size_mb > MAX_SIZE_MB:
            return jsonify({'message': f'File too large. Max {MAX_SIZE_MB}MB.'}), 413

        ext = file.filename.rsplit('.', 1)[1].lower()
        file_bytes = file.read()
        content_type = file.content_type or 'image/jpeg'

        # Use centralized storage (Supabase → permanent absolute local path)
        if _save_file:
            public_url = _save_file(
                file_bytes,
                original_filename=file.filename,
                subfolder='gallery',
                prefix='gallery_',
                content_type=content_type,
            )
        else:
            import uuid as _uuid
            backend_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            upload_dir = os.path.join(backend_root, 'uploads', 'gallery')
            os.makedirs(upload_dir, exist_ok=True)
            safe_name = f"gallery_{_uuid.uuid4().hex}.{ext}"
            with open(os.path.join(upload_dir, safe_name), 'wb') as f:
                f.write(file_bytes)
            static_dir = os.path.join(backend_root, 'static', 'uploads', 'gallery')
            os.makedirs(static_dir, exist_ok=True)
            try:
                with open(os.path.join(static_dir, safe_name), 'wb') as f:
                    f.write(file_bytes)
            except Exception:
                pass
            public_url = f"/api/uploads/gallery/{safe_name}"

        return jsonify({'url': public_url}), 201
    except Exception as e:
        logger.exception("Error in upload_image: %s", e)
        return jsonify({'message': str(e)}), 500


@uploads_bp.route('/gallery/<filename>', methods=['GET'])
def serve_gallery_image(filename):
    """Serve uploaded gallery image from local disk with caching and CORS headers."""
    from flask import send_from_directory, Response
    backend_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # Check permanent uploads/ dir first, then static/ mirror
    for base in [
        os.path.join(backend_root, 'uploads', 'gallery'),
        os.path.join(backend_root, 'static', 'uploads', 'gallery'),
    ]:
        target = os.path.join(base, filename)
        if os.path.isfile(target):
            resp = send_from_directory(base, filename)
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
            return resp

    return jsonify({'message': 'Image not found'}), 404


@uploads_bp.route('/proxy', methods=['GET'])
@jwt_required()
def proxy_image():
    """Proxy allow-listed image URLs with CORS headers. Requires authentication to prevent SSRF."""
    target_url = request.args.get('url', '').strip()
    if not target_url or not target_url.startswith('https://'):
        return jsonify({'message': 'Valid HTTPS image url is required'}), 400

    try:
        parsed = urlparse(target_url)
        host = (parsed.hostname or '').lower()
    except Exception:
        return jsonify({'message': 'Invalid url'}), 400

    allowed_hosts = {
        'supabase.co',
        'storage.googleapis.com',
        'firebasestorage.googleapis.com',
        'cubag-backend.onrender.com',
        'cubag-production.up.railway.app',
        'cubag-web-app.onrender.com',
    }
    extra = os.getenv('IMAGE_PROXY_ALLOWED_HOSTS', '')
    for h in extra.split(','):
        h = h.strip().lower()
        if h:
            allowed_hosts.add(h)

    host_ok = any(host == allowed or host.endswith('.' + allowed) for allowed in allowed_hosts)
    if not host_ok:
        return jsonify({'message': 'Image host is not allowed'}), 403

    try:
        r = requests.get(target_url, timeout=10, allow_redirects=False)
        content_type = (r.headers.get('Content-Type') or '').lower()
        if r.status_code == 200 and content_type.startswith('image/'):
            from flask import Response
            resp = Response(r.content, mimetype=content_type.split(';')[0])
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=86400'
            return resp
        return jsonify({'message': 'Remote image not found'}), 404
    except Exception as ex:
        logger.warning(f"Failed to proxy image: {ex}")
        return jsonify({'message': 'Failed to proxy image'}), 502
