# Removed eventlet to avoid psycopg2 kqueue bugs on macOS
import hashlib
try:
    # macOS system Python is compiled against LibreSSL and lacks hashlib.scrypt.
    # We monkey-patch it using cryptography's implementation if missing.
    if not hasattr(hashlib, 'scrypt'):
        from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
        from cryptography.hazmat.backends import default_backend

        def _scrypt_fallback(password, *, salt, n, r, p, maxmem=0, dklen=64):
            kdf = Scrypt(
                salt=salt,
                length=dklen,
                n=n,
                r=r,
                p=p,
                backend=default_backend()
            )
            return kdf.derive(password)

        hashlib.scrypt = _scrypt_fallback
except Exception:
    pass

import os
import json
import logging
import sys
import time
from flask import g
from flask import Flask, jsonify, request, send_from_directory, send_file
from flask_cors import CORS
from flask_jwt_extended import JWTManager, get_jwt_identity, verify_jwt_in_request
from dotenv import load_dotenv
from datetime import timedelta
import firebase_admin

load_dotenv(os.path.join(os.path.dirname(__file__), '.env'))
from firebase_admin import credentials
from utils import log_admin_action

# ── Configure logging ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)
logger = logging.getLogger(__name__)

# ── Sentry Error Reporting ─────────────────────────────────────────────────────
# Set SENTRY_DSN in your environment to enable error tracking.
# Get your DSN from https://sentry.io → Project Settings → Client Keys.
_SENTRY_DSN = os.getenv('SENTRY_DSN', '').strip()
if _SENTRY_DSN:
    try:
        import sentry_sdk
        from sentry_sdk.integrations.flask import FlaskIntegration
        from sentry_sdk.integrations.logging import LoggingIntegration
        sentry_sdk.init(
            dsn=_SENTRY_DSN,
            integrations=[
                FlaskIntegration(),
                LoggingIntegration(level=logging.WARNING, event_level=logging.ERROR),
            ],
            traces_sample_rate=0.2,   # 20% of requests profiled for performance
            profiles_sample_rate=0.1,
            environment=os.getenv('FLASK_ENV', 'production'),
            send_default_pii=False,   # Don't send user PII to Sentry
        )
        logger.info("[Sentry] Error reporting initialized ✓")
    except Exception as _se:
        logger.warning(f"[Sentry] Failed to initialize: {_se}")
else:
    logger.info("[Sentry] SENTRY_DSN not set — error reporting disabled (local mode)")

logger.info("Starting CUBAG Production Backend...")
logger.info(f"Python {sys.version}")
logger.info(f"PORT env = {os.getenv('PORT', 'NOT SET')}")
logger.info(f"DB_HOST env = {'SET' if os.getenv('DB_HOST') or os.getenv('DATABASE_URL') else 'NOT SET'}")
logger.info(f"SECRET_KEY env = {'SET' if os.getenv('SECRET_KEY') else 'NOT SET'}")
logger.info(f"JWT_SECRET_KEY env = {'SET' if os.getenv('JWT_SECRET_KEY') else 'NOT SET'}")

from config.db import get_db, init_db
from config.cache import cache
from config.csrf import validate_csrf_token, CSRF_PROTECTED_METHODS, CSRF_EXEMPT_ENDPOINTS
from routes.auth import auth_bp
from routes.members import members_bp
from routes.announcements import announcements_bp
from routes.tasks import tasks_bp
from routes.payments import payments_bp
from routes.events_surveys import events_bp, surveys_bp
from routes.sub_admins import sub_admins_bp

# ── Resolve static file path (Flutter web build or fallback) ─────────────────
FLUTTER_BUILD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'cubag_flutter', 'build', 'web'))
if os.path.isdir(FLUTTER_BUILD_DIR) and os.path.isfile(os.path.join(FLUTTER_BUILD_DIR, 'main.dart.js')):
    STATIC_DIR = FLUTTER_BUILD_DIR
