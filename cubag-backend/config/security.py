"""
Security utility functions for IDOR protection and access control.
"""
import logging
from flask import jsonify
from functools import wraps

logger = logging.getLogger(__name__)


def verify_payment_ownership(caller_id, payment_id, cursor):
    """
    Verify that the caller owns the payment or is an admin.
    Returns (has_access: bool, is_admin: bool, error_response: tuple or None)
    """
    try:
        # Check if caller is admin
        cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
        caller = cursor.fetchone()
        is_admin = caller and caller.get('role') in ('admin', 'sub_admin', 'super_admin')
        
        if is_admin:
            return True, True, None
        
        # Verify payment ownership
        cursor.execute(
            "SELECT member_id FROM payments WHERE id = %s",
            (payment_id,)
        )
        payment = cursor.fetchone()
        
        if not payment:
            return False, False, (jsonify({'message': 'Payment not found'}), 404)
        
        if str(payment['member_id']) != str(caller_id):
            logger.warning(f"IDOR attempt: User {caller_id} tried to access payment {payment_id} owned by {payment['member_id']}")
            return False, False, (jsonify({'message': 'Unauthorized access to payment'}), 403)
        
        return True, False, None
        
    except Exception as e:
        logger.error(f"Error in verify_payment_ownership: {e}")
        return False, False, (jsonify({'message': 'Error verifying ownership'}), 500)


def verify_member_ownership(caller_id, target_member_id, cursor):
    """
    Verify that the caller is accessing their own data or is an admin.
    Returns (has_access: bool, is_admin: bool, error_response: tuple or None)
    """
    try:
        # Check if caller is admin
        cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
        caller = cursor.fetchone()
        is_admin = caller and caller.get('role') in ('admin', 'sub_admin', 'super_admin')
        
        if is_admin:
            return True, True, None
        
        # Verify self-access
        if str(caller_id) != str(target_member_id):
            logger.warning(f"IDOR attempt: User {caller_id} tried to access member data for {target_member_id}")
            return False, False, (jsonify({'message': 'Unauthorized access to member data'}), 403)
        
        return True, False, None
        
    except Exception as e:
        logger.error(f"Error in verify_member_ownership: {e}")
        return False, False, (jsonify({'message': 'Error verifying ownership'}), 500)


def verify_compliance_ownership(caller_id, application_id, cursor):
    """
    Verify that the caller owns the compliance application or is an admin.
    Returns (has_access: bool, is_admin: bool, error_response: tuple or None)
    """
    try:
        # Check if caller is admin
        cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
        caller = cursor.fetchone()
        is_admin = caller and caller.get('role') in ('admin', 'sub_admin', 'super_admin')
        
        if is_admin:
            return True, True, None
        
        # Verify application ownership
        cursor.execute(
            "SELECT member_id FROM compliance_applications WHERE id = %s",
            (application_id,)
        )
        application = cursor.fetchone()
        
        if not application:
            return False, False, (jsonify({'message': 'Application not found'}), 404)
        
        if str(application['member_id']) != str(caller_id):
            logger.warning(f"IDOR attempt: User {caller_id} tried to access compliance application {application_id} owned by {application['member_id']}")
            return False, False, (jsonify({'message': 'Unauthorized access to compliance application'}), 403)
        
        return True, False, None
        
    except Exception as e:
        logger.error(f"Error in verify_compliance_ownership: {e}")
        return False, False, (jsonify({'message': 'Error verifying ownership'}), 500)


def require_ownership_or_admin(resource_type='payment'):
    """
    Decorator to enforce ownership checks or admin access.
    Automatically verifies ownership based on resource type and ID parameter.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            from flask_jwt_extended import get_jwt_identity
            from config.db import get_db
            
            caller_id = get_jwt_identity()
            if not caller_id:
                return jsonify({'message': 'Authentication required'}), 401
            
            # Extract resource ID from kwargs or request
            resource_id = kwargs.get(f'{resource_type}_id') or kwargs.get('id')
            if not resource_id:
                return jsonify({'message': 'Resource ID required'}), 400
            
            conn = get_db()
            try:
                with conn.cursor() as cursor:
                    if resource_type == 'payment':
                        has_access, is_admin, error = verify_payment_ownership(caller_id, resource_id, cursor)
                    elif resource_type == 'member':
                        has_access, is_admin, error = verify_member_ownership(caller_id, resource_id, cursor)
                    elif resource_type == 'compliance':
                        has_access, is_admin, error = verify_compliance_ownership(caller_id, resource_id, cursor)
                    else:
                        return jsonify({'message': 'Invalid resource type'}), 400
                    
                    if error:
                        return error
                    
                    # Add admin flag to request context for use in the route
                    from flask import g
                    g.is_admin = is_admin
                    
                    return f(*args, **kwargs)
            finally:
                conn.close()
                
        return decorated_function
    return decorator