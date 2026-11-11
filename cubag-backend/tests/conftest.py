"""
pytest fixtures for CUBAG backend tests.

Legacy suite. It talks to PostgreSQL through the real app, so it is locked to a
local *_test database (TEST_DATABASE_URL) — see the SAFETY note below.
"""
import pytest
import os

import re

# SAFETY: importing the app runs init_db() (DDL) and some tests write rows. The
# previous version left DB_HOST/DB_PASSWORD to be filled from the developer's
# .env, i.e. the production database. Now the suite can only ever reach a LOCAL
# database named *_test given in TEST_DATABASE_URL; otherwise it is pointed at a
# closed local port so nothing can connect anywhere (DB-less tests still run).
def _safe_test_dsn(dsn):
    dsn = (dsn or '').strip()
    if not dsn:
        return False
    if '://' in dsn:
        from urllib.parse import urlparse
        u = urlparse(dsn)
        host, dbname = (u.hostname or ''), (u.path or '').lstrip('/').split('?')[0]
    else:
        kv = dict(re.findall(r"(\w+)\s*=\s*'?([^'\s]*)'?", dsn))
        host, dbname = kv.get('host', ''), kv.get('dbname', '')
    return (host in {'localhost', '127.0.0.1', '::1', ''} or host.startswith('/')) and dbname.endswith('_test')


_dsn = os.environ.get('TEST_DATABASE_URL', '')
os.environ['DATABASE_URL'] = _dsn if _safe_test_dsn(_dsn) else 'host=127.0.0.1 port=1 dbname=no_database_test connect_timeout=1'
os.environ['SECRET_KEY'] = 'test-secret-key-0123456789abcdef'
os.environ['JWT_SECRET_KEY'] = 'test-jwt-secret-0123456789abcdef'
os.environ.setdefault('FLASK_DEBUG', 'true')
os.environ['SENTRY_DSN'] = ''  # Disable Sentry in tests
# Never let a real .env drive email, MoMo, storage, push or AIS calls from tests.
for _k in ('AIS_API_KEY', 'REDIS_URL', 'RESEND_API_KEY', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS',
           'SMTP_PASSWORD', 'WHITSUNPAY_API_KEY', 'WHITSUNPAY_CLIENT_ID', 'x-api-key', 'x-client-id',
           'WHITSUNPAY_CALLBACK_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY', 'SUPABASE_ANON_KEY',
           'FIREBASE_CREDENTIALS_JSON', 'FIREBASE_SERVICE_ACCOUNT', 'DB_HOST', 'DB_PASSWORD'):
    os.environ[_k] = ''
os.environ['FIREBASE_CREDENTIALS'] = '/nonexistent/firebase-key.json'


@pytest.fixture(scope='session')
def app():
    """Create Flask test app."""
    from server import app as flask_app
    flask_app.config.update({
        'TESTING': True,
        'JWT_SECRET_KEY': 'test-jwt-secret',
        'SECRET_KEY': 'test-secret-key',
    })
    yield flask_app


@pytest.fixture()
def client(app):
    """Flask test client — no real HTTP needed."""
    return app.test_client()


@pytest.fixture()
def auth_headers(client):
    """
    Returns JWT Authorization header for a mock admin user.
    Uses the /api/v1/auth/login endpoint with a test user.
    Requires a real DB connection — skip in pure unit tests.
    """
    resp = client.post('/api/v1/auth/login', json={
        'email': os.getenv('TEST_ADMIN_EMAIL', ''),
        'password': os.getenv('TEST_ADMIN_PASSWORD', ''),
    })
    if resp.status_code != 200:
        pytest.skip("TEST_ADMIN_EMAIL/PASSWORD not set or login failed")
    token = resp.get_json().get('access_token', '')
    return {'Authorization': f'Bearer {token}'}