else:
    STATIC_DIR = os.path.join(os.path.dirname(__file__), 'static')
    if not os.path.isdir(STATIC_DIR):
        STATIC_DIR = os.path.join(os.path.dirname(__file__), 'dist')

# Create Flask app
app = Flask(__name__, static_folder=STATIC_DIR, static_url_path='')
app.url_map.strict_slashes = False
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

@app.after_request
def add_security_headers(response):
    """Add comprehensive security headers to prevent common vulnerabilities."""
    # Cache control (already present)
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    
    # Security headers for XSS, clickjacking, and other attacks
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # Content Security Policy (CSP) - restricts sources of content
    csp_directives = [
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://www.google.com https://www.gstatic.com",
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.googleapis.com",
        "img-src 'self' data: https: http:",
        "font-src 'self' https://fonts.gstatic.com https://fonts.googleapis.com",
        "connect-src 'self' https://api.whitsun.dev https://developer.whitsun.dev https://whitsun.dev wss://*.fly.dev https://*.fly.dev https://cubag-api-server.fly.dev wss://*.onrender.com wss://*.railway.app https://www.gstatic.com https://fonts.gstatic.com https://fonts.googleapis.com https://cubag-api-server.onrender.com",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'",
    ]
    response.headers['Content-Security-Policy'] = '; '.join(csp_directives)
    
    # HSTS (HTTP Strict Transport Security) - only in production
    if not IS_DEBUG:
        response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
    
    return response

# Auto-run DB migrations & schema setup on startup
try:
    init_db()
except Exception as e:
    logger.exception("Failed to run init_db on server start: %s", e)

# Initialize Firebase Admin
try:
    firebase_json_env = os.getenv('FIREBASE_CREDENTIALS_JSON') or os.getenv('FIREBASE_SERVICE_ACCOUNT')
    cred_path = os.getenv('FIREBASE_CREDENTIALS', 'firebase-key.json')  # Updated to match project file
    
    if firebase_json_env:
        try:
            cred_dict = json.loads(firebase_json_env)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            logger.info("Firebase Admin initialized from ENV.")
        except Exception as e:
            logger.error(f"Error initializing Firebase from ENV: {e}")
    elif os.path.exists(cred_path):
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        logger.info(f"Firebase Admin initialized from FILE: {cred_path}")
    else:
        logger.warning("Firebase credentials not found. Push notifications will be disabled.")
except Exception as e:
    logger.error(f"Failed to initialize Firebase Admin: {e}")

# Config
# SECURITY: In production, app will fail to start if these secrets are not provided.
_DEFAULT_SECRET = 'cubag-secret-placeholder-insecure'
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', _DEFAULT_SECRET)
app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', _DEFAULT_SECRET)
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(seconds=int(os.getenv('JWT_ACCESS_TOKEN_EXPIRES', 604800)))

# PRODUCTION GUARD: Ensure we are not using default secrets in non-debug mode
IS_DEBUG = os.getenv('FLASK_DEBUG', 'false').lower() == 'true'
if not IS_DEBUG:
    if app.config['SECRET_KEY'] == _DEFAULT_SECRET or app.config['JWT_SECRET_KEY'] == _DEFAULT_SECRET:
        logger.critical("[SECURITY] PRODUCTION FAILURE: SECRET_KEY or JWT_SECRET_KEY is missing or insecure! Set these env vars before deploying.")
        logger.critical("[SECURITY] Set SECRET_KEY and JWT_SECRET_KEY in your Railway environment variables.")
        # Log all env var names (not values) for debugging
        logger.critical(f"[SECURITY] Available env vars: {list(os.environ.keys())}")
        # Fail fast in production to avoid running with insecure defaults
        sys.exit(1)

