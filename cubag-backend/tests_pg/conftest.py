"""
Real-PostgreSQL integration tests (separate from the fake-DB tests_security suite).

SAFETY: these tests TRUNCATE tables. They only run when TEST_DATABASE_URL is set
AND points at a local server AND the database name ends in "_test". Anything
else (Supabase, Render, Fly, any remote host) is refused before the app loads.

Run:
    createdb cubag_test
    TEST_DATABASE_URL="host=127.0.0.1 port=5432 user=postgres dbname=cubag_test" \
        python -m pytest tests_pg -q

Run this suite on its own. Do not combine it with tests_security in one pytest
invocation: that suite replaces psycopg2 with an in-memory fake.
"""
import os
import re
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(HERE)
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

_LOCAL_HOSTS = {'localhost', '127.0.0.1', '::1', ''}


def parse_test_dsn(dsn):
    """Return (host, dbname) from a URL or key=value DSN."""
    dsn = (dsn or '').strip()
    if '://' in dsn:
        from urllib.parse import urlparse
        u = urlparse(dsn)
        return (u.hostname or ''), (u.path or '').lstrip('/').split('?')[0]
    kv = dict(re.findall(r"(\w+)\s*=\s*'?([^'\s]*)'?", dsn))
    return kv.get('host', ''), kv.get('dbname', '')


def is_safe_test_dsn(dsn):
    if not (dsn or '').strip():
        return False
    host, dbname = parse_test_dsn(dsn)
    return (host in _LOCAL_HOSTS or host.startswith('/')) and dbname.endswith('_test')


TEST_DSN = os.environ.get('TEST_DATABASE_URL', '')
ENABLED = is_safe_test_dsn(TEST_DSN)

if ENABLED:
    os.environ['DATABASE_URL'] = TEST_DSN
    os.environ['SECRET_KEY'] = 'test-secret-key-0123456789abcdef'
    os.environ['JWT_SECRET_KEY'] = 'test-jwt-secret-0123456789abcdef'
    os.environ['FLASK_DEBUG'] = 'false'
    os.environ['SENTRY_DSN'] = ''
    os.environ['WHITSUNPAY_WEBHOOK_SECRET'] = 'whsec-test'
    # Blank every outbound integration before the app (and load_dotenv) runs.
    for _k in ('AIS_API_KEY', 'REDIS_URL', 'RESEND_API_KEY', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS',
               'SMTP_PASSWORD', 'WHITSUNPAY_API_KEY', 'WHITSUNPAY_CLIENT_ID', 'x-api-key', 'x-client-id',
               'WHITSUNPAY_CALLBACK_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY', 'SUPABASE_ANON_KEY',
               'FIREBASE_CREDENTIALS_JSON', 'FIREBASE_SERVICE_ACCOUNT', 'DB_HOST', 'DB_PASSWORD'):
        os.environ[_k] = ''
    os.environ['FIREBASE_CREDENTIALS'] = '/nonexistent/firebase-key.json'


def pytest_collection_modifyitems(config, items):
    if ENABLED:
        return
    reason = ('TEST_DATABASE_URL is not set' if not TEST_DSN.strip() else
              'TEST_DATABASE_URL refused: must be a local server and a database named *_test')
    skip = pytest.mark.skip(reason=reason)
    for item in items:
        if 'tests_pg' in str(item.fspath) and 'test_guard' not in str(item.fspath):
            item.add_marker(skip)


PASSWORD = 'Password123!'
# Tables holding per-test data. Reference/seed tables (fees, settings) are left alone.
_DATA_TABLES = ('members', 'cti_courses', 'otp_codes', 'member_blocks', 'message_reports',
                'complaints', 'payments', 'messages', 'notifications', 'cti_course_enrollments',
                'biometric_tokens', 'compliance_applications', 'compliance_documents',
                'member_rating_history')


@pytest.fixture(scope='session')
def app():
    import server
    server.app.config['TESTING'] = True
    # Tables production has but the repository never creates (see schema_gaps.sql).
    import psycopg2
    conn = psycopg2.connect(TEST_DSN)
    try:
        with conn.cursor() as cur:
            cur.execute(open(os.path.join(HERE, 'schema_gaps.sql')).read())
        conn.commit()
    finally:
        conn.close()
    return server.app


@pytest.fixture()
def sql(app):
    """Run SQL on a dedicated autocommit-style connection; returns list of dict rows."""
    import psycopg2
    from psycopg2.extras import RealDictCursor
    assert is_safe_test_dsn(TEST_DSN)
    conn = psycopg2.connect(TEST_DSN, cursor_factory=RealDictCursor)

    def run(query, params=None):
        with conn.cursor() as cur:
            cur.execute(query, params)
            rows = cur.fetchall() if cur.description else []
        conn.commit()
        return rows
    yield run
    conn.close()


@pytest.fixture(autouse=True)
def clean_db(request):
    """Every test starts from empty data tables (schema and fee seed data stay)."""
    if not ENABLED or 'test_guard' in str(request.node.fspath):
        yield
        return
    sql = request.getfixturevalue('sql')
    app = request.getfixturevalue('app')
    existing = {r['table_name'] for r in sql(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}
    tables = [t for t in _DATA_TABLES if t in existing]
    sql('TRUNCATE ' + ', '.join(tables) + ' RESTART IDENTITY CASCADE')
    from config.cache import cache
    with app.app_context():
        cache.clear()
    try:
        from config import rate_limit
        for name in ('_buckets', '_otp_failures', '_store', '_attempts'):
            store = getattr(rate_limit, name, None)
            if hasattr(store, 'clear'):
                store.clear()
    except Exception:
        pass
    yield


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def member(sql):
    """Insert a member row; returns its id."""
    from werkzeug.security import generate_password_hash
    counter = {'n': 0}

    def make(role='member', status='active', email=None, **extra):
        counter['n'] += 1
        n = counter['n']
        cols = {
            'name': f'Test {role} {n}', 'email': email or f'user{n}@example.test',
            'phone': f'02400000{n:02d}', 'password_hash': generate_password_hash(PASSWORD),
            'role': role, 'status': status, 'email_verified': True,
        }
        cols.update(extra)
        keys = list(cols)
        row = sql(f"INSERT INTO members ({', '.join(keys)}) VALUES ({', '.join(['%s'] * len(keys))}) RETURNING id",
                  [cols[k] for k in keys])
        return row[0]['id']
    return make


@pytest.fixture()
def login(client):
    def do(identifier, password=PASSWORD, headers=None):
        return client.post('/api/v1/auth/login', json={'identifier': identifier, 'password': password},
                           headers=headers or {})
    return do


@pytest.fixture()
def auth(app, sql):
    """Authorization header for a member id, carrying the member's current token_version."""
    from flask_jwt_extended import create_access_token

    def headers(uid):
        row = sql('SELECT role, COALESCE(token_version, 0) AS tv FROM members WHERE id = %s', (uid,))[0]
        with app.app_context():
            tok = create_access_token(identity=str(uid), additional_claims={'role': row['role'], 'tv': row['tv']})
        return {'Authorization': f'Bearer {tok}'}
    return headers
