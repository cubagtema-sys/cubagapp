"""
Audit Logging for Data Access - Tracks access to sensitive data for compliance.
"""
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any
from flask import request

logger = logging.getLogger(__name__)


class DataAccessLogger:
    """
    Logs access to sensitive data for audit and compliance purposes.
    """
    
    # Sensitive data access types
    ACCESS_TYPES = {
        'member_profile_view',
        'payment_history_view',
        'compliance_data_view',
        'personal_data_export',
        'admin_data_access',
        'bulk_data_export',
        'data_deletion_request',
    }
    
    def __init__(self, db_connection):
        """
        Initialize the data access logger.
        
        Args:
            db_connection: Database connection
        """
        self.db = db_connection
    
    def log_data_access(self, access_type: str, user_id: int, target_id: int = None,
                      resource_type: str = None, details: Dict[str, Any] = None):
        """
        Log data access event.
        
        Args:
            access_type: Type of data access
            user_id: ID of the user accessing the data
            target_id: ID of the target data (optional)
            resource_type: Type of resource being accessed (optional)
            details: Additional details about the access (optional)
        """
        try:
            with self.db.cursor() as cursor:
                # Get IP address from request context
                ip_address = request.remote_addr if request else 'unknown'
                
                # Log to audit table
                cursor.execute("""
                    INSERT INTO audit_log 
                    (admin_id, action, target_type, target_id, details, ip_address, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, NOW())
                """, (
                    user_id,
                    f"data_access_{access_type}",
                    resource_type or 'unknown',
                    target_id,
                    str(details) if details else None,
                    ip_address
                ))
                
                self.db.commit()
                logger.debug(f"Logged data access: {access_type} by user {user_id}")
                
        except Exception as e:
            logger.error(f"Error logging data access: {e}")
            self.db.rollback()
    
    def log_member_profile_access(self, accessor_id: int, target_member_id: int, reason: str = None):
        """Log access to member profile data."""
        self.log_data_access(
            access_type='member_profile_view',
            user_id=accessor_id,
            target_id=target_member_id,
            resource_type='member',
            details={'reason': reason} if reason else None
        )
    
    def log_payment_history_access(self, accessor_id: int, target_member_id: int, reason: str = None):
        """Log access to payment history."""
        self.log_data_access(
            access_type='payment_history_view',
            user_id=accessor_id,
            target_id=target_member_id,
            resource_type='payment',
            details={'reason': reason} if reason else None
        )
    
    def log_data_export(self, user_id: int, export_type: str, record_count: int = 0):
        """Log data export event."""
        self.log_data_access(
            access_type='personal_data_export',
            user_id=user_id,
            resource_type='export',
            details={
                'export_type': export_type,
                'record_count': record_count
            }
        )
    
    def log_admin_data_access(self, admin_id: int, access_type: str, target_type: str, target_id: int = None):
        """Log admin access to sensitive data."""
        self.log_data_access(
            access_type='admin_data_access',
            user_id=admin_id,
            target_id=target_id,
            resource_type=target_type,
            details={'admin_access_type': access_type}
        )
    
    def get_access_logs(self, user_id: int = None, access_type: str = None, 
                       limit: int = 100) -> List[Dict]:
        """
        Get access logs for audit purposes.
        
        Args:
            user_id: Filter by user ID (optional)
            access_type: Filter by access type (optional)
            limit: Maximum number of records to return
            
        Returns:
            List of access log entries
        """
        try:
            with self.db.cursor() as cursor:
                query = """
                    SELECT id, admin_id, action, target_type, target_id, 
                           details, ip_address, created_at
                    FROM audit_log
                    WHERE action LIKE 'data_access_%'
                """
                params = []
                
                if user_id:
                    query += " AND admin_id = %s"
                    params.append(user_id)
                
                if access_type:
                    query += " AND action = %s"
                    params.append(f"data_access_{access_type}")
                
                query += " ORDER BY created_at DESC LIMIT %s"
                params.append(limit)
                
                cursor.execute(query, params)
                return [dict(row) for row in cursor.fetchall()]
                
        except Exception as e:
            logger.error(f"Error getting access logs: {e}")
            return []


def get_data_access_logger(db_connection) -> DataAccessLogger:
    """
    Get a data access logger instance.
    
    Args:
        db_connection: Database connection
        
    Returns:
        DataAccessLogger instance
    """
    return DataAccessLogger(db_connection)