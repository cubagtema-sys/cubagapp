"""
Data Retention Policy Manager - Implements automated data retention and cleanup policies.
"""
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


class DataRetentionPolicy:
    """
    Defines data retention policies for different data types.
    Ensures compliance with data privacy regulations and efficient storage management.
    """
    
    # Retention periods (in days) for different data types
    RETENTION_POLICIES = {
        # Authentication & Security
        'otp_codes': 7,  # OTP codes expire after 7 days
        'password_reset_tokens': 1,  # Password reset tokens expire after 1 day
        
        # Payment & Financial
        'payment_logs': 365,  # Payment logs kept for 1 year
        'failed_payments': 90,  # Failed payment records kept for 90 days
        'receipt_uploads': 1825,  # Receipts kept for 5 years for audit
        
        # User Activity
        'login_history': 365,  # Login history kept for 1 year
        'activity_logs': 180,  # General activity logs kept for 6 months
        
        # Communications
        'notifications': 365,  # Notifications kept for 1 year
        'email_logs': 90,  # Email logs kept for 90 days
        
        # Support & Tickets
        'closed_tickets': 730,  # Closed support tickets kept for 2 years
        'ticket_replies': 730,  # Ticket replies kept for 2 years
        
        # Compliance & Documents
        'document_versions': 365,  # Previous document versions kept for 1 year
        'audit_logs': 2555,  # Audit logs kept for 7 years
        
        # Temporary Data
        'cache_entries': 1,  # Cache entries expire after 1 day
        'temp_uploads': 7,  # Temporary uploads expire after 7 days
    }
    
    # Data that should never be automatically deleted
    PERMANENT_DATA = {
        'members',  # Member records (unless explicitly deleted)
        'compliance_applications',  # Compliance applications
        'payments',  # Payment records (financial records)
        'tasks',  # Task records
        'events',  # Event records
        'announcements',  # Announcement records
    }
    
    @classmethod
    def get_retention_period(cls, data_type: str) -> Optional[int]:
        """Get retention period for a specific data type."""
        return cls.RETENTION_POLICIES.get(data_type)
    
    @classmethod
    def should_retain_permanently(cls, data_type: str) -> bool:
        """Check if data type should be retained permanently."""
        return data_type in cls.PERMANENT_DATA
    
    @classmethod
    def is_expired(cls, data_type: str, created_at: datetime) -> bool:
        """Check if data has expired based on retention policy."""
        retention_days = cls.get_retention_period(data_type)
        if retention_days is None:
            return False  # No retention policy means keep indefinitely
        
        expiry_date = created_at + timedelta(days=retention_days)
        return datetime.now() > expiry_date


class DataRetentionPolicyEnforcer:
    """
    Enforces data retention policies by cleaning up expired data.
    """
    
    def __init__(self, db_connection):
        """
        Initialize the policy enforcer.
        
        Args:
            db_connection: Database connection
        """
        self.db = db_connection
    
    def cleanup_expired_otp_codes(self) -> Dict[str, int]:
        """Clean up expired OTP codes."""
        results = {'deleted': 0, 'errors': 0}
        
        try:
            retention_days = DataRetentionPolicy.get_retention_period('otp_codes')
            if retention_days is None:
                return results
            
            expiry_date = datetime.now() - timedelta(days=retention_days)
            
            with self.db.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM otp_codes WHERE created_at < %s",
                    (expiry_date,)
                )
                results['deleted'] = cursor.rowcount
                self.db.commit()
                
            logger.info(f"Cleaned up {results['deleted']} expired OTP codes")
            
        except Exception as e:
            logger.error(f"Error cleaning up OTP codes: {e}")
            results['errors'] += 1
            self.db.rollback()
        
        return results
    
    def cleanup_old_notifications(self) -> Dict[str, int]:
        """Clean up old notifications."""
        results = {'deleted': 0, 'errors': 0}
        
        try:
            retention_days = DataRetentionPolicy.get_retention_period('notifications')
            if retention_days is None:
                return results
            
            expiry_date = datetime.now() - timedelta(days=retention_days)
            
            with self.db.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM notifications WHERE created_at < %s",
                    (expiry_date,)
                )
                results['deleted'] = cursor.rowcount
                self.db.commit()
                
            logger.info(f"Cleaned up {results['deleted']} old notifications")
            
        except Exception as e:
            logger.error(f"Error cleaning up notifications: {e}")
            results['errors'] += 1
            self.db.rollback()
        
        return results
    
    def cleanup_old_temp_uploads(self) -> Dict[str, int]:
        """Clean up old temporary uploads."""
        results = {'deleted': 0, 'errors': 0}
        
        try:
            retention_days = DataRetentionPolicy.get_retention_period('temp_uploads')
            if retention_days is None:
                return results
            
            expiry_date = datetime.now() - timedelta(days=retention_days)
            
            with self.db.cursor() as cursor:
                # This would need to be adapted based on your temp upload storage structure
                # For now, this is a placeholder for the logic
                cursor.execute(
                    "DELETE FROM temp_uploads WHERE created_at < %s",
                    (expiry_date,)
                )
                results['deleted'] = cursor.rowcount
                self.db.commit()
                
            logger.info(f"Cleaned up {results['deleted']} old temporary uploads")
            
        except Exception as e:
            logger.error(f"Error cleaning up temp uploads: {e}")
            results['errors'] += 1
            self.db.rollback()
        
        return results
    
    def cleanup_failed_payments(self) -> Dict[str, int]:
        """Clean up old failed payment records."""
        results = {'deleted': 0, 'errors': 0}
        
        try:
            retention_days = DataRetentionPolicy.get_retention_period('failed_payments')
            if retention_days is None:
                return results
            
            expiry_date = datetime.now() - timedelta(days=retention_days)
            
            with self.db.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM payments WHERE status = 'failed' AND created_at < %s",
                    (expiry_date,)
                )
                results['deleted'] = cursor.rowcount
                self.db.commit()
                
            logger.info(f"Cleaned up {results['deleted']} old failed payment records")
            
        except Exception as e:
            logger.error(f"Error cleaning up failed payments: {e}")
            results['errors'] += 1
            self.db.rollback()
        
        return results
    
    def run_all_cleanup_tasks(self) -> Dict[str, any]:
        """Run all data cleanup tasks."""
        results = {
            'timestamp': datetime.now().isoformat(),
            'tasks_completed': 0,
            'total_deleted': 0,
            'total_errors': 0,
            'task_results': {}
        }
        
        tasks = [
            ('otp_codes', self.cleanup_expired_otp_codes),
            ('notifications', self.cleanup_old_notifications),
            ('failed_payments', self.cleanup_failed_payments),
            ('temp_uploads', self.cleanup_old_temp_uploads),
        ]
        
        for task_name, task_func in tasks:
            try:
                task_result = task_func()
                results['task_results'][task_name] = task_result
                results['total_deleted'] += task_result.get('deleted', 0)
                results['total_errors'] += task_result.get('errors', 0)
                results['tasks_completed'] += 1
            except Exception as e:
                logger.error(f"Error in cleanup task {task_name}: {e}")
                results['task_results'][task_name] = {'error': str(e)}
                results['total_errors'] += 1
        
        logger.info(f"Data retention cleanup completed: {results}")
        return results


def run_data_retention_cleanup(db_connection) -> Dict[str, any]:
    """
    Run complete data retention cleanup process.
    
    Args:
        db_connection: Database connection
        
    Returns:
        Dict with cleanup results
    """
    enforcer = DataRetentionPolicyEnforcer(db_connection)
    return enforcer.run_all_cleanup_tasks()