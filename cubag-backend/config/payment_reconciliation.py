"""
Payment Reconciliation Jobs - Ensures payment data consistency between local DB and external payment systems.
"""
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


class PaymentReconciler:
    """
    Reconciles payment data between local database and external payment gateways.
    """
    
    def __init__(self, db_connection, payment_gateway_client=None):
        """
        Initialize the payment reconciler.
        
        Args:
            db_connection: Database connection
            payment_gateway_client: External payment gateway client (optional)
        """
        self.db = db_connection
        self.gateway_client = payment_gateway_client
    
    def reconcile_pending_payments(self, max_age_hours: int = 24) -> Dict[str, any]:
        """
        Reconcile pending payments that are older than specified age.
        
        Args:
            max_age_hours: Maximum age in hours for pending payments to reconcile
            
        Returns:
            Dict with reconciliation results
        """
        results = {
            'total_checked': 0,
            'updated': 0,
            'failed': 0,
            'no_change': 0,
            'errors': []
        }
        
        try:
            with self.db.cursor() as cursor:
                # Find pending payments older than max_age_hours
                time_threshold = datetime.now() - timedelta(hours=max_age_hours)
                
                cursor.execute("""
                    SELECT id, payment_ref, amount, member_id, status, created_at
                    FROM payments
                    WHERE status = 'pending'
                      AND payment_ref IS NOT NULL
                      AND created_at < %s
                    ORDER BY created_at ASC
                    LIMIT 50
                """, (time_threshold,))
                
                pending_payments = cursor.fetchall()
                results['total_checked'] = len(pending_payments)
                
                for payment in pending_payments:
                    try:
                        payment_id = payment['id']
                        payment_ref = payment['payment_ref']
                        
                        # Check with external gateway
                        gateway_status = self._check_gateway_status(payment_ref)
                        
                        if gateway_status:
                            # Update local status based on gateway status
                            if gateway_status.lower() in ['successful', 'success', 'completed']:
                                cursor.execute(
                                    "UPDATE payments SET status = 'paid', paid_at = NOW() WHERE id = %s",
                                    (payment_id,)
                                )
                                results['updated'] += 1
                                logger.info(f"Reconciled payment {payment_id} as paid via gateway check")
                            
                            elif gateway_status.lower() in ['failed', 'declined', 'cancelled']:
                                cursor.execute(
                                    "UPDATE payments SET status = 'failed' WHERE id = %s",
                                    (payment_id,)
                                )
                                results['updated'] += 1
                                logger.info(f"Reconciled payment {payment_id} as failed via gateway check")
                            
                            else:
                                results['no_change'] += 1
                        else:
                            results['no_change'] += 1
                            logger.warning(f"Could not determine gateway status for payment {payment_id}")
                    
                    except Exception as e:
                        results['errors'].append(f"Payment {payment.get('id')}: {str(e)}")
                        results['failed'] += 1
                        logger.error(f"Error reconciling payment {payment.get('id')}: {e}")
                
                self.db.commit()
                
        except Exception as e:
            logger.error(f"Error in payment reconciliation: {e}")
            results['errors'].append(f"Reconciliation failed: {str(e)}")
        
        return results
    
    def _check_gateway_status(self, payment_ref: str) -> Optional[str]:
        """
        Check payment status with external gateway.
        
        Args:
            payment_ref: Payment reference
            
        Returns:
            Gateway status or None if unavailable
        """
        if not self.gateway_client:
            return None
        
        try:
            # This would be implemented based on the specific gateway API
            # For now, return None to indicate gateway check not available
            return None
        except Exception as e:
            logger.error(f"Error checking gateway status for {payment_ref}: {e}")
            return None
    
    def reconcile_orphaned_payments(self) -> Dict[str, any]:
        """
        Find and handle orphaned payments (payments without corresponding records).
        
        Returns:
            Dict with reconciliation results
        """
        results = {
            'orphaned_found': 0,
            'resolved': 0,
            'requires_manual_review': 0,
            'errors': []
        }
        
        try:
            with self.db.cursor() as cursor:
                # Find payments that are paid but don't have corresponding member updates
                cursor.execute("""
                    SELECT p.id, p.member_id, p.amount, p.description, p.paid_at
                    FROM payments p
                    LEFT JOIN members m ON p.member_id = m.id
                    WHERE p.status = 'paid'
                      AND p.paid_at > NOW() - INTERVAL '7 days'
                      AND (
                          m.registration_fee_paid IS FALSE 
                          OR m.application_fee_paid IS FALSE
                      )
                    LIMIT 100
                """)
                
                orphaned_payments = cursor.fetchall()
                results['orphaned_found'] = len(orphaned_payments)
                
                for payment in orphaned_payments:
                    try:
                        payment_id = payment['id']
                        member_id = payment['member_id']
                        description = payment.get('description', '').lower()
                        
                        # Check if this should have updated member flags
                        if any(k in description for k in ['registration', 'new member', 'entrance', 'package']):
                            cursor.execute(
                                "UPDATE members SET registration_fee_paid = TRUE, application_fee_paid = TRUE WHERE id = %s",
                                (member_id,)
                            )
                            results['resolved'] += 1
                            logger.info(f"Resolved orphaned payment {payment_id} - updated member flags")
                        else:
                            results['requires_manual_review'] += 1
                            logger.warning(f"Payment {payment_id} may require manual review")
                    
                    except Exception as e:
                        results['errors'].append(f"Payment {payment.get('id')}: {str(e)}")
                        logger.error(f"Error resolving orphaned payment {payment.get('id')}: {e}")
                
                self.db.commit()
                
        except Exception as e:
            logger.error(f"Error in orphaned payment reconciliation: {e}")
            results['errors'].append(f"Orphaned reconciliation failed: {str(e)}")
        
        return results
    
    def detect_payment_anomalies(self) -> Dict[str, any]:
        """
        Detect payment anomalies that may indicate fraud or system issues.
        
        Returns:
            Dict with anomaly detection results
        """
        results = {
            'anomalies_detected': 0,
            'high_amount_payments': [],
            'rapid_payments': [],
            'same_amount_multiple': [],
            'errors': []
        }
        
        try:
            with self.db.cursor() as cursor:
                # Detect unusually high payments
                cursor.execute("""
                    SELECT id, member_id, amount, description, created_at
                    FROM payments
                    WHERE amount > 10000
                      AND created_at > NOW() - INTERVAL '30 days'
                    ORDER BY amount DESC
                    LIMIT 20
                """)
                
                high_amount = cursor.fetchall()
                for payment in high_amount:
                    results['high_amount_payments'].append({
                        'payment_id': payment['id'],
                        'member_id': payment['member_id'],
                        'amount': float(payment['amount']),
                        'description': payment['description']
                    })
                
                # Detect rapid payments from same member (potential fraud)
                cursor.execute("""
                    SELECT member_id, COUNT(*) as payment_count,
                           MAX(amount) as max_amount,
                           ARRAY_AGG(id ORDER BY created_at) as payment_ids
                    FROM payments
                    WHERE created_at > NOW() - INTERVAL '1 hour'
                    GROUP BY member_id
                    HAVING COUNT(*) >= 5
                """)
                
                rapid_payments = cursor.fetchall()
                for rapid in rapid_payments:
                    results['rapid_payments'].append({
                        'member_id': rapid['member_id'],
                        'payment_count': rapid['payment_count'],
                        'max_amount': float(rapid['max_amount']),
                        'payment_ids': rapid['payment_ids']
                    })
                
                # Detect multiple payments with same amount (potential duplicates)
                cursor.execute("""
                    SELECT amount, COUNT(*) as count, 
                           ARRAY_AGG(DISTINCT member_id) as members,
                           ARRAY_AGG(id ORDER BY created_at) as payment_ids
                    FROM payments
                    WHERE created_at > NOW() - INTERVAL '24 hours'
                      AND amount > 0
                    GROUP BY amount
                    HAVING COUNT(*) >= 10
                """)
                
                same_amount = cursor.fetchall()
                for same in same_amount:
                    results['same_amount_multiple'].append({
                        'amount': float(same['amount']),
                        'count': same['count'],
                        'member_count': len(same['members']),
                        'payment_ids': same['payment_ids']
                    })
                
                results['anomalies_detected'] = (
                    len(results['high_amount_payments']) + 
                    len(results['rapid_payments']) + 
                    len(results['same_amount_multiple'])
                )
                
        except Exception as e:
            logger.error(f"Error in payment anomaly detection: {e}")
            results['errors'].append(f"Anomaly detection failed: {str(e)}")
        
        return results


