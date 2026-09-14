import os
import uuid
import requests
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

uploads_bp = Blueprint('uploads', __name__)

# ─── Supabase Configuration ──────────────────────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

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
        safe_name = f"gallery_{uuid.uuid4().hex}.{ext}"
        file_bytes = file.read()
        content_type = file.content_type or 'image/jpeg'

        public_url = None
        if SUPABASE_URL and SUPABASE_KEY:
            storage_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"
            headers = {
                "apikey": SUPABASE_KEY,
                "Authorization": f"Bearer {SUPABASE_KEY}",
                "Content-Type": content_type,
                "x-upsert": "true",
            }
            try:
                resp = requests.post(storage_url, data=file_bytes, headers=headers, timeout=15)
                if resp.status_code in (200, 201):
                    public_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{safe_name}"
            except Exception as se:
                logger.warning("Supabase upload failed: %s", se)

        # Always save local backup copy in addition to cloud storage
        upload_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'static', 'uploads', 'gallery')
        os.makedirs(upload_dir, exist_ok=True)
        local_path = os.path.join(upload_dir, safe_name)
        try:
            with open(local_path, 'wb') as f:
                f.write(file_bytes)
        except Exception as le:
            logger.warning("Local backup save warning: %s", le)

        if not public_url:
            public_url = f"/api/uploads/gallery/{safe_name}"

        return jsonify({'url': public_url}), 201
    except Exception as e:
        logger.exception("Error in upload_image: %s", e)
        return jsonify({'message': str(e)}), 500


@uploads_bp.route('/gallery/<filename>', methods=['GET'])
def serve_gallery_image(filename):
    """Serve uploaded gallery image from local disk with caching and CORS headers."""
    from flask import send_from_directory, Response
    upload_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'static', 'uploads', 'gallery')
    if os.path.isfile(os.path.join(upload_dir, filename)):
        resp = send_from_directory(upload_dir, filename)
        resp.headers['Access-Control-Allow-Origin'] = '*'
        resp.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
        return resp

    # Fallback to Supabase if not on local disk
    if SUPABASE_URL:
        supa_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{filename}"
        try:
            r = requests.get(supa_url, timeout=10)
            if r.status_code == 200:
                resp = Response(r.content, mimetype=r.headers.get('Content-Type', 'image/jpeg'))
                resp.headers['Access-Control-Allow-Origin'] = '*'
                resp.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
                return resp
        except Exception:
            pass

    return jsonify({'message': 'Image not found'}), 404


@uploads_bp.route('/proxy', methods=['GET'])
def proxy_image():
    """Proxy external image with CORS headers and long-term caching to prevent broken canvas rendering."""
    target_url = request.args.get('url', '').strip()
    if not target_url or not (target_url.startswith('http://') or target_url.startswith('https://')):
        return jsonify({'message': 'Valid image url is required'}), 400

    try:
        r = requests.get(target_url, timeout=10)
        if r.status_code == 200:
            from flask import Response
            resp = Response(r.content, mimetype=r.headers.get('Content-Type', 'image/jpeg'))
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
            return resp
        return jsonify({'message': 'Remote image not found'}), r.status_code
    except Exception as ex:
        logger.warning(f"Failed to proxy image: {ex}")
        return jsonify({'message': 'Failed to proxy image'}), 502