# Extensions — restrict CORS to explicitly allowed origins
_RAW_ORIGINS = os.getenv(
    'CORS_ALLOWED_ORIGINS',
    'https://cubag-backend.onrender.com,https://cubag-production.up.railway.app,http://localhost:8080,http://127.0.0.1:8080'
)
# Mobile apps (Android/iOS APK/IPA) send requests with no Origin header (null origin).
# We must include "*" OR handle the null case to allow native apps to reach the API.
_CORS_ORIGINS = [o.strip() for o in _RAW_ORIGINS.split(',') if o.strip()]

CORS(
    app,
    origins="*",          # Allow ALL origins — mobile APKs send null/no Origin
    supports_credentials=False,   # Must be False when origins="*"
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Requested-With", "Cache-Control", "cache-control", "Pragma", "Origin", "X-CSRF-Token"],
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
)


JWTManager(app)
cache.init_app(app)


def _is_admin_api_path(path):
    return path.startswith('/api/v1/admin') or \
           path.startswith('/api/admin') or (
               (path.startswith('/api/v1/') or path.startswith('/api/')) and '/admin/' in path
           )

@app.before_request
def require_admin_role_for_admin_api():
    if request.method == 'OPTIONS':
        return None

    # 1. Automatic Admin Activity Logging
    is_admin_path = request.path.startswith('/api/v1/admin/') or request.path.startswith('/api/admin/')
    if is_admin_path:
        is_write = request.method in ('POST', 'PUT', 'DELETE', 'PATCH')
        is_sensitive_read = request.method == 'GET' and any(k in request.path for k in ('audit-log', 'export', 'members', 'payments', 'credentials', 'sub-admins'))
        if is_write or is_sensitive_read:
            try:
                verify_jwt_in_request()
                admin_id = get_jwt_identity()
                if admin_id:
                    clean_path = request.path.replace('/api/v1/admin/', '').replace('/api/admin/', '')
                    action_desc = f"{request.method} {clean_path}"
                    # ── Scrub sensitive fields before logging ─────────────────────
                    import json as _json
                    _SENSITIVE = {'password', 'password_hash', 'current_password',
                                  'new_password', 'token', 'secret', 'api_key', 'key'}
                    try:
                        _body = _json.loads(request.get_data(as_text=True) or '{}')
                        if isinstance(_body, dict):
                            _body = {k: ('***' if k.lower() in _SENSITIVE else v)
                                     for k, v in _body.items()}
                        _payload_log = _json.dumps(_body)[:300]
                    except Exception:
                        _payload_log = '[unreadable body]'
                    log_admin_action(admin_id, 'Admin Action', 'system', None, action_desc,
                                     f"Payload: {_payload_log}")
            except Exception as e:
                logger.exception("Failed to log admin action: %s", e)

    # 2. Access Control for Admin Routes
    if not _is_admin_api_path(request.path):
        return None

    try:
        verify_jwt_in_request()
        member_id = get_jwt_identity()
        if not member_id:
            return jsonify({'message': 'Missing or invalid authorization token'}), 401

        conn = get_db()
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT role FROM members WHERE id = %s", (member_id,))
                row = cursor.fetchone()
                role = (row.get('role') if row else None) or ''
        finally:
            conn.close()

        if role not in ('admin', 'sub_admin', 'super_admin'):
            return jsonify({'message': 'Admin access required'}), 403

    except Exception:
        return jsonify({'message': 'Missing or invalid authorization token'}), 401

    return None


@app.before_request
def enforce_csrf_protection():
    """
    CSRF protection for state-changing operations.
    Validates CSRF tokens for POST/PUT/DELETE/PATCH requests except for exempt endpoints.
    """
    if request.method == 'OPTIONS':
        return None
    
    # Skip CSRF for exempt endpoints
    if request.path in CSRF_EXEMPT_ENDPOINTS:
        return None
    
    # Only apply to state-changing methods
    if request.method not in CSRF_PROTECTED_METHODS:
        return None
    
    # Skip for static files and non-API routes
    if not request.path.startswith('/api/'):
        return None
    
    # Validate CSRF token
    is_valid, error_msg = validate_csrf_token()
    if not is_valid:
        logger.warning(f"CSRF validation failed for {request.method} {request.path}")
        return jsonify({'message': error_msg}), 403
    
    return None