def run_payment_reconciliation(db_connection) -> Dict[str, any]:
    """
    Run full payment reconciliation process.
    
    Args:
        db_connection: Database connection
        
    Returns:
        Dict with complete reconciliation results
    """
    reconciler = PaymentReconciler(db_connection)
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'pending_reconciliation': {},
        'orphaned_reconciliation': {},
        'anomaly_detection': {},
        'overall_status': 'completed'
    }
    
    try:
        # Reconcile pending payments
        results['pending_reconciliation'] = reconciler.reconcile_pending_payments()
        
        # Reconcile orphaned payments
        results['orphaned_reconciliation'] = reconciler.reconcile_orphaned_payments()
        
        # Detect anomalies
        results['anomaly_detection'] = reconciler.detect_payment_anomalies()
        
        # Determine overall status
        total_errors = (
            len(results['pending_reconciliation'].get('errors', [])) +
            len(results['orphaned_reconciliation'].get('errors', [])) +
            len(results['anomaly_detection'].get('errors', []))
        )
        
        if total_errors > 0:
            results['overall_status'] = 'completed_with_errors'
        
        logger.info(f"Payment reconciliation completed: {results}")
        
    except Exception as e:
        logger.error(f"Payment reconciliation failed: {e}")
        results['overall_status'] = 'failed'
        results['error'] = str(e)
    
    return results