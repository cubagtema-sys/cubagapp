import os
import logging
import random
import string
from datetime import datetime
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import resend
from flask import Blueprint, jsonify, request
from config.db import get_db
from flask_jwt_extended import jwt_required, get_jwt

logger = logging.getLogger(__name__)

complaints_bp = Blueprint('complaints', __name__)

resend.api_key = os.getenv('RESEND_API_KEY')


def _send_complaint_confirmation_email(to_email, name, comp_id, subject, category, port, target_entity=None, description=""):
    """
    Sends an executive confirmation email to the complainant with their tracking ID,
    complaint summary, and tracking instructions.
    """
    if not to_email:
        return False

    sender_email = os.getenv('SMTP_USER', 'support@winningedgeinvestment.com')
    sender_name = os.getenv('SMTP_SENDER_NAME', 'CUBAG Secretariat')
    email_subject = f"[CUBAG Grievance Registry] Complaint Received — Tracking ID: {comp_id}"
    now_str = datetime.utcnow().strftime("%B %d, %Y at %I:%M UTC")

    target_entity_html = ""
    if target_entity:
        target_entity_html = f"""
        <tr>
          <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Party / Entity Involved</td>
          <td style="padding:10px 14px;color:#0F172A;font-size:13.5px;font-weight:700;border-bottom:1px solid #E2E8F0;">{target_entity}</td>
        </tr>
        """

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>CUBAG Grievance & Complaint Confirmation</title>
    </head>
    <body style="margin:0;padding:0;background-color:#F1F5F9;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#F1F5F9;padding:30px 15px;">
        <tr>
          <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.06);border:1px solid #E2E8F0;">
              
              <!-- TOP EXECUTIVE HEADER -->
              <tr>
                <td style="background:linear-gradient(135deg, #1E110B 0%, #381E13 100%);padding:28px 32px;text-align:left;border-bottom:3px solid #FF5000;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td>
                        <div style="display:inline-block;background:#FF5000;color:#ffffff;font-size:11px;font-weight:900;letter-spacing:1px;padding:4px 10px;border-radius:6px;margin-bottom:8px;">CUBAG SECRETARIAT</div>
                        <h1 style="margin:0;color:#ffffff;font-size:18px;font-weight:800;letter-spacing:0.3px;">CUSTOMS BROKERS ASSOCIATION OF GHANA</h1>
                        <p style="margin:4px 0 0 0;color:#E2E8F0;font-size:12px;opacity:0.85;">Grievance & Disciplinary Standing Committee</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- BODY CONTAINER -->
              <tr>
                <td style="padding:32px 32px 24px 32px;">
                  
                  <!-- STATUS BADGE -->
                  <div style="background:#FFF7ED;border:1px solid #FFD8A8;border-radius:10px;padding:12px 16px;margin-bottom:24px;">
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="24" valign="middle" style="color:#FF5000;font-size:16px;font-weight:bold;">📋</td>
                        <td style="color:#9A3412;font-size:13.5px;font-weight:700;padding-left:8px;">Grievance Logged & Under Secretariat Review</td>
                      </tr>
                    </table>
                  </div>

                  <p style="margin:0 0 16px 0;color:#1E293B;font-size:15px;line-height:1.5;">
                    Dear <strong>{name}</strong>,
                  </p>
                  <p style="margin:0 0 20px 0;color:#475569;font-size:13.5px;line-height:1.6;">
                    Your complaint has been formally registered into the central records of the Customs Brokers Association of Ghana (CUBAG). The Secretariat Grievance Committee has been notified and will conduct a merit review.
                  </p>

                  <!-- TRACKING ID HIGHLIGHT BOX -->
                  <div style="background:linear-gradient(135deg, #FFF8F2 0%, #FFF1E6 100%);border:2px dashed #FF5000;border-radius:14px;padding:20px;text-align:center;margin-bottom:26px;">
                    <div style="color:#C2410C;font-size:11px;font-weight:800;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">Official Complaint Tracking ID</div>
                    <div style="color:#1E110B;font-size:24px;font-weight:900;letter-spacing:1.5px;font-family:monospace;">{comp_id}</div>
                    <div style="color:#78350F;font-size:12px;margin-top:6px;">Please save this reference number for all follow-ups and status checks.</div>
                  </div>

                  <!-- COMPLAINT SUMMARY TABLE -->
                  <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #E2E8F0;border-radius:12px;overflow:hidden;margin-bottom:24px;border-collapse:collapse;">
                    <tr style="background:#F8FAFC;">
                      <th colspan="2" style="padding:12px 14px;text-align:left;color:#0F172A;font-size:13px;font-weight:800;border-bottom:1px solid #E2E8F0;">
                        COMPLAINT PARTICULARS
                      </th>
                    </tr>
                    <tr>
                      <td width="38%" style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Subject / Title</td>
                      <td style="padding:10px 14px;color:#0F172A;font-size:13.5px;font-weight:700;border-bottom:1px solid #E2E8F0;">{subject}</td>
                    </tr>
                    <tr>
                      <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Category</td>
                      <td style="padding:10px 14px;color:#0F172A;font-size:13.5px;border-bottom:1px solid #E2E8F0;">{category}</td>
                    </tr>
                    <tr>
                      <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Port / Operation Station</td>
                      <td style="padding:10px 14px;color:#0F172A;font-size:13.5px;border-bottom:1px solid #E2E8F0;">{port}</td>
                    </tr>
                    {target_entity_html}
                    <tr>
                      <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Current Status</td>
                      <td style="padding:10px 14px;color:#059669;font-size:13.5px;font-weight:700;border-bottom:1px solid #E2E8F0;">Received</td>
                    </tr>
                    <tr>
                      <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;border-bottom:1px solid #E2E8F0;background:#F8FAFC;">Assigned Handler</td>
                      <td style="padding:10px 14px;color:#0F172A;font-size:13.5px;border-bottom:1px solid #E2E8F0;">Secretariat Grievance Committee</td>
                    </tr>
                    <tr>
                      <td style="padding:10px 14px;color:#64748B;font-size:13px;font-weight:600;background:#F8FAFC;">Date Lodged</td>
                      <td style="padding:10px 14px;color:#475569;font-size:13px;">{now_str}</td>
                    </tr>
                  </table>

                  <!-- HOW TO TRACK BOX -->
                  <div style="background:#F8FAFC;border:1px solid #E2E8F0;border-radius:12px;padding:18px;margin-bottom:24px;">
                    <div style="color:#0F172A;font-size:13.5px;font-weight:800;margin-bottom:8px;">🔍 How to Track Your Complaint:</div>
                    <ol style="margin:0;padding-left:18px;color:#475569;font-size:13px;line-height:1.6;">
                      <li>Open the <strong>CUBAG Portal or Mobile App</strong>.</li>
                      <li>Navigate to <strong>Complaints & Grievance Hub</strong> or <strong>Track Grievance</strong>.</li>
                      <li>Enter your Tracking ID: <strong style="color:#FF5000;">{comp_id}</strong> to view real-time stage updates, investigation findings, and resolution notices.</li>
                    </ol>
                  </div>

                  <!-- WHAT HAPPENS NEXT -->
                  <div style="border-left:3px solid #0284C7;background:#F0F9FF;padding:14px 16px;border-radius:0 8px 8px 0;margin-bottom:24px;">
                    <div style="color:#0369A1;font-size:13px;font-weight:700;margin-bottom:4px;">Next Steps:</div>
                    <p style="margin:0;color:#0C4A6E;font-size:12.5px;line-height:1.5;">
                      The committee will assess the particulars of your report. If additional documentation is required, an assigned secretariat officer will contact you directly via this email or phone.
                    </p>
                  </div>

                  <p style="margin:0;color:#64748B;font-size:13px;line-height:1.5;">
                    Warm regards,<br>
                    <strong>CUBAG Grievance & Disciplinary Standing Committee</strong><br>
                    Customs Brokers Association of Ghana
                  </p>

                </td>
              </tr>

              <!-- FOOTER -->
              <tr>
                <td style="background:#F8FAFC;padding:20px 32px;text-align:center;border-top:1px solid #E2E8F0;">
                  <p style="margin:0 0 6px 0;color:#94A3B8;font-size:11.5px;">
                    Customs Brokers Association of Ghana (CUBAG) • Secretariat Office, Tema Port & KIA Chapter
                  </p>
                  <p style="margin:0;color:#CBD5E1;font-size:11px;">
                    This is an automated administrative notification. Please do not reply directly to this email.
                  </p>
                </td>
              </tr>

            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """

    body_text = f"""CUBAG GRIEVANCE & COMPLAINT CONFIRMATION
