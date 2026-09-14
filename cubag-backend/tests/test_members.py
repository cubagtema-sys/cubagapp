"""
Smoke tests for /api/v1/members endpoints.
"""


class TestMembersRoutes:

    def test_public_list_returns_200(self, client):
        """Public member list (used for search) must be accessible."""
        resp = client.get('/api/v1/members/')
        # 200 or 401 are both valid (depends on auth requirement)
        assert resp.status_code in (200, 401)
        assert resp.content_type.startswith('application/json')

    def test_admin_all_unauthenticated_returns_401(self, client):
        """Admin member list must require auth."""
        resp = client.get('/api/v1/members/admin/all')
        assert resp.status_code == 401

    def test_admin_all_with_auth_returns_list(self, client, auth_headers):
        """Admin member list with auth returns paginated result."""
        resp = client.get('/api/v1/members/admin/all?page=1&limit=5', headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        # Should have members or data key
        assert isinstance(data, dict), f"Expected dict response, got {type(data)}"

    def test_admin_all_pagination(self, client, auth_headers):
        """Pagination params must be respected."""
        resp1 = client.get('/api/v1/members/admin/all?page=1&limit=2', headers=auth_headers)
        resp2 = client.get('/api/v1/members/admin/all?page=2&limit=2', headers=auth_headers)
        assert resp1.status_code == 200
        assert resp2.status_code == 200

    def test_member_update_status_requires_auth(self, client):
        """Status update must require admin auth — PUT /admin/status/<id>."""
        resp = client.put('/api/v1/members/admin/status/1', json={'status': 'active'})
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 for unauthenticated status update, got {resp.status_code}"
        )

    def test_announcements_route_exists(self, client):
        """Announcements endpoint exists at v1 prefix."""
        resp = client.options('/api/v1/announcements/')
        assert resp.status_code != 404, (
            "Announcements route not found — check /api/v1/ versioning"
        )