@app.before_request
def enforce_account_status():
    """
    CROSS-04: Check live member status on every authenticated API call.
    This makes account suspension/deactivation take effect immediately
    without needing a JWT blocklist or Redis — the DB is the source of truth.
    Skips: OPTIONS preflight, public auth endpoints, static files.
    """
    if request.method == 'OPTIONS':
        return None

    # Only check protected API routes (skip auth, public, static)
    _OPEN_PREFIXES = ('/api/v1/auth/', '/api/auth/', '/static/', '/#')
    if any(request.path.startswith(p) for p in _OPEN_PREFIXES):
        return None
    if not request.path.startswith('/api/v1/') and not request.path.startswith('/api/'):
        return None

    try:
        verify_jwt_in_request(optional=True)
        member_id = get_jwt_identity()
        if not member_id:
            return None  # unauthenticated request — let route handle it

        cache_key = f'live_status_{member_id}'
        status = cache.get(cache_key)
        if status is None:
            conn = get_db()
            try:
                with conn.cursor() as cursor:
                    cursor.execute(
                        "SELECT status FROM members WHERE id = %s",
                        (member_id,)
                    )
                    row = cursor.fetchone()
                    status = str(row.get('status') or '').lower() if row else ''
                    cache.set(cache_key, status, timeout=15)
            finally:
                conn.close()

        if status == 'suspended':
            return jsonify({
                'message': 'Your account has been suspended. Please contact the CUBAG Secretariat.'
            }), 403
        if status == 'inactive':
            return jsonify({
                'message': 'Your account is inactive. Please contact the CUBAG Secretariat.'
            }), 403

    except Exception as e:
        logger.error('[enforce_account_status] Status check failed: %s', e)
        return jsonify({'message': 'Unable to verify account status. Please try again.'}), 503

    return None



@app.before_request
def _start_request_timer():
    try:
        g._start_time = time.time()
    except Exception:
        pass


@app.after_request
def _log_request_time(response):
    try:
        if request.path.startswith('/api/'):
            # Cache headers are now handled by add_security_headers
            start = getattr(g, '_start_time', None)
            if start:
                duration = time.time() - start
                logger.info("%s %s completed in %.3fs", request.method, request.path, duration)
                response.headers['X-Response-Time'] = f"{duration:.3f}s"
    except Exception:
        pass
    return response

# Initialize SocketIO
from socket_instance import socketio
from flask_socketio import join_room
socketio.init_app(app)


@socketio.on('connect')
def _socket_connect(auth):
    """Authenticate the socket and join member-scoped rooms for private events."""
    from flask import request as flask_request
    from flask_jwt_extended import decode_token

    token = None
    if isinstance(auth, dict):
        token = auth.get('token')
    if not token:
        token = flask_request.args.get('token')
    if not token:
        hdr = flask_request.headers.get('Authorization', '')
        if hdr.lower().startswith('bearer '):
            token = hdr[7:].strip()
    if not token:
        return False

    try:
        decoded = decode_token(token)
        member_id = decoded.get('sub')
        if member_id:
            join_room(f'member_{member_id}')
            try:
                conn = get_db()
                try:
                    with conn.cursor() as cursor:
                        cursor.execute("SELECT role FROM members WHERE id = %s", (member_id,))
                        row = cursor.fetchone()
                        role = (row.get('role') if row else '') or ''
                finally:
                    conn.close()
            except Exception:
                role = decoded.get('role') or ''
            if role in ('admin', 'sub_admin', 'super_admin'):
                join_room('admins')
    except Exception as e:
        logger.debug('[Socket] connect auth failed: %s', e)
        return False
    return True

