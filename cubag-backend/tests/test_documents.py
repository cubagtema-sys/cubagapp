"""
Smoke tests for /api/v1/documents endpoints.
"""


class TestDocumentsRoutes:

    def test_requirements_unauthenticated_returns_401(self, client):
        """Member document requirements must require auth."""
        resp = client.get('/api/v1/documents/requirements')
        assert resp.status_code == 401

    def test_admin_pending_unauthenticated_returns_401(self, client):
        """Admin pending list must require auth."""
        resp = client.get('/api/v1/documents/admin/pending')
        assert resp.status_code == 401

    def test_upload_unauthenticated_returns_401(self, client):
        """Upload endpoint must require auth."""
        resp = client.post('/api/v1/documents/upload')
        assert resp.status_code == 401

    def test_confirm_upload_unauthenticated_returns_401(self, client):
        """Confirm upload must require auth."""
        resp = client.post('/api/v1/documents/confirm-upload', json={})
        assert resp.status_code == 401

    def test_submit_application_unauthenticated_returns_401(self, client):
        """Submit application must require auth."""
        resp = client.post('/api/v1/documents/submit-application')
        assert resp.status_code == 401

    def test_admin_pending_with_auth(self, client, auth_headers):
        """Admin pending list with valid token returns 200 with members key."""
        resp = client.get('/api/v1/documents/admin/pending', headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert 'members' in data, f"Expected 'members' key in response, got: {list(data.keys())}"
        assert isinstance(data['members'], list)

    def test_admin_pending_active_filter(self, client, auth_headers):
        """?status=active filter must return 200."""
        resp = client.get('/api/v1/documents/admin/pending?status=active', headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert 'members' in data
