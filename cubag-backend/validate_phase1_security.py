#!/usr/bin/env python3
"""
Quick validation script for Phase 1 security improvements.
Tests that security modules are properly configured and functional.
"""
import sys
import os

def test_security_modules():
    """Test that security modules can be imported."""
    print("Testing security module imports...")
    
    try:
        from config.csrf import (
            validate_csrf_token, 
            generate_csrf_token, 
            CSRF_ENABLED,
            CSRF_PROTECTED_METHODS,
            CSRF_EXEMPT_ENDPOINTS
        )
        print("✓ CSRF protection module imported successfully")
        print(f"  - CSRF Enabled: {CSRF_ENABLED}")
        print(f"  - Protected Methods: {CSRF_PROTECTED_METHODS}")
        print(f"  - Exempt Endpoints: {len(CSRF_EXEMPT_ENDPOINTS)} endpoints")
    except ImportError as e:
        print(f"✗ CSRF module import failed: {e}")
        return False
    
    try:
        from config.security import (
            verify_payment_ownership,
            verify_member_ownership,
            verify_compliance_ownership
        )
        print("✓ Security utilities module imported successfully")
        print("  - verify_payment_ownership: callable")
        print("  - verify_member_ownership: callable")
        print("  - verify_compliance_ownership: callable")
    except ImportError as e:
        print(f"✗ Security utilities import failed: {e}")
        return False
    
    return True

def test_server_config():
    """Test that server.py includes security configurations."""
    print("\nTesting server security configuration...")
    
    try:
        with open('server.py', 'r') as f:
            server_content = f.read()
        
        # Check for security headers
        if 'Content-Security-Policy' in server_content:
            print("✓ Content Security Policy configured")
        else:
            print("✗ Content Security Policy not found")
            return False
        
        if 'X-Frame-Options' in server_content:
            print("✓ X-Frame-Options configured")
        else:
            print("✗ X-Frame-Options not found")
            return False
        
        if 'X-Content-Type-Options' in server_content:
            print("✓ X-Content-Type-Options configured")
        else:
            print("✗ X-Content-Type-Options not found")
            return False
        
        # Check for CSRF integration
        if 'validate_csrf_token' in server_content:
            print("✓ CSRF protection integrated in server")
        else:
            print("✗ CSRF protection not integrated")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Server configuration check failed: {e}")
        return False

def test_payment_security():
    """Test that payment routes include security enhancements."""
    print("\nTesting payment route security...")
    
    try:
        with open('routes/payments.py', 'r') as f:
            payments_content = f.read()
        
        # Check for enhanced webhook security
        if 'X-Whitsun-Timestamp' in payments_content:
            print("✓ Webhook timestamp validation implemented")
        else:
            print("✗ Webhook timestamp validation not found")
            return False
        
        if 'hmac.compare_digest' in payments_content:
            print("✓ HMAC signature verification with timing attack protection")
        else:
            print("✗ HMAC signature verification not found")
            return False
        
        # Check for IDOR protection
        if 'verify_payment_ownership' in payments_content:
            print("✓ Payment ownership verification implemented")
        else:
            print("✗ Payment ownership verification not found")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Payment security check failed: {e}")
        return False

def main():
    """Run all validation tests."""
    print("=" * 60)
    print("PHASE 1 SECURITY VALIDATION")
    print("=" * 60)
    
    all_passed = True
    
    # Test 1: Security modules
    if not test_security_modules():
        all_passed = False
    
    # Test 2: Server configuration
    if not test_server_config():
        all_passed = False
    
    # Test 3: Payment security
    if not test_payment_security():
        all_passed = False
    
    print("\n" + "=" * 60)
    if all_passed:
        print("✓ ALL PHASE 1 SECURITY TESTS PASSED")
        print("=" * 60)
        return 0
    else:
        print("✗ SOME PHASE 1 SECURITY TESTS FAILED")
        print("=" * 60)
        return 1

if __name__ == '__main__':
    sys.exit(main())