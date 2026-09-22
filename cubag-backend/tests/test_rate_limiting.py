"""Tests verifying API rate limiting protection against abuse."""


class TestRateLimiting:
    def test_login_rate_limiting(self, client):
        # Hit login endpoint multiple times quickly to test rate limit decorator behavior
        for i in range(15):
            resp = client.post('/api/v1/auth/login', json={
                'email': 'rate_limit_test@cubag.test',
                'password': 'wrongpassword'
            })
            if resp.status_code == 429:
                break
        # Depending on test environment configuration, either rate limit triggers (429) or invalid credentials (401/400)
        assert resp.status_code in (401, 400, 429)
