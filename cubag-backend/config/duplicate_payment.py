"""
Duplicate Payment Detection - Prevents duplicate payment processing.
"""
import logging
from datetime import datetime, timedelta
from typing import Optional, Tuple

logger = logging.getLogger(__name__)


class DuplicatePaymentDetector:
    """
    Detects and prevents duplicate payment processing.
    """
    
    # Time window to consider payments as potential duplicates (in minutes)
    DUPLICATE_TIME_WINDOW = 30
    
    # Fields to consider for duplicate detection
    DUPLICATE_FIELDS = ['member_id', 'amount', 'description', 'payment_method']
    
    @classmethod
    def check_duplicate_payment(cls, cursor, member_id: int, amount: float, 
                             description: str, payment_method: str = None,
                             payment_ref: str = None, is_installment: bool = False) -> Tuple[bool, Optional[dict]]:
        """
        Check if a payment is a potential duplicate.
        
        Args:
            cursor: Database cursor
            member_id: Member ID
            amount: Payment amount
            description: Payment description
            payment_method: Payment method (optional)
            payment_ref: Payment reference (optional)
            is_installment: Whether this is an installment payment (optional)
            
        Returns:
            Tuple of (is_duplicate: bool, duplicate_payment: Optional[dict])
        """
        try:
            # Installment payments are legitimate multiple payments, so skip duplicate checks
            if is_installment:
                logger.debug(f"Skipping duplicate check for installment payment for member {member_id}")
                return False, None
            
            # First check by payment reference (if provided)
            if payment_ref:
                cursor.execute(
                    "SELECT id, status, created_at FROM payments WHERE payment_ref = %s AND member_id = %s",
                    (payment_ref, member_id)
                )
                existing = cursor.fetchone()
                if existing:
                    status = str(existing.get('status', '')).lower()
                    if status in ['paid', 'successful', 'processing']:
                        logger.warning(f"Duplicate payment detected by reference: {payment_ref} for member {member_id}")
                        return True, existing
            
            # Check for potential duplicates by amount and description within time window
            time_threshold = datetime.now() - timedelta(minutes=cls.DUPLICATE_TIME_WINDOW)
            
            query = """
                SELECT id, status, amount, description, payment_method, 
                       payment_ref, created_at, paid_at, is_installment
                FROM payments 
                WHERE member_id = %s 
                  AND amount = %s 
                  AND LOWER(description) = LOWER(%s)
                  AND created_at >= %s
                  AND LOWER(status) NOT IN ('failed', 'cancelled', 'reversed')
                  AND (is_installment IS FALSE OR is_installment IS NULL)
                ORDER BY created_at DESC
                LIMIT 5
            """
            
            cursor.execute(query, (member_id, amount, description, time_threshold))
            recent_payments = cursor.fetchall()
            
            for payment in recent_payments:
                # Check if payment method matches (if provided)
                if payment_method and payment.get('payment_method'):
                    if str(payment.get('payment_method')).lower() != str(payment_method).lower():
                        continue
                
                # Check if payment is already paid/processing
                status = str(payment.get('status', '')).lower()
                if status in ['paid', 'successful', 'processing']:
                    logger.warning(f"Potential duplicate payment detected for member {member_id}: amount={amount}, description={description}")
                    return True, payment
            
            return False, None
            
        except Exception as e:
            logger.error(f"Error checking duplicate payment: {e}")
            return False, None
    
    @classmethod
    def check_payment_ref_uniqueness(cls, cursor, payment_ref: str, exclude_id: int = None) -> bool:
        """
        Check if a payment reference is unique (not already used).
        
        Args:
            cursor: Database cursor
            payment_ref: Payment reference to check
            exclude_id: Payment ID to exclude from check (for updates)
            
        Returns:
            bool: True if reference is unique, False if already exists
        """
        try:
            if not payment_ref:
                return True  # Empty reference is allowed
            
            query = "SELECT id FROM payments WHERE payment_ref = %s"
            params = [payment_ref]
            
            if exclude_id:
                query += " AND id != %s"
                params.append(exclude_id)
            
            cursor.execute(query, params)
            existing = cursor.fetchone()
            
            return existing is None
            
        except Exception as e:
            logger.error(f"Error checking payment reference uniqueness: {e}")
            return False
    
    @classmethod
    def detect_refund_duplicates(cls, cursor, original_payment_id: int, 
                               refund_amount: float) -> Tuple[bool, Optional[dict]]:
        """
        Check if a refund has already been processed for the original payment.
        
        Args:
            cursor: Database cursor
            original_payment_id: Original payment ID
            refund_amount: Refund amount
            
        Returns:
            Tuple of (has_duplicate_refund: bool, refund_payment: Optional[dict])
        """
        try:
            cursor.execute(
                """
                SELECT id, status, amount, created_at 
                FROM payments 
                WHERE id = %s AND LOWER(status) = 'refunded'
                """,
                (original_payment_id,)
            )
            original = cursor.fetchone()
            
            if original:
                # Check if a refund payment already exists
                cursor.execute(
                    """
                    SELECT id, status, amount, description, created_at
                    FROM payments
                    WHERE description LIKE %s 
                      AND member_id = %s
                      AND LOWER(status) = 'successful'
                    """,
                    (f'%refund%{original_payment_id}%', original.get('member_id'))
                )
                refund = cursor.fetchone()
                
                if refund:
                    logger.warning(f"Duplicate refund detected for payment {original_payment_id}")
                    return True, refund
            
            return False, None
            
        except Exception as e:
            logger.error(f"Error checking refund duplicates: {e}")
            return False, None


def check_duplicate_payment(cursor, member_id: int, amount: float, 
                           description: str, payment_method: str = None,
                           payment_ref: str = None, is_installment: bool = False) -> Tuple[bool, Optional[dict]]:
    """
    Convenience function for duplicate payment detection.
    
    Args:
        cursor: Database cursor
        member_id: Member ID
        amount: Payment amount
        description: Payment description
        payment_method: Payment method (optional)
        payment_ref: Payment reference (optional)
        is_installment: Whether this is an installment payment (optional)
        
    Returns:
        Tuple of (is_duplicate: bool, duplicate_payment: Optional[dict])
    """
    return DuplicatePaymentDetector.check_duplicate_payment(
        cursor, member_id, amount, description, payment_method, payment_ref, is_installment
    )