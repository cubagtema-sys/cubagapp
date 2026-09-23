"""
GDPR Compliance Routes - API endpoints for data export, deletion, and privacy controls.
"""
import logging
from flask import Blueprint, jsonify, request, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import admin_required
from config.gdpr_compliance import GDPRComplianceManager
from config.audit_logging import get_data_access_logger

gdpr_bp = Blueprint('gdpr', __name__)
logger = logging.getLogger(__name__)


@gdpr_bp.route('/export/my-data', methods=['GET'])
@jwt_required()
def export_my_data():
    """Export current member's data (GDPR data portability)."""
    member_id = get_jwt_identity()
    if not member_id:
        return jsonify({'message': 'Authentication required'}), 401
    
    conn = get_db()
    try:
        gdpr_manager = GDPRComplianceManager(conn)
        audit_logger = get_data_access_logger(conn)
        
        # Get export format preference
        export_format = request.args.get('format', 'json').lower()
        
        # Export data
        exported_data = gdpr_manager.export_member_data(member_id)
        
        # Log the data export
        record_count = (
            len(exported_data.get('payment_data', [])) +
            len(exported_data.get('compliance_data', [])) +
            len(exported_data.get('communications', [])) +
            len(exported_data.get('support_data', []))
        )
        audit_logger.log_data_export(member_id, f"self_export_{export_format}", record_count)
        
        if export_format == 'json':
            data = gdpr_manager.export_member_data_as_json(member_id)
            return jsonify({
                'data': data,
                'format': 'json',
                'exported_at': exported_data['export_date']
            }), 200
        
        elif export_format == 'csv':
            csv_data = gdpr_manager.export_member_data_as_csv(member_id)
            return jsonify({
                'data': csv_data,
                'format': 'csv',
                'exported_at': exported_data['export_date']
            }), 200
        
        else:
            return jsonify({'message': 'Invalid format. Use json or csv'}), 400
            
    except Exception as e:
        logger.error(f"Error exporting data for member {member_id}: {e}")
        return jsonify({'message': 'Error exporting data'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/export/member/<int:member_id>', methods=['GET'])
@admin_required
def export_member_data_admin(member_id):
    """Admin endpoint to export any member's data."""
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        gdpr_manager = GDPRComplianceManager(conn)
        audit_logger = get_data_access_logger(conn)
        
        # Get export format preference
        export_format = request.args.get('format', 'json').lower()
        
        # Export data
        exported_data = gdpr_manager.export_member_data(member_id)
        
        # Log the admin data access
        record_count = (
            len(exported_data.get('payment_data', [])) +
            len(exported_data.get('compliance_data', [])) +
            len(exported_data.get('communications', [])) +
            len(exported_data.get('support_data', []))
        )
        audit_logger.log_admin_data_access(admin_id, 'data_export', 'member', member_id)
        audit_logger.log_data_export(admin_id, f"admin_export_member_{export_format}", record_count)
        
        if export_format == 'json':
            data = gdpr_manager.export_member_data_as_json(member_id)
            return jsonify({
                'data': data,
                'format': 'json',
                'exported_at': exported_data['export_date']
            }), 200
        
        elif export_format == 'csv':
            csv_data = gdpr_manager.export_member_data_as_csv(member_id)
            return jsonify({
                'data': csv_data,
                'format': 'csv',
                'exported_at': exported_data['export_date']
            }), 200
        
        else:
            return jsonify({'message': 'Invalid format. Use json or csv'}), 400
            
    except Exception as e:
        logger.error(f"Error exporting data for member {member_id} by admin {admin_id}: {e}")
        return jsonify({'message': 'Error exporting data'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/deletion/request', methods=['POST'])
@admin_required
def request_data_deletion():
    """Request deletion of member data (admin only)."""
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    member_id = data.get('member_id')
    
    if not member_id:
        return jsonify({'message': 'member_id is required'}), 400
    
    conn = get_db()
    try:
        gdpr_manager = GDPRComplianceManager(conn)
        success, message = gdpr_manager.request_member_data_deletion(member_id, admin_id)
        
        if success:
            return jsonify({'message': message}), 200
        else:
            return jsonify({'message': message}), 400
            
    except Exception as e:
        logger.error(f"Error requesting deletion for member {member_id}: {e}")
        return jsonify({'message': 'Error requesting deletion'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/deletion/approve/<int:request_id>', methods=['POST'])
@admin_required
def approve_data_deletion(request_id):
    """Approve and process a data deletion request (admin only)."""
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        gdpr_manager = GDPRComplianceManager(conn)
        success, message = gdpr_manager.process_member_data_deletion(request_id, admin_id)
        
        if success:
            return jsonify({'message': message}), 200
        else:
            return jsonify({'message': message}), 400
            
    except Exception as e:
        logger.error(f"Error processing deletion request {request_id}: {e}")
        return jsonify({'message': 'Error processing deletion'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/deletion/requests', methods=['GET'])
@admin_required
def get_deletion_requests():
    """Get all data deletion requests (admin only)."""
    admin_id = get_jwt_identity()
    status_filter = request.args.get('status')
    
    conn = get_db()
    try:
        gdpr_manager = GDPRComplianceManager(conn)
        requests = gdpr_manager.get_data_deletion_requests(status_filter)
        
        return jsonify({'requests': requests}), 200
            
    except Exception as e:
        logger.error(f"Error getting deletion requests: {e}")
        return jsonify({'message': 'Error getting deletion requests'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/privacy/settings', methods=['GET'])
@jwt_required()
def get_privacy_settings():
    """Get current member's privacy settings."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, email, phone, company, license_number,
                       data_sharing_consent, marketing_consent
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()
            
            if not member:
                return jsonify({'message': 'Member not found'}), 404
            
            privacy_settings = {
                'data_sharing_consent': member.get('data_sharing_consent', True),
                'marketing_consent': member.get('marketing_consent', False),
                'profile_visibility': 'public' if member.get('status') == 'active' else 'private'
            }
            
            return jsonify(privacy_settings), 200
            
    except Exception as e:
        logger.error(f"Error getting privacy settings for member {member_id}: {e}")
        return jsonify({'message': 'Error getting privacy settings'}), 500
    finally:
        conn.close()


@gdpr_bp.route('/privacy/settings', methods=['PUT'])
@jwt_required()
def update_privacy_settings():
    """Update current member's privacy settings."""
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Build update query dynamically based on provided fields
            update_fields = []
            params = []
            
            if 'data_sharing_consent' in data:
                update_fields.append("data_sharing_consent = %s")
                params.append(data['data_sharing_consent'])
            
            if 'marketing_consent' in data:
                update_fields.append("marketing_consent = %s")
                params.append(data['marketing_consent'])
            
            if not update_fields:
                return jsonify({'message': 'No valid fields to update'}), 400
            
            params.append(member_id)
            
            query = f"UPDATE members SET {', '.join(update_fields)} WHERE id = %s"
            cursor.execute(query, params)
            conn.commit()
            
            return jsonify({'message': 'Privacy settings updated successfully'}), 200
            
    except Exception as e:
        logger.error(f"Error updating privacy settings for member {member_id}: {e}")
        conn.rollback()
        return jsonify({'message': 'Error updating privacy settings'}), 500
    finally:
        conn.close()