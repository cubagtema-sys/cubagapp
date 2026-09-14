"""
Smoke tests for /api/v1/auth endpoints.

These tests verify the auth routes respond correctly to basic
valid and invalid inputs — they do NOT require a real database
(they check status codes and response shape, not data).
"""
import pytest


class TestAuthRoutes:
    """Tests that auth endpoints exist and respond correctly."""

    def test_login_missing_body_returns_400_or_401(self, client):
        """Login with no credentials should not return 200."""
        resp = client.post('/api/v1/auth/login', json={})
        assert resp.status_code in (400, 401, 422), (
            f"Expected 400/401/422 for empty login, got {resp.status_code}"
        )

    def test_login_wrong_password_returns_401(self, client):
        """Login with bad credentials must return 401."""
        resp = client.post('/api/v1/auth/login', json={
            'email': 'nobody@cubag.test',
            'password': 'wrongpassword123',
        })
        assert resp.status_code in (401, 404), (
            f"Expected 401/404 for bad credentials, got {resp.status_code}"
        )

    def test_login_returns_json(self, client):
        """Login endpoint must always return JSON."""
        resp = client.post('/api/v1/auth/login', json={
            'email': 'test@example.com',
            'password': 'bad',
        })
        assert resp.content_type.startswith('application/json')

    def test_me_without_token_returns_401(self, client):
        """/auth/me with no token must return 401."""
        resp = client.get('/api/v1/auth/me')
        assert resp.status_code == 401, (
            f"Expected 401 for unauthenticated /auth/me, got {resp.status_code}"
        )

    def test_register_missing_fields_returns_error(self, client):
        """Register with missing required fields must fail."""
        resp = client.post('/api/v1/auth/register', json={'email': 'x@y.com'})
        assert resp.status_code in (400, 422), (
            f"Expected 400/422 for incomplete register, got {resp.status_code}"
        )

    def test_health_endpoint_reachable(self, client):
        """Health check must return 200."""
        resp = client.get('/api/health')
        assert resp.status_code == 200

    def test_ping_endpoint_reachable(self, client):
        """Ping must respond."""
        resp = client.get('/api/ping')
        assert resp.status_code == 200

    def test_v1_routes_exist(self, client):
        """Verify the /api/v1/ prefix is active (not 404 due to wrong prefix)."""
        # OPTIONS is always allowed — use it to probe route existence
        resp = client.options('/api/v1/auth/login')
        assert resp.status_code != 404, (
            "Route /api/v1/auth/login returned 404 — API versioning may not be applied"
        )
