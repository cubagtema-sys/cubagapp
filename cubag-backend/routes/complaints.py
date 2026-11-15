import os
import logging
import random
import string
import secrets
from datetime import datetime
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import resend
from flask import Blueprint, jsonify, request
from config.db import get_db
from flask_jwt_extended import jwt_required, get_jwt
from config.rate_limit import rate_limit
from utils import sub_admin_required, log_admin_action

logger = logging.getLogger(__name__)

complaints_bp = Blueprint('complaints', __name__)

resend.api_key = os.getenv('RESEND_API_KEY')


def _send_complaint_confirmation_email(to_email, name, comp_id, subject, category, port, target_entity=None, description=""):
    """Confirmation to the person who made a complaint: their tracking ID and
    how to follow it, in the CUBAG email design."""
    if not to_email:
        return False
    import html as _h
    from datetime import datetime as _dt
    from config.email_template import FONT, INK, LINE, MUTED, _base_url, branded, button, code_box, paragraph
    from routes.auth import _send_email
    first = _h.escape((name or 'there').split()[0])
    when = _dt.now().strftime('%d %B %Y').lstrip('0')
    rows = [('Subject', subject), ('Category', category), ('Port', port), ('Against', target_entity), ('Received', when)]
    table = ''.join(
        f'<tr><td style="padding:9px 0;border-bottom:1px solid {LINE};font-family:{FONT};font-size:14px;color:{MUTED};">{k}</td>'
        f'<td style="padding:9px 0;border-bottom:1px solid {LINE};font-family:{FONT};font-size:14px;color:{INK};text-align:right;">{_h.escape(str(v))}</td></tr>'
        for k, v in rows if v)
    inner = (
        paragraph(f'Hello {first},')
        + paragraph('We have received your complaint. Keep this tracking ID to follow it:')
        + code_box(comp_id)
        + f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px;">{table}</table>'
        + button('Track your complaint', f"{_base_url()}/#/track-complaint")
        + paragraph('Enter your tracking ID on that page to see its progress.', muted=True, small=True)
        + paragraph('The Secretariat\'s complaints committee will look into it and update the status.', muted=True, small=True)
    )
    text = (f"Hello {first},\n\nWe have received your complaint. Your tracking ID is {comp_id}.\n\n"
            f"Subject: {subject}\nCategory: {category}\nPort: {port}\nReceived: {when}\n\n"
            f"To see its progress, go to {_base_url()}/#/track-complaint and enter the tracking ID.")
    return _send_email(to_email, f'Complaint received: {comp_id}', text,
                       branded(inner, subject='Complaint received', preheader=f'Tracking ID {comp_id}'))


def _generate_complaint_id():
    """Generates a clean tracking ID like CMP-2026-83941"""
    digits = ''.join(random.choices(string.digits, k=5))
    year = datetime.utcnow().year
    return f"CMP-{year}-{digits}"


@complaints_bp.route('/submit', methods=['POST'])
@rate_limit('complaint_submit', max_requests=5, window_seconds=3600)
def submit_complaint():
    """
    Public endpoint for filing a trade / customs / broker grievance or complaint.
    Returns a unique tracking ID and a 128-bit cryptographic tracking secret.
    Enforces honeypot spam protection.
    """
    data = request.get_json(silent=True) or {}
    
    # Honeypot Anti-Spam Check: bots fill hidden decoy fields
    honeypot = data.get('hp_field') or data.get('website') or data.get('fax_number')
    if honeypot:
        logger.warning("[SPAM] Blocked automated bot complaint submission targeting honeypot: %s", honeypot)
        # Return fake 201 to prevent automated bots from adapting
        return jsonify({
            'success': True,
            'message': 'Complaint lodged successfully. Keep your tracking token secure to monitor grievance status.',
            'complaint_id': 'CMP-2026-99999',
            'tracking_token': '00000000000000000000000000000000'
        }), 201

    name = (data.get('name') or '').strip()
    email = (data.get('email') or '').strip().lower()
    phone = (data.get('phone') or '').strip()
    category = (data.get('category') or 'General Grievance').strip()
    port = (data.get('port') or 'Tema Port').strip()
    target_entity = (data.get('target_entity') or data.get('targetEntity') or '').strip()
    subject = (data.get('subject') or '').strip()
    description = (data.get('description') or '').strip()

    if not name or not email or not phone or not subject or not description:
        return jsonify({'success': False, 'message': 'Please fill in all required fields (Name, Email, Phone, Subject, and Description).'}), 400

    tracking_secret = secrets.token_hex(16)  # 128-bit cryptographically secure tracking secret

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Generate unique ID
            for _ in range(5):
                comp_id = _generate_complaint_id()
                cursor.execute("SELECT 1 FROM complaints WHERE complaint_id = %s", (comp_id,))
                if not cursor.fetchone():
                    break

            cursor.execute("""
                INSERT INTO complaints (
                    complaint_id, name, email, phone, category, port, target_entity, subject, description, status, assigned_to, tracking_secret, created_at, updated_at
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Received', 'Secretariat Grievance Committee', %s, NOW(), NOW()
                ) RETURNING complaint_id, category, port, status, created_at
            """, (comp_id, name, email, phone, category, port, target_entity, subject, description, tracking_secret))
            row = cursor.fetchone()
            conn.commit()

        # Send confirmation email in a non-blocking try-except
        try:
            _send_complaint_confirmation_email(
                to_email=email,
                name=name,
                comp_id=comp_id,
                subject=subject,
                category=category,
                port=port,
                target_entity=target_entity,
                description=description
            )
        except Exception as em_err:
            logger.warning(f"Failed to dispatch complaint confirmation email: {em_err}")

        created_dt = row.get('created_at') if row else datetime.utcnow()
        created_str = created_dt.isoformat() if hasattr(created_dt, 'isoformat') and created_dt else datetime.utcnow().isoformat()

        res_payload = jsonify({
            'success': True,
            'message': 'Complaint lodged successfully. Keep your tracking token secure; both complaint_id and tracking_token are required to view grievance status.',
            'complaint_id': comp_id,
            'tracking_token': tracking_secret,
            'data': {
                'complaint_id': comp_id,
                'category': category,
                'port': port,
                'status': 'Received',
                'created_at': created_str,
            }
        })
        try:
            from socket_instance import socketio
            socketio.emit('complaints_updated', {'complaint_id': comp_id})
            socketio.emit('tasks_updated', {})
        except Exception:
            pass
        return res_payload, 201
    except Exception as e:
        conn.rollback()
        logger.exception("Error submitting complaint: %s", e)
        return jsonify({'success': False, 'message': 'Failed to submit complaint. Please try again.'}), 500
    finally:
        conn.close()