# Initialize Background Workers (Beta)
try:
    logger.info("[Init] Starting background workers...")
    from ais_stream import ais_manager
    ais_manager.start()
    logger.info("[Init] AIS manager started.")

    from routes.news import start_news_worker
    start_news_worker()
    logger.info("[Init] News worker started.")

    from jobs import start_scheduler
    start_scheduler()

    @socketio.on('track_vessel')
    def handle_track_vessel(data):
        mmsi = data.get('mmsi')
        logger.info(f"[AIS] Search request for MMSI: {mmsi}")
        if mmsi:
            ais_manager.add_track(mmsi)
    logger.info("[Init] All background workers started successfully.")
except Exception as e:
    logger.error(f"[Init] Failed to start background workers: {e}", exc_info=True)

# ── Register blueprints (API compatibility: support both /api/v1 and /api) ───
from routes.news import news_bp
from routes.notifications import notifications_bp
from routes.admin import admin_bp
from routes.schedules import schedules_bp
from routes.messages import messages_bp
from routes.tickets import tickets_bp
from routes.settings import settings_bp
from routes.intelligence import intelligence_bp
from routes.uploads import uploads_bp
from routes.compliance_settings import compliance_settings_bp
from routes.documents import documents_bp
from routes.compliance import compliance_bp
from routes.complaints import complaints_bp
from routes.gdpr import gdpr_bp

_BLUEPRINTS = [
    (auth_bp,          '/auth'),
    (members_bp,       '/members'),
    (announcements_bp, '/announcements'),
    (notifications_bp, '/notifications'),
    (tasks_bp,         '/tasks'),
    (payments_bp,      '/payments'),
    (events_bp,        '/events'),
    (surveys_bp,       '/surveys'),
    (admin_bp,         '/admin'),
    (schedules_bp,     '/schedules'),
    (messages_bp,      '/messages'),
    (tickets_bp,       '/tickets'),
    (settings_bp,      '/settings'),
    (intelligence_bp,  '/intelligence'),
    (uploads_bp,       '/uploads'),
    (news_bp,          '/news'),
    (sub_admins_bp,    '/sub-admins'),
    (compliance_settings_bp, '/compliance-settings'),
    (documents_bp,     '/documents'),
    (compliance_bp,    '/compliance'),
    (complaints_bp,    '/complaints'),
    (gdpr_bp,          '/gdpr'),
]

for bp, prefix in _BLUEPRINTS:
    # Register with v1 (standard)
    app.register_blueprint(bp, url_prefix=f'/api/v1{prefix}')
    # Register without v1 (for compatibility with existing web builds)
    app.register_blueprint(bp, url_prefix=f'/api{prefix}', name=f"{bp.name}_compat")

@app.route('/api/ping', methods=['GET'])
@app.route('/api/v1/ping', methods=['GET'])
def ping():
    return 'pong', 200

@app.route('/api/health', methods=['GET'])
@app.route('/api/v1/health', methods=['GET'])
def health():
    return {'status': 'CUBAG API is running'}, 200

@app.route('/api/vessels', methods=['GET'])
@app.route('/api/v1/vessels', methods=['GET'])
def get_vessels():
    try:
        from ais_stream import ais_manager
        with ais_manager.lock:
            vessels = list(ais_manager.active_vessels.values())
        # B-31 fix: wrap in 'items' for consistent Flutter data service parsing
        return jsonify({'items': vessels, 'total': len(vessels)}), 200
    except Exception as e:
        logger.error(f"Error in /api/vessels: {e}")
        return jsonify({'items': [], 'total': 0}), 200


