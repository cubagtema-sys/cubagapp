"""
Payment Security Tests - Tests for payment state machine, duplicate detection, and reconciliation.
"""
import pytest
from datetime import datetime, timedelta


class TestPaymentStateMachine:
    """Test payment state machine validation."""
    
    def test_valid_state_transitions(self):
        """Test that valid state transitions are allowed."""
        from config.payment_state_machine import PaymentStateMachine, PaymentState
        
        # Test pending -> processing
        is_valid, error = PaymentStateMachine.is_valid_transition('pending', 'processing')
        assert is_valid is True
        assert error is None
        
        # Test processing -> successful
        is_valid, error = PaymentStateMachine.is_valid_transition('processing', 'successful')
        assert is_valid is True
        assert error is None
        
        # Test successful -> paid
        is_valid, error = PaymentStateMachine.is_valid_transition('successful', 'paid')
        assert is_valid is True
        assert error is None
    
    def test_invalid_state_transitions(self):
        """Test that invalid state transitions are rejected."""
        from config.payment_state_machine import PaymentStateMachine
        
        # Test paid -> pending (should be invalid)
        is_valid, error = PaymentStateMachine.is_valid_transition('paid', 'pending')
        assert is_valid is False
        assert error is not None
        
        # Test failed -> paid (should be invalid)
        is_valid, error = PaymentStateMachine.is_valid_transition('failed', 'paid')
        assert is_valid is False
        assert error is not None
    
    def test_terminal_states(self):
        """Test that terminal states are correctly identified."""
        from config.payment_state_machine import PaymentStateMachine
        
        assert PaymentStateMachine.is_terminal_state('cancelled') is True
        assert PaymentStateMachine.is_terminal_state('refunded') is True
        assert PaymentStateMachine.is_terminal_state('reversed') is True
        assert PaymentStateMachine.is_terminal_state('pending') is False
        assert PaymentStateMachine.is_terminal_state('paid') is False
    
    def test_retryable_states(self):
        """Test that retryable states are correctly identified."""
        from config.payment_state_machine import PaymentStateMachine
        
        assert PaymentStateMachine.is_retryable_state('failed') is True
        assert PaymentStateMachine.is_retryable_state('cancelled') is True
        assert PaymentStateMachine.is_retryable_state('paid') is False
        assert PaymentStateMachine.is_retryable_state('pending') is False


class TestDuplicatePaymentDetection:
    """Test duplicate payment detection."""
    
    def test_duplicate_detector_exists(self):
        """Test that duplicate payment detector is available."""
        from config.duplicate_payment import DuplicatePaymentDetector
        assert DuplicatePaymentDetector is not None
    
    def test_duplicate_check_function_exists(self):
        """Test that duplicate check function is available."""
        from config.duplicate_payment import check_duplicate_payment
        assert callable(check_duplicate_payment)
    
    def test_payment_ref_uniqueness_check(self):
        """Test payment reference uniqueness check."""
        from config.duplicate_payment import DuplicatePaymentDetector
        
        # This is a structural test - actual functionality would require DB
        assert hasattr(DuplicatePaymentDetector, 'check_payment_ref_uniqueness')
        assert callable(DuplicatePaymentDetector.check_payment_ref_uniqueness)


class TestPaymentReconciliation:
    """Test payment reconciliation functionality."""
    
    def test_reconciler_class_exists(self):
        """Test that payment reconciler class exists."""
        from config.payment_reconciliation import PaymentReconciler
        assert PaymentReconciler is not None
    
    def test_reconciliation_function_exists(self):
        """Test that reconciliation function exists."""
        from config.payment_reconciliation import run_payment_reconciliation
        assert callable(run_payment_reconciliation)
    
    def test_reconciler_has_required_methods(self):
        """Test that reconciler has required methods."""
        from config.payment_reconciliation import PaymentReconciler
        
        assert hasattr(PaymentReconciler, 'reconcile_pending_payments')
        assert hasattr(PaymentReconciler, 'reconcile_orphaned_payments')
        assert hasattr(PaymentReconciler, 'detect_payment_anomalies')


class TestPaymentValidationIntegration:
    """Test integration of payment security features."""
    
    def test_state_machine_import(self):
        """Test that state machine can be imported."""
        from config.payment_state_machine import validate_payment_state_transition
        assert callable(validate_payment_state_transition)
    
    def test_duplicate_detection_import(self):
        """Test that duplicate detection can be imported."""
        from config.duplicate_payment import check_duplicate_payment
        assert callable(check_duplicate_payment)
    
    def test_reconciliation_import(self):
        """Test that reconciliation can be imported."""
        from config.payment_reconciliation import run_payment_reconciliation
        assert callable(run_payment_reconciliation)


if __name__ == '__main__':
    pytest.main([__file__, '-v'])