@complaints_bp.route('/track/<complaint_id>', methods=['GET'])
@rate_limit('complaint_track', max_requests=20, window_seconds=60)
def track_complaint(complaint_id):
    """
    Public tracking endpoint. Requires the 128-bit tracking secret to prevent enumeration
    and information leakage. Never returns private complainant or party details.
    """
    cid = (complaint_id or '').strip().upper()
    if not cid:
        return jsonify({'success': False, 'message': 'Complaint ID is required.'}), 400

    token = (request.args.get('token') or request.args.get('tracking_token') or request.headers.get('X-Tracking-Token') or '').strip()
    if not token:
        return jsonify({
            'success': False,
            'message': 'Tracking secret token is required. Please supply ?token=<secret> or header X-Tracking-Token.'
        }), 401

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    complaint_id, category, port, status, resolution_notes, 
                    created_at, updated_at
                FROM complaints 
                WHERE UPPER(complaint_id) = %s AND tracking_secret = %s
            """, (cid, token))
            comp = cursor.fetchone()

        if not comp:
            return jsonify({
                'success': False, 
                'message': 'No grievance found matching this complaint ticket and tracking token.'
            }), 404

        # Build tracking timeline based on current status
        status = comp.get('status') or 'Received'
        created_at_dt = comp.get('created_at')
        updated_at_dt = comp.get('updated_at') or created_at_dt

        created_str = created_at_dt.strftime('%d %b %Y, %I:%M %p') if hasattr(created_at_dt, 'strftime') and created_at_dt else 'Recent'
        updated_str = updated_at_dt.strftime('%d %b %Y') if hasattr(updated_at_dt, 'strftime') and updated_at_dt else 'In Progress'

        timeline = [
            {
                'step': 1,
                'title': 'Complaint Lodged',
                'desc': 'Formal grievance logged into CUBAG Central Secretariat Registry.',
                'done': True,
                'active': status == 'Received',
                'date': created_str
            },
            {
                'step': 2,
                'title': 'Secretariat Review',
                'desc': 'Assigned to the Grievance & Disciplinary Standing Committee for preliminary merit assessment.',
                'done': status in ('Under Review', 'Investigating', 'Resolved', 'Closed'),
                'active': status == 'Under Review',
                'date': updated_str if status in ('Under Review', 'Investigating', 'Resolved', 'Closed') else 'Pending'
            },
            {
                'step': 3,
                'title': 'Port & Stakeholder Investigation',
                'desc': f"Evidence verification and stakeholder engagement at {comp.get('port') or 'Port'}.",
                'done': status in ('Investigating', 'Resolved', 'Closed'),
                'active': status == 'Investigating',
                'date': updated_str if status in ('Investigating', 'Resolved', 'Closed') else 'Pending'
            },
            {
                'step': 4,
                'title': 'Resolution & Official Action',
                'desc': comp.get('resolution_notes') or 'Formal resolution notice issued by CUBAG Executive Committee.',
                'done': status in ('Resolved', 'Closed'),
                'active': status in ('Resolved', 'Closed'),
                'date': updated_str if status in ('Resolved', 'Closed') else 'Pending'
            }
        ]

        return jsonify({
            'success': True,
            'data': {
                'complaint_id': comp.get('complaint_id'),
                'category': comp.get('category'),
                'port': comp.get('port'),
                'status': comp.get('status'),
                'created_at': created_at_dt.isoformat() if hasattr(created_at_dt, 'isoformat') and created_at_dt else None,
                'updated_at': updated_at_dt.isoformat() if hasattr(updated_at_dt, 'isoformat') and updated_at_dt else None,
                'timeline': timeline
            }
        }), 200
    except Exception as e:
        logger.exception("Error tracking complaint: %s", e)
        return jsonify({'success': False, 'message': 'Internal error retrieving complaint.'}), 500
    finally:
        conn.close()

@complaints_bp.route('', methods=['GET'])
@complaints_bp.route('/', methods=['GET'])
@sub_admin_required('complaints')  # SEC-01: admin-only (was any logged-in member)
def list_complaints():
    """
    List complaints for admin or management review.
    Supports ?status=, ?port=, ?category=, and ?search=
    """
    status = request.args.get('status', '').strip()
    port = request.args.get('port', '').strip()
    category = request.args.get('category', '').strip()
    search = request.args.get('search', '').strip()

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            query = """
                SELECT id, complaint_id, name, email, phone, category, port, 
                       target_entity, subject, description, status, resolution_notes, 
                       assigned_to, priority, created_at, updated_at
                FROM complaints
                WHERE 1=1
            """
            params = []
            if status and status.lower() != 'all':
                query += " AND LOWER(status) = LOWER(%s)"
                params.append(status)
            if port and port.lower() != 'all':
                query += " AND LOWER(port) = LOWER(%s)"
                params.append(port)
            if category and category.lower() != 'all':
                query += " AND LOWER(category) = LOWER(%s)"
                params.append(category)
            if search:
                query += " AND (LOWER(complaint_id) LIKE LOWER(%s) OR LOWER(name) LIKE LOWER(%s) OR LOWER(subject) LIKE LOWER(%s) OR LOWER(phone) LIKE LOWER(%s) OR LOWER(email) LIKE LOWER(%s))"
                params.extend([f'%{search}%', f'%{search}%', f'%{search}%', f'%{search}%', f'%{search}%'])

            query += " ORDER BY created_at DESC LIMIT 100"
            cursor.execute(query, tuple(params))
            rows = cursor.fetchall()

        def _serialize(row):
            d = dict(row)
            for k, v in d.items():
                if hasattr(v, 'isoformat'):
                    d[k] = v.isoformat()
            return d

        complaints = [_serialize(r) for r in rows]
        return jsonify({'success': True, 'data': complaints}), 200
    except Exception as e:
        logger.exception("Error listing complaints: %s", e)
        return jsonify({'success': False, 'message': 'Failed to fetch complaints.'}), 500
    finally:
        conn.close()

@complaints_bp.route('/<complaint_id>/status', methods=['PUT'])
@sub_admin_required('complaints')  # SEC-02: admin-only (was any logged-in member)
def update_complaint_status(complaint_id):
    """
    Updates the status, resolution notes, and handler of a complaint.
    """
    data = request.get_json(silent=True) or {}
    new_status = data.get('status')
    resolution_notes = data.get('resolution_notes')
    assigned_to = data.get('assigned_to')
    priority = data.get('priority')

    if not new_status:
        return jsonify({'success': False, 'message': 'Status is required.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE complaints
                SET status = %s,
                    resolution_notes = COALESCE(%s, resolution_notes),
                    assigned_to = COALESCE(%s, assigned_to),
                    priority = COALESCE(%s, priority),
                    updated_at = CURRENT_TIMESTAMP
                WHERE UPPER(complaint_id) = %s
                RETURNING complaint_id, status, resolution_notes, updated_at
            """, (new_status, resolution_notes, assigned_to, priority, complaint_id.strip().upper()))
            updated = cursor.fetchone()
            conn.commit()

        if not updated:
            return jsonify({'success': False, 'message': 'Complaint not found.'}), 404

        d = dict(updated)
        for k, v in d.items():
            if hasattr(v, 'isoformat'):
                d[k] = v.isoformat()
        try:
            from flask_jwt_extended import get_jwt_identity
            log_admin_action(get_jwt_identity(), 'Updated complaint status', 'complaint', None,
                             d.get('complaint_id'), f"Status: {new_status}")
        except Exception:
            logger.debug('complaint audit log failed', exc_info=True)
        try:
            from socket_instance import socketio
            socketio.emit('complaints_updated', {'complaint_id': complaint_id, 'status': new_status})
            socketio.emit('tasks_updated', {})
        except Exception:
            pass
        return jsonify({'success': True, 'message': 'Complaint status updated.', 'data': d}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error updating complaint: %s", e)
        return jsonify({'success': False, 'message': 'Failed to update complaint.'}), 500
    finally:
        conn.close()
