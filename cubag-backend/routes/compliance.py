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
import resend
from datetime import datetime
from flask import Blueprint, jsonify, request, Response
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from config.cache import cache
from utils import sub_admin_required, send_push_notification

logger = logging.getLogger(__name__)
compliance_bp = Blueprint('compliance', __name__)

# ── Supabase ──────────────────────────────────────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

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
# NOTE: 'approved' is intentionally excluded so members can start a new renewal cycle.
ACTIVE_STATUSES = ('draft', 'submitted', 'payment_pending', 'payment_confirmed', 'under_review', 'revision_requested')


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
        # Table already exists — skip all DDL, mark as verified
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
                payment_confirmed_at    TIMESTAMP,
                admin_note              TEXT,
                reviewed_by             INTEGER,
                reviewed_at             TIMESTAMP,
                created_at              TIMESTAMP DEFAULT NOW(),
                updated_at              TIMESTAMP DEFAULT NOW()
            )
        """)
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


def _build_doc_list(app_id, app_type, cursor):
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
        return jsonify({'applications': [dict(a) for a in apps]}), 200
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
        return jsonify({'application': dict(app), 'documents': docs}), 200
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
    if not SUPABASE_URL or not SUPABASE_KEY:
        return jsonify({'message': 'Cloud storage not configured'}), 500

    safe_name  = f"compliance/{member_id}/{app_id}/{requirement}_{uuid.uuid4().hex}.{ext}"
    public_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{safe_name}"
    upload_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"

    return jsonify({
        'upload_url':   upload_url,
        'public_url':   public_url,
        'safe_name':    safe_name,
        'supabase_key': SUPABASE_KEY,
    }), 200


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
                return jsonify({'message': 'Application submitted. Please proceed to payment.', 'next_step': 'payment'}), 200

    except Exception as e:
        logger.exception('[Compliance] submit_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/applications/<int:app_id>/payment-fee', methods=['GET'])
@jwt_required()
def get_payment_fee(app_id):
    """Return the payment fee from compliance_settings or a sensible default."""
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


@compliance_bp.route('/applications/<int:app_id>/certificate', methods=['GET'])
def get_certificate(app_id):
    """
    FIX #6: Returns an HTML approval certificate.
    Authentication via ?token=<jwt> query param so launchUrl() works without
    Authorization headers (standard browser navigation strips custom headers).
    """
    from flask_jwt_extended import decode_token
    token = request.args.get('token', '').strip()
    if not token:
        return jsonify({'message': 'token query parameter is required'}), 401
    try:
        decoded   = decode_token(token)
        member_id = int(decoded.get('sub', 0))
    except Exception:
        return jsonify({'message': 'Invalid or expired token'}), 401

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT ca.*, m.name AS member_name, m.email AS member_email,
                       m.company AS member_company, m.license_number
                FROM compliance_applications ca
                JOIN members m ON m.id = ca.member_id
                WHERE ca.id = %s AND ca.member_id = %s AND ca.status = 'approved'
            """, (app_id, member_id))
            app = cursor.fetchone()
            if not app:
                return jsonify({'message': 'Approved application not found'}), 404

    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

    type_label  = 'License Renewal' if app['type'] == 'renewal' else 'Member ID Application'
    issued_date = datetime.now().strftime('%d %B %Y')
    reviewed_at = ''
    if app.get('reviewed_at'):
        try:
            reviewed_at = datetime.fromisoformat(str(app['reviewed_at'])).strftime('%d %B %Y')
        except Exception:
            reviewed_at = str(app['reviewed_at'])

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>CUBAG Compliance Certificate — {app['member_company'] or app['member_name']}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700;900&display=swap');
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Outfit', sans-serif; background: #f8fafc; display: flex; justify-content: center; padding: 40px 20px; }}
  .cert {{ background: #fff; border: 2px solid #0f62fe; border-radius: 20px; max-width: 760px; width: 100%; padding: 50px 60px; position: relative; }}
  .cert::before {{ content: ''; position: absolute; inset: 10px; border: 1px solid #0f62fe44; border-radius: 14px; pointer-events: none; }}
  .logo {{ text-align: center; margin-bottom: 8px; }}
  .logo-title {{ font-size: 28px; font-weight: 900; color: #0f62fe; letter-spacing: -1px; }}
  .logo-sub {{ font-size: 13px; color: #64748b; margin-top: 2px; }}
  .divider {{ height: 2px; background: linear-gradient(90deg, transparent, #0f62fe, transparent); margin: 24px 0; }}
  .cert-title {{ text-align: center; font-size: 22px; font-weight: 700; color: #0a0f1e; margin-bottom: 6px; }}
  .cert-subtitle {{ text-align: center; font-size: 14px; color: #64748b; margin-bottom: 32px; }}
  .awarded-to {{ text-align: center; font-size: 14px; color: #64748b; margin-bottom: 6px; }}
  .member-name {{ text-align: center; font-size: 30px; font-weight: 900; color: #0f62fe; margin-bottom: 4px; }}
  .member-company {{ text-align: center; font-size: 16px; color: #475569; margin-bottom: 32px; }}
  .details {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 32px; }}
  .detail-box {{ background: #f8fafc; border-radius: 10px; padding: 14px 18px; border: 1px solid #e2e8f0; }}
  .detail-label {{ font-size: 11px; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; }}
  .detail-value {{ font-size: 14px; font-weight: 600; color: #0a0f1e; }}
  .approved-badge {{ text-align: center; background: #d1fae5; border: 1px solid #10b981; border-radius: 50px; padding: 10px 24px; display: inline-block; margin: 0 auto 32px; }}
  .approved-badge-text {{ color: #059669; font-weight: 800; font-size: 14px; letter-spacing: 0.5px; }}
  .center {{ text-align: center; }}
  .note {{ text-align: center; font-size: 12px; color: #94a3b8; margin-top: 24px; }}
  .seal {{ font-size: 64px; line-height: 1; }}
  @media print {{ body {{ background: #fff; padding: 0; }} .cert {{ border-radius: 0; border: none; box-shadow: none; }} }}
</style>
</head>
<body>
<div class="cert">
  <div class="logo">
    <div class="logo-title">CUBAG</div>
    <div class="logo-sub">Customs Brokers and Freight Forwarders Association of Ghana</div>
  </div>
  <div class="divider"></div>
  <div class="cert-title">Certificate of Compliance</div>
  <div class="cert-subtitle">{type_label}</div>
  <div class="awarded-to">This is to certify that</div>
  <div class="member-name">{app['member_name']}</div>
  <div class="member-company">{app['member_company'] or ''}</div>
  <div class="center">
    <div class="approved-badge">
      <div class="approved-badge-text">✓ APPROVED</div>
    </div>
  </div>
  <div class="details">
    <div class="detail-box">
      <div class="detail-label">Application Type</div>
      <div class="detail-value">{type_label}</div>
    </div>
    <div class="detail-box">
      <div class="detail-label">Application Reference</div>
      <div class="detail-value">CUBAG-COMP-{app_id:05d}</div>
    </div>
    <div class="detail-box">
      <div class="detail-label">Date Approved</div>
      <div class="detail-value">{reviewed_at or issued_date}</div>
    </div>
    <div class="detail-box">
      <div class="detail-label">Certificate Issued</div>
      <div class="detail-value">{issued_date}</div>
    </div>
    {f'<div class="detail-box"><div class="detail-label">License Number</div><div class="detail-value">{app["license_number"]}</div></div>' if app.get("license_number") else ''}
    <div class="detail-box">
      <div class="detail-label">Member Email</div>
      <div class="detail-value">{app['member_email']}</div>
    </div>
  </div>
  <div class="center seal">🏛️</div>
  <div class="note">
    This certificate was electronically issued by the CUBAG Compliance Management System.<br>
    Ref: CUBAG-COMP-{app_id:05d} | Issued: {issued_date}
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
            docs = _build_doc_list(app_id, app['type'], cursor)
        return jsonify({'application': dict(app), 'documents': docs}), 200
    except Exception as e:
        logger.exception('[Compliance] admin_get_application error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@compliance_bp.route('/admin/applications/<int:app_id>/doc/<int:doc_id>/status', methods=['PUT'])
@sub_admin_required('members')
def admin_update_doc_status(app_id, doc_id):
    """Approve or reject a single document."""
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
            conn.commit()
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
            cursor.execute("SELECT license_number FROM members WHERE id = %s", (mid,))
            m_row = cursor.fetchone()
            from datetime import datetime, timedelta
            year = datetime.now().year
            lic_num = m_row['license_number'] if m_row and m_row.get('license_number') and \
                str(m_row['license_number']).lower() not in ('none', 'pending', 'n/a', '') \
                else f"CUBAG-LIC-{year}-{mid:04d}"
            expiry = (datetime.now() + timedelta(days=365)).date()

            cursor.execute("""
                UPDATE members
                SET status = 'active', license_number = %s, license_expiry_date = %s
                WHERE id = %s
            """, (lic_num, expiry, mid))

            cursor.execute("""
                INSERT INTO license_history (member_id, license_number, start_date, expiry_date, duration_label)
                VALUES (%s, %s, CURRENT_DATE, %s, '1 Year')
                ON CONFLICT DO NOTHING
            """, (mid, lic_num, expiry))

            try:
                cache.delete(f'me_{mid}')
            except Exception:
                pass
            conn.commit()

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
