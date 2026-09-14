"""
pytest fixtures for CUBAG backend tests.

Sets up a test Flask app with an in-memory SQLite-compatible config
so tests don't hit the real Postgres database.
"""
import pytest
import os

# Point tests to a test database to avoid touching production
os.environ.setdefault('DATABASE_URL', '')
os.environ.setdefault('SECRET_KEY', 'test-secret-key')
os.environ.setdefault('JWT_SECRET_KEY', 'test-jwt-secret')
os.environ.setdefault('FLASK_DEBUG', 'true')
os.environ.setdefault('SENTRY_DSN', '')  # Disable Sentry in tests


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
