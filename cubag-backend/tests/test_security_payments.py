"""Comprehensive integration and security tests for payments, webhooks, and fee validation."""
import hmac
import hashlib
import json


class TestPaymentSecurityAndWebhooks:
    def test_webhook_fails_closed_without_secret_in_production(self, client, monkeypatch):
        import routes.payments as payments_mod
        monkeypatch.setattr(payments_mod, 'WHITSUNPAY_WEBHOOK_SECRET', '')
        monkeypatch.setenv('FLASK_DEBUG', 'false')

        resp = client.post('/api/v1/payments/webhook', json={
            'transactionReference': 'TEST-REF',
            'status': 'successful'
        })
        assert resp.status_code == 503
        data = resp.get_json() or {}
        assert 'secret not configured' in data.get('message', '').lower()

    def test_webhook_signature_verification_mismatch(self, client, monkeypatch):
        import routes.payments as payments_mod
        monkeypatch.setattr(payments_mod, 'WHITSUNPAY_WEBHOOK_SECRET', 'super_secret_key')
        monkeypatch.setenv('FLASK_DEBUG', 'false')

        payload = {'transactionReference': 'TEST-REF', 'status': 'successful'}
        body = json.dumps(payload).encode('utf-8')
        resp = client.post(
            '/api/v1/payments/webhook',
            data=body,
            headers={
                'X-Whitsun-Signature': 'sha256=invalid_signature_hash',
                'Content-Type': 'application/json'
            }
        )
        assert resp.status_code == 401

    def test_webhook_signature_verification_success(self, client, monkeypatch):
        import routes.payments as payments_mod
        secret = 'super_secret_key'
        monkeypatch.setattr(payments_mod, 'WHITSUNPAY_WEBHOOK_SECRET', secret)
        monkeypatch.setenv('FLASK_DEBUG', 'false')

        payload = {'transactionReference': 'NONEXISTENT-REF', 'status': 'successful'}
        body = json.dumps(payload).encode('utf-8')
        sig = 'sha256=' + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()

        resp = client.post(
            '/api/v1/payments/webhook',
            data=body,
            headers={
                'X-Whitsun-Signature': sig,
                'Content-Type': 'application/json'
            }
        )
        # Nonexistent ref should return 404 or process gracefully without signature failure
        assert resp.status_code in (200, 404)
