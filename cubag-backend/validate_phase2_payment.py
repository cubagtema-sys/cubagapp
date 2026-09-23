#!/usr/bin/env python3
"""
Quick validation script for Phase 2 payment security improvements.
Tests that payment security modules are properly configured and functional.
"""
import sys
import os

def test_payment_state_machine():
    """Test that payment state machine is properly configured."""
    print("Testing payment state machine...")
    
    try:
        from config.payment_state_machine import (
            PaymentStateMachine,
            validate_payment_state_transition,
            PaymentState
        )
        print("✓ Payment state machine imported successfully")
        
        # Test basic functionality
        is_valid, error = PaymentStateMachine.is_valid_transition('pending', 'processing')
        assert is_valid is True
        print("✓ Valid state transition test passed")
        
        is_valid, error = PaymentStateMachine.is_valid_transition('paid', 'pending')
        assert is_valid is False
        print("✓ Invalid state transition test passed")
        
        return True
    except Exception as e:
        print(f"✗ Payment state machine test failed: {e}")
        return False

def test_duplicate_payment_detection():
    """Test that duplicate payment detection is properly configured."""
    print("\nTesting duplicate payment detection...")
    
    try:
        from config.duplicate_payment import (
            DuplicatePaymentDetector,
            check_duplicate_payment
        )
        print("✓ Duplicate payment detection imported successfully")
        
        # Test basic functionality
        assert callable(check_duplicate_payment)
        print("✓ check_duplicate_payment function is callable")
        
        assert hasattr(DuplicatePaymentDetector, 'check_duplicate_payment')
        print("✓ DuplicatePaymentDetector has check_duplicate_payment method")
        
        return True
    except Exception as e:
        print(f"✗ Duplicate payment detection test failed: {e}")
        return False

def test_payment_reconciliation():
    """Test that payment reconciliation is properly configured."""
    print("\nTesting payment reconciliation...")
    
    try:
        from config.payment_reconciliation import (
            PaymentReconciler,
            run_payment_reconciliation
        )
        print("✓ Payment reconciliation imported successfully")
        
        # Test basic functionality
        assert callable(run_payment_reconciliation)
        print("✓ run_payment_reconciliation function is callable")
        
        assert hasattr(PaymentReconciler, 'reconcile_pending_payments')
        print("✓ PaymentReconciler has reconcile_pending_payments method")
        
        assert hasattr(PaymentReconciler, 'reconcile_orphaned_payments')
        print("✓ PaymentReconciler has reconcile_orphaned_payments method")
        
        assert hasattr(PaymentReconciler, 'detect_payment_anomalies')
        print("✓ PaymentReconciler has detect_payment_anomalies method")
        
        return True
    except Exception as e:
        print(f"✗ Payment reconciliation test failed: {e}")
        return False

def test_payment_route_integration():
    """Test that payment routes include security enhancements."""
    print("\nTesting payment route security integration...")
    
    try:
        with open('routes/payments.py', 'r') as f:
            payments_content = f.read()
        
        # Check for state machine integration
        if 'PaymentStateMachine' in payments_content:
            print("✓ Payment state machine integrated in payment routes")
        else:
            print("✗ Payment state machine not integrated")
            return False
        
        # Check for duplicate detection integration
        if 'check_duplicate_payment' in payments_content:
            print("✓ Duplicate payment detection integrated in payment routes")
        else:
            print("✗ Duplicate payment detection not integrated")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Payment route integration check failed: {e}")
        return False

def test_jobs_integration():
    """Test that jobs scheduler includes payment reconciliation."""
    print("\nTesting jobs scheduler integration...")
    
    try:
        with open('jobs.py', 'r') as f:
            jobs_content = f.read()
        
        # Check for payment reconciliation import
        if 'PaymentReconciler' in jobs_content:
            print("✓ Payment reconciliation imported in jobs")
        else:
            print("✗ Payment reconciliation not imported")
            return False
        
        # Check for payment reconciliation job
        if 'run_payment_reconciliation_job' in jobs_content:
            print("✓ Payment reconciliation job function defined")
        else:
            print("✗ Payment reconciliation job function not defined")
            return False
        
        # Check for scheduler integration
        if 'run_payment_reconciliation_job' in jobs_content and 'add_job' in jobs_content:
            print("✓ Payment reconciliation job added to scheduler")
        else:
            print("✗ Payment reconciliation job not added to scheduler")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Jobs integration check failed: {e}")
        return False

def main():
    """Run all validation tests."""
    print("=" * 60)
    print("PHASE 2 PAYMENT SECURITY VALIDATION")
    print("=" * 60)
    
    all_passed = True
    
    # Test 1: Payment state machine
    if not test_payment_state_machine():
        all_passed = False
    
    # Test 2: Duplicate payment detection
    if not test_duplicate_payment_detection():
        all_passed = False
    
    # Test 3: Payment reconciliation
    if not test_payment_reconciliation():
        all_passed = False
    
    # Test 4: Payment route integration
    if not test_payment_route_integration():
        all_passed = False
    
    # Test 5: Jobs integration
    if not test_jobs_integration():
        all_passed = False
    
    print("\n" + "=" * 60)
    if all_passed:
        print("✓ ALL PHASE 2 PAYMENT SECURITY TESTS PASSED")
        print("=" * 60)
        return 0
    else:
        print("✗ SOME PHASE 2 PAYMENT SECURITY TESTS FAILED")
        print("=" * 60)
        return 1

if __name__ == '__main__':
    sys.exit(main())