"""
Payment State Machine - Enforces valid payment state transitions.
Prevents invalid payment status changes and ensures business logic integrity.
"""
import logging
from enum import Enum
from typing import Dict, Set, Tuple, Optional

logger = logging.getLogger(__name__)


class PaymentState(Enum):
    """Valid payment states."""
    PENDING = "pending"
    PROCESSING = "processing"
    SUCCESSFUL = "successful"
    FAILED = "failed"
    CANCELLED = "cancelled"
    REVERSED = "reversed"
    REFUNDED = "refunded"
    PAID = "paid"  # Internal state after verification


class PaymentStateMachine:
    """
    State machine for payment status transitions.
    Ensures only valid state transitions are allowed.
    """
    
    # Define valid state transitions
    VALID_TRANSITIONS: Dict[PaymentState, Set[PaymentState]] = {
        PaymentState.PENDING: {
            PaymentState.PROCESSING,
            PaymentState.FAILED,
            PaymentState.CANCELLED,
            PaymentState.SUCCESSFUL,
            PaymentState.PAID  # Direct success for some payment methods
        },
        PaymentState.PROCESSING: {
            PaymentState.SUCCESSFUL,
            PaymentState.FAILED,
            PaymentState.CANCELLED
        },
        PaymentState.SUCCESSFUL: {
            PaymentState.PAID,  # Verification step
            PaymentState.FAILED,  # Post-verification failure
            PaymentState.REFUNDED
        },
        PaymentState.FAILED: {
            PaymentState.PENDING,  # Retry
            PaymentState.CANCELLED,
            # Recovery: a payment marked 'failed' by a gateway timeout/network
            # error can later be confirmed by an authoritative source (HMAC-verified
            # webhook or gateway status poll). Without these, a real debit is lost.
            PaymentState.SUCCESSFUL,
            PaymentState.PAID
        },
        PaymentState.CANCELLED: set(),  # Terminal state
        PaymentState.PAID: {
            PaymentState.REFUNDED,
            PaymentState.REVERSED
        },
        PaymentState.REFUNDED: set(),  # Terminal state
        PaymentState.REVERSED: set(),  # Terminal state
    }
    
    # Terminal states (no further transitions allowed)
    TERMINAL_STATES: Set[PaymentState] = {
        PaymentState.CANCELLED,
        PaymentState.REFUNDED,
        PaymentState.REVERSED
    }
    
    # States that allow retry
    RETRYABLE_STATES: Set[PaymentState] = {
        PaymentState.FAILED,
        PaymentState.CANCELLED
    }
    
    @classmethod
    def is_valid_transition(cls, current_state: str, new_state: str) -> Tuple[bool, Optional[str]]:
        """
        Validate if a state transition is allowed.
        
        Args:
            current_state: Current payment state
            new_state: Desired new state
            
        Returns:
            Tuple of (is_valid: bool, error_message: Optional[str])
        """
        try:
            current = PaymentState(current_state.lower())
            new = PaymentState(new_state.lower())
        except ValueError as e:
            return False, f"Invalid state: {e}"
        
        # Same state is always valid (idempotent)
        if current == new:
            return True, None
        
        # Check if transition is allowed
        allowed_transitions = cls.VALID_TRANSITIONS.get(current, set())
        if new not in allowed_transitions:
            return False, f"Invalid transition from {current.value} to {new.value}. Allowed: {[s.value for s in allowed_transitions]}"
        
        return True, None
    
    @classmethod
    def is_terminal_state(cls, state: str) -> bool:
        """Check if a state is terminal (no further transitions allowed)."""
        try:
            return PaymentState(state.lower()) in cls.TERMINAL_STATES
        except ValueError:
            return False
    
    @classmethod
    def is_retryable_state(cls, state: str) -> bool:
        """Check if a payment in this state can be retried."""
        try:
            return PaymentState(state.lower()) in cls.RETRYABLE_STATES
        except ValueError:
            return False
    
    @classmethod
    def get_allowed_transitions(cls, state: str) -> Set[str]:
        """Get all allowed transitions from a given state."""
        try:
            current = PaymentState(state.lower())
            allowed = cls.VALID_TRANSITIONS.get(current, set())
            return {s.value for s in allowed}
        except ValueError:
            return set()
    
    @classmethod
    def validate_payment_update(cls, payment_id: int, current_status: str, new_status: str, 
                              amount: float, verified_by: Optional[int] = None) -> Tuple[bool, Optional[str]]:
        """
        Comprehensive validation for payment status updates.
        
        Args:
            payment_id: Payment ID
            current_status: Current payment status
            new_status: New payment status
            amount: Payment amount
            verified_by: ID of admin verifying the payment (if applicable)
            
        Returns:
            Tuple of (is_valid: bool, error_message: Optional[str])
        """
        # Validate state transition
        is_valid, error = cls.is_valid_transition(current_status, new_status)
        if not is_valid:
            logger.warning(f"Invalid payment state transition for payment {payment_id}: {current_status} -> {new_status}")
            return False, error
        
        # Business logic validations
        if new_status.lower() == 'paid':
            if verified_by is None:
                return False, "Payment verification requires admin approval"
            
            if amount <= 0:
                return False, "Payment amount must be positive"
        
        if new_status.lower() == 'refunded':
            if current_status.lower() not in ['paid', 'successful']:
                return False, "Can only refund paid or successful payments"
        
        if new_status.lower() == 'reversed':
            if current_status.lower() != 'paid':
                return False, "Can only reverse paid payments"
        
        return True, None


def validate_payment_state_transition(current_status: str, new_status: str) -> Tuple[bool, Optional[str]]:
    """
    Convenience function for state transition validation.
    
    Args:
        current_status: Current payment status
        new_status: New payment status
        
    Returns:
        Tuple of (is_valid: bool, error_message: Optional[str])
    """
    return PaymentStateMachine.is_valid_transition(current_status, new_status)