"""
GDPR Compliance Module - Implements data export, deletion, and privacy controls.
"""
import logging
import json
import io
import csv
from datetime import datetime
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class GDPRComplianceManager:
    """
    Manages GDPR compliance features including data export and deletion.
    """
    
    def __init__(self, db_connection):
        """
        Initialize the GDPR compliance manager.
        
        Args:
            db_connection: Database connection
        """
        self.db = db_connection
    
    def export_member_data(self, member_id: int) -> Dict[str, any]:
        """
        Export all data associated with a member for GDPR data portability.
        
        Args:
            member_id: Member ID
            
        Returns:
            Dict containing all member data
        """
        export_data = {
            'export_date': datetime.now().isoformat(),
            'member_id': member_id,
            'personal_data': {},
            'payment_data': [],
            'compliance_data': [],
            'activity_data': [],
            'communications': [],
            'support_data': []
        }
        
        try:
            with self.db.cursor() as cursor:
                # 1. Personal Data
                cursor.execute("""
                    SELECT id, name, email, phone, company, license_number, 
                           agency_code, port_of_operation, member_type, status,
                           created_at, license_expiry_date
                    FROM members WHERE id = %s
                """, (member_id,))
                member = cursor.fetchone()
                if member:
                    export_data['personal_data'] = dict(member)
                
                # 2. Payment Data
                cursor.execute("""
                    SELECT id, amount, description, status, payment_method,
                           payment_ref, created_at, paid_at
                    FROM payments WHERE member_id = %s
                    ORDER BY created_at DESC
                """, (member_id,))
                export_data['payment_data'] = [dict(row) for row in cursor.fetchall()]
                
                # 3. Compliance Applications
                cursor.execute("""
                    SELECT id, type, status, payment_amount, amount_paid,
                           created_at, updated_at
                    FROM compliance_applications WHERE member_id = %s
                    ORDER BY created_at DESC
                """, (member_id,))
                export_data['compliance_data'] = [dict(row) for row in cursor.fetchall()]
                
                # 4. Activity/Notifications
                cursor.execute("""
                    SELECT id, title, body, category, created_at
                    FROM notifications WHERE member_id = %s
                    ORDER BY created_at DESC LIMIT 100
                """, (member_id,))
                export_data['communications'] = [dict(row) for row in cursor.fetchall()]
                
                # 5. Support Tickets
                cursor.execute("""
                    SELECT id, subject, message, status, created_at
                    FROM support_tickets WHERE member_id = %s
                    ORDER BY created_at DESC
                """, (member_id,))
                export_data['support_data'] = [dict(row) for row in cursor.fetchall()]
                
            logger.info(f"Data export completed for member {member_id}")
            return export_data
            
        except Exception as e:
            logger.error(f"Error exporting data for member {member_id}: {e}")
            raise
    
    def export_member_data_as_json(self, member_id: int) -> str:
        """Export member data as JSON string."""
        data = self.export_member_data(member_id)
        return json.dumps(data, indent=2, default=str)
    
    def export_member_data_as_csv(self, member_id: int) -> str:
        """Export member data as CSV string."""
        data = self.export_member_data(member_id)
        
        output = io.StringIO()
        writer = csv.writer(output)
        
        # Write personal data
        writer.writerow(['PERSONAL DATA'])
        if data['personal_data']:
            writer.writerow(data['personal_data'].keys())
            writer.writerow(data['personal_data'].values())
        
        # Write payment data
        writer.writerow([])
        writer.writerow(['PAYMENT DATA'])
        if data['payment_data']:
            writer.writerow(data['payment_data'][0].keys())
            for payment in data['payment_data']:
                writer.writerow(payment.values())
        
        return output.getvalue()
    
    def request_member_data_deletion(self, member_id: int, requesting_admin_id: int) -> Tuple[bool, str]:
        """
        Request deletion of member data (GDPR right to be forgotten).
        This initiates a deletion request that requires admin approval.
        
        Args:
            member_id: Member ID to delete
            requesting_admin_id: Admin ID making the request
            
        Returns:
            Tuple of (success: bool, message: str)
        """
        try:
            with self.db.cursor() as cursor:
                # Check if member exists
                cursor.execute("SELECT id, name, email FROM members WHERE id = %s", (member_id,))
                member = cursor.fetchone()
                if not member:
                    return False, "Member not found"
                
                # Check if there are active obligations (unpaid payments, active compliance)
                cursor.execute("""
                    SELECT COUNT(*) as active_obligations
                    FROM payments 
                    WHERE member_id = %s AND status IN ('pending', 'processing')
                """, (member_id,))
                obligations = cursor.fetchone()['active_obligations']
                
                if obligations > 0:
                    return False, f"Cannot delete member with {obligations} active payment obligations"
                
                # Create deletion request record
                cursor.execute("""
                    INSERT INTO data_deletion_requests 
                    (member_id, requested_by, status, created_at)
                    VALUES (%s, %s, 'pending', NOW())
                    RETURNING id
                """, (member_id, requesting_admin_id))
                request_id = cursor.fetchone()['id']
                
                self.db.commit()
                logger.info(f"Data deletion request {request_id} created for member {member_id}")
                return True, f"Deletion request {request_id} created and pending approval"
                
        except Exception as e:
            logger.error(f"Error creating deletion request for member {member_id}: {e}")
            self.db.rollback()
            return False, str(e)
    
    def process_member_data_deletion(self, deletion_request_id: int, approving_admin_id: int) -> Tuple[bool, str]:
        """
        Process an approved data deletion request.
        This performs anonymization rather than complete deletion for audit purposes.
        
        Args:
            deletion_request_id: Deletion request ID
            approving_admin_id: Admin ID approving the deletion
            
        Returns:
            Tuple of (success: bool, message: str)
        """
        try:
            with self.db.cursor() as cursor:
                # Get deletion request details
                cursor.execute("""
                    SELECT id, member_id, status FROM data_deletion_requests 
                    WHERE id = %s AND status = 'pending'
                """, (deletion_request_id,))
                request = cursor.fetchone()
                if not request:
                    return False, "Deletion request not found or already processed"
                
                member_id = request['member_id']
                
                # Anonymize personal data
                anonymized_data = {
                    'name': f'Anonymous User {member_id}',
                    'email': f'anonymous{member_id}@deleted.local',
                    'phone': '0000000000',
                    'company': 'Anonymous Company',
                    'license_number': f'DELETED-{member_id}',
                    'agency_code': f'DELETED-{member_id}',
                }
                
                # Update member record with anonymized data
                cursor.execute("""
                    UPDATE members SET 
                        name = %s, email = %s, phone = %s, company = %s,
                        license_number = %s, agency_code = %s, status = 'deleted',
                        updated_at = NOW()
                    WHERE id = %s
                """, (
                    anonymized_data['name'], anonymized_data['email'], anonymized_data['phone'],
                    anonymized_data['company'], anonymized_data['license_number'], 
                    anonymized_data['agency_code'], member_id
                ))
                
                # Update deletion request status
                cursor.execute("""
                    UPDATE data_deletion_requests 
                    SET status = 'completed', approved_by = %s, completed_at = NOW()
                    WHERE id = %s
                """, (approving_admin_id, deletion_request_id))
                
                self.db.commit()
                logger.info(f"Data deletion completed for member {member_id} via request {deletion_request_id}")
                return True, f"Member data anonymized successfully for member {member_id}"
                
        except Exception as e:
            logger.error(f"Error processing deletion request {deletion_request_id}: {e}")
            self.db.rollback()
            return False, str(e)
    
    def get_data_deletion_requests(self, status: str = None) -> List[Dict]:
        """
        Get data deletion requests.
        
        Args:
            status: Filter by status (optional)
            
        Returns:
            List of deletion requests
        """
        try:
            with self.db.cursor() as cursor:
                query = """
                    SELECT dr.id, dr.member_id, m.name as member_name, m.email as member_email,
                           dr.requested_by, dr.status, dr.created_at, dr.approved_by, dr.completed_at
                    FROM data_deletion_requests dr
                    LEFT JOIN members m ON dr.member_id = m.id
                """
                params = []
                
                if status:
                    query += " WHERE dr.status = %s"
                    params.append(status)
                
                query += " ORDER BY dr.created_at DESC"
                
                cursor.execute(query, params)
                return [dict(row) for row in cursor.fetchall()]
                
        except Exception as e:
            logger.error(f"Error getting deletion requests: {e}")
            return []