Customs Brokers Association of Ghana (CUBAG)

Dear {name},

Your complaint has been formally lodged into the CUBAG Central Registry.

--------------------------------------------------
OFFICIAL TRACKING ID: {comp_id}
--------------------------------------------------
Subject: {subject}
Category: {category}
Port / Location: {port}
Party Involved: {target_entity or 'N/A'}
Status: Received
Assigned To: Secretariat Grievance Committee
Date Lodged: {now_str}

HOW TO TRACK:
1. Open the CUBAG Portal or App.
2. Go to Complaints & Grievance Hub -> Track Grievance.
3. Enter Tracking ID: {comp_id} to view live status and updates.

Warm regards,
CUBAG Grievance & Disciplinary Standing Committee
Customs Brokers Association of Ghana
"""

    # 1. Try Resend
    if resend.api_key:
        try:
            params = {
                "from": f"{sender_name} <{sender_email}>",
                "to": [to_email],
                "subject": email_subject,
                "text": body_text,
                "html": html,
            }
            resend.Emails.send(params)
            logger.info(f"[Resend] Complaint confirmation sent to {to_email} for {comp_id}")
            return True
        except Exception as e:
            logger.error(f"[Resend] Failed sending complaint confirmation: {e}. Trying SMTP...")

    # 2. Try SMTP
    smtp_host = os.getenv('SMTP_HOST')
    if smtp_host:
        try:
            smtp_port = int(os.getenv('SMTP_PORT', '587'))
            smtp_pass = os.getenv('SMTP_PASS') or os.getenv('SMTP_PASSWORD')
            msg = MIMEMultipart('alternative')
            msg['Subject'] = email_subject
            msg['From'] = f"{sender_name} <{sender_email}>"
            msg['To'] = to_email
            msg.attach(MIMEText(body_text, 'plain'))
            msg.attach(MIMEText(html, 'html'))

            server = smtplib.SMTP(smtp_host, smtp_port)
            server.starttls()
            if smtp_pass:
                server.login(sender_email, smtp_pass)
            server.sendmail(sender_email, to_email, msg.as_string())
            server.quit()
            logger.info(f"[SMTP] Complaint confirmation sent to {to_email} for {comp_id}")
            return True
        except Exception as e:
            logger.error(f"[SMTP] Failed sending complaint confirmation: {e}")

    logger.info(f"[Email] Complaint confirmation logged for {to_email} (Tracking ID: {comp_id})")
    return False


def _generate_complaint_id():
    """Generates a clean tracking ID like CMP-2026-83941"""
    digits = ''.join(random.choices(string.digits, k=5))
    year = datetime.utcnow().year
    return f"CMP-{year}-{digits}"


@complaints_bp.route('/submit', methods=['POST'])
def submit_complaint():
    """
    Public endpoint for filing a trade / customs / broker grievance or complaint.
    Returns a unique tracking ID and sends a confirmation email to complainant.
    """
    data = request.get_json(silent=True) or {}
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
                    complaint_id, name, email, phone, category, port, target_entity, subject, description, status, assigned_to
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Received', 'Secretariat Grievance Committee'
                ) RETURNING id, complaint_id, name, email, phone, category, port, target_entity, subject, status, created_at
            """, (comp_id, name, email, phone, category, port, target_entity, subject, description))
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

        res_payload = jsonify({
            'success': True,
            'message': 'Complaint lodged successfully. A confirmation email with your Tracking ID has been sent.',
            'complaint_id': comp_id,
            'data': {
                'complaint_id': comp_id,
                'name': name,
                'email': email,
                'phone': phone,
                'category': category,
                'port': port,
                'target_entity': target_entity,
                'subject': subject,
                'status': 'Received',
                'created_at': row['created_at'].isoformat() if hasattr(row['created_at'], 'isoformat') else str(row['created_at']),
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
def track_complaint(complaint_id):
    """
    Public tracking endpoint. Returns the live status and timeline of a complaint by its ID.
    """
    cid = (complaint_id or '').strip().upper()
    if not cid:
        return jsonify({'success': False, 'message': 'Complaint ID is required.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    id, complaint_id, name, email, phone, category, port, 
                    target_entity, subject, description, status, resolution_notes, 
                    assigned_to, priority, created_at, updated_at
                FROM complaints 
                WHERE UPPER(complaint_id) = %s OR UPPER(complaint_id) = %s
            """, (cid, cid.replace(' ', '')))
            comp = cursor.fetchone()

        if not comp:
            return jsonify({'success': False, 'message': f'No complaint found with ID: {cid}. Please check the reference number and try again.'}), 404

        # Build tracking timeline based on current status
        status = comp['status'] or 'Received'
        timeline = [
            {
                'step': 1,
                'title': 'Complaint Lodged',
                'desc': 'Formal grievance logged into CUBAG Central Secretariat Registry.',
                'done': True,
                'active': status == 'Received',
                'date': comp['created_at'].strftime('%d %b %Y, %I:%M %p') if hasattr(comp['created_at'], 'strftime') else str(comp['created_at'])
            },
            {
                'step': 2,
                'title': 'Secretariat Review',
                'desc': 'Assigned to the Grievance & Disciplinary Standing Committee for preliminary merit assessment.',
                'done': status in ('Under Review', 'Investigating', 'Resolved', 'Closed'),
                'active': status == 'Under Review',
                'date': comp['updated_at'].strftime('%d %b %Y') if (status in ('Under Review', 'Investigating', 'Resolved', 'Closed') and hasattr(comp['updated_at'], 'strftime')) else 'Pending'
            },
            {
                'step': 3,
                'title': 'Port & Stakeholder Investigation',
                'desc': f"Evidence verification and stakeholder engagement at {comp['port'] or 'Port'}.",
                'done': status in ('Investigating', 'Resolved', 'Closed'),
                'active': status == 'Investigating',
                'date': comp['updated_at'].strftime('%d %b %Y') if (status in ('Investigating', 'Resolved', 'Closed') and hasattr(comp['updated_at'], 'strftime')) else 'Pending'
            },
            {
                'step': 4,
                'title': 'Resolution & Official Action',
                'desc': comp['resolution_notes'] or 'Formal resolution notice issued by CUBAG Executive Committee.',
                'done': status in ('Resolved', 'Closed'),
                'active': status in ('Resolved', 'Closed'),
                'date': comp['updated_at'].strftime('%d %b %Y') if (status in ('Resolved', 'Closed') and hasattr(comp['updated_at'], 'strftime')) else 'Pending'
            }
        ]

        return jsonify({
            'success': True,
            'data': {
                'complaint_id': comp['complaint_id'],
                'name': comp['name'],
                'email': comp['email'],
                'phone': comp['phone'],
                'category': comp['category'],
                'port': comp['port'],
                'target_entity': comp['target_entity'],
                'subject': comp['subject'],
                'description': comp['description'],
                'status': comp['status'],
                'resolution_notes': comp['resolution_notes'],
                'assigned_to': comp['assigned_to'],
                'priority': comp['priority'],
                'created_at': comp['created_at'].isoformat() if hasattr(comp['created_at'], 'isoformat') else str(comp['created_at']),
                'updated_at': comp['updated_at'].isoformat() if hasattr(comp['updated_at'], 'isoformat') else str(comp['updated_at']),
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
@jwt_required()
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
@jwt_required()
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
