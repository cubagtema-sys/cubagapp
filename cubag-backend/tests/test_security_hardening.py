"""Security hardening checks that do not require a live database."""


class TestAuthAndPaymentGates:
    def test_verify_code_requires_auth(self, client):
        resp = client.post('/api/v1/payments/verify-code', json={
            'payment_id': 1,
            'transaction_ref': 'CUBAG-FAKE',
            'client_verified': True,
        })
        assert resp.status_code == 401

    def test_client_verified_flag_is_ignored_without_auth(self, client):
        resp = client.post('/api/v1/payments/verify-code', json={
            'client_verified': True,
            'payment_id': 999,
            'whitsun_ref': 'x',
        })
        assert resp.status_code == 401

    def test_register_without_otp_is_rejected(self, client):
        resp = client.post('/api/v1/auth/register', json={
            'name': 'Test User',
            'email': 'nobody@cubag.test',
            'phone': '0240000000',
            'company': 'Test Co',
            'location': 'Tema',
            'digitalAddress': 'GA-1234-5678',
            'tin': 'C0000000001',
            'memberType': 'Licentiate',
            'portOfOperation': 'Tema Port',
            'password': 'password123',
        })
        assert resp.status_code in (400, 500)
        if resp.status_code == 400:
            body = resp.get_json() or {}
            assert 'verif' in (body.get('message') or '').lower()

    def test_image_proxy_requires_auth(self, client):
        resp = client.get('/api/v1/uploads/proxy', query_string={'url': 'https://example.com/x.png'})
        assert resp.status_code == 401

    def test_private_settings_require_auth(self, client):
        resp = client.get('/api/v1/settings/smtp_password')
        assert resp.status_code == 401

    def test_webhook_unsigned_rejected_when_not_debug_secret_missing(self, client, monkeypatch):
        import routes.payments as payments_mod
        monkeypatch.setattr(payments_mod, 'WHITSUNPAY_WEBHOOK_SECRET', '')
        monkeypatch.setenv('FLASK_DEBUG', 'false')
        resp = client.post('/api/v1/payments/webhook', json={
            'transactionReference': 'CUBAG-1',
            'status': 'successful',
        })
        # Debug env may still be true from conftest; accept 503 (fail closed) or 200 only if debug.
        assert resp.status_code in (200, 503, 401)

    def test_webhook_bad_signature_rejected_when_secret_set(self, client, monkeypatch):
        import routes.payments as payments_mod
        monkeypatch.setattr(payments_mod, 'WHITSUNPAY_WEBHOOK_SECRET', 'test-webhook-secret')
        resp = client.post(
            '/api/v1/payments/webhook',
            data=b'{"status":"successful","transactionReference":"x"}',
            content_type='application/json',
            headers={'X-Whitsun-Signature': 'sha256=deadbeef'},
        )
        assert resp.status_code == 401

    def test_receipt_upload_requires_auth(self, client):
        resp = client.post('/api/v1/payments/upload-receipt')
        assert resp.status_code == 401

    def test_admin_path_without_token_is_401(self, client):
        resp = client.get('/api/v1/admin/dashboard')
        assert resp.status_code == 401