@app.route('/api/vessels/registry', methods=['GET'])
@app.route('/api/v1/vessels/registry', methods=['GET'])
def get_vessel_registry():
    """
    Known vessel registry for Gulf of Guinea shipping lanes.
    Used by Flutter for autocomplete suggestions when the live AIS stream
    doesn't yet have a vessel. Centralised here so it can be updated without
    a new app release.
    """
    registry = [
        {'name': 'Maersk Charleston',   'mmsi': '563297800', 'imo': '9454199', 'flag': 'Singapore',       'type': 'Container Ship',             'length': '266', 'width': '37', 'callsign': '9V8129', 'departure_port': 'Tema, Ghana', 'atd': '2026-06-08 14:00 UTC', 'destination': 'Lome, Togo', 'eta': '2026-06-10 08:00 UTC'},
        {'name': 'Maersk Cubango',       'mmsi': '477174700', 'imo': '9513361', 'flag': 'Hong Kong',        'type': 'Container Ship',             'length': '254', 'width': '32', 'callsign': 'VRJZ8', 'departure_port': 'Takoradi, Ghana', 'atd': '2026-06-09 06:30 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-09 20:00 UTC'},
        {'name': 'Maersk Tema',          'mmsi': '477353900', 'imo': '9624275', 'flag': 'Hong Kong',        'type': 'Container Ship',             'length': '255', 'width': '37', 'callsign': 'VRNX6', 'departure_port': 'Tema, Ghana', 'atd': '2026-06-07 10:00 UTC', 'destination': 'Abidjan, Ivory Coast', 'eta': '2026-06-11 12:00 UTC'},
        {'name': 'MSC Johannesburg V',   'mmsi': '636024423', 'imo': '9308637', 'flag': 'Liberia',          'type': 'Container Ship',             'length': '275', 'width': '40', 'callsign': 'A8IF9', 'departure_port': 'Durban, South Africa', 'atd': '2026-06-02 08:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-12 18:00 UTC'},
        {'name': 'MSC Assunta III',      'mmsi': '636023923', 'imo': '9211028', 'flag': 'Liberia',          'type': 'Container Ship',             'length': '259', 'width': '32', 'callsign': 'A8GX6', 'departure_port': 'Pointe Noire, Congo', 'atd': '2026-06-05 16:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-10 14:00 UTC'},
        {'name': 'MSC Aniello',          'mmsi': '372741000', 'imo': '9203928', 'flag': 'Panama',           'type': 'Container Ship',             'length': '259', 'width': '32', 'callsign': '3FYQ9', 'departure_port': 'Lagos, Nigeria', 'atd': '2026-06-08 12:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-09 16:00 UTC'},
        {'name': 'MSC Pamela',           'mmsi': '636022359', 'imo': '9290531', 'flag': 'Liberia',          'type': 'Container Ship',             'length': '337', 'width': '46', 'callsign': 'A8HR2', 'departure_port': 'Tema, Ghana', 'atd': '2026-06-09 08:00 UTC', 'destination': 'Algeciras, Spain', 'eta': '2026-06-16 10:00 UTC'},
        {'name': 'One Presence',         'mmsi': '563290200', 'imo': '9347504', 'flag': 'Singapore',        'type': 'Container Ship',             'length': '300', 'width': '40', 'callsign': '9V7182', 'departure_port': 'Singapore, Singapore', 'atd': '2026-05-20 00:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-15 06:00 UTC'},
        {'name': 'Grande Argentina',     'mmsi': '215949000', 'imo': '9220976', 'flag': 'Malta',            'type': 'Ro-Ro/Cargo',                'length': '214', 'width': '32', 'callsign': '9HNM6', 'departure_port': 'Antwerp, Belgium', 'atd': '2026-05-28 14:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-14 08:00 UTC'},
        {'name': 'Grande Tema',          'mmsi': '247343700', 'imo': '9672105', 'flag': 'Italy',            'type': 'Ro-Ro/Cargo',                'length': '236', 'width': '36', 'callsign': 'IBDR', 'departure_port': 'Tema, Ghana', 'atd': '2026-06-09 12:00 UTC', 'destination': 'Lagos, Nigeria', 'eta': '2026-06-10 18:00 UTC'},
        {'name': 'Grande Dakar',         'mmsi': '247341900', 'imo': '9680724', 'flag': 'Italy',            'type': 'Ro-Ro/Container Carrier',    'length': '236', 'width': '36', 'callsign': 'IBDK', 'departure_port': 'Dakar, Senegal', 'atd': '2026-06-06 10:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-11 06:00 UTC'},
        {'name': 'African Wind',         'mmsi': '305537000', 'imo': '9372107', 'flag': 'Antigua Barbuda',  'type': 'General Cargo',              'length': '132', 'width': '16', 'callsign': 'V2CG9', 'departure_port': 'Tema, Ghana', 'atd': '2026-06-08 18:00 UTC', 'destination': 'Takoradi, Ghana', 'eta': '2026-06-09 08:00 UTC'},
        {'name': 'Oslo Trader',          'mmsi': '636014459', 'imo': '9239082', 'flag': 'Liberia',          'type': 'Container Ship',             'length': '200', 'width': '30', 'callsign': 'A8HF8', 'departure_port': 'Abidjan, Ivory Coast', 'atd': '2026-06-09 04:00 UTC', 'destination': 'Tema, Ghana', 'eta': '2026-06-10 10:00 UTC'},
    ]
    return jsonify(registry), 200


