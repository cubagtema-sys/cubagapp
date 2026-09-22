"""
Compliance Centre — License Renewal & Member ID Application
-----------------------------------------------------------------
Member flow  : create application → upload docs → submit → pay (webhook) → admin review
Admin flow   : list applications → review docs → request revision | approve | reject

Improvements:
  - "Request Revision" status: admin sends back to member for specific doc updates (no repayment)
  - Fixed duplicate check: approved applications don't block new renewal cycles
  - Payment confirmation is webhook-driven only (not self-confirmed by client)
  - Push notifications sent to member on approve / reject / revision_requested
  - Certificate endpoint: generates an HTML approval certificate
  - Auto-fill staleness: returns original upload date so client can warn the member
"""

import os
import uuid
import logging
import requests
import resend
from datetime import datetime
from flask import Blueprint, jsonify, request, Response
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from config.cache import cache
from utils import sub_admin_required, send_push_notification, log_admin_action

logger = logging.getLogger(__name__)
compliance_bp = Blueprint('compliance', __name__)

# ── Supabase ──────────────────────────────────────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

try:
    from file_storage import save_file as _save_file
except ImportError:
    _save_file = None

ALLOWED_EXT = {'pdf', 'png', 'jpg', 'jpeg'}
MAX_MB      = 15

# ── Document Requirements ─────────────────────────────────────────────────────

RENEWAL_REQUIREMENTS = [
    {'key': 'renewal_application_letter',    'label': 'Application for Renewal on Company Letterhead'},
    {'key': 'renewal_clearance_forms',       'label': 'Clearance Forms from District (Tema / AIA / Aflao / Takoradi)'},
    {'key': 'renewal_staff_list',            'label': 'Staff List (Indicating Positions)'},
    {'key': 'renewal_certificate_commence',  'label': 'Copy of Certificate to Commence Business'},
    {'key': 'renewal_proficiency_cert',      'label': 'Copy of Proficiency Certificate'},
]

CUSTOMS_LICENCE_REQUIREMENTS = [
    {'key': 'cl_application_letter',   'label': 'Application Letter on Company Letterhead'},
    {'key': 'cl_recommendation',       'label': 'Recommendation from Association'},
    {'key': 'cl_companies_code',       'label': "Companies Code Act 179 (Registrar-General's Department)"},
    {'key': 'cl_tax_clearance',        'label': 'Tax Clearance Certificate'},
    {'key': 'cl_ssnit_clearance',      'label': 'SSNIT Clearance Certificate'},
    {'key': 'cl_staff_list',           'label': 'Staff List (Designation, Telephone, Ghana Card Numbers)'},
    {'key': 'cl_digital_address',      'label': 'Digital Address (Office Location)'},
    {'key': 'cl_customs_certificate',  'label': 'Verification of Customs Proficiency Certificate'},
    {'key': 'cl_sic_bond',             'label': 'SIC Bond'},
]

# Map: compliance_requirement_key -> initial_application_requirement_key
RENEWAL_OVERLAP = {
    'renewal_application_letter':   'application_letter',
    'renewal_clearance_forms':      'acceptance_letter',
    'renewal_staff_list':           'staff_list',
    'renewal_certificate_commence': 'certificate_commence',
    'renewal_proficiency_cert':     'proficiency_certificate',
}

CUSTOMS_OVERLAP = {
    'cl_application_letter':  'application_letter',
    'cl_recommendation':      'acceptance_letter',
    'cl_companies_code':      'certificate_commence',
    'cl_tax_clearance':       'tax_clearance',
    'cl_ssnit_clearance':     'ssnit_clearance',
    'cl_staff_list':          'staff_list',
    'cl_customs_certificate': 'proficiency_certificate',
}

APPLICATION_TYPES = {
    'renewal':         {'requirements': RENEWAL_REQUIREMENTS,         'overlap': RENEWAL_OVERLAP},
    'customs_licence': {'requirements': CUSTOMS_LICENCE_REQUIREMENTS, 'overlap': CUSTOMS_OVERLAP},
}

# Statuses that indicate an application is still active (block new application of same type)
# NOTE: 'approved' and 'rejected' are intentionally excluded so members can start a new renewal cycle.
ACTIVE_STATUSES = (
    'draft', 'submitted', 'under_review', 'awaiting_bill',
    'payment_pending', 'awaiting_payment', 'partially_paid', 'payment_submitted',
    'payment_confirmed', 'revision_requested'
)


# ── DB helpers ────────────────────────────────────────────────────────────────
# Use a module-level set to track which DB connections have already verified
# the schema. This is process-local but avoids re-running DDL on every request.
_schema_verified = False

def _ensure_tables(cursor):
    """Ensure compliance tables exist. Uses a DB-side check so DDL only runs once."""
    global _schema_verified
    if _schema_verified:
        return

    # Fast DB-side check: does the table already exist?
    cursor.execute("""
        SELECT 1 FROM pg_class
        WHERE relname = 'compliance_applications' AND relkind = 'r'
        LIMIT 1
    """)
    table_exists = cursor.fetchone() is not None

    if table_exists:
        try:
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS payment_deadline DATE")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS fee_breakdown TEXT")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS payment_amount NUMERIC(10,2)")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS bill_title TEXT")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(10,2) DEFAULT 0.00")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS allow_installments BOOLEAN DEFAULT TRUE")
            cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS min_installment_amount NUMERIC(10,2) DEFAULT 0.00")
            cursor.execute("ALTER TABLE compliance_documents ADD COLUMN IF NOT EXISTS admin_note TEXT")
            cursor.execute("ALTER TABLE compliance_documents ADD COLUMN IF NOT EXISTS auto_filled BOOLEAN NOT NULL DEFAULT FALSE")
            cursor.execute("ALTER TABLE compliance_documents ADD COLUMN IF NOT EXISTS source_uploaded_at TIMESTAMP")
            if hasattr(cursor, 'connection') and cursor.connection:
                cursor.connection.commit()
        except Exception:
            pass
        _schema_verified = True
        return

    # First-time setup only
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS compliance_applications (
                id                      SERIAL PRIMARY KEY,
                member_id               INTEGER NOT NULL,
                type                    VARCHAR(30) NOT NULL,
                status                  VARCHAR(30) NOT NULL DEFAULT 'draft',
                payment_ref             TEXT,
                payment_amount          NUMERIC(10,2),
                payment_deadline        DATE,
                fee_breakdown           TEXT,
                payment_confirmed_at    TIMESTAMP,
                admin_note              TEXT,
                reviewed_by             INTEGER,
                reviewed_at             TIMESTAMP,
                created_at              TIMESTAMP DEFAULT NOW(),
                updated_at              TIMESTAMP DEFAULT NOW()
            )
        """)
        cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS payment_deadline DATE")
        cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS fee_breakdown TEXT")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS compliance_documents (
                id              SERIAL PRIMARY KEY,
                application_id  INTEGER NOT NULL,
                requirement     VARCHAR(100) NOT NULL,
                label           TEXT NOT NULL,
                file_url        TEXT,
                file_name       TEXT,
                file_size       INTEGER,
                status          VARCHAR(20) NOT NULL DEFAULT 'pending',
                auto_filled     BOOLEAN NOT NULL DEFAULT FALSE,
                source_uploaded_at TIMESTAMP,
                admin_note      TEXT,
                uploaded_at     TIMESTAMP DEFAULT NOW(),
                reviewed_at     TIMESTAMP,
                reviewed_by     INTEGER
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS compliance_settings (
                key VARCHAR(50) PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
        cursor.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS ux_compliance_active_app_per_member_type
            ON compliance_applications (member_id, type)
            WHERE status IN ('draft', 'submitted', 'payment_pending', 'payment_confirmed', 'under_review', 'revision_requested')
        """)
        cursor.execute("ALTER TABLE members ADD COLUMN IF NOT EXISTS renewal_fee_amount NUMERIC(10,2)")
        cursor.execute("ALTER TABLE members ADD COLUMN IF NOT EXISTS renewal_fee_breakdown TEXT")
        cursor.execute("ALTER TABLE members ADD COLUMN IF NOT EXISTS renewal_fee_title TEXT")
        cursor.execute("ALTER TABLE compliance_applications ADD COLUMN IF NOT EXISTS bill_title TEXT")
        if hasattr(cursor, 'connection') and cursor.connection:
            cursor.connection.commit()
        _schema_verified = True
    except Exception as e:
        try:
            if hasattr(cursor, 'connection') and cursor.connection:
                cursor.connection.rollback()
        except Exception:
            pass
        logger.warning(f"[_ensure_tables] Failed to create tables: {e}")
        raise


def _reqs_for_type(app_type):
    return APPLICATION_TYPES.get(app_type, {}).get('requirements', [])

def _overlap_for_type(app_type):
    return APPLICATION_TYPES.get(app_type, {}).get('overlap', {})


