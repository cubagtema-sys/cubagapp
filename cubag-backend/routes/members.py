from flask import Blueprint, jsonify, request, send_file
import logging
import io
import os
import math
import datetime
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from routes.admin import log_admin_action
from utils import admin_required, sub_admin_required, eval_good_standing
from config.cache import cache

# PDF Generation imports
try:
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib import colors
    from reportlab.lib.units import inch
    from reportlab.pdfgen import canvas
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    REPORTLAB_AVAILABLE = True
except ImportError:
    REPORTLAB_AVAILABLE = False

members_bp = Blueprint('members', __name__)
logger = logging.getLogger(__name__)

@members_bp.route('/', methods=['GET'])
@members_bp.route('', methods=['GET'])
@jwt_required()
def get_member_directory():
    """Member Networking Directory for authenticated users."""
    conn = get_db()
    try:
        from utils import eval_good_standing
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, email, phone, company, member_type,
                       COALESCE(primary_port, port_of_operation, 'Tema Port') as port_of_operation,
                       license_number, star_rating, compliance_score, role,
                       status, profile_photo, good_standing
                FROM members
                WHERE LOWER(COALESCE(status, '')) IN ('active', 'approved')
                  AND LOWER(COALESCE(role, '')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')
                ORDER BY name ASC
            """)
            raw_members = cursor.fetchall()
            for m in raw_members:
                is_good, audit_reasons = eval_good_standing(m, cursor)
                m['is_good_standing'] = is_good or (m.get('good_standing') is True)
        return jsonify(raw_members), 200
    except Exception as e:
        logger.error(f"Error fetching member directory: {e}")
        return jsonify({'message': 'Unable to fetch members'}), 500
    finally:
        conn.close()

@members_bp.route('/public/members', methods=['GET'])
def get_public_members():
    """Public Member Directory — strictly returns ONLY members in Good Standing."""
    conn = get_db()
    try:
        search = request.args.get('search', '').strip().lower()
        port = request.args.get('port', '').strip().lower()
        category = request.args.get('category', '').strip().lower()
        status_filter = request.args.get('status', '').strip().lower()

        # Public directory search strictly requires Good Standing & active status and excludes admins/staff
        query = """
            SELECT id, name, company, email, phone, member_type, role,
                   COALESCE(primary_port, port_of_operation, 'Tema Port') as primary_port,
                   COALESCE(membership_number, 'CUBAG-2026-00' || id) as membership_number,
                   star_rating, compliance_score, profile_photo,
                   location, digital_address,
                   COALESCE(good_standing, FALSE) as good_standing,
                   status
            FROM members 
            WHERE LOWER(COALESCE(status, '')) IN ('active', 'approved')
              AND LOWER(COALESCE(role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')
        """
        params = []

        if search:
            query += " AND (LOWER(name) LIKE %s OR LOWER(company) LIKE %s OR LOWER(COALESCE(membership_number, '')) LIKE %s)"
            params.extend([f"%{search}%", f"%{search}%", f"%{search}%"])
        if port and port != 'all':
            p_lower = port.lower()
            if 'tema' in p_lower:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%tema%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%tema%%')"
            elif 'takoradi' in p_lower or 'tkd' in p_lower:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%takoradi%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%takoradi%%')"
            elif any(k in p_lower for k in ('accra', 'kia', 'kotoka', 'airport')):
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%accra%%' OR LOWER(COALESCE(primary_port, '')) LIKE '%%kia%%' OR LOWER(COALESCE(primary_port, '')) LIKE '%%kotoka%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%accra%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%kia%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%kotoka%%')"
            elif 'aflao' in p_lower:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%aflao%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%aflao%%')"
            elif 'elubo' in p_lower:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%elubo%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%elubo%%')"
            elif 'paga' in p_lower:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE '%%paga%%' OR LOWER(COALESCE(port_of_operation, '')) LIKE '%%paga%%')"
            else:
                query += " AND (LOWER(COALESCE(primary_port, '')) LIKE %s OR LOWER(COALESCE(port_of_operation, '')) LIKE %s)"
                params.extend([f"%{port}%", f"%{port}%"])
        if category:
            query += " AND LOWER(member_type) = %s"
            params.append(category)
        if status_filter == 'not_good_standing':
            return jsonify([]), 200

        query += " ORDER BY company ASC, name ASC"

        from utils import eval_good_standing
        with conn.cursor() as cursor:
            cursor.execute(query, params)
            raw_members = cursor.fetchall()
            good_members = []
            for m in raw_members:
                is_good, audit_reasons = eval_good_standing(m, cursor)
                if is_good or m.get('good_standing') is True:
                    m['is_good_standing'] = True
                    m['status_label'] = 'Member in Good Standing'
                    good_members.append(m)
        return jsonify(good_members), 200
    except Exception as e:
        logger.exception("Error in public members directory: %s", e)
        return jsonify([]), 200
    finally:
        conn.close()

@members_bp.route('/public/ports', methods=['GET'])
def get_public_ports():
    """Returns active ports of operation for dropdowns."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, code 
                FROM ports_of_operation 
                WHERE is_active = TRUE 
                ORDER BY name ASC
            """)
            ports = cursor.fetchall()
        return jsonify(ports), 200
    except Exception as e:
        logger.warning("Falling back to default ports: %s", e)
        default_ports = [
            {'id': 3, 'name': 'Accra International Airport', 'code': 'ACC'},
            {'id': 4, 'name': 'Aflao Border Port', 'code': 'AFL'},
            {'id': 5, 'name': 'Elubo Border Port', 'code': 'ELB'},
            {'id': 6, 'name': 'Paga Border Port', 'code': 'PAG'},
            {'id': 2, 'name': 'Takoradi Port', 'code': 'TKD'},
            {'id': 1, 'name': 'Tema Port', 'code': 'TMP'},
        ]
        return jsonify(default_ports), 200
    finally:
        conn.close()

@members_bp.route('/public/verify-member', methods=['GET'])
def verify_member_public():
    """Public Member Verification — Non-disclosing dynamic evaluation of Good Standing."""
    query_str = request.args.get('query', '').strip()
    if not query_str:
        return jsonify({'verified': False, 'message': 'Please provide a membership number, license number, or company name.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, company, member_type,
                       COALESCE(membership_number, 'CUBAG-2026-00' || id) as membership_number,
                       COALESCE(license_number, 'LIC-CUBAG-2026-00' || id) as license_number,
                       COALESCE(primary_port, port_of_operation, 'Tema Port') as primary_port,
                       license_expiry_date, good_standing, status
                FROM members
                WHERE (LOWER(COALESCE(membership_number, '')) = LOWER(%s)
                   OR LOWER(COALESCE(license_number, '')) = LOWER(%s)
                   OR LOWER(company) = LOWER(%s)
                   OR LOWER(name) = LOWER(%s))
                  AND LOWER(status) IN ('active', 'approved')
                LIMIT 1
            """, (query_str, query_str, query_str, query_str))
            m = cursor.fetchone()

            if m:
                today_str = datetime.date.today().strftime('%d %b %Y')
                expiry = m.get('license_expiry_date')
                valid_until = expiry.strftime('%d %b %Y') if isinstance(expiry, (datetime.date, datetime.datetime)) else '31 Dec 2026'

                is_good, _ = eval_good_standing(dict(m), cursor)

                return jsonify({
                    'verified': True,
                    'member_id': m['id'],
                    'member_name': m.get('company') or m.get('name'),
                    'membership_number': m.get('membership_number') or f"CUBAG-2026-{m['id']:04d}",
                    'license_number': m.get('license_number') or f"LIC-CUBAG-2026-{m['id']:04d}",
                    'primary_port': m.get('primary_port') or 'Tema Port',
                    'good_standing': is_good,
                    'valid_until': valid_until,
                    'verified_at': today_str,
                }), 200

            return jsonify({
                'verified': False,
                'message': 'No verified CUBAG member found matching those credentials. Please check the membership or license number.',
            }), 200
    except Exception as e:
        logger.exception("Error in public member verification: %s", e)
        return jsonify({
            'verified': False,
            'message': 'Membership verification service temporarily unavailable.',
        }), 200
    finally:
        conn.close()

@members_bp.route('/public/fees', methods=['GET'])
def get_public_fee_schedules():
    """Serves the official CUBAG dynamic fee schedules."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT fee_type, key, name, scale, scope, amount, description FROM fee_schedules WHERE is_active = TRUE")
            schedules = cursor.fetchall()
        return jsonify({
            'effective_date': '2026-01-01',
            'currency': 'GHS',
            'fees': schedules
        }), 200
    except Exception as e:
        logger.exception("Error fetching public fees: %s", e)
        return jsonify({'message': 'Unable to fetch fee schedule'}), 500
    finally:
        conn.close()


@members_bp.route('/public/guest-service', methods=['POST'])
def submit_guest_service_request():
    """
    Public endpoint — no auth required.
    Accepts guest service requests from the landing page:
      - Customs clearance requests (cargo_clearance)
      - CTI course enrolment (cti_training)
    Stores a record in guest_service_requests and returns a unique reference number.
    """
    import uuid
    data = request.get_json(force=True) or {}

    service_type = (data.get('service_type') or '').strip()
    name         = (data.get('name') or '').strip()
    phone        = (data.get('phone') or '').strip()
    email        = (data.get('email') or '').strip().lower()
    company      = (data.get('company') or '').strip()
    primary_port = (data.get('primary_port') or '').strip()
    course_name  = (data.get('course_name') or '').strip()
    details      = (data.get('details') or '').strip()

    if not service_type:
        return jsonify({'message': 'service_type is required'}), 400
    if not name:
        return jsonify({'message': 'name is required'}), 400
    if not phone:
        return jsonify({'message': 'phone is required'}), 400

    # Generate unique reference number e.g. GSR-20260825-A3F9
    ref_suffix = uuid.uuid4().hex[:6].upper()
    today_str  = datetime.date.today().strftime('%Y%m%d')
    ref_no     = f"GSR-{today_str}-{ref_suffix}"

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO guest_service_requests
                    (reference_no, service_type, name, phone, email, company,
                     primary_port, course_name, details, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending')
                RETURNING id, reference_no, created_at
            """, (ref_no, service_type, name, phone, email, company,
                  primary_port, course_name or None, details or None))
            row = cursor.fetchone()
            conn.commit()

        return jsonify({
            'message': 'Request submitted successfully',
            'reference_number': row['reference_no'],
            'id': row['id'],
        }), 201
    except Exception as e:
        logger.exception("Error in guest-service submission: %s", e)
        return jsonify({'message': 'Failed to submit request. Please try again.'}), 500
    finally:
        conn.close()


@members_bp.route('/public/initiate-momo', methods=['POST', 'OPTIONS'])
def members_public_initiate_momo():
    """Compatibility endpoint: delegates to canonical implementation in payments module."""
    from routes.payments import public_initiate_momo
    return public_initiate_momo()


@members_bp.route('/public/confirm-momo/<string:reference>', methods=['POST', 'OPTIONS'])
def members_public_confirm_momo(reference):
    """Compatibility endpoint: delegates to canonical implementation in payments module."""
    from routes.payments import public_confirm_momo
    return public_confirm_momo(reference)


@members_bp.route('/certificate-request', methods=['POST'])
@jwt_required()
def request_hardcopy_certificate():
    """Submit a request for physical hardcopy CUBAG Membership License / Certificate delivery."""
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    cert_type = data.get('certificate_type', 'membership_license')
    address = data.get('delivery_address', '').strip()
    phone = data.get('contact_phone', '').strip()
    method = data.get('delivery_method', 'courier')
    fee = float(data.get('fee_amount', 150.00))

    if not address or not phone:
        return jsonify({'message': 'Delivery address and contact phone are required.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO hardcopy_certificate_requests 
                (member_id, certificate_type, fee_amount, delivery_method, delivery_address, contact_phone, payment_status, processing_status, collection_status)
                VALUES (%s, %s, %s, %s, %s, %s, 'unpaid', 'pending', 'pending')
                RETURNING id, request_date, processing_status
            """, (member_id, cert_type, fee, method, address, phone))
            req = cursor.fetchone()
            conn.commit()

        return jsonify({
            'message': 'Hardcopy certificate request submitted successfully!',
            'request_id': req['id'],
            'certificate_type': cert_type,
            'processing_status': req['processing_status'],
            'fee_amount': fee
        }), 201
    except Exception as e:
        logger.exception("Error submitting certificate request: %s", e)
        return jsonify({'message': 'Failed to submit certificate request'}), 500
    finally:
        conn.close()

@members_bp.route('/certificate-request', methods=['GET'])
@jwt_required()
def get_hardcopy_certificate_requests():
    """Fetch all hardcopy certificate requests for current member."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, member_id, certificate_type, request_date, fee_amount,
                       payment_status, processing_status, delivery_method, delivery_address,
                       contact_phone, collection_status, completed_at, created_at, updated_at
                FROM hardcopy_certificate_requests
                WHERE member_id = %s
                ORDER BY created_at DESC
            """, (member_id,))
            reqs = cursor.fetchall()
            for r in reqs:
                for k, v in list(r.items()):
                    if hasattr(v, 'isoformat'):
                        r[k] = v.isoformat()
        return jsonify(reqs), 200
    except Exception as e:
        logger.exception("Error fetching certificate requests: %s", e)
        return jsonify({'message': 'Failed to fetch certificate requests'}), 500
    finally:
        conn.close()

@members_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('members')
def get_all_members_admin():
    page = int(request.args.get('page', 1))
    limit = int(request.args.get('limit', 50))
    status_filter = request.args.get('status', 'all').lower()
    
    # 20-second per-query cache keyed by page+status+limit
    cache_key = f'admin_members_{status_filter}_p{page}_l{limit}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200

    conn = get_db()
    try:
        offset = (page - 1) * limit

        where_clause = ""
        if status_filter == 'pending':
            where_clause = "WHERE m.status = 'pending'"
        elif status_filter == 'active':
            where_clause = "WHERE m.status IN ('active', 'suspended')"

        with conn.cursor() as cursor:
            count_query = f"SELECT COUNT(*) as total FROM members m {where_clause}"
            cursor.execute(count_query)
            total = cursor.fetchone()['total']

            # Use a LATERAL join to efficiently fetch the latest renewal payment reference for each member
            cursor.execute(f"""
                SELECT m.id, m.name, m.email, m.phone, m.company, m.member_type,
                       m.port_of_operation, m.license_number, m.agency_code,
                       m.location, m.digital_address, m.tin, m.status, m.created_at,
                       COALESCE(m.payment_ref, p.payment_ref) as payment_ref,
                       m.fcm_token, m.license_expiry_date,
                       m.compliance_score, m.star_rating, m.manual_review_score
                FROM members m
                LEFT JOIN LATERAL (
                    SELECT payment_ref
                    FROM payments
                    WHERE member_id = m.id AND description ILIKE '%%License Renewal%%'
                    ORDER BY created_at DESC
                    LIMIT 1
                ) p ON TRUE
                {where_clause}
                ORDER BY m.created_at DESC
                LIMIT %s OFFSET %s
            """, (limit, offset))
            members = cursor.fetchall()

            result = []
            for m in members:
                d = dict(m)
                score = d.get('compliance_score') if d.get('compliance_score') is not None else 100
                stars = float(d.get('star_rating')) if d.get('star_rating') is not None else 5.0
                manual = d.get('manual_review_score') if d.get('manual_review_score') is not None else 10

                d['compliance_score'] = score
                d['star_rating'] = stars
                d['manual_review_score'] = manual
                d['breakdown'] = {
                    'standing': 40 if d.get('status') == 'active' else 0,
                    'financial': round(score * 0.3),
                    'documents': round(score * 0.3),
                    'trust': round(score * 0.15),
                    'events': round(score * 0.3),
                    'admin': round(score * 0.15),
                    'payment_score': round(score * 0.3),
                    'payment_punctual_score': round(score * 0.18),
                    'payment_history_score': round(score * 0.12),
                    'total_payments_paid': 1,
                    'overdue_payments_count': 0,
                    'on_time_payments_paid': 1,
                    'license_score': 40 if d.get('status') == 'active' else 0,
                    'task_score': round(score * 0.3),
                    'task_completion_score': round(score * 0.3),
                    'total_tasks': 11,
                    'completed_tasks': 11 if score >= 70 else 7,
                    'engagement_score': round(score * 0.15),
                    'survey_score': round(score * 0.15),
                    'total_surveys': 1,
                    'responded_surveys': 1,
                    'agm_score': round(score * 0.15),
                    'admin_score': round(score * 0.15)
                }

                for key, value in list(d.items()):
                    if hasattr(value, 'isoformat'):
                        d[key] = value.isoformat()
                    elif hasattr(value, 'strftime'):
                        d[key] = str(value)
                    elif value is None:
                        d[key] = None
                    elif not isinstance(value, (str, int, float, bool, list, dict)):
                        d[key] = str(value)
                result.append(d)

        response = {"data": result, "total": total, "page": page, "limit": limit}
        cache.set(cache_key, response, timeout=20)
        return jsonify(response), 200
    except Exception as e:
        logger.exception("[Admin Members Error] %s", e)
        return jsonify({'message': f"Server error fetching members: {str(e)}"}), 500
    finally:
        conn.close()

@members_bp.route('/renew', methods=['POST'])
@jwt_required()
def submit_renewal():
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    payment_ref = (data.get('payment_ref') or '').strip()

    if not payment_ref:
        return jsonify({'message': 'A valid payment reference is required to submit renewal'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # ── Active License Guard ──────────────────────────────────────────
            from datetime import date, timedelta
            cursor.execute(
                "SELECT status, license_expiry_date FROM members WHERE id = %s",
                (member_id,)
            )
            m = cursor.fetchone()
            if m and str(m['status']).lower() == 'active' and m.get('license_expiry_date'):
                expiry = m['license_expiry_date']
                if isinstance(expiry, str):
                    from datetime import datetime
                    expiry = datetime.strptime(expiry, '%Y-%m-%d').date()
                renewal_open_date = expiry - timedelta(days=30)
                if date.today() < renewal_open_date:
                    return jsonify({
                        'message': (
                            f'Your license is active until {expiry.strftime("%B %d, %Y")}. '
                            f'Renewal opens on {renewal_open_date.strftime("%B %d, %Y")}.'
                        ),
                        'license_expiry_date': str(expiry),
                        'renewal_opens': str(renewal_open_date),
                        'error_code': 'LICENSE_ACTIVE',
                    }), 200

            cursor.execute("UPDATE members SET status = 'pending', payment_ref = %s WHERE id = %s", (payment_ref, member_id))
            conn.commit()
        return jsonify({'message': 'Renewal submitted'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@members_bp.route('/license-history', methods=['GET'])
@jwt_required()
def get_license_history():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, email, company, license_number, member_type,
                       port_of_operation, status, payment_ref, created_at
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()
            if not member:
                return jsonify({'message': 'Member not found'}), 404

            # Auto-heal license number if active but has none/pending/none string
            status = str(member.get('status')).lower()
            lic_num = member.get('license_number')
            if status == 'active' and (not lic_num or str(lic_num).lower() in ('pending', 'none', 'n/a', '')):
                import datetime
                year = datetime.datetime.now().year
                new_license = f"CUBAG-LIC-{year}-{member_id:04d}"
                cursor.execute("UPDATE members SET license_number = %s WHERE id = %s", (new_license, member_id))
                conn.commit()
                # Update in local dict
                member = dict(member)
                member['license_number'] = new_license

        # Always build a history entry from the member's current record.
        # A record is considered "submitted" if payment_ref is set OR status is active/pending.
        history = []
        has_activity = (
            member.get('payment_ref') or
            str(member.get('status')).lower() in ('active', 'pending', 'suspended')
        )
        if has_activity:
            history.append({
                'id': member['id'],
                'payment_ref': member.get('payment_ref') or 'N/A',
                'status': member['status'],
                'license_number': member.get('license_number'),
                'member_type': member.get('member_type'),
                'company': member.get('company'),
                'name': member.get('name'),
                'email': member.get('email'),
                'port_of_operation': member.get('port_of_operation'),
                'submitted_at': str(member['created_at']) if member.get('created_at') else '',
                'approved': member['status'] == 'active',
            })

        return jsonify({'member': member, 'history': history}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@members_bp.route('/admin/status/<int:member_id>', methods=['PUT'])
@sub_admin_required('members')
def update_member_status(member_id):
    admin_id = get_jwt_identity()
    data = request.get_json()
    new_status = data.get('status')
    if not new_status:
        return jsonify({'message': 'Status is required'}), 400
        
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Get member name for audit log
            cursor.execute("SELECT name, license_number FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            member_name = member['name'] if member else f'Member #{member_id}'

            new_license = None
            norm_status = str(new_status).lower()
            if norm_status in ('active', 'approved'):
                # Approve all uploaded documents for this member as well so member sees app dashboard
                cursor.execute("""
                    UPDATE member_documents
                    SET status = 'approved', reviewed_at = NOW(), reviewed_by = %s
                    WHERE member_id = %s AND (status IS NULL OR status = 'pending')
                """, (admin_id, member_id))

                if member and (not member['license_number'] or str(member['license_number']).lower() in ('pending', 'none', 'null', '')):
                    import datetime
                    year = datetime.datetime.now().year
                    new_license = f"CUBAG-LIC-{year}-{member_id:04d}"
                    cursor.execute("UPDATE members SET status = 'active', license_number = %s WHERE id = %s", (new_license, member_id))
                else:
                    cursor.execute("UPDATE members SET status = 'active' WHERE id = %s", (member_id,))
            else:
                cursor.execute("UPDATE members SET status = %s WHERE id = %s", (new_status, member_id))
        conn.commit()
        cache.delete(f'me_{member_id}')

        try:
            from config.socket import socketio
            socketio.emit('member_updated', {'member_id': member_id, 'status': new_status})
            socketio.emit('fees_updated', {'member_id': member_id})
            socketio.emit('tasks_updated', {'member_id': member_id})
        except Exception as se:
            logger.debug("[Socket emit member_updated] %s", se)

        # Log admin action
        action_label = {'active': 'Activated', 'suspended': 'Suspended', 'inactive': 'Deactivated', 'pending': 'Set to Pending'}.get(new_status, f'Changed to {new_status}')
        log_admin_action(admin_id, f'{action_label} member', 'member', member_id, member_name, f'Status → {new_status}')
        
        response_data = {'message': f'Member {member_id} status updated to {new_status}'}
        if new_license:
            response_data['license_number'] = new_license
            
        return jsonify(response_data), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@members_bp.route('/admin/set-expiry/<int:member_id>', methods=['PUT'])
@sub_admin_required('members')
def set_license_expiry(member_id):
    """Admin: archive old license period then set new expiry date."""
    admin_id = get_jwt_identity()
    data          = request.get_json()
    expiry_date   = data.get('license_expiry_date')   # 'YYYY-MM-DD'
    duration_label = data.get('duration_label', '')   # e.g. '1 Year'
    start_date    = data.get('start_date', '')         # defaults to today server-side

    if not expiry_date:
        return jsonify({'message': 'license_expiry_date is required (YYYY-MM-DD)'}), 400

    from datetime import date
    today = date.today().isoformat()
    effective_start = start_date or today

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # ── 2. Read the current (outgoing) license period ─────────────────
            cursor.execute("""
                SELECT name, license_number, license_expiry_date
                FROM members WHERE id = %s
            """, (member_id,))
            current = cursor.fetchone()
            member_name = current['name'] if current else f'Member #{member_id}'

            # ── 3. Archive it only if there was a previous expiry set ─────────
            if current and current.get('license_expiry_date'):
                cursor.execute("""
                    INSERT INTO license_history
                        (member_id, license_number, start_date, expiry_date, duration_label)
                    SELECT %s, license_number,
                           COALESCE(
                               (SELECT MAX(expiry_date) FROM license_history WHERE member_id = %s),
                               created_at::date
                           ),
                           %s, 'Previous Period'
                    FROM members WHERE id = %s
                """, (member_id, member_id, str(current['license_expiry_date']), member_id))

            # ── 4. Set new expiry, update license number, and log the new period ──
            import datetime
            year = datetime.datetime.now().year
            new_license = f"CUBAG-LIC-{year}-{member_id:04d}"

            cursor.execute(
                "UPDATE members SET license_expiry_date = %s, license_number = %s WHERE id = %s",
                (expiry_date, new_license, member_id)
            )
            cursor.execute("""
                INSERT INTO license_history
                    (member_id, license_number, start_date, expiry_date, duration_label)
                SELECT %s, license_number, %s, %s, %s
                FROM members WHERE id = %s
            """, (member_id, effective_start, expiry_date, duration_label or 'Custom', member_id))

        conn.commit()

        # Audit log
        log_admin_action(admin_id, 'Updated license expiry', 'member', member_id, member_name, f'Expiry → {expiry_date} ({duration_label or "Custom"})')

        return jsonify({
            'message': 'License period updated and history archived.',
            'license_expiry_date': expiry_date,
            'start_date': effective_start
        }), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@members_bp.route('/admin/license-history/<int:member_id>', methods=['GET'])
@sub_admin_required('members')
def get_member_license_history(member_id):
    """Admin: fetch the full license period history for a member."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Return empty list gracefully if table doesn't exist yet
            try:
                cursor.execute("""
                    SELECT lh.id, lh.license_number, lh.start_date, lh.expiry_date,
                           lh.duration_label, lh.archived_at
                    FROM license_history lh
                    WHERE lh.member_id = %s
                    ORDER BY lh.archived_at DESC
                """, (member_id,))
                rows = cursor.fetchall()
                result = []
                for r in rows:
                    d = dict(r)
                    for field in ('start_date', 'expiry_date', 'archived_at'):
                        if d.get(field):
                            d[field] = str(d[field])
                    result.append(d)
                return jsonify(result), 200
            except Exception:
                conn.rollback()
                return jsonify([]), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@members_bp.route('/my-license-history', methods=['GET'])
@jwt_required()
def get_my_license_history():
    """Member: fetch their own license period history."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            try:
                cursor.execute("""
                    SELECT id, license_number, start_date, expiry_date,
                           duration_label, archived_at
                    FROM license_history
                    WHERE member_id = %s
                    ORDER BY archived_at DESC
                """, (member_id,))
                rows = cursor.fetchall()
                result = []
                for r in rows:
                    d = dict(r)
                    for field in ('start_date', 'expiry_date', 'archived_at'):
                        if d.get(field):
                            d[field] = str(d[field])
                    result.append(d)
                return jsonify(result), 200
            except Exception:
                conn.rollback()
                return jsonify([]), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@members_bp.route('/public-directory', methods=['GET'])
@jwt_required()  # Require login — phone/email are not exposed
def get_public_directory():
    conn = get_db()
    try:
        from utils import eval_good_standing
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, company as name, member_type as type,
                       port_of_operation as location, star_rating as rating,
                       status, good_standing
                FROM members WHERE LOWER(COALESCE(status, '')) IN ('active', 'approved') AND company IS NOT NULL
            """)
            raw_members = cursor.fetchall()
            good_members = []
            for m in raw_members:
                is_good, audit_reasons = eval_good_standing(m, cursor)
                if is_good or m.get('good_standing') is True:
                    good_members.append(m)
        return jsonify(good_members), 200
    except Exception as e:
        return jsonify({'message': 'Unable to fetch directory'}), 500
    finally:
        conn.close()


@members_bp.route('/<int:member_id>', methods=['GET'])
@jwt_required()
def get_member(member_id):
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Check caller's role
            cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
            caller = cursor.fetchone()
            is_admin = caller and caller.get('role') in ('admin', 'sub_admin', 'super_admin')
            is_owner = str(caller_id) == str(member_id)

            if is_owner or is_admin:
                # Full profile for self or admins
                cursor.execute("""
                    SELECT m.id, m.name, m.email, m.phone, m.company, m.member_type, m.port_of_operation,
                           m.status, m.compliance_score, m.star_rating, m.manual_review_score,
                           m.license_number, m.agency_code, m.location, m.digital_address, m.tin, m.profile_photo,
                           COALESCE(m.payment_ref, p.payment_ref) as payment_ref
                    FROM members m
                    LEFT JOIN LATERAL (
                        SELECT payment_ref
                        FROM payments
                        WHERE member_id = m.id AND payment_ref IS NOT NULL
                        ORDER BY id DESC
                        LIMIT 1
                    ) p ON TRUE
                    WHERE m.id = %s
                """, (member_id,))
            else:
                # Other members see only safe public fields — no PII
                cursor.execute("""
                    SELECT id, name, company, member_type, port_of_operation,
                           status, star_rating
                    FROM members WHERE id = %s AND LOWER(status) = 'active'
                """, (member_id,))

            member = cursor.fetchone()
            if not member:
                return jsonify({'message': 'Member not found'}), 404

            if is_owner or is_admin:
                # Auto-heal license number if active but has none/pending/none string
                status = str(member.get('status')).lower()
                lic_num = member.get('license_number')
                if status == 'active' and (not lic_num or str(lic_num).lower() in ('pending', 'none', 'n/a', '')):
                    import datetime
                    year = datetime.datetime.now().year
                    new_license = f"CUBAG-LIC-{year}-{member_id:04d}"
                    cursor.execute("UPDATE members SET license_number = %s WHERE id = %s", (new_license, member_id))
                    # Update local dict
                    result_member = dict(member)
                    result_member['license_number'] = new_license
                else:
                    result_member = dict(member)

                from utils import calculate_and_update_member_rating
                rating_data = calculate_and_update_member_rating(member_id, cursor)
                cursor.execute("""
                    SELECT compliance_score, star_rating, recorded_at
                    FROM member_rating_history WHERE member_id = %s
                    ORDER BY recorded_at DESC LIMIT 30
                """, (member_id,))
                history_rows = cursor.fetchall()
                history_rows.reverse()
                history = [
                    {'compliance_score': h['compliance_score'],
                     'star_rating': float(h['star_rating']),
                     'recorded_at': str(h['recorded_at'])}
                    for h in history_rows
                ]
                result = result_member
                result['compliance_score']    = rating_data['compliance_score']
                result['star_rating']          = rating_data['star_rating']
                result['manual_review_score']  = rating_data['manual_review_score']
                result['breakdown']            = rating_data.get('breakdown', {})
                result['rating_history']       = history
                
                # Commit the rating updates made by calculate_and_update_member_rating
                conn.commit()
                
                return jsonify(result), 200

            return jsonify(dict(member)), 200
    finally:
        conn.close()

@members_bp.route('/verify/<int:member_id>', methods=['GET'])
def verify_member_by_id_public(member_id):
    """Public Member Verification by ID — Non-disclosing Good Standing evaluation."""
    from utils import eval_good_standing
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, company, member_type, membership_number, license_number,
                       COALESCE(primary_port, port_of_operation, 'Tema') as primary_port,
                       license_expiry_date, good_standing, status
                FROM members WHERE id = %s AND LOWER(status) = 'active'
            """, (member_id,))
            m = cursor.fetchone()

            is_good, reasons = eval_good_standing(m, cursor) if m else (False, ["Not found"])

            if m and is_good:
                today_str = datetime.date.today().strftime('%d %b %Y')
                expiry = m.get('license_expiry_date')
                valid_until = expiry.strftime('%d %b %Y') if expiry else '31 Dec 2026'

                return jsonify({
                    'verified': True,
                    'member_name': m.get('company') or m.get('name'),
                    'membership_number': m.get('membership_number') or f'CUBAG-2026-{member_id:04d}',
                    'license_number': m.get('license_number') or f'LIC-CUBAG-2026-{member_id:04d}',
                    'primary_port': m.get('primary_port') or 'Tema',
                    'category': m.get('member_type') or 'Corporate',
                    'status': 'Verified Member',
                    'good_standing': True,
                    'valid_until': valid_until,
                    'last_verified_date': today_str,
                }), 200
            else:
                return jsonify({
                    'verified': False,
                    'message': 'Membership could not be verified. Please contact CUBAG for assistance.'
                }), 200
    except Exception as e:
        logger.exception("Error in public member verification by ID: %s", e)
        return jsonify({'verified': False, 'message': 'Membership could not be verified. Please contact CUBAG for assistance.'}), 200
    finally:
        conn.close()

@members_bp.route('/admin/set-review-score/<int:member_id>', methods=['PUT'])
@sub_admin_required('members')
def set_manual_review_score(member_id):
    admin_id = get_jwt_identity()
    data = request.get_json()
    score = data.get('manual_review_score')
    if score is None or not (0 <= int(score) <= 10):
        return jsonify({'message': 'manual_review_score must be between 0 and 10'}), 400
        
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Get member name for audit
            cursor.execute("SELECT name FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            member_name = member['name'] if member else f'Member #{member_id}'

            cursor.execute("UPDATE members SET manual_review_score = %s WHERE id = %s", (int(score), member_id))
            conn.commit()
            
            # Recalculate
            from utils import calculate_and_update_member_rating
            rating_data = calculate_and_update_member_rating(member_id, cursor)

        # Audit log
        log_admin_action(admin_id, 'Updated review score', 'member', member_id, member_name, f'Manual review score → {score}/10')
            
        return jsonify({
            'message': 'Manual review score updated successfully.',
            'compliance_score': rating_data['compliance_score'],
            'star_rating': rating_data['star_rating']
        }), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@members_bp.route('/<int:member_id>/certificate-pdf', methods=['GET'])
def generate_certificate_pdf(member_id):
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT name, company, license_number, member_type, port_of_operation, status, license_expiry_date
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()

        if not member:
            return jsonify({'message': 'Member not found'}), 404

        # Auto-heal license number if active but missing
        lic_num = member.get('license_number')
        if not lic_num or str(lic_num).lower() in ('pending', 'none', 'n/a', ''):
            import datetime
            year = datetime.datetime.now().year
            new_license = f"CUBAG-LIC-{year}-{member_id:04d}"
            with conn.cursor() as cursor:
                cursor.execute("UPDATE members SET license_number = %s WHERE id = %s", (new_license, member_id))
            conn.commit()
            member['license_number'] = new_license

        buffer = io.BytesIO()
        c = canvas.Canvas(buffer, pagesize=landscape(A4))
        width, height = landscape(A4)
        
        # 1. Background Paper Tint
        c.setFillColor(colors.HexColor("#faf9f6"))
        c.rect(0, 0, width, height, fill=1, stroke=0)
        
        # 2. Executive Multi-Layer Border
        margin = 0.4 * inch
        # Outer Orange Frame
        c.setStrokeColor(colors.HexColor("#FF5000"))
        c.setLineWidth(4)
        c.rect(margin, margin, width - 2*margin, height - 2*margin)
        
        # Inner Metallic Gold Line
        c.setStrokeColor(colors.HexColor("#d4af37"))
        c.setLineWidth(1.5)
        c.rect(margin + 6, margin + 6, width - 2*margin - 12, height - 2*margin - 12)

        # Thin Accent Navy Line
        c.setStrokeColor(colors.HexColor("#1e293b"))
        c.setLineWidth(0.5)
        c.rect(margin + 10, margin + 10, width - 2*margin - 20, height - 2*margin - 20)
        
        # Corner Flourish Accents
        for (cx, cy) in [
            (margin + 14, margin + 14),
            (width - margin - 14, margin + 14),
            (margin + 14, height - margin - 14),
            (width - margin - 14, height - margin - 14)
        ]:
            c.setStrokeColor(colors.HexColor("#d4af37"))
            c.setLineWidth(1.5)
            c.circle(cx, cy, 4, fill=0, stroke=1)
        
        # 3. Watermark Emblem
        c.saveState()
        c.translate(width/2.0, height/2.0)
        c.rotate(25)
        c.setFont("Helvetica-Bold", 130)
        c.setFillColor(colors.Color(0.83, 0.68, 0.21, alpha=0.035)) # Metallic Gold Faint
        c.drawCentredString(0, -35, "CUBAG")
        c.restoreState()
        
        # Draw Brand Logo Image at top center (absolute path, no mask for JPEG)
        logo_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'static', 'logo.jpeg'))
        if not os.path.exists(logo_path):
            # Fallback: look relative to cwd
            logo_path = os.path.abspath(os.path.join('static', 'logo.jpeg'))
        if os.path.exists(logo_path):
            logo_w = 52
            logo_h = 52
            c.drawImage(logo_path, width / 2.0 - logo_w / 2.0, height - 1.1 * inch, width=logo_w, height=logo_h)
        
        # 4. Header: Organization & Title — CUBAG in brand orange
        c.setFillColor(colors.HexColor("#FF5000"))
        c.setFont("Helvetica-Bold", 38)
        c.drawCentredString(width/2.0, height - 1.6 * inch, "CUBAG")
        
        c.setFillColor(colors.HexColor("#64748b"))
        c.setFont("Helvetica-Bold", 11)
        c.drawCentredString(width/2.0, height - 1.82 * inch, "CUSTOMS BROKERS ASSOCIATION OF GHANA")
        
        # Decorative Gold Line
        c.setStrokeColor(colors.HexColor("#d4af37"))
        c.setLineWidth(1)
        c.line(width/2.0 - 140, height - 1.98 * inch, width/2.0 + 140, height - 1.98 * inch)
        
        # Main Certificate Title
        c.setFillColor(colors.HexColor("#1e293b"))
        c.setFont("Helvetica-Bold", 24)
        c.drawCentredString(width/2.0, height - 2.45 * inch, "CERTIFICATE OF LICENSURE & STANDING")
        
        # 5. Body Text & Recipient Details
        c.setFont("Helvetica-Oblique", 13)
        c.setFillColor(colors.HexColor("#475569"))
        c.drawCentredString(width/2.0, height - 2.95 * inch, "This is to officially certify that")
        
        company_name = (member.get('company') or member.get('name') or 'Member Organization').strip()
        c.setFont("Helvetica-Bold", 24)
        c.setFillColor(colors.HexColor("#0f172a"))
        c.drawCentredString(width/2.0, height - 3.45 * inch, company_name)
        
        c.setFont("Helvetica-Oblique", 13)
        c.setFillColor(colors.HexColor("#64748b"))
        c.drawCentredString(width/2.0, height - 3.82 * inch, f"represented by  {member.get('name', '')}")
        
        c.setFont("Helvetica", 13)
        c.setFillColor(colors.HexColor("#1e293b"))
        c.drawCentredString(width/2.0, height - 4.38 * inch, f"is a duly registered, licensed, and active {member.get('member_type', 'Member')} of CUBAG")
        
        # Port & ID Container Box
        box_y = height - 5.0 * inch
        box_w = 480
        box_h = 30
        box_x = width/2.0 - box_w/2.0
        c.setFillColor(colors.HexColor("#f8fafc"))
        c.setStrokeColor(colors.HexColor("#e2e8f0"))
        c.setLineWidth(1)
        c.roundRect(box_x, box_y, box_w, box_h, 6, fill=1, stroke=1)
        
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(colors.HexColor("#334155"))
        port_txt = member.get('port_of_operation') or 'All Ports of Ghana'
        lic_num = member.get('license_number') or 'Pending'
        c.drawCentredString(width/2.0, box_y + 10, f"License No:  {lic_num}    |    Port of Operation:  {port_txt}")
        
        # 6. Validity Date Footer Line
        expiry = member.get('license_expiry_date')
        expiry_str = expiry.strftime("%d %B %Y") if expiry else "Active Standing"
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(colors.HexColor("#64748b"))
        c.drawCentredString(width/2.0, height - 5.4 * inch, f"Valid Until: {expiry_str}")
        
        # 7. Executive Signatures (Left & Right)
        sig_y = margin + 0.9 * inch
        
        # Left Signature (President)
        c.setFont("Times-BoldItalic", 19)
        c.setFillColor(colors.HexColor("#1e3a8a")) # Deep Royal Navy Blue Ink
        c.drawCentredString(margin + 2.2*inch, sig_y + 9, "Alhaji A. R. Busia")
        c.setStrokeColor(colors.HexColor("#475569"))
        c.setLineWidth(1)
        c.line(margin + 1.2*inch, sig_y, margin + 3.2*inch, sig_y)
        c.setFont("Helvetica-Bold", 9)
        c.setFillColor(colors.HexColor("#334155"))
        c.drawCentredString(margin + 2.2*inch, sig_y - 13, "President")
        c.setFont("Helvetica", 8)
        c.setFillColor(colors.HexColor("#94a3b8"))
        c.drawCentredString(margin + 2.2*inch, sig_y - 23, "CUBAG Executive Council")
        
        # Right Signature (Secretary General)
        c.setFont("Times-BoldItalic", 19)
        c.setFillColor(colors.HexColor("#1e3a8a"))
        c.drawCentredString(width - margin - 2.2*inch, sig_y + 9, "Kwame E. Mensah")
        c.setStrokeColor(colors.HexColor("#475569"))
        c.setLineWidth(1)
        c.line(width - margin - 3.2*inch, sig_y, width - margin - 1.2*inch, sig_y)
        c.setFont("Helvetica-Bold", 9)
        c.setFillColor(colors.HexColor("#334155"))
        c.drawCentredString(width - margin - 2.2*inch, sig_y - 13, "Secretary General")
        c.setFont("Helvetica", 8)
        c.setFillColor(colors.HexColor("#94a3b8"))
        c.drawCentredString(width - margin - 2.2*inch, sig_y - 23, "CUBAG Executive Secretariat")
        
        # 8. Premium Official Gold Seal (Centered at Bottom)
        seal_x = width/2.0
        seal_y = sig_y - 0.05 * inch
        
        # Starburst background
        c.setFillColor(colors.HexColor("#d4af37"))
        c.setStrokeColor(colors.HexColor("#b8860b"))
        c.setLineWidth(1)
        path = c.beginPath()
        points = 36
        radius_outer = 38
        radius_inner = 32
        for i in range(points * 2):
            angle = i * math.pi / points
            r = radius_outer if i % 2 == 0 else radius_inner
            x = seal_x + r * math.cos(angle)
            y = seal_y + r * math.sin(angle)
            if i == 0:
                path.moveTo(x, y)
            else:
                path.lineTo(x, y)
        path.close()
        c.drawPath(path, fill=1, stroke=1)
        
        # Inner Embossed Circles
        c.setFillColor(colors.HexColor("#b8860b"))
        c.circle(seal_x, seal_y, 28, fill=1, stroke=1)
        c.setFillColor(colors.HexColor("#d4af37"))
        c.circle(seal_x, seal_y, 25, fill=1, stroke=1)
        
        # Inner Ring Text
        c.setFillColor(colors.white)
        c.setFont("Helvetica-Bold", 8)
        c.drawCentredString(seal_x, seal_y + 4, "OFFICIAL")
        c.drawCentredString(seal_x, seal_y - 6, "SEAL")
        
        c.showPage()
        c.save()
        
        buffer.seek(0)
        filename = f"CUBAG_Certificate_{member_id}.pdf"
        return send_file(buffer, as_attachment=True, download_name=filename, mimetype='application/pdf')

    except Exception as e:
        logger.exception("PDF Generation failed: %s", e)
        return str(e), 500
    finally:
        conn.close()
