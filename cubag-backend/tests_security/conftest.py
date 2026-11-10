"""
Security regression test harness — runs WITHOUT a real database.

psycopg2 is replaced by tests_security/_stubs/psycopg2 (backed by fakedb.FAKE_DB)
before the app is imported, so every test controls exactly what the DB returns
and can assert which statements were executed.

Run:  cd cubag-backend && python -m pytest tests_security -q
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(HERE)
for p in (os.path.join(HERE, '_stubs'), HERE, BACKEND):
    if p not in sys.path:
        sys.path.insert(0, p)
for name in [m for m in list(sys.modules) if m == 'psycopg2' or m.startswith('psycopg2.')]:
    del sys.modules[name]

os.environ['DATABASE_URL'] = 'postgresql://fake/fake'
os.environ['SECRET_KEY'] = 'test-secret-key-0123456789abcdef'
os.environ['JWT_SECRET_KEY'] = 'test-jwt-secret-0123456789abcdef'
os.environ['FLASK_DEBUG'] = 'false'          # exercise production code paths
os.environ['SENTRY_DSN'] = ''
os.environ['WHITSUNPAY_WEBHOOK_SECRET'] = 'whsec-test'
os.environ.setdefault('CLIENT_IP_HEADER', 'Fly-Client-IP')
# Blank every outbound integration BEFORE the app (and load_dotenv) runs, so a
# developer's real .env can never make tests send email, push notifications,
# MoMo prompts or storage calls. load_dotenv() does not override existing keys.
for _k in ('AIS_API_KEY', 'REDIS_URL', 'RESEND_API_KEY', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS',
           'SMTP_PASSWORD', 'WHITSUNPAY_API_KEY', 'WHITSUNPAY_CLIENT_ID', 'x-api-key', 'x-client-id',
           'WHITSUNPAY_CALLBACK_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY', 'SUPABASE_ANON_KEY',
           'FIREBASE_CREDENTIALS_JSON', 'FIREBASE_SERVICE_ACCOUNT', 'DB_HOST', 'DB_PASSWORD'):
    os.environ[_k] = ''
os.environ['FIREBASE_CREDENTIALS'] = '/nonexistent/firebase-key.json'

import pytest  # noqa: E402
from fakedb import FAKE_DB  # noqa: E402

# Users known to the fake DB: id -> attributes
USERS = {
    1: {'role': 'admin', 'status': 'active'},
    2: {'role': 'sub_admin', 'status': 'active', 'perms': []},
    3: {'role': 'sub_admin', 'status': 'active', 'perms': ['complaints', 'gdpr', 'fees', 'members']},
    10: {'role': 'member', 'status': 'active'},
    11: {'role': 'member', 'status': 'active'},
    12: {'role': 'member', 'status': 'pending'},
    13: {'role': 'member', 'status': 'deleted'},
    14: {'role': 'member', 'status': 'suspended'},
}


def _uid(params):
    try:
        return int(params[0])
    except Exception:
        return None


def install_default_responders():
    FAKE_DB.reset()

    def role(params):
        u = USERS.get(_uid(params))
        return [{'role': u['role']}] if u else []

    def status(params):
        u = USERS.get(_uid(params))
        return [{'status': u['status'], 'token_version': u.get('tv', 0)}] if u else []

    def perm(params):
        u = USERS.get(_uid(params))
        if u and params[1] in u.get('perms', []):
            return [{'?column?': 1}]
        return []

    FAKE_DB.on(r"SELECT role FROM members WHERE id = %s", role)
    FAKE_DB.on(r"SELECT status, COALESCE\(token_version", status)
    FAKE_DB.on(r"FROM sub_admin_permissions WHERE sub_admin_id = %s AND permission_key = %s", perm)


@pytest.fixture(scope='session')
def app():
    install_default_responders()
    import server  # noqa: F401  (import after stubbing)
    server.app.config['TESTING'] = True
    return server.app


@pytest.fixture()
def client(app):
    install_default_responders()
    from config.cache import cache
    with app.app_context():
        cache.clear()
    return app.test_client()


@pytest.fixture()
def token(app):
    from flask_jwt_extended import create_access_token

    def make(uid, tv=None, expires=None):
        u = USERS.get(uid, {'role': 'member'})
        claims = {'role': u['role']}
        if tv is not None:
            claims['tv'] = tv
        with app.app_context():
            kw = {}
            if expires is not None:
                kw['expires_delta'] = expires
            return create_access_token(identity=str(uid), additional_claims=claims, **kw)
    return make


@pytest.fixture()
def auth(token):
    def headers(uid, **kw):
        return {'Authorization': f'Bearer {token(uid, **kw)}'}
    return headers


@pytest.fixture()
def db():
    return FAKE_DB
