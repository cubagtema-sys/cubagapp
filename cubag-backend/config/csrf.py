"""
CSRF Protection Configuration for CUBAG Backend.

Since we use JWT authentication (stateless), traditional CSRF attacks are less likely,
but we implement additional protection for state-changing operations as a defense-in-depth measure.
"""
import os
import secrets
import logging
from flask import request, jsonify
from functools import wraps

logger = logging.getLogger(__name__)

# Enable CSRF protection (can be disabled for testing if needed)
CSRF_ENABLED = os.getenv('CSRF_ENABLED', 'true').lower() == 'true'

# Methods that require CSRF protection
CSRF_PROTECTED_METHODS = {'POST', 'PUT', 'DELETE', 'PATCH'}

# Endpoints that are exempt from CSRF protection (public endpoints, webhooks, etc.)
CSRF_EXEMPT_ENDPOINTS = {
    '/api/v1/auth/login',
    '/api/v1/auth/register',
    '/api/v1/auth/send-otp',
    '/api/v1/payments/webhook',
    '/api/payments/webhook',
    '/api/v1/payments/public/initiate-momo',
    '/api/payments/public/initiate-momo',
    '/api/health',
    '/api/ping',
}


def generate_csrf_token():
    """Generate a secure CSRF token."""
    return secrets.token_urlsafe(32)


def validate_csrf_token():
    """
    Validate CSRF token from request headers.
    Returns (is_valid: bool, error_message: str)
    """
    if not CSRF_ENABLED:
        return True, None
    
    # Check if endpoint is exempt
    if request.path in CSRF_EXEMPT_ENDPOINTS:
        return True, None
    
    # Only check CSRF for state-changing methods
    if request.method not in CSRF_PROTECTED_METHODS:
        return True, None

    # Bearer-token (JWT-in-header) requests are not vulnerable to CSRF: a
    # cross-site attacker can neither read nor set a custom Authorization
    # header, and browsers never attach it automatically. CSRF applies only to
    # ambient credentials (cookies), so skip the check for Bearer-auth calls.
    if (request.headers.get('Authorization') or '').startswith('Bearer '):
        return True, None

    # For JWT-based auth, we validate using the Authorization header + custom CSRF header
    # This provides double protection against CSRF attacks
    csrf_token = request.headers.get('X-CSRF-Token') or request.headers.get('X-CSRFToken')
    
    if not csrf_token:
        return False, 'CSRF token missing. Include X-CSRF-Token header.'
    
    # For JWT-based systems, we can validate that the token matches expected format
    # In a session-based system, we'd compare against a stored token
    if len(csrf_token) < 20:
        return False, 'Invalid CSRF token format.'
    
    return True, None


def csrf_protect(f):
    """
    Decorator to protect routes from CSRF attacks.
    Use this decorator on state-changing endpoints that need extra protection.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        is_valid, error_msg = validate_csrf_token()
        if not is_valid:
            logger.warning(f"CSRF validation failed for {request.method} {request.path}")
            return jsonify({'message': error_msg}), 403
        return f(*args, **kwargs)
    return decorated_function


def csrf_exempt(f):
    """
    Decorator to explicitly exempt a route from CSRF protection.
    Use this for public endpoints or webhooks.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        return f(*args, **kwargs)
    # Mark the endpoint as exempt
    decorated_function._csrf_exempt = True
    return decorated_function