@app.route('/logo.jpeg')
@app.route('/v1/logo.jpeg')
@app.route('/api/logo.jpeg')
@app.route('/api/v1/logo.jpeg')
def serve_logo():
    if app.static_folder and os.path.isfile(os.path.join(app.static_folder, 'logo.jpeg')):
        return send_from_directory(app.static_folder, 'logo.jpeg')
    static_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'static'))
    return send_from_directory(static_dir, 'logo.jpeg')

_SENSITIVE_UPLOAD_PREFIXES = (
    'receipts/', 'compliance/', 'compliance_docs/', 'documents/',
    'member_documents/', 'member_docs/', 'private/', 'bank/',
)


def _upload_path_is_sensitive(filename: str) -> bool:
    normalized = os.path.normpath(filename).replace('\\', '/').lstrip('/')
    if '..' in normalized.split('/'):
        return True
    return any(normalized.startswith(p) for p in _SENSITIVE_UPLOAD_PREFIXES)


def _require_jwt_for_sensitive_upload(filename: str):
    if not _upload_path_is_sensitive(filename):
        return None
    try:
        verify_jwt_in_request()
        if not get_jwt_identity():
            return jsonify({'message': 'Authentication required to access this file'}), 401
    except Exception:
        return jsonify({'message': 'Authentication required to access this file'}), 401
    return None


@app.route('/static/uploads/<path:filename>')
@app.route('/uploads/<path:filename>')
@app.route('/api/v1/static/uploads/<path:filename>')
@app.route('/api/static/uploads/<path:filename>')
@app.route('/api/v1/uploads/<path:filename>')
@app.route('/api/uploads/<path:filename>')
def serve_uploads(filename):
    auth_block = _require_jwt_for_sensitive_upload(filename)
    if auth_block is not None:
        return auth_block
    _backend = os.path.dirname(os.path.abspath(__file__))
    for base in [
        os.path.join(_backend, 'uploads'),          # permanent store (checked first)
        os.path.join(_backend, 'static', 'uploads'),# static mirror
        os.path.join(os.getcwd(), 'uploads'),
        os.path.join(os.getcwd(), 'static', 'uploads'),
    ]:
        target = os.path.join(base, filename)
        if os.path.isfile(target):
            resp = send_from_directory(base, filename)
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=86400'
            return resp
    return jsonify({'message': 'File not found'}), 404

@app.route('/api/analytics/telemetry', methods=['POST', 'OPTIONS'])
@app.route('/api/v1/analytics/telemetry', methods=['POST', 'OPTIONS'])
def telemetry():
    try:
        # Just ack the telemetry for now to prevent 405 errors
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        logger.error(f"Error in telemetry: {e}")
        return jsonify({"status": "error"}), 500

@app.route('/flutter_bootstrap.js')
def serve_flutter_bootstrap():
    candidates = [
        app.static_folder,
        os.path.join(os.path.dirname(__file__), 'static'),
        os.path.join(os.path.dirname(__file__), 'dist'),
        FLUTTER_BUILD_DIR,
    ]
    for d in candidates:
        if d and os.path.isfile(os.path.join(d, 'flutter_bootstrap.js')):
            resp = send_from_directory(d, 'flutter_bootstrap.js', mimetype='application/javascript')
            resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
            return resp

    # Safe dynamic fallback bootstrap if the file wasn't generated or copied
    bootstrap_code = """
(function() {
  if (typeof _flutter !== 'undefined' && _flutter.loader) {
    _flutter.loader.loadEntrypoint({
      onEntrypointLoaded: function(engineInitializer) {
        engineInitializer.initializeEngine().then(function(appRunner) {
          appRunner.runApp();
        });
      }
    });
  } else {
    var script = document.createElement('script');
    script.src = 'main.dart.js';
    script.type = 'application/javascript';
    document.body.appendChild(script);
  }
})();
"""
    resp = app.response_class(bootstrap_code, mimetype='application/javascript')
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
    return resp


@app.route('/static/uploads/<path:filename>')
@app.route('/uploads/<path:filename>')
def serve_uploaded_file(filename):
    auth_block = _require_jwt_for_sensitive_upload(filename)
    if auth_block is not None:
        return auth_block
    backend_root = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(backend_root, 'static', 'uploads', filename),
        os.path.join(backend_root, 'uploads', filename),
        os.path.join(backend_root, 'dist', 'uploads', filename),
    ]
    for p in candidates:
        if os.path.isfile(p):
            resp = send_file(p)
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=3600'
            return resp

    ext = os.path.splitext(filename)[1].lower()
    if ext in ('.jpg', '.jpeg', '.png', '.webp', '.gif'):
        placeholder_path = os.path.join(backend_root, 'static', 'uploads', 'doc_placeholder.png')
        if os.path.isfile(placeholder_path):
            resp = send_file(placeholder_path, mimetype='image/png')
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'no-cache'
            return resp
    return jsonify({'error': 'File not found', 'path': filename}), 404


@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve_spa(path):
    ext = os.path.splitext(path)[1].lower()
    is_static_asset = ext in ('.js', '.css', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico', '.woff', '.woff2', '.ttf', '.json', '.pdf')
    is_upload_path = path.startswith('static/uploads/') or path.startswith('uploads/')
    if is_upload_path:
        rel = path.split('uploads/', 1)[-1] if 'uploads/' in path else path
        auth_block = _require_jwt_for_sensitive_upload(rel)
        if auth_block is not None:
            return auth_block

    # Check if the requested path is a real file (like an image or JS)
    if app.static_folder:
        full_path = os.path.join(app.static_folder, path)
        resp = None
        if path and os.path.isfile(full_path):
            resp = send_from_directory(app.static_folder, path, conditional=False)
        elif is_static_asset or is_upload_path:
            # Never return HTML for missing static assets or upload files
            return jsonify({'error': 'File not found', 'path': path}), 404
        else:
            # Otherwise, always serve index.html to let Flutter web router handle the URL
            index_path = os.path.join(app.static_folder, 'index.html')
            if os.path.isfile(index_path):
                resp = send_from_directory(app.static_folder, 'index.html', conditional=False)
        
        if resp:
            resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
            resp.headers['Pragma'] = 'no-cache'
            resp.headers['Expires'] = '0'
            if 'ETag' in resp.headers:
                del resp.headers['ETag']
            if 'Last-Modified' in resp.headers:
                del resp.headers['Last-Modified']
            return resp

    # Fallback if no static files exist
    return jsonify({'status': 'CUBAG API is running', 'message': 'No frontend build found. Use /api/health for API status.'}), 200


logger.info("[Init] CUBAG Backend fully loaded and ready to accept requests.")

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5005))
    logger.info(f"Running on port {port}")
    socketio.run(app, host='0.0.0.0', port=port, debug=False, allow_unsafe_werkzeug=True)
