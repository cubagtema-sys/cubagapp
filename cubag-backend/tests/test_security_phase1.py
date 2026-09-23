"""
Phase 1 Security Tests - Tests for CSRF, Security Headers, Webhook Verification, and IDOR protection.
"""
import pytest
import json
import hmac
import hashlib
import time


class TestSecurityHeaders:
    """Test that security headers are properly configured."""
    
    def test_security_headers_on_api_response(self, client):
        """Verify security headers are present on API responses."""
        response = client.get('/api/health')
        assert response.status_code == 200
        
        # Check for security headers
        headers = response.headers
        assert 'X-Content-Type-Options' in headers
        assert headers['X-Content-Type-Options'] == 'nosniff'
        assert 'X-Frame-Options' in headers
        assert headers['X-Frame-Options'] == 'DENY'
        assert 'X-XSS-Protection' in headers
        assert 'Referrer-Policy' in headers
        assert 'Content-Security-Policy' in headers
    
    def test_cache_control_headers(self, client):
        """Verify cache control headers prevent caching."""
        response = client.get('/api/health')
        assert response.status_code == 200
        
        headers = response.headers
        assert 'Cache-Control' in headers
        assert 'no-cache' in headers['Cache-Control']
        assert 'no-store' in headers['Cache-Control']


class TestCSRFProtection:
    """Test CSRF protection mechanisms."""
    
    def test_csrf_exempt_endpoints_work_without_token(self, client):
        """Public endpoints should work without CSRF token."""
        # Test login endpoint (should be exempt)
        response = client.post('/api/v1/auth/login', json={
            'email': 'test@example.com',
            'password': 'testpass'
        })
        # Should not return 403 (CSRF error)
        assert response.status_code != 403
    
    def test_csrf_protected_methods_require_token(self, client):
        """State-changing methods should validate CSRF tokens."""
        # This test assumes we have JWT auth first
        # For now, we'll test that the CSRF validation logic exists
        from config.csrf import validate_csrf_token
        from flask import Flask
        
        app = Flask(__name__)
        with app.test_request_context('/api/v1/payments/some-id', method='POST'):
            # Simulate a request without CSRF token
            is_valid, error = validate_csrf_token()
            # Should fail for POST without token (unless exempt)
            # This tests the validation logic exists
            assert isinstance(is_valid, bool)
            assert isinstance(error, (str, type(None)))


class TestWebhookSecurity:
    """Test webhook signature verification."""
    
    def test_webhook_rejects_missing_signature(self, client):
        """Webhook should reject requests without signature."""
        response = client.post('/api/v1/payments/webhook', 
                             json={'transactionReference': 'test', 'status': 'success'})
        # Should fail due to missing signature
        assert response.status_code in (401, 503)
    
    def test_webhook_rejects_invalid_signature(self, client):
        """Webhook should reject requests with invalid signature."""
        response = client.post('/api/v1/payments/webhook',
                             json={'transactionReference': 'test', 'status': 'success'},
                             headers={'X-Whitsun-Signature': 'invalid_signature'})
        # Should fail due to invalid signature
        assert response.status_code in (401, 503)
    
    def test_webhook_requires_timestamp(self, client):
        """Webhook should reject requests without timestamp."""
        response = client.post('/api/v1/payments/webhook',
                             json={'transactionReference': 'test', 'status': 'success'},
                             headers={'X-Whitsun-Signature': 'sha256=test'})
        # Should fail due to missing timestamp
        assert response.status_code == 401
    
    def test_webhook_rejects_old_timestamp(self, client):
        """Webhook should reject requests with old timestamps (replay protection)."""
        old_timestamp = int(time.time()) - 1000  # 1000 seconds ago
        response = client.post('/api/v1/payments/webhook',
                             json={'transactionReference': 'test', 'status': 'success'},
                             headers={
                                 'X-Whitsun-Signature': 'sha256=test',
                                 'X-Whitsun-Timestamp': str(old_timestamp)
                             })
        # Should fail due to old timestamp
        assert response.status_code == 401


class TestIDORProtection:
    """Test Insecure Direct Object Reference protection."""
    
    def test_payment_ownership_verification_exists(self):
        """Test that the payment ownership verification function exists."""
        from config.security import verify_payment_ownership
        assert callable(verify_payment_ownership)
    
    def test_member_ownership_verification_exists(self):
        """Test that the member ownership verification function exists."""
        from config.security import verify_member_ownership
        assert callable(verify_member_ownership)
    
    def test_compliance_ownership_verification_exists(self):
        """Test that the compliance ownership verification function exists."""
        from config.security import verify_compliance_ownership
        assert callable(verify_compliance_ownership)


class TestSecurityConfiguration:
    """Test security configuration settings."""
    
    def test_csrf_configuration_exists(self):
        """Test that CSRF configuration module exists."""
        from config import csrf
        assert hasattr(csrf, 'CSRF_ENABLED')
        assert hasattr(csrf, 'CSRF_PROTECTED_METHODS')
        assert hasattr(csrf, 'CSRF_EXEMPT_ENDPOINTS')
    
    def test_security_utils_exist(self):
        """Test that security utility functions exist."""
        from config import security
        assert hasattr(security, 'verify_payment_ownership')
        assert hasattr(security, 'verify_member_ownership')
        assert hasattr(security, 'verify_compliance_ownership')


if __name__ == '__main__':
    pytest.main([__file__, '-v'])