def _build_doc_list(app_id, app_type, cursor, is_admin=False):
    """Return merged requirement list with upload status for a given application."""
    cursor.execute("SELECT * FROM compliance_documents WHERE application_id = %s", (app_id,))
    rows = cursor.fetchall()
    uploaded_map = {r['requirement']: dict(r) for r in rows}
    result = []
    for req in _reqs_for_type(app_type):
        doc = uploaded_map.get(req['key'])
        result.append({
            'key':                req['key'],
            'label':              req['label'],
            'uploaded':           doc is not None and doc.get('file_url') is not None,
            'auto_filled':        doc['auto_filled']          if doc else False,
            'source_uploaded_at': str(doc['source_uploaded_at']) if doc and doc.get('source_uploaded_at') else None,
            'id':                 doc['id']                   if doc else None,
            'file_url':           doc['file_url']             if doc else None,
            'file_name':          doc['file_name']            if doc else None,
            'status':             doc['status']               if doc else 'not_uploaded',
            'admin_note':         doc['admin_note']           if doc else None,
            'uploaded_at':        str(doc['uploaded_at'])     if doc and doc.get('uploaded_at') else None,
        })

    # Include Bank Deposit Slip in the statutory documents list ONLY for admin review
    if is_admin:
        deposit_doc = uploaded_map.get('bank_deposit_slip')
        if deposit_doc and deposit_doc.get('file_url'):
            doc_status = deposit_doc.get('status') or 'pending'
            cursor.execute("""
                SELECT p.id, p.payment_ref, p.bank_name, p.status, p.amount, p.notes
                FROM payments p
                WHERE (p.receipt_url IS NOT NULL AND (p.receipt_url = %s OR p.receipt_url LIKE %s))
                   OR (p.application_id = %s)
                   OR (p.payment_ref IS NOT NULL AND p.payment_ref = (SELECT payment_ref FROM compliance_applications WHERE id = %s))
                   OR (p.member_id = (SELECT member_id FROM compliance_applications WHERE id = %s) AND (p.description ILIKE '%%renewal%%' OR p.description ILIKE '%%compliance%%' OR p.description ILIKE '%%dues%%'))
                ORDER BY p.id DESC LIMIT 1
            """, (deposit_doc['file_url'], f"%{deposit_doc.get('file_name', '')}%", app_id, app_id, app_id))
            p_match = cursor.fetchone()
            payment_id = None
            bank_label = deposit_doc.get('label') or 'Bank Deposit Receipt Slip'
            if p_match:
                payment_id = p_match['id']
                if p_match['status'] == 'paid':
                    doc_status = 'approved'
                elif p_match['status'] == 'rejected':
                    doc_status = 'rejected'
                b_name = p_match.get('bank_name') or 'GCB Bank Limited'
                amt_str = f" · GH₵ {float(p_match['amount']):.2f}" if p_match.get('amount') is not None else ""
                bank_label = f"Bank Deposit Receipt Slip ({b_name}){amt_str}"

            result.append({
                'key':                'bank_deposit_slip',
                'label':              bank_label,
                'uploaded':           True,
                'auto_filled':        False,
                'source_uploaded_at': None,
                'id':                 deposit_doc['id'],
                'file_url':           deposit_doc['file_url'],
                'file_name':          deposit_doc.get('file_name') or deposit_doc['file_url'].split('/')[-1],
                'status':             doc_status,
                'admin_note':         deposit_doc.get('admin_note') or (f"Ref: {p_match['payment_ref']}" if p_match and p_match.get('payment_ref') else None),
                'uploaded_at':        str(deposit_doc['uploaded_at']) if deposit_doc.get('uploaded_at') else None,
                'is_payment_receipt': True,
                'payment_id':         payment_id,
            })
        else:
            cursor.execute("""
                SELECT p.id, p.payment_ref, p.receipt_url, p.bank_name, p.status, p.created_at, p.amount, p.notes
                FROM payments p
                JOIN compliance_applications ca ON (
                    (ca.payment_ref IS NOT NULL AND ca.payment_ref = p.payment_ref)
                    OR (ca.member_id = p.member_id AND (p.description ILIKE '%%renewal%%' OR p.description ILIKE '%%compliance%%' OR p.description ILIKE '%%dues%%'))
                )
                WHERE ca.id = %s AND p.receipt_url IS NOT NULL AND p.receipt_url != ''
                ORDER BY p.created_at DESC
                LIMIT 1
            """, (app_id,))
            p_row = cursor.fetchone()
            if p_row:
                file_name = p_row['receipt_url'].split('/')[-1]
                bank_name = p_row.get('bank_name') or 'GCB Bank Limited'
                amt_str = f" · GH₵ {float(p_row['amount']):.2f}" if p_row.get('amount') is not None else ""
                result.append({
                    'key':                'bank_deposit_slip',
                    'label':              f"Bank Deposit Receipt Slip ({bank_name}){amt_str}",
                    'uploaded':           True,
                    'auto_filled':        False,
                    'source_uploaded_at': None,
                    'id':                 p_row['id'],
                    'file_url':           p_row['receipt_url'],
                    'file_name':          file_name,
                    'status':             'approved' if p_row['status'] == 'paid' else 'pending',
                    'admin_note':         f"Ref: {p_row['payment_ref']}" + (f" | {p_row['notes']}" if p_row.get('notes') else ""),
                    'uploaded_at':        str(p_row['created_at']) if p_row.get('created_at') else None,
                    'is_payment_receipt': True,
                    'payment_id':         p_row['id'],
                })
    return result


def _get_member_fcm_and_email(member_id, cursor):
    """Return (fcm_token, email, name) for a member."""
    cursor.execute("SELECT fcm_token, email, name FROM members WHERE id = %s", (member_id,))
    row = cursor.fetchone()
    if row:
        return row.get('fcm_token'), row.get('email', ''), row.get('name', '')
    return None, '', ''


def _send_compliance_email(to_email, member_name, subject, body_html):
    """Send a compliance decision email via Resend."""
    resend.api_key = os.getenv('RESEND_API_KEY')
    if not resend.api_key or not to_email:
        return
    sender = os.getenv('SMTP_USER', 'support@cubag.org')
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:32px;border:1px solid #eee;border-radius:12px">
      <h2 style="color:#0f62fe">CUBAG Compliance Centre</h2>
      <p>Hi <strong>{member_name}</strong>,</p>
      {body_html}
      <p style="margin-top:24px;color:#888;font-size:0.85em">This is an automated message from the CUBAG Compliance System.</p>
    </div>
    """
    try:
        resend.Emails.send({"from": f"CUBAG <{sender}>", "to": [to_email], "subject": subject, "html": html})
        logger.info(f'[Compliance] Email sent to {to_email}: {subject}')
    except Exception as e:
        logger.warning(f'[Compliance] Email failed: {e}')


# ─────────────────────────────────────────────────────────────────────────────
# MEMBER ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────────

@compliance_bp.route('/my-applications', methods=['GET'])
@jwt_required()
def my_applications():
    """List all compliance applications for the logged-in member."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("""
                SELECT ca.*,
                       COUNT(cd.id)                                                    AS docs_total,
                       COUNT(cd.id) FILTER (WHERE cd.file_url IS NOT NULL)             AS docs_uploaded,
                       COUNT(cd.id) FILTER (WHERE cd.status = 'approved')              AS docs_approved,
                       COUNT(cd.id) FILTER (WHERE cd.status = 'rejected')              AS docs_rejected
                FROM compliance_applications ca
                LEFT JOIN compliance_documents cd ON cd.application_id = ca.id
                WHERE ca.member_id = %s
                GROUP BY ca.id
                ORDER BY ca.created_at DESC
            """, (member_id,))
            apps = cursor.fetchall()
            apps_list = []
            for a in apps:
                d = dict(a)
                p_amt = float(d.get('payment_amount') or 0.0)
                amt_pd = float(d.get('amount_paid') or 0.0)
                d['balance_due'] = max(0.0, p_amt - amt_pd)
                apps_list.append(d)
        return jsonify({'applications': apps_list}), 200
    except Exception as e:
        logger.exception('[Compliance] my_applications error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications', methods=['POST'])
@jwt_required()
def create_application():
    """
    Create a new compliance application (renewal or customs_licence).
    Auto-fills documents from the member's existing 11-doc registration uploads
    where the requirement keys overlap. Includes source upload date for staleness warning.
    FIX: approved applications no longer block new cycles.
    """
    member_id = get_jwt_identity()
    data      = request.get_json() or {}
    app_type  = data.get('type', '').strip().lower()

    if app_type not in APPLICATION_TYPES:
        return jsonify({'message': 'type must be "renewal" or "customs_licence"'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)

            # Serialize creation per member to avoid double-tap / race duplicate rows.
            cursor.execute("SELECT id FROM members WHERE id = %s FOR UPDATE", (member_id,))

            # Clean up any legacy duplicate active rows before deciding whether to resume.
            cursor.execute("""
                DELETE FROM compliance_applications ca
                USING (
                    SELECT id,
                           ROW_NUMBER() OVER (
                               PARTITION BY member_id, type
                               ORDER BY created_at ASC, id ASC
                           ) AS rn
                    FROM compliance_applications
                    WHERE member_id = %s AND type = %s AND status = ANY(%s)
                ) dup
                WHERE ca.id = dup.id AND dup.rn > 1
            """, (member_id, app_type, list(ACTIVE_STATUSES)))

            # FIX #3: Only block if there is a currently-active (non-approved, non-rejected) application
            cursor.execute("""
                SELECT id FROM compliance_applications
                WHERE member_id = %s AND type = %s AND status = ANY(%s)
            """, (member_id, app_type, list(ACTIVE_STATUSES)))
            existing = cursor.fetchone()
            if existing:
                return jsonify({
                    'message': 'Resuming existing active application of this type.',
                    'application_id': existing['id'],
                    'existing': True
                }), 200

            # Create the application
            cursor.execute("""
                INSERT INTO compliance_applications (member_id, type, status)
                VALUES (%s, %s, 'draft') RETURNING id
            """, (member_id, app_type))
            app_id = cursor.fetchone()['id']

            # ── Auto-fill overlapping documents from member_documents ──────────
            overlap_map = _overlap_for_type(app_type)
            if overlap_map:
                src_keys = list(overlap_map.values())
                cursor.execute("""
                    SELECT requirement, label, file_url, file_name, file_size, uploaded_at
                    FROM member_documents
                    WHERE member_id = %s AND requirement = ANY(%s) AND file_url IS NOT NULL
                """, (member_id, src_keys))
                existing_docs = {r['requirement']: dict(r) for r in cursor.fetchall()}

                for comp_key, reg_key in overlap_map.items():
                    doc = existing_docs.get(reg_key)
                    if doc and doc.get('file_url'):
                        label = next(
                            (r['label'] for r in _reqs_for_type(app_type) if r['key'] == comp_key),
                            comp_key
                        )
                        # Store source_uploaded_at for staleness warning in UI
                        cursor.execute("""
                            INSERT INTO compliance_documents
                                (application_id, requirement, label, file_url, file_name,
                                 file_size, status, auto_filled, source_uploaded_at)
                            VALUES (%s, %s, %s, %s, %s, %s, 'pending', TRUE, %s)
                        """, (app_id, comp_key, label,
                              doc['file_url'], doc['file_name'], doc.get('file_size', 0),
                              doc.get('uploaded_at')))

            conn.commit()

        return jsonify({'message': 'Application created', 'application_id': app_id}), 201
    except Exception as e:
        logger.exception('[Compliance] create_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>', methods=['GET'])
@jwt_required()
def get_application(app_id):
    """Get a single application with full document list."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT * FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            docs = _build_doc_list(app_id, app['type'], cursor)

            cursor.execute("""
                SELECT p.id, p.id as tx_id, p.amount, p.description, p.status,
                       COALESCE(p.payment_method, 'bank') as payment_method,
                       p.payment_ref, p.receipt_url, p.bank_name, p.account_name,
                       p.account_number, p.notes, p.created_at, p.paid_at, p.verified_at,
                       p.is_installment, p.installment_number
                FROM payments p
                WHERE p.application_id = %s
                   OR (p.member_id = %s AND (p.description ILIKE '%%renewal%%' OR p.description ILIKE '%%compliance%%' OR p.description ILIKE '%%dues%%'))
                ORDER BY p.created_at ASC
            """, (app_id, member_id))
            all_payments = [dict(r) for r in cursor.fetchall()]
            for p_rec in all_payments:
                if p_rec.get('created_at'):
                    p_rec['date'] = p_rec['created_at'].isoformat()

            app_dict = dict(app)
            confirmed_paid = sum(float(p['amount']) for p in all_payments if str(p.get('status', '')).lower() in ('paid', 'completed', 'success', 'successful'))
            app_dict['amount_paid'] = confirmed_paid if confirmed_paid > 0 else float(app.get('amount_paid') or 0.0)
            tot_amt = float(app.get('payment_amount') or 0.0)
            app_dict['balance_due'] = max(0.0, tot_amt - app_dict['amount_paid'])
            app_dict['installments'] = all_payments

        return jsonify({'application': app_dict, 'documents': docs, 'installments': all_payments}), 200
    except Exception as e:
        logger.exception('[Compliance] get_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/sign-upload', methods=['POST'])
@jwt_required()
def sign_upload(app_id):
    """Get a Supabase-signed upload URL for a compliance document."""
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    requirement = data.get('requirement', '').strip()
    ext         = data.get('ext', 'pdf').strip().lower()
    size        = int(data.get('size', 0))
    label       = data.get('label', '').strip()

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT type, status FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            # Allow upload in draft AND revision_requested statuses (FIX #1)
            if app['status'] not in ('draft', 'revision_requested'):
                return jsonify({'message': 'Application is not editable in its current state'}), 400
            valid_keys = [r['key'] for r in _reqs_for_type(app['type'])]
            if requirement not in valid_keys:
                return jsonify({'message': 'Invalid requirement key for this application type'}), 400
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

    if ext not in ALLOWED_EXT:
        return jsonify({'message': 'Only PDF, PNG, JPG, JPEG allowed'}), 400
    if size > MAX_MB * 1024 * 1024:
        return jsonify({'message': f'File too large. Max {MAX_MB}MB.'}), 413
    # NOTE: sign-upload is only used when Supabase is available.
    # When Supabase is unreachable, clients should use the direct /upload endpoint instead.
    from file_storage import supabase_available
    if not supabase_available():
        # Tell the client to fall back to direct multipart upload
        return jsonify({
            'fallback': True,
            'message': 'Cloud storage unavailable. Use direct /upload endpoint.',
        }), 200

    safe_name  = f"compliance/{member_id}/{app_id}/{requirement}_{uuid.uuid4().hex}.{ext}"
    public_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{safe_name}"
    upload_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"

    return jsonify({
        'upload_url':   upload_url,
        'public_url':   public_url,
        'safe_name':    safe_name,
        'supabase_key': SUPABASE_KEY,
    }), 200


@compliance_bp.route('/applications/<int:app_id>/upload', methods=['POST'])
@jwt_required()
def upload_compliance_document(app_id):
    """Direct multipart upload for compliance documents with local fallback."""
    member_id   = get_jwt_identity()
    requirement = (request.form.get('requirement') or request.form.get('document_key') or '').strip()
    label       = request.form.get('label', '').strip()
    file        = request.files.get('file') or request.files.get('photo') or request.files.get('image')

    if not requirement:
        return jsonify({'message': 'Requirement key is required'}), 400
    if not file or not file.filename:
        return jsonify({'message': 'No file provided'}), 400

    ext = file.filename.rsplit('.', 1)[1].lower() if '.' in file.filename else 'pdf'
    if ext not in ('pdf', 'png', 'jpg', 'jpeg'):
        return jsonify({'message': 'Only PDF, PNG, JPG, JPEG files are accepted'}), 400

    file.seek(0, 2)
    size_bytes = file.tell()
    file.seek(0)
    if size_bytes > 15 * 1024 * 1024:
        return jsonify({'message': 'File too large. Max 15MB.'}), 413

    file_bytes = file.read()
    content_type = file.content_type or ('application/pdf' if ext == 'pdf' else 'image/jpeg')

    # ── Upload to persistent storage ────────────────────────────────────────────
    if _save_file:
        public_url = _save_file(
            file_bytes,
            original_filename=file.filename,
            subfolder=f'compliance_docs/{app_id}',
            prefix=f'{requirement}_',
            content_type=content_type,
        )
    else:
        # Inline fallback: absolute persistent paths
        backend_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        upload_dir = os.path.join(backend_root, 'uploads', 'compliance_docs', str(app_id))
        os.makedirs(upload_dir, exist_ok=True)
        local_filename = f"{requirement}_{uuid.uuid4().hex[:8]}.{ext}"
        with open(os.path.join(upload_dir, local_filename), 'wb') as f:
            f.write(file_bytes)
        # Mirror to static
        static_dir = os.path.join(backend_root, 'static', 'uploads', 'compliance_docs', str(app_id))
        os.makedirs(static_dir, exist_ok=True)
        try:
            with open(os.path.join(static_dir, local_filename), 'wb') as f:
                f.write(file_bytes)
        except Exception:
            pass
        public_url = f"/static/uploads/compliance_docs/{app_id}/{local_filename}"

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT type, status FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            if app['status'] not in ('draft', 'revision_requested', 'rejected', 'under_review', 'submitted'):
                return jsonify({'message': 'Application is not editable in its current state'}), 400

            if not label:
                label = next(
                    (r['label'] for r in _reqs_for_type(app['type']) if r['key'] == requirement),
                    requirement.replace('_', ' ').title()
                )

            cursor.execute(
                "SELECT id FROM compliance_documents WHERE application_id = %s AND requirement = %s",
                (app_id, requirement)
            )
            existing = cursor.fetchone()
            if existing:
                cursor.execute("""
                    UPDATE compliance_documents
                    SET file_url = %s, file_name = %s, file_size = %s,
                        status = 'pending', admin_note = NULL, uploaded_at = NOW(),
                        auto_filled = FALSE, source_uploaded_at = NULL
                    WHERE id = %s
                """, (public_url, file.filename, size_bytes, existing['id']))
            else:
                cursor.execute("""
                    INSERT INTO compliance_documents
                        (application_id, requirement, label, file_url, file_name, file_size, status)
                    VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                """, (app_id, requirement, label, public_url, file.filename, size_bytes))
            conn.commit()

        return jsonify({'message': 'Document uploaded successfully', 'file_url': public_url}), 200
    except Exception as e:
        logger.exception('[Compliance] upload_compliance_document error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/confirm-upload', methods=['POST'])
@jwt_required()
def confirm_upload(app_id):
    """Called after a successful Supabase direct upload; saves the DB record."""
    member_id   = get_jwt_identity()
    data        = request.get_json() or {}
    requirement = data.get('requirement', '').strip()
    label       = data.get('label', '').strip()
    public_url  = data.get('public_url', '').strip()
    filename    = data.get('filename', '').strip()
    size        = int(data.get('size', 0))

    if not requirement or not public_url:
        return jsonify({'message': 'Missing requirement or public_url'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT type, status FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            if app['status'] not in ('draft', 'revision_requested', 'rejected', 'under_review', 'submitted'):
                return jsonify({'message': 'Application is not editable in its current state'}), 400

            if not label:
                label = next(
                    (r['label'] for r in _reqs_for_type(app['type']) if r['key'] == requirement),
                    requirement
                )

            cursor.execute(
                "SELECT id FROM compliance_documents WHERE application_id = %s AND requirement = %s",
                (app_id, requirement)
            )
            existing = cursor.fetchone()
            if existing:
                cursor.execute("""
                    UPDATE compliance_documents
                    SET file_url = %s, file_name = %s, file_size = %s,
                        status = 'pending', admin_note = NULL, uploaded_at = NOW(),
                        auto_filled = FALSE, source_uploaded_at = NULL
                    WHERE id = %s
                """, (public_url, filename, size, existing['id']))
            else:
                cursor.execute("""
                    INSERT INTO compliance_documents
                        (application_id, requirement, label, file_url, file_name, file_size, status)
                    VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                """, (app_id, requirement, label, public_url, filename, size))
            conn.commit()

        return jsonify({'message': 'Document saved'}), 200
    except Exception as e:
        logger.exception('[Compliance] confirm_upload error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/submit', methods=['POST'])
@jwt_required()
def submit_application(app_id):
    """
    Member submits after uploading all required docs.
    - First submission: draft -> submitted (then pay)
    - After revision: revision_requested -> under_review directly (already paid, no repayment)
    """
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT type, status FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            if app['status'] not in ('draft', 'revision_requested', 'rejected'):
                return jsonify({'message': f'Application cannot be submitted from status: {app["status"]}'}), 400

            required_keys = [r['key'] for r in _reqs_for_type(app['type'])]
            cursor.execute("""
                SELECT requirement FROM compliance_documents
                WHERE application_id = %s AND file_url IS NOT NULL
            """, (app_id,))
            uploaded_keys = {r['requirement'] for r in cursor.fetchall()}
            missing = [k for k in required_keys if k not in uploaded_keys]
            if missing:
                reqs = _reqs_for_type(app['type'])
                missing_labels = [r['label'] for r in reqs if r['key'] in missing]
                return jsonify({'message': 'Please upload all required documents first.', 'missing': missing_labels}), 400

            if app['status'] in ('revision_requested', 'rejected'):
                # Already paid / re-submitting — go straight to under_review, no payment step
                cursor.execute("""
                    UPDATE compliance_applications
                    SET status = 'under_review', updated_at = NOW()
                    WHERE id = %s
                """, (app_id,))
                conn.commit()
                return jsonify({'message': 'Revision resubmitted. Application is now under review.', 'next_step': 'review'}), 200
            else:
                # First submission — needs payment
                cursor.execute("""
                    UPDATE compliance_applications
                    SET status = 'submitted', updated_at = NOW()
                    WHERE id = %s
                """, (app_id,))
                conn.commit()
                return jsonify({'message': 'Application submitted successfully. A bill will be generated by the Secretariat for payment.', 'next_step': 'bill_pending'}), 200

    except Exception as e:
        logger.exception('[Compliance] submit_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/payment-fee', methods=['GET'])
@jwt_required()
def get_payment_fee(app_id):
    """Return the payment fee from custom bill or compliance_settings."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT type, status, payment_amount, payment_deadline, fee_breakdown FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404

            if app.get('payment_amount') is not None and float(app['payment_amount']) > 0:
                import json
                breakdown = []
                try:
                    if app.get('fee_breakdown'):
                        breakdown = json.loads(app['fee_breakdown'])
                except Exception:
                    pass
                return jsonify({
                    'fee': float(app['payment_amount']),
                    'payment_amount': float(app['payment_amount']),
                    'payment_deadline': str(app.get('payment_deadline') or ''),
                    'fee_breakdown': breakdown,
                    'status': app.get('status')
                }), 200

            fee = None
            app_type = app['type']
            try:
                # Prefer admin-set fee values from the platform fees configuration.
                cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = 'cubag_fees_v2'")
                ps_row = cursor.fetchone()
                if ps_row and ps_row.get('config_value'):
                    val = ps_row['config_value']
                    import json
                    fees_list = json.loads(val) if isinstance(val, str) else val
                    for item in fees_list:
                        lbl = str(item.get('label', '')).lower()
                        amt = item.get('amount')
                        if amt is None or str(amt).strip() == '':
                            continue
                        try:
                            amt_val = float(str(amt).replace(',', ''))
                        except (TypeError, ValueError):
                            continue

                        if app_type == 'renewal' and 'renewal' in lbl:
                            fee = amt_val
                            break
                        elif app_type != 'renewal' and (('custom' in lbl and 'licence' in lbl) or 'application' in lbl):
                            fee = amt_val
                            break

                # Fallback to compliance_settings if the admin fees list did not yield a value.
                if fee is None or fee == 0:
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
                    cursor.execute("""
                        SELECT renewal_fee, customs_licence_fee
                        FROM compliance_settings
                        ORDER BY id DESC, updated_at DESC NULLS LAST
                        LIMIT 1
                    """)
                    row = cursor.fetchone()
                    if row:
                        renewal_fee = row.get('renewal_fee')
                        customs_fee = row.get('customs_licence_fee')
                        if renewal_fee is None or renewal_fee == '':
                            renewal_fee = 500.00
                        if customs_fee is None or customs_fee == '':
                            customs_fee = 750.00
                        fee = float(renewal_fee if app_type == 'renewal' else customs_fee)
            except Exception as fee_err:
                logger.warning(f'[compliance/payment-fee] Fee lookup failed, using default: {fee_err}')

            if fee is None or fee == 0:
                try:
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
                    cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
                    cursor.execute("""
                        SELECT renewal_fee, customs_licence_fee
                        FROM compliance_settings
                        ORDER BY id DESC, updated_at DESC NULLS LAST
                        LIMIT 1
                    """)
                    row = cursor.fetchone()
                    if row:
                        renewal_fee = row.get('renewal_fee')
                        customs_fee = row.get('customs_licence_fee')
                        if renewal_fee is not None and renewal_fee != '':
                            fee = float(renewal_fee) if app_type == 'renewal' else fee
                        if customs_fee is not None and customs_fee != '':
                            fee = float(customs_fee) if app_type != 'renewal' else fee
                except Exception as fallback_err:
                    logger.warning(f'[compliance/payment-fee] Fallback lookup failed: {fallback_err}')

            if fee is None or fee == 0:
                logger.error(f'[compliance/payment-fee] No fee could be resolved for app_type={app_type} and application={app_id}')
                return jsonify({'message': 'Unable to resolve compliance fee. Please set the fee in admin/fees.'}), 500

        return jsonify({'fee': fee, 'currency': 'GHS', 'type': app['type']}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/payment-status', methods=['GET'])
@jwt_required()
def poll_payment_status(app_id):
    """
    FIX #4: Client polls this instead of self-confirming payment.
    Returns current application status so client knows when webhook has updated it.
    """
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute(
                "SELECT status, payment_ref, payment_amount, payment_confirmed_at FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
        return jsonify(dict(app)), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/store-payment-ref', methods=['POST'])
@jwt_required()
def store_payment_ref(app_id):
    """
    After initiating a payment via the generic /payments/initiate endpoint,
    Flutter calls this to save the WhitsunPay transaction reference against the
    compliance application so the webhook can match and confirm it.
    """
    member_id = get_jwt_identity()
    data      = request.get_json() or {}
    pay_ref   = data.get('payment_ref', '').strip()

    if not pay_ref:
        return jsonify({'message': 'payment_ref is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id FROM compliance_applications WHERE id = %s AND member_id = %s",
                (app_id, member_id)
            )
            if not cursor.fetchone():
                return jsonify({'message': 'Application not found'}), 404
            cursor.execute(
                "UPDATE compliance_applications SET payment_ref = %s, updated_at = NOW() WHERE id = %s",
                (pay_ref, app_id)
            )
            conn.commit()
        return jsonify({'message': 'Payment reference stored'}), 200
    except Exception as e:
        logger.exception('[Compliance] store_payment_ref error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


import base64
import math

def _get_logo_base64():
    for p in [
        os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'static', 'logo.jpeg')),
        os.path.abspath(os.path.join('static', 'logo.jpeg')),
        os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'dist', 'logo.jpeg')),
    ]:
        if os.path.exists(p):
            try:
                with open(p, 'rb') as f:
                    return f"data:image/jpeg;base64,{base64.b64encode(f.read()).decode('utf-8')}"
            except Exception:
                pass
    return ""


@compliance_bp.route('/applications/<int:app_id>/certificate', methods=['GET'])
def get_certificate(app_id):
    """
    Returns the official CUBAG Certificate of Licensure & Standing.
    Supports ?format=pdf to seamlessly redirect to the vector PDF stream.
    Authentication accepts ?token=<jwt> query parameter or Authorization Bearer header.
    """
    from flask_jwt_extended import decode_token, verify_jwt_in_request, get_jwt_identity
    token = request.args.get('token', '').strip()
    member_id = None
    is_admin = False

    if token:
        try:
            decoded = decode_token(token)
            member_id = int(decoded.get('sub', 0))
            is_admin = decoded.get('role') in ('admin', 'sub_admin', 'super_admin')
        except Exception:
            pass

    if not member_id:
        try:
            verify_jwt_in_request(optional=True)
            ident = get_jwt_identity()
            if ident:
                member_id = int(ident)
        except Exception:
            pass

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if is_admin or not member_id:
                cursor.execute("""
                    SELECT ca.*, m.name AS member_name, m.email AS member_email,
                           m.company AS member_company, m.license_number, m.port_of_operation,
                           m.member_type, m.member_scale, m.license_expiry_date
                    FROM compliance_applications ca
                    JOIN members m ON m.id = ca.member_id
                    WHERE ca.id = %s
                """, (app_id,))
            else:
                cursor.execute("""
                    SELECT ca.*, m.name AS member_name, m.email AS member_email,
                           m.company AS member_company, m.license_number, m.port_of_operation,
                           m.member_type, m.member_scale, m.license_expiry_date
                    FROM compliance_applications ca
                    JOIN members m ON m.id = ca.member_id
                    WHERE ca.id = %s AND ca.member_id = %s
                """, (app_id, member_id))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Certificate record not found'}), 404

            # If user requested PDF format directly, redirect to PDF generator
            if request.args.get('format') == 'pdf':
                from flask import redirect
                return redirect(f"/api/v1/members/{app['member_id']}/certificate-pdf")

    except Exception as e:
        logger.exception(f"[Certificate] Failed fetching cert: {e}")
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

    # Format fields to exact executive standards
    company_name = (app.get('member_company') or app.get('member_name') or 'HART LOGISTICS').strip().upper()
    rep_name = (app.get('member_name') or '').strip().upper()
    
    raw_scale = app.get('member_scale') or app.get('member_type') or 'Individual Broker'
    scale_lower = raw_scale.lower()
    if 'broker' not in scale_lower:
        type_display = f"{raw_scale.title()} Broker"
    else:
        type_display = raw_scale.title()

    lic_num = app.get('license_number')
    if not lic_num or str(lic_num).lower() in ('pending', 'none', 'n/a', ''):
        year = datetime.now().year
        lic_num = f"CUBAG-LIC-{year}-{app['member_id']:04d}"

    port_txt = app.get('port_of_operation') or 'KIA Air Cargo'

    expiry = app.get('license_expiry_date')
    if expiry:
        if isinstance(expiry, str):
            try:
                expiry_date_str = datetime.fromisoformat(expiry).strftime('%d %B %Y')
            except Exception:
                expiry_date_str = expiry
        else:
            expiry_date_str = expiry.strftime('%d %B %Y')
    else:
        from datetime import timedelta
        expiry_date_str = (datetime.now() + timedelta(days=365)).strftime('%d %B %Y')

    logo_b64 = _get_logo_base64()
    pdf_download_url = f"/api/v1/members/{app['member_id']}/certificate-pdf"

    # Precompute 36-point starburst polygon coordinates for official seal
    starburst_pts = []
    cx, cy = 50.0, 50.0
    r_out, r_in = 46.0, 39.5
    for i in range(72):
        angle = i * math.pi / 36.0 - math.pi / 2.0
        r = r_out if i % 2 == 0 else r_in
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        starburst_pts.append(f"{x:.2f},{y:.2f}")
    starburst_str = " ".join(starburst_pts)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CUBAG Certificate of Licensure & Standing — {company_name}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Great+Vibes&family=Montserrat:wght@700;800;900&family=Outfit:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    background: #e2e8f0;
    font-family: 'Outfit', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    color: #0f172a;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 24px 12px;
    min-height: 100vh;
  }}
  .toolbar {{
    max-width: 980px;
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
    padding: 0 4px;
  }}
  .brand-badge {{
    font-size: 13px;
    font-weight: 700;
    color: #475569;
    display: flex;
    align-items: center;
    gap: 8px;
  }}
  .brand-badge-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #16a34a;
  }}
  .btn-actions {{
    display: flex;
    gap: 10px;
  }}
  .btn-action {{
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 9px 18px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
    text-decoration: none;
    transition: all 0.15s ease;
  }}
  .btn-print {{
    background: #0f172a;
    color: #ffffff;
    border: none;
  }}
  .btn-print:hover {{
    background: #1e293b;
  }}
  .btn-pdf {{
    background: #ea580c;
    color: #ffffff;
    border: none;
  }}
  .btn-pdf:hover {{
    background: #c2410c;
  }}
  .cert-wrapper {{
    width: 100%;
    max-width: 980px;
    background: #ffffff;
    box-shadow: 0 20px 45px -10px rgba(15, 23, 42, 0.2), 0 4px 12px rgba(0,0,0,0.06);
    border-radius: 4px;
    overflow: hidden;
  }}
  .cert-card {{
    position: relative;
    width: 100%;
    aspect-ratio: 1.414 / 1;
    background: #fdfdfc;
    padding: 28px 36px 24px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    text-align: center;
    border: 3px solid #ea580c;
    outline: 1.5px solid #d4af37;
    outline-offset: -7px;
  }}
  /* Corner concentric ring accents */
  .rivet {{
    position: absolute;
    width: 13px;
    height: 13px;
    border: 1.5px solid #d4af37;
    border-radius: 50%;
    pointer-events: none;
  }}
  .rivet::after {{
    content: '';
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 5px;
    height: 5px;
    border: 1px solid #d4af37;
    border-radius: 50%;
  }}
  .rivet-tl {{ top: 12px; left: 12px; }}
  .rivet-tr {{ top: 12px; right: 12px; }}
  .rivet-bl {{ bottom: 12px; left: 12px; }}
  .rivet-br {{ bottom: 12px; right: 12px; }}

  .watermark {{
    position: absolute;
    top: 48%;
    left: 50%;
    transform: translate(-50%, -50%) rotate(-12deg);
    font-family: 'Montserrat', sans-serif;
    font-weight: 900;
    font-size: 140px;
    color: rgba(212, 175, 55, 0.04);
    letter-spacing: 4px;
    user-select: none;
    pointer-events: none;
  }}
  .cert-header {{
    position: relative;
    z-index: 2;
  }}
  .logo-img {{
    width: 62px;
    height: 62px;
    object-fit: contain;
    margin: 0 auto 3px;
    display: block;
  }}
  .brand-title {{
    font-family: 'Montserrat', sans-serif;
    font-weight: 900;
    font-size: 32px;
    color: #ea580c;
    letter-spacing: 1px;
    line-height: 1.1;
  }}
  .brand-subtitle {{
    font-family: 'Outfit', sans-serif;
    font-weight: 700;
    font-size: 10.5px;
    color: #1e3a8a;
    letter-spacing: 1.8px;
    text-transform: uppercase;
    margin-top: 3px;
  }}
  .header-divider {{
    width: 280px;
    height: 1px;
    background: #cbd5e1;
    margin: 6px auto 12px;
  }}
  .main-cert-title {{
    font-family: 'Outfit', sans-serif;
    font-weight: 800;
    font-size: 21px;
    color: #0f172a;
    letter-spacing: 0.8px;
    text-transform: uppercase;
    margin-bottom: 8px;
  }}
  .certify-intro {{
    font-family: 'Georgia', serif;
    font-style: italic;
    font-size: 13.5px;
    color: #64748b;
    margin-bottom: 5px;
  }}
  .recipient-name {{
    font-family: 'Outfit', sans-serif;
    font-weight: 900;
    font-size: 26px;
    color: #0f172a;
    letter-spacing: 0.5px;
    text-transform: uppercase;
    margin-bottom: 3px;
  }}
  .rep-by {{
    font-family: 'Georgia', serif;
    font-style: italic;
    font-size: 13px;
    color: #64748b;
    margin-bottom: 8px;
  }}
  .rep-by strong {{
    font-style: normal;
    font-family: 'Outfit', sans-serif;
    color: #475569;
  }}
  .status-statement {{
    font-family: 'Outfit', sans-serif;
    font-size: 12.5px;
    color: #1e293b;
    margin-bottom: 10px;
  }}
  .pill-container {{
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
    padding: 7px 22px;
    display: inline-block;
    font-size: 11px;
    color: #1e293b;
    margin-bottom: 8px;
  }}
  .pill-container strong {{
    font-weight: 700;
    color: #0f172a;
  }}
  .validity-line {{
    font-size: 11px;
    font-weight: 700;
    color: #475569;
    margin-bottom: 16px;
  }}
  .cert-footer {{
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: flex-end;
    padding: 0 16px 6px;
    position: relative;
    z-index: 2;
  }}
  .sig-col {{
    text-align: center;
  }}
  .sig-script {{
    font-family: 'Great Vibes', cursive;
    font-size: 26px;
    color: #1e3a8a;
    border-bottom: 1.5px solid #1e3a8a;
    padding-bottom: 2px;
    display: inline-block;
    min-width: 150px;
    margin-bottom: 4px;
  }}
  .sig-role {{
    font-weight: 800;
    font-size: 11.5px;
    color: #0f172a;
  }}
  .sig-dept {{
    font-size: 9px;
    color: #64748b;
  }}
  .seal-col {{
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 0 16px;
  }}
  .official-seal {{
    width: 82px;
    height: 82px;
    display: block;
  }}

  @media print {{
    body {{
      background: #ffffff !important;
      padding: 0 !important;
    }}
    .toolbar {{
      display: none !important;
    }}
    .cert-wrapper {{
      box-shadow: none !important;
      max-width: 100% !important;
      border-radius: 0 !important;
    }}
    .cert-card {{
      outline-offset: -5px;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }}
    @page {{
      size: A4 landscape;
      margin: 0;
    }}
  }}
  @media (max-width: 768px) {{
    .cert-card {{
      padding: 16px 12px;
    }}
    .brand-title {{ font-size: 24px; }}
    .main-cert-title {{ font-size: 16px; }}
    .recipient-name {{ font-size: 19px; }}
    .cert-footer {{ padding: 0; }}
    .sig-script {{ font-size: 20px; min-width: 100px; }}
    .official-seal {{ width: 62px; height: 62px; }}
  }}
</style>
</head>
<body>

<div class="toolbar no-print">
  <div class="brand-badge">
    <div class="brand-badge-dot"></div>
    Official Licensed & Active Certificate
  </div>
  <div class="btn-actions">
    <button class="btn-action btn-print" onclick="window.print()">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 9V2h12v7M6 18H4a2 2 0 01-2-2v-5a2 2 0 012-2h16a2 2 0 012 2v5a2 2 0 01-2 2h-2"/><path d="M6 14h12v8H6z"/></svg>
      Print Certificate
    </button>
    <a class="btn-action btn-pdf" href="{pdf_download_url}" target="_blank">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
      Download Vector PDF
    </a>
  </div>
</div>

<div class="cert-wrapper">
  <div class="cert-card">
    <!-- Corner Rivets -->
    <div class="rivet rivet-tl"></div>
    <div class="rivet rivet-tr"></div>
    <div class="rivet rivet-bl"></div>
    <div class="rivet rivet-br"></div>

    <!-- Watermark -->
    <div class="watermark">cubag</div>

    <!-- Header -->
    <div class="cert-header">
      {f'<img class="logo-img" src="{logo_b64}" alt="CUBAG Logo" />' if logo_b64 else ''}
      <div class="brand-title">CUBAG</div>
      <div class="brand-subtitle">CUSTOMS BROKERS ASSOCIATION OF GHANA</div>
      <div class="header-divider"></div>

      <!-- Main Title -->
      <div class="main-cert-title">CERTIFICATE OF LICENSURE &amp; STANDING</div>

      <!-- Certify Preamble -->
      <div class="certify-intro">This is to officially certify that</div>

      <!-- Recipient -->
      <div class="recipient-name">{company_name}</div>

      <!-- Represented By -->
      <div class="rep-by">represented by &nbsp;<strong>{rep_name}</strong></div>

      <!-- Standing statement -->
      <div class="status-statement">
        is a duly registered, licensed, and active {type_display} of CUBAG
      </div>

      <!-- Pill Container -->
      <div>
        <div class="pill-container">
          License No: <strong>{lic_num}</strong> &nbsp;&nbsp;|&nbsp;&nbsp; Port of Operation: <strong>{port_txt}</strong>
        </div>
      </div>

      <!-- Validity Line -->
      <div class="validity-line">Valid Until: {expiry_date_str}</div>
    </div>

    <!-- Signatures & Seal -->
    <div class="cert-footer">
      <!-- President -->
      <div class="sig-col">
        <div class="sig-script">Alhaji A. R. Busia</div>
        <div class="sig-role">President</div>
        <div class="sig-dept">CUBAG Executive Council</div>
      </div>

      <!-- Seal -->
      <div class="seal-col">
        <svg class="official-seal" viewBox="0 0 100 100">
          <defs>
            <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#f59e0b" />
              <stop offset="50%" stop-color="#d97706" />
              <stop offset="100%" stop-color="#b45309" />
            </linearGradient>
            <filter id="sealShadow">
              <feDropShadow dx="0" dy="1.5" stdDeviation="1.5" flood-color="#000" flood-opacity="0.25"/>
            </filter>
          </defs>
          <polygon points="{starburst_str}" fill="url(#goldGrad)" stroke="#b45309" stroke-width="0.8" filter="url(#sealShadow)"/>
          <circle cx="50" cy="50" r="28" fill="#d97706" stroke="#fbbf24" stroke-width="0.8"/>
          <circle cx="50" cy="50" r="25" fill="#f59e0b"/>
          <circle cx="50" cy="50" r="23.5" fill="none" stroke="#d97706" stroke-width="0.5" stroke-dasharray="1.5 1"/>
          <text x="50" y="47.5" text-anchor="middle" font-family="'Outfit', sans-serif" font-weight="900" font-size="7.5" fill="#ffffff" letter-spacing="0.8">OFFICIAL</text>
          <text x="50" y="58" text-anchor="middle" font-family="'Outfit', sans-serif" font-weight="900" font-size="7.5" fill="#ffffff" letter-spacing="0.8">SEAL</text>
        </svg>
      </div>

      <!-- Secretary General -->
      <div class="sig-col">
        <div class="sig-script">Kwame E. Mensah</div>
        <div class="sig-role">Secretary General</div>
        <div class="sig-dept">CUBAG Executive Secretariat</div>
      </div>
    </div>
  </div>
</div>

</body>
</html>"""

    return Response(html, mimetype='text/html')


# ─────────────────────────────────────────────────────────────────────────────
# WEBHOOK — WhitsunPay payment confirmation (FIX #4)
# ─────────────────────────────────────────────────────────────────────────────

@compliance_bp.route('/payment-webhook', methods=['POST', 'PUT'])
def payment_webhook():
    """
    WhitsunPay webhook: when a compliance payment succeeds, move the application
    to under_review. The payment_ref stored in the compliance application matches
    the transactionReference in the webhook payload.
    This endpoint does NOT require a JWT — it's called by WhitsunPay server.
    Signature verification is handled by checking against the shared webhook secret.
    """
    import hashlib, hmac as hmac_lib
    secret = os.getenv('WHITSUNPAY_WEBHOOK_SECRET', '')
    sig    = request.headers.get('X-Whitsun-Signature', '')
    body   = request.get_data()

    if secret:
        expected = 'sha256=' + hmac_lib.new(secret.encode(), body, hashlib.sha256).hexdigest()
        if not hmac_lib.compare_digest(sig, expected):
            return jsonify({'message': 'Invalid signature'}), 401

    event     = request.get_json() or {}
    tx_ref    = str(event.get('transactionReference', '')).strip()
    wp_status = str(event.get('status', '')).lower()

    if not tx_ref:
        return jsonify({'message': 'ok'}), 200

    if wp_status not in ('successful', 'success', 'completed'):
        return jsonify({'message': 'ok'}), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Match by payment_ref stored in compliance_applications
            cursor.execute("""
                SELECT ca.id, ca.member_id, ca.type, ca.status
                FROM compliance_applications ca
                WHERE ca.payment_ref = %s AND ca.status = 'submitted'
            """, (tx_ref,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'ok'}), 200

            amount = event.get('amount')
            cursor.execute("""
                UPDATE compliance_applications
                SET status = 'under_review', payment_amount = %s,
                    payment_confirmed_at = NOW(), updated_at = NOW()
                WHERE id = %s
            """, (amount, app['id']))
            conn.commit()

            # Push notification to member
            fcm_token, email, name = _get_member_fcm_and_email(app['member_id'], cursor)
            type_label = 'License Renewal' if app['type'] == 'renewal' else 'Member ID Application'

        send_push_notification(
            fcm_token,
            title='Payment Confirmed ✓',
            body=f'Your {type_label} payment has been received. Your application is now under review.',
            data={'screen': 'compliance', 'application_id': str(app['id'])}
        )
        _send_compliance_email(
            email, name,
            subject=f'CUBAG — {type_label} Payment Confirmed',
            body_html=f"""
            <p>Your payment for the <strong>{type_label}</strong> application has been confirmed.</p>
            <p>Your application is now <strong>under review</strong> by the CUBAG Secretariat.
            Applications are typically reviewed within 5 business days.</p>
            <p>Reference: <strong>CUBAG-COMP-{app['id']:05d}</strong></p>
            """
        )

    except Exception as e:
        logger.exception('[Compliance Webhook] error')
    finally:
        conn.close()

    return jsonify({'message': 'ok'}), 200


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────────

@compliance_bp.route('/admin/applications', methods=['GET'])
@sub_admin_required('members')
def admin_list_applications():
    """List compliance applications with filters: type, status, page, per_page."""
    app_type    = request.args.get('type', '').strip().lower() or None
    status      = request.args.get('status', '').strip().lower() or None
    member_type = request.args.get('member_type', '').strip().lower() or None
    page        = max(1, int(request.args.get('page', 1)))
    per_page    = min(100, max(5, int(request.args.get('per_page', 50))))
    offset      = (page - 1) * per_page

    cache_key = f'admin_comp_apps_{app_type}_{status}_{member_type}_p{page}_l{per_page}'
    cached_res = cache.get(cache_key)
    if cached_res is not None:
        return jsonify(cached_res), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            where_clauses, params = [], []
            if app_type:
                where_clauses.append("ca.type = %s"); params.append(app_type)
            if status:
                where_clauses.append("ca.status = %s"); params.append(status)
            if member_type:
                where_clauses.append("LOWER(COALESCE(m.member_type, 'corporate')) = %s"); params.append(member_type)
            where_sql = ('WHERE ' + ' AND '.join(where_clauses)) if where_clauses else ''

            cursor.execute(
                f"""SELECT COUNT(DISTINCT ca.id) AS cnt 
                    FROM compliance_applications ca 
                    JOIN members m ON m.id = ca.member_id 
                    {where_sql}""",
                list(params)
            )
            total = cursor.fetchone()['cnt']

            cursor.execute(f"""
                SELECT ca.id, ca.member_id, ca.type, ca.status,
                       ca.payment_ref, ca.payment_amount, ca.payment_confirmed_at,
                       ca.created_at, ca.updated_at, ca.admin_note,
                       m.name AS member_name, m.email AS member_email,
                       m.company AS member_company,
                       COALESCE(m.member_type, 'corporate') AS member_type,
                       COUNT(cd.id)                                           AS docs_total,
                       COUNT(cd.id) FILTER (WHERE cd.file_url IS NOT NULL)    AS docs_uploaded,
                       COUNT(cd.id) FILTER (WHERE cd.status = 'approved')     AS docs_approved,
                       COUNT(cd.id) FILTER (WHERE cd.status = 'rejected')     AS docs_rejected
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                LEFT JOIN compliance_documents cd ON cd.application_id = ca.id
                {where_sql}
                GROUP BY ca.id, m.name, m.email, m.company, m.member_type
                ORDER BY ca.created_at DESC
                LIMIT %s OFFSET %s
            """, list(params) + [per_page, offset])
            apps = cursor.fetchall()

        resp = {'applications': [dict(a) for a in apps], 'total': total, 'page': page, 'per_page': per_page}
        try:
            cache.set(cache_key, resp, timeout=10)
        except Exception:
            pass
        return jsonify(resp), 200
    except Exception as e:
        logger.exception('[Compliance] admin_list_applications error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>', methods=['GET'])
@sub_admin_required('members')
def admin_get_application(app_id):
    """Full detail: application + member info + all documents."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("""
                SELECT ca.*, m.name AS member_name, m.email AS member_email,
                       m.company AS member_company, m.phone AS member_phone
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s
            """, (app_id,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404
            docs = _build_doc_list(app_id, app['type'], cursor, is_admin=True)

            # Also fetch all linked payments / installments
            cursor.execute("""
                SELECT p.id, p.id as tx_id, p.amount, p.description, p.status,
                       COALESCE(p.payment_method, 'bank') as payment_method,
                       p.payment_ref, p.receipt_url, p.bank_name, p.account_name,
                       p.account_number, p.notes, p.created_at, p.paid_at, p.verified_at,
                       p.is_installment, p.installment_number
                FROM payments p
                WHERE p.application_id = %s
                   OR (p.payment_ref IS NOT NULL AND p.payment_ref = %s)
                   OR (p.member_id = %s AND (p.description ILIKE '%%renewal%%' OR p.description ILIKE '%%compliance%%' OR p.description ILIKE '%%dues%%'))
                ORDER BY p.created_at ASC
            """, (app_id, app.get('payment_ref'), app.get('member_id')))
            all_payments = [dict(r) for r in cursor.fetchall()]
            for p_rec in all_payments:
                if p_rec.get('created_at'):
                    p_rec['date'] = p_rec['created_at'].isoformat()
            payment_record = all_payments[-1] if all_payments else None
            pay_dict = payment_record

            app_dict = dict(app)
            confirmed_paid = sum(float(p['amount']) for p in all_payments if str(p.get('status', '')).lower() in ('paid', 'completed', 'success', 'successful'))
            app_dict['amount_paid'] = confirmed_paid if confirmed_paid > 0 else float(app.get('amount_paid') or 0.0)
            tot_amt = float(app.get('payment_amount') or 0.0)
            app_dict['balance_due'] = max(0.0, tot_amt - app_dict['amount_paid'])
            app_dict['installments'] = all_payments

        return jsonify({'application': app_dict, 'documents': docs, 'payment': pay_dict, 'installments': all_payments}), 200
    except Exception as e:
        logger.exception('[Compliance] admin_get_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/doc/<int:doc_id>/status', methods=['PUT'])
@sub_admin_required('members')
def admin_update_doc_status(app_id, doc_id):
    """Approve or reject a single document. If all docs are approved, auto-transition application to awaiting_bill."""
    admin_id = get_jwt_identity()
    data     = request.get_json() or {}
    status   = data.get('status', '').strip()
    note     = data.get('note', '').strip()
    if status not in ('approved', 'rejected'):
        return jsonify({'message': 'status must be "approved" or "rejected"'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE compliance_documents
                SET status = %s, admin_note = %s, reviewed_at = NOW(), reviewed_by = %s
                WHERE id = %s AND application_id = %s
            """, (status, note or None, admin_id, doc_id, app_id))

            # If this document is a bank deposit slip, also sync the corresponding payment record
            post_mark_pay_id = None
            cursor.execute("SELECT requirement, file_url, file_name FROM compliance_documents WHERE id = %s", (doc_id,))
            doc_meta = cursor.fetchone()
            if doc_meta and doc_meta.get('requirement') == 'bank_deposit_slip':
                cursor.execute("SELECT member_id, payment_ref FROM compliance_applications WHERE id = %s", (app_id,))
                app_meta = cursor.fetchone()
                app_pref = app_meta.get('payment_ref') if app_meta else None
                app_mid = app_meta.get('member_id') if app_meta else None
                doc_url = doc_meta.get('file_url') or ''
                doc_name = doc_meta.get('file_name') or ''

                cursor.execute("""
                    SELECT id FROM payments
                    WHERE (
                        (%s IS NOT NULL AND %s != '' AND payment_ref = %s)
                        OR (%s != '' AND receipt_url IS NOT NULL AND (receipt_url = %s OR receipt_url LIKE %s))
                        OR (application_id = %s)
                        OR (%s IS NOT NULL AND member_id = %s AND payment_method = 'bank_deposit')
                    )
                    ORDER BY id DESC LIMIT 1
                """, (app_pref, app_pref, app_pref, doc_url, doc_url, f"%{doc_name}%", app_id, app_mid, app_mid))
                matched_pay = cursor.fetchone()
                if matched_pay:
                    pay_id = matched_pay['id']
                    if status == 'approved':
                        cursor.execute("""
                            UPDATE payments
                            SET verified_by = %s, verified_at = NOW(), status = 'paid', paid_at = NOW()
                            WHERE id = %s
                        """, (admin_id, pay_id))
                        if app_mid:
                            cursor.execute("""
                                UPDATE members 
                                SET package_fee_paid = TRUE, good_standing = TRUE 
                                WHERE id = %s
                            """, (app_mid,))
                        post_mark_pay_id = pay_id
                    elif status == 'rejected':
                        cursor.execute("""
                            UPDATE payments
                            SET verified_by = %s, verified_at = NOW(), status = 'rejected', notes = %s
                            WHERE id = %s
                        """, (admin_id, note or 'Bank deposit receipt rejected by admin', pay_id))

            # Check if all documents for this application are now approved
            cursor.execute("""
                SELECT COUNT(*) AS total_docs,
                       COUNT(*) FILTER (WHERE status = 'approved') AS approved_docs,
                       COUNT(*) FILTER (WHERE status = 'rejected') AS rejected_docs,
                       COUNT(*) FILTER (WHERE status = 'pending') AS pending_docs
                FROM compliance_documents
                WHERE application_id = %s
            """, (app_id,))
            doc_counts = cursor.fetchone()

            cursor.execute("SELECT status, payment_amount, member_id FROM compliance_applications WHERE id = %s", (app_id,))
            current_app = cursor.fetchone()

            if doc_counts and doc_counts['total_docs'] > 0 and doc_counts['total_docs'] == doc_counts['approved_docs']:
                # All documents approved! If bill already issued -> awaiting_payment; otherwise -> awaiting_bill
                new_app_status = 'awaiting_payment' if current_app and current_app.get('payment_amount') else 'awaiting_bill'
                cursor.execute("""
                    UPDATE compliance_applications
                    SET status = %s, updated_at = NOW()
                    WHERE id = %s AND status NOT IN ('approved', 'rejected')
                """, (new_app_status, app_id))

            conn.commit()
            log_admin_action(admin_id, f'Compliance Doc {status.capitalize()}', target_type='compliance_document', target_id=doc_id, details={'application_id': app_id, 'status': status, 'note': note})

            if post_mark_pay_id:
                try:
                    from routes.payments import _mark_payment_as_paid
                    _mark_payment_as_paid(post_mark_pay_id)
                except Exception as p_ex:
                    logger.warning(f"[Compliance Doc Status] _mark_payment_as_paid failed: {p_ex}")

            try:
                from socket_instance import socketio
                socketio.emit('compliance_updated', {'application_id': app_id, 'doc_id': doc_id, 'doc_status': status})
                if current_app:
                    socketio.emit('tasks_updated', {'member_id': current_app['member_id']})
            except Exception:
                pass

        return jsonify({'message': f'Document {status}'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/request-revision', methods=['POST'])
@sub_admin_required('members')
def admin_request_revision(app_id):
    """
    FIX #1: Sends the application back to the member with specific notes on what
    needs to be fixed, WITHOUT full rejection. The member re-uploads only rejected
    docs and re-submits. No repayment required.
    """
    admin_id = get_jwt_identity()
    data     = request.get_json() or {}
    note     = data.get('note', '').strip()

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT ca.member_id, ca.type, ca.status, m.fcm_token, m.email, m.name
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s
            """, (app_id,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404

            cursor.execute("""
                UPDATE compliance_applications
                SET status = 'revision_requested', admin_note = %s, reviewed_by = %s,
                    reviewed_at = NOW(), updated_at = NOW()
                WHERE id = %s
            """, (note or None, admin_id, app_id))
            conn.commit()
            log_admin_action(admin_id, 'Compliance Revision Requested', target_type='compliance_application', target_id=app_id, details={'note': note})

            type_label = 'License Renewal' if app['type'] == 'renewal' else 'Member ID Application'
            fcm_token, email, name = app.get('fcm_token'), app.get('email', ''), app.get('name', '')

        # FIX #5: Push notification + email
        send_push_notification(
            fcm_token,
            title='Revision Required 📋',
            body=f'Your {type_label} requires updates. Please review the admin notes and resubmit.',
            data={'screen': 'compliance', 'application_id': str(app_id)}
        )
        _send_compliance_email(
            email, name,
            subject=f'CUBAG — Action Required: {type_label} Revision',
            body_html=f"""
            <p>Your <strong>{type_label}</strong> application (Ref: CUBAG-COMP-{app_id:05d}) requires revision before it can be approved.</p>
            <p><strong>Admin Notes:</strong></p>
            <blockquote style="border-left:3px solid #f59e0b;padding:10px 16px;background:#fffbeb;border-radius:4px;color:#92400e">
              {note or 'Please review your uploaded documents and resubmit.'}
            </blockquote>
            <p>Please log in to the CUBAG portal, update the flagged documents, and resubmit. <strong>No additional payment is required.</strong></p>
            """
        )

        return jsonify({'message': 'Revision requested. Member has been notified.'}), 200
    except Exception as e:
        logger.exception('[Compliance] admin_request_revision error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/set-bill', methods=['POST'])
@sub_admin_required('members')
def admin_set_application_bill(app_id):
    """Set or update the itemized fee breakdown, total payment amount, and payment deadline for a compliance application."""
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    fee_breakdown = data.get('fee_breakdown')
    payment_deadline = data.get('payment_deadline')
    bill_title = str(data.get('bill_title') or '').strip()
    if not bill_title:
        bill_title = 'Annual Renewal Dues'

    if not fee_breakdown or not isinstance(fee_breakdown, list):
        return jsonify({'message': 'fee_breakdown list is required'}), 400
    if not payment_deadline:
        return jsonify({'message': 'payment_deadline is required'}), 400

    total_amount = 0.0
    for item in fee_breakdown:
        try:
            amt = float(str(item.get('amount', 0)).replace(',', ''))
            if amt < 0:
                return jsonify({'message': 'Fee amount cannot be negative'}), 400
            total_amount += amt
        except (TypeError, ValueError):
            return jsonify({'message': 'Invalid fee amount in breakdown'}), 400

    allow_installments = data.get('allow_installments', True)
    if isinstance(allow_installments, str):
        allow_installments = allow_installments.lower() in ('true', '1', 'yes')
    else:
        allow_installments = bool(allow_installments)

    try:
        min_installment_amount = float(str(data.get('min_installment_amount', 0.0)).replace(',', ''))
        if min_installment_amount < 0:
            min_installment_amount = 0.0
    except (TypeError, ValueError):
        min_installment_amount = 0.0

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("""
                SELECT ca.id, ca.member_id, ca.status, ca.amount_paid, m.email, m.name, m.fcm_token
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s
            """, (app_id,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404

            import json
            breakdown_json = json.dumps(fee_breakdown)

            cursor.execute("""
                UPDATE compliance_applications
                SET payment_amount = %s,
                    payment_deadline = %s,
                    fee_breakdown = %s,
                    bill_title = %s,
                    allow_installments = %s,
                    min_installment_amount = %s,
                    status = CASE 
                        WHEN status IN ('approved', 'payment_confirmed') THEN status 
                        WHEN COALESCE(amount_paid, 0) > 0 AND COALESCE(amount_paid, 0) < %s THEN 'partially_paid'
                        ELSE 'awaiting_payment' 
                    END,
                    updated_at = NOW()
                WHERE id = %s
            """, (total_amount, payment_deadline, breakdown_json, bill_title, allow_installments, min_installment_amount, total_amount, app_id))

            # Sync renewal fee to member profile so /payments and membership services get the exact bill
            cursor.execute("""
                UPDATE members
                SET renewal_fee_amount = %s,
                    renewal_fee_breakdown = %s,
                    renewal_fee_title = %s
                WHERE id = %s
            """, (total_amount, breakdown_json, bill_title, app['member_id']))

            conn.commit()
            cache.delete(f'me_{app["member_id"]}')
            log_admin_action(admin_id, 'Issued Compliance Bill', target_type='compliance_application', target_id=app_id, details={'amount': total_amount, 'deadline': payment_deadline})

            member_email = app.get('email')
            member_name = app.get('name', 'Member')
            fcm_token = app.get('fcm_token')

            # Send Push Notification
            if fcm_token:
                send_push_notification(
                    fcm_token,
                    title='New Renewal Bill Issued 💳',
                    body=f'An official renewal bill of GHS {total_amount:,.2f} has been issued. Payment deadline: {payment_deadline}.',
                    data={'screen': 'compliance', 'type': 'payment', 'route': '/payments?fee=Annual%20Renewal%20Dues'}
                )

            if member_email:
                body_html = f"""
                <div style="font-family:Arial,sans-serif;padding:20px;color:#333;">
                    <h2>New Renewal Bill Issued</h2>
                    <p>Dear {member_name},</p>
                    <p>Your renewal application documents have been reviewed and an official bill has been issued by the CUBAG Secretariat.</p>
                    <p><strong>Total Amount Due: GHS {total_amount:.2f}</strong></p>
                    <p><strong>Payment Deadline: {payment_deadline}</strong></p>
                    <p>Please log in to the CUBAG portal to view your itemized fee breakdown and complete your payment.</p>
                </div>
                """
                _send_compliance_email(member_email, member_name, 'New Renewal Bill Issued - CUBAG', body_html)

            try:
                from socket_instance import socketio
                socketio.emit('renewal_bill_issued', {
                    'member_id': app['member_id'],
                    'app_id': app_id,
                    'amount': total_amount,
                    'deadline': payment_deadline,
                    'fee_breakdown': fee_breakdown
                })
                socketio.emit('compliance_updated', {
                    'application_id': app_id,
                    'status': 'awaiting_payment',
                    'member_id': app['member_id']
                })
                socketio.emit('tasks_updated', {'member_id': app['member_id']})
                socketio.emit('member_updated', {'member_id': app['member_id']})
                socketio.emit('fees_updated', {'member_id': app['member_id']})
            except Exception:
                pass

            return jsonify({
                'message': 'Bill issued successfully',
                'payment_amount': total_amount,
                'payment_deadline': payment_deadline,
                'fee_breakdown': fee_breakdown
            }), 200
    except Exception as e:
        logger.exception('[Compliance] admin_set_application_bill error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/approve', methods=['POST'])
@sub_admin_required('members')
def admin_approve_application(app_id):
    """Approve the entire compliance application and notify the member."""
    admin_id = get_jwt_identity()
    data     = request.get_json() or {}
    note     = data.get('note', '').strip()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT ca.member_id, ca.type, m.fcm_token, m.email, m.name
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s
            """, (app_id,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404

            cursor.execute("""
                UPDATE compliance_documents
                SET status = 'approved', reviewed_at = NOW(), reviewed_by = %s
                WHERE application_id = %s AND status = 'pending'
            """, (admin_id, app_id))

            cursor.execute("""
                UPDATE compliance_applications
                SET status = 'approved', admin_note = %s, reviewed_by = %s,
                    reviewed_at = NOW(), updated_at = NOW()
                WHERE id = %s
            """, (note or None, admin_id, app_id))

            # ── Issue License & Activate Member ──
            mid = app['member_id']
            cursor.execute("SELECT license_number, license_expiry_date FROM members WHERE id = %s", (mid,))
            m_row = cursor.fetchone()
            from datetime import datetime, timedelta
            year = datetime.now().year
            lic_num = m_row['license_number'] if m_row and m_row.get('license_number') and \
                str(m_row['license_number']).lower() not in ('none', 'pending', 'n/a', '') \
                else f"CUBAG-LIC-{year}-{mid:04d}"
            
            cur_expiry = m_row.get('license_expiry_date') if m_row else None
            if isinstance(cur_expiry, str):
                try:
                    cur_expiry = datetime.strptime(cur_expiry, '%Y-%m-%d').date()
                except Exception:
                    cur_expiry = None
            today = datetime.now().date()
            if cur_expiry and cur_expiry > today and app.get('type') == 'renewal':
                expiry = cur_expiry + timedelta(days=365)
                start_date = cur_expiry
            else:
                expiry = today + timedelta(days=365)
                start_date = today

            cursor.execute("""
                UPDATE members
                SET status = 'active', license_number = %s, license_expiry_date = %s
                WHERE id = %s
            """, (lic_num, expiry, mid))

            cursor.execute("""
                INSERT INTO license_history (member_id, license_number, start_date, expiry_date, duration_label)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT DO NOTHING
            """, (mid, lic_num, start_date, expiry, '1 Year (Cumulative Renewal)' if app.get('type') == 'renewal' else '1 Year'))

            try:
                cache.delete(f'me_{mid}')
            except Exception:
                pass
            conn.commit()
            log_admin_action(admin_id, 'Approved Compliance Application', target_type='compliance_application', target_id=app_id, details={'type': app.get('type'), 'license_number': lic_num, 'note': note})

            type_label = 'License Renewal' if app['type'] == 'renewal' else 'Member ID Application'
            fcm_token, email, name = app.get('fcm_token'), app.get('email', ''), app.get('name', '')

        # FIX #5: Push + email on approval
        send_push_notification(
            fcm_token,
            title='Application Approved! ✅',
            body=f'Your {type_label} has been approved by CUBAG. Your compliance certificate is ready.',
            data={'screen': 'compliance', 'application_id': str(app_id)}
        )
        _send_compliance_email(
            email, name,
            subject=f'CUBAG — {type_label} Approved ✅',
            body_html=f"""
            <p>Congratulations! Your <strong>{type_label}</strong> application 
            (Ref: CUBAG-COMP-{app_id:05d}) has been <strong style="color:#10b981">approved</strong>.</p>
            {f'<p><em>{note}</em></p>' if note else ''}
            <p>You can download your compliance certificate from the CUBAG portal under <strong>Compliance Centre</strong>.</p>
            """
        )

        try:
            from socket_instance import socketio
            socketio.emit('compliance_updated', {'application_id': app_id, 'status': 'approved'})
            socketio.emit('tasks_updated', {})
        except Exception:
            pass
        return jsonify({'message': 'Application approved'}), 200
    except Exception as e:
        logger.exception('[Compliance] admin_approve_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/reject', methods=['POST'])
@sub_admin_required('members')
def admin_reject_application(app_id):
    """Reject the entire compliance application and notify the member."""
    admin_id = get_jwt_identity()
    data     = request.get_json() or {}
    note     = data.get('note', '').strip()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT ca.member_id, ca.type, m.fcm_token, m.email, m.name
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s
            """, (app_id,))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Application not found'}), 404

            cursor.execute("""
                UPDATE compliance_applications
                SET status = 'rejected', admin_note = %s, reviewed_by = %s,
                    reviewed_at = NOW(), updated_at = NOW()
                WHERE id = %s
            """, (note or None, admin_id, app_id))
            conn.commit()
            log_admin_action(admin_id, 'Rejected Compliance Application', target_type='compliance_application', target_id=app_id, details={'type': app.get('type'), 'note': note})

            type_label = 'License Renewal' if app['type'] == 'renewal' else 'Member ID Application'
            fcm_token, email, name = app.get('fcm_token'), app.get('email', ''), app.get('name', '')

        # FIX #5: Push + email on rejection
        send_push_notification(
            fcm_token,
            title='Application Rejected',
            body=f'Your {type_label} was not approved. Please review the admin notes in the Compliance Centre.',
            data={'screen': 'compliance', 'application_id': str(app_id)}
        )
        _send_compliance_email(
            email, name,
            subject=f'CUBAG — {type_label} Not Approved',
            body_html=f"""
            <p>We regret to inform you that your <strong>{type_label}</strong> application 
            (Ref: CUBAG-COMP-{app_id:05d}) has been <strong style="color:#ef4444">rejected</strong>.</p>
            <p><strong>Reason:</strong></p>
            <blockquote style="border-left:3px solid #ef4444;padding:10px 16px;background:#fef2f2;border-radius:4px;color:#991b1b">
              {note or 'Please contact the CUBAG Secretariat for more information.'}
            </blockquote>
            <p>You may submit a new application once the issues have been resolved.</p>
            """
        )

        try:
            from socket_instance import socketio
            socketio.emit('compliance_updated', {'application_id': app_id, 'status': 'rejected'})
            socketio.emit('tasks_updated', {})
        except Exception:
            pass
        return jsonify({'message': 'Application rejected'}), 200
    except Exception as e:
        logger.exception('[Compliance] admin_reject_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/stats', methods=['GET'])
@sub_admin_required('members')
def admin_stats():
    """Quick stats counts including revision_requested for the badge counter."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("""
                SELECT
                    COUNT(*) FILTER (WHERE type = 'renewal'         AND status = 'under_review')        AS renewal_pending,
                    COUNT(*) FILTER (WHERE type = 'customs_licence' AND status = 'under_review')        AS customs_pending,
                    COUNT(*) FILTER (WHERE status = 'under_review')                                     AS total_under_review,
                    COUNT(*) FILTER (WHERE status = 'revision_requested')                               AS total_revision_requested,
                    COUNT(*) FILTER (WHERE status = 'approved')                                         AS total_approved,
                    COUNT(*) FILTER (WHERE status = 'rejected')                                         AS total_rejected,
                    COUNT(*)                                                                             AS total
                FROM compliance_applications
            """)
            stats = cursor.fetchone()
        return jsonify(dict(stats)), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
