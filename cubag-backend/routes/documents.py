import os
import uuid
import requests
import logging
from datetime import datetime
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from config.cache import cache
from utils import sub_admin_required

logger = logging.getLogger(__name__)
documents_bp = Blueprint('documents', __name__)

# ── Supabase (reuse same bucket as uploads.py) ────────────────────────────────
SUPABASE_URL    = os.getenv('SUPABASE_URL', '').strip().strip('\'"')
SUPABASE_KEY    = os.getenv('SUPABASE_SERVICE_KEY', '').strip().strip('\'"')
SUPABASE_BUCKET = os.getenv('SUPABASE_BUCKET', 'uploads').strip().strip('\'"')

ALLOWED_EXTENSIONS = {'pdf', 'png', 'jpg', 'jpeg'}
MAX_SIZE_MB = 15


def _allowed(filename: str) -> bool:
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


_table_ready = False  # module-level guard: only create table once

def _ensure_table(cursor):
    """Create member_documents and document_requirements tables if they don't exist yet."""
    global _table_ready
    if _table_ready:
        return
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS document_requirements (
            id           SERIAL PRIMARY KEY,
            key          VARCHAR(100) NOT NULL,
            label        TEXT NOT NULL,
            description  TEXT,
            member_type  VARCHAR(50) DEFAULT 'corporate',
            application_type VARCHAR(50) DEFAULT 'new',
            is_required  BOOLEAN DEFAULT TRUE,
            display_order INTEGER DEFAULT 0,
            is_active    BOOLEAN DEFAULT TRUE,
            deleted_at   TIMESTAMP DEFAULT NULL,
            created_at   TIMESTAMP DEFAULT NOW()
        )
    """)
    cursor.execute("ALTER TABLE document_requirements ADD COLUMN IF NOT EXISTS member_type VARCHAR(50) DEFAULT 'corporate';")
    cursor.execute("ALTER TABLE document_requirements ADD COLUMN IF NOT EXISTS application_type VARCHAR(50) DEFAULT 'new';")
    cursor.execute("ALTER TABLE document_requirements ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;")
    cursor.execute("ALTER TABLE document_requirements DROP CONSTRAINT IF EXISTS document_requirements_key_key;")
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS member_documents (
            id           SERIAL PRIMARY KEY,
            member_id    INTEGER NOT NULL,
            requirement  VARCHAR(100) NOT NULL,
            label        TEXT NOT NULL,
            file_url     TEXT,
            file_name    TEXT,
            file_size    INTEGER,
            status       VARCHAR(20) NOT NULL DEFAULT 'pending',
            admin_note   TEXT,
            uploaded_at  TIMESTAMP DEFAULT NOW(),
            reviewed_at  TIMESTAMP,
            reviewed_by  INTEGER
        )
    """)
    cursor.connection.commit()
    _table_ready = True


def _get_active_requirements(cursor, member_type='corporate', application_type='new'):
    _ensure_table(cursor)
    raw_m = (member_type or 'corporate').strip().lower()
    if 'licentiate' in raw_m or 'individual' in raw_m:
        m_type = 'licentiate'
    elif 'associate' in raw_m or 'affiliate' in raw_m:
        m_type = 'associate'
    else:
        m_type = 'corporate'

    a_type = (application_type or 'new').strip().lower()
    if 'renewal' in a_type:
        a_type = 'renewal'
    else:
        a_type = 'new'

    cursor.execute("""
        SELECT id, key, label, description, member_type, application_type, is_required, display_order
        FROM document_requirements
        WHERE is_active = TRUE AND deleted_at IS NULL
          AND LOWER(member_type) = %s AND LOWER(application_type) = %s
        ORDER BY display_order ASC, id ASC
    """, (m_type, a_type))
    rows = cursor.fetchall()
    return [dict(r) for r in rows] if rows else []


# ─────────────────────────────────────────────────────────────────────────────
# MEMBER ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────────

@documents_bp.route('/requirements', methods=['GET'])
@jwt_required()
def get_requirements():
    """Return the list of required documents and the member's upload status for each."""
    member_id = get_jwt_identity()

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT status, fee_category, member_scale, member_type, company FROM members WHERE id = %s", (member_id,))
            mem_row = cursor.fetchone()
            member_status = mem_row['status'] if mem_row else 'pending'
            raw_member_type = (mem_row.get('member_type') if mem_row else '') or 'corporate'
            m_type_clean = raw_member_type.strip().lower()
            if 'licentiate' in m_type_clean or 'individual' in m_type_clean:
                m_type_clean = 'licentiate'
            elif 'associate' in m_type_clean or 'affiliate' in m_type_clean:
                m_type_clean = 'associate'
            else:
                m_type_clean = 'corporate'

            fee_cat = (mem_row.get('fee_category') if mem_row else '') or 'cf_only'
            member_scale = str(mem_row.get('member_scale') or 'sme').lower().strip() if mem_row else 'sme'
            is_large = member_scale in ('large_corporate', 'large', 'corporate')

            req_list = _get_active_requirements(cursor, member_type=m_type_clean, application_type='new')

            cursor.execute(
                "SELECT requirement, file_url, file_name, status, admin_note, uploaded_at "
                "FROM member_documents WHERE member_id = %s",
                (member_id,)
            )
            rows = cursor.fetchall()
            uploaded = {r['requirement']: r for r in rows}

            # Dynamically query all active fees from fee_schedules
            cursor.execute("SELECT key, amount, name, description FROM fee_schedules WHERE is_active = TRUE")
            sched_map = {r['key']: r for r in cursor.fetchall()}

            def get_fee_amt(key, default_amt='0.00'):
                row = sched_map.get(key)
                if row and row.get('amount') is not None:
                    return f"{float(row['amount']):.2f}"
                return default_amt

            if m_type_clean == 'licentiate':
                cat_title = 'LICENTIATE MEMBERSHIP'
                upfront_reg_fee = get_fee_amt('licentiate_reg_form_fee', '0.00')
                sub_amt = get_fee_amt('licentiate_sub_fee', '0.00')
                vetting_amt = get_fee_amt('licentiate_vetting_fee', '0.00')
                district_amt = get_fee_amt('licentiate_district_fee', '0.00')
                welfare_amt = get_fee_amt('licentiate_welfare_dues', '0.00')
                legal_amt = get_fee_amt('licentiate_legal_audit_fee', '0.00')
                agm_amt = get_fee_amt('licentiate_agm_levy', '0.00')

                breakdown = [
                    {'label': 'Subscription Fee', 'amount': sub_amt, 'frequency': 'Annual'},
                    {'label': 'Vetting Fee', 'amount': vetting_amt, 'frequency': 'Annual'},
                    {'label': 'District Dues', 'amount': district_amt, 'frequency': 'Annual'},
                    {'label': 'Welfare Dues', 'amount': welfare_amt, 'frequency': 'Annual'},
                    {'label': 'Legal & Audit Fee', 'amount': legal_amt, 'frequency': 'Annual'},
                    {'label': 'AGM Levy', 'amount': agm_amt, 'frequency': 'Annual'},
                ]
                sched_row = sched_map.get('licentiate_package')
                if sched_row and sched_row.get('amount') is not None:
                    package_fee_amount = f"{float(sched_row['amount']):.2f}"
                else:
                    package_fee_amount = f"{sum(float(x['amount']) for x in breakdown):.2f}"

            elif m_type_clean == 'associate':
                cat_title = 'ASSOCIATE MEMBERSHIP'
                upfront_reg_fee = get_fee_amt('associate_reg_form_fee', '0.00')
                sub_amt = get_fee_amt('associate_sub_fee', '0.00')
                vetting_amt = get_fee_amt('associate_vetting_fee', '0.00')
                district_amt = get_fee_amt('associate_district_fee', '0.00')
                welfare_amt = get_fee_amt('associate_welfare_dues', '0.00')
                legal_amt = get_fee_amt('associate_legal_audit_fee', '0.00')
                agm_amt = get_fee_amt('associate_agm_levy', '0.00')

                breakdown = [
                    {'label': 'Subscription Fee', 'amount': sub_amt, 'frequency': 'Annual'},
                    {'label': 'Vetting Fee', 'amount': vetting_amt, 'frequency': 'Annual'},
                    {'label': 'District Dues', 'amount': district_amt, 'frequency': 'Annual'},
                    {'label': 'Welfare Dues', 'amount': welfare_amt, 'frequency': 'Annual'},
                    {'label': 'Legal & Audit Fee', 'amount': legal_amt, 'frequency': 'Annual'},
                    {'label': 'AGM Levy', 'amount': agm_amt, 'frequency': 'Annual'},
                ]
                sched_row = sched_map.get('associate_package')
                if sched_row and sched_row.get('amount') is not None:
                    package_fee_amount = f"{float(sched_row['amount']):.2f}"
                else:
                    package_fee_amount = f"{sum(float(x['amount']) for x in breakdown):.2f}"

            else:
                if is_large:
                    if fee_cat == 'cf_only':
                        schedule_key = 'new_large_cf_only'
                        cat_title = 'CLEARING & FORWARDING ONLY (LARGE CORPORATE)'
                    elif fee_cat == 'consolidation':
                        schedule_key = 'new_large_consolidation'
                        cat_title = 'CONSOLIDATION (LARGE CORPORATE)'
                    else:
                        schedule_key = 'new_large_cf_consolidation'
                        cat_title = 'CONSOLIDATION, CLEARING & FORWARDING (LARGE CORPORATE)'
                else:
                    if fee_cat == 'cf_only':
                        schedule_key = 'new_cf_only'
                        cat_title = 'CLEARING & FORWARDING ONLY (SMEs)'
                    elif fee_cat == 'consolidation':
                        schedule_key = 'new_consolidation'
                        cat_title = 'CONSOLIDATION (SMEs)'
                    else:
                        schedule_key = 'new_cf_consolidation'
                        cat_title = 'CONSOLIDATION, CLEARING & FORWARDING (SMEs)'

                sub_amt = get_fee_amt('new_sub_fee', '0.00')
                vetting_amt = get_fee_amt('new_vetting_fee', '0.00')
                district_amt = get_fee_amt('new_district_fee', '0.00')
                cf_amt = get_fee_amt('new_cf_fee', '0.00')
                consol_amt = get_fee_amt('new_consolidation_fee', '0.00')
                upfront_reg_fee = get_fee_amt('reg_form_fee', get_fee_amt('new_reg_fee', '0.00'))

                breakdown = [
                    {'label': 'Subscription Fee', 'amount': sub_amt, 'frequency': 'Annual'},
                    {'label': 'Vetting Fee', 'amount': vetting_amt, 'frequency': 'One-Time'},
                    {'label': 'District', 'amount': district_amt, 'frequency': 'One-Time'},
                ]
                if is_large:
                    corp_scope = f"{(float(consol_amt) + float(cf_amt)):.2f}" if fee_cat == 'cf_consolidation' else (consol_amt if fee_cat == 'consolidation' else cf_amt)
                    breakdown.append({'label': 'Corporate Operational Scope Fee', 'amount': corp_scope, 'frequency': 'Annual'})
                elif fee_cat == 'cf_only':
                    breakdown.append({'label': 'Clearing & Forwarding', 'amount': cf_amt, 'frequency': 'Annual'})
                elif fee_cat == 'consolidation':
                    breakdown.append({'label': 'Consolidation', 'amount': consol_amt, 'frequency': 'Annual'})
                elif fee_cat == 'cf_consolidation':
                    breakdown.append({'label': 'Consolidation', 'amount': consol_amt, 'frequency': 'Annual'})
                    breakdown.append({'label': 'Clearing & Forwarding', 'amount': cf_amt, 'frequency': 'Annual'})

                sched_row = sched_map.get(schedule_key)
                if sched_row and sched_row.get('amount') is not None:
                    package_fee_amount = f"{float(sched_row['amount']):.2f}"
                else:
                    package_fee_amount = f"{sum(float(x['amount']) for x in breakdown):.2f}"

            cursor.execute("""
                SELECT COUNT(*) as cnt FROM payments
                WHERE member_id = %s
                  AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                  AND (
                    LOWER(description) LIKE '%%registration fee%%'
                    OR LOWER(description) LIKE '%%registration%%'
                    OR LOWER(description) LIKE '%%customs licence application fee%%'
                    OR LOWER(description) LIKE '%%customs license application fee%%'
                    OR LOWER(description) LIKE '%%application fee%%'
                    OR LOWER(description) LIKE '%%membership fee%%'
                    OR LOWER(description) LIKE '%%new member%%'
                  )
            """, (member_id,))
            p_row = cursor.fetchone()
            registration_fee_paid = (p_row['cnt'] > 0) if p_row else False

        result = []
        for req in req_list:
            doc = uploaded.get(req['key'])
            result.append({
                'id':          req.get('id'),
                'key':         req['key'],
                'label':       req['label'],
                'description': req.get('description'),
                'is_required': req.get('is_required', True),
                'uploaded':    doc is not None,
                'file_url':    doc['file_url']    if doc else None,
                'file_name':   doc['file_name']   if doc else None,
                'status':      doc['status']       if doc else 'not_uploaded',
                'admin_note':  doc['admin_note']   if doc else None,
                'uploaded_at': str(doc['uploaded_at']) if doc and doc['uploaded_at'] else None,
            })

        total          = len(result)
        uploaded_count = sum(1 for r in result if r['uploaded'])
        all_required_approved = all(
            r['status'] == 'approved' for r in result if r.get('is_required', True)
        )
        if member_status != 'active':
            if all_required_approved and registration_fee_paid:
                member_status = 'active'
            elif all_required_approved:
                member_status = 'approved'

        response_data = {
            'requirements': result,
            'total': total,
            'uploaded': uploaded_count,
            'member_status': member_status,
            'member_type': raw_member_type,
            'registration_fee_paid': registration_fee_paid,
            'application_fee_paid': registration_fee_paid,
            'registration_fee_amount': upfront_reg_fee,
            'package_fee_amount': package_fee_amount,
            'registration_package_amount': package_fee_amount,
            'registration_fee_breakdown': breakdown,
            'fee_category': fee_cat,
            'fee_category_title': cat_title,
        }
        return jsonify(response_data), 200

    except Exception as e:
        logger.exception('[Documents] get_requirements error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/upload', methods=['POST'])
@jwt_required()
def upload_document():
    """Upload a file for a specific requirement key."""
    member_id   = get_jwt_identity()
    requirement = request.form.get('requirement', '').strip()
    label       = request.form.get('label', '').strip()
    file        = request.files.get('file')

    if not requirement:
        return jsonify({'message': 'Requirement key is required'}), 400
    if not file or not file.filename:
        return jsonify({'message': 'No file provided'}), 400
    if not _allowed(file.filename):
        return jsonify({'message': 'Only PDF, PNG, JPG, JPEG files are accepted'}), 400

    # Size check
    file.seek(0, 2)
    size_bytes = file.tell()
    file.seek(0)
    if size_bytes > MAX_SIZE_MB * 1024 * 1024:
        return jsonify({'message': f'File too large. Max {MAX_SIZE_MB}MB.'}), 413

    if not label:
        label = requirement.replace('_', ' ').title()

    ext = file.filename.rsplit('.', 1)[1].lower() if '.' in file.filename else 'pdf'
    file_bytes = file.read()
    content_type = file.content_type or ('application/pdf' if ext == 'pdf' else 'image/jpeg')

    # ── Upload to Supabase with local fallback ──
    public_url = None
    if SUPABASE_URL and SUPABASE_KEY:
        safe_name = f"member_docs/{member_id}/{requirement}_{uuid.uuid4().hex}.{ext}"
        storage_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"
        headers = {
            "apikey":        SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type":  content_type,
            "x-upsert":      "true",
        }
        try:
            resp = requests.post(storage_url, data=file_bytes, headers=headers, timeout=10)
            if resp.status_code in (200, 201):
                public_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{safe_name}"
            else:
                logger.warning("[Documents] Supabase returned status %s: %s", resp.status_code, resp.text)
        except Exception as e:
            logger.warning("[Documents] Supabase upload error/timeout: %s", e)

    # ── Fallback to local static storage if Supabase failed or unconfigured ──
    if not public_url:
        import os
        upload_dir = os.path.join(os.getcwd(), 'static', 'uploads', 'member_docs', str(member_id))
        os.makedirs(upload_dir, exist_ok=True)
        local_filename = f"{requirement}_{uuid.uuid4().hex[:8]}.{ext}"
        local_path = os.path.join(upload_dir, local_filename)
        with open(local_path, 'wb') as f:
            f.write(file_bytes)
        public_url = f"/static/uploads/member_docs/{member_id}/{local_filename}"

    # ── Save / update DB record ──
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            # Upsert: update if already uploaded, insert otherwise
            cursor.execute(
                "SELECT id FROM member_documents WHERE member_id = %s AND requirement = %s",
                (member_id, requirement)
            )
            existing = cursor.fetchone()
            if existing:
                cursor.execute("""
                    UPDATE member_documents
                    SET file_url = %s, file_name = %s, file_size = %s,
                        status = 'pending', admin_note = NULL, uploaded_at = NOW()
                    WHERE id = %s
                """, (public_url, file.filename, size_bytes, existing['id']))
            else:
                cursor.execute("""
                    INSERT INTO member_documents
                        (member_id, requirement, label, file_url, file_name, file_size, status)
                    VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                """, (member_id, requirement, label, public_url, file.filename, size_bytes))
            conn.commit()
        return jsonify({'message': 'Document uploaded successfully', 'file_url': public_url}), 200
    except Exception as e:
        logger.exception('[Documents] upload_document DB error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/sign-upload', methods=['POST'])
@jwt_required()
def sign_upload():
    """
    Returns a signed Supabase URL so Flutter can upload directly to Supabase
    without routing file bytes through Flask. Much faster — one less network hop.
    """
    member_id   = get_jwt_identity()
    data        = request.get_json() or {}
    requirement = data.get('requirement', '').strip()
    label       = data.get('label', '').strip()
    filename    = data.get('filename', 'document').strip()
    ext         = data.get('ext', 'pdf').strip().lower()
    size        = int(data.get('size', 0))

    if not requirement:
        return jsonify({'message': 'Requirement key is required'}), 400
    if ext not in ALLOWED_EXTENSIONS:
        return jsonify({'message': 'Only PDF, PNG, JPG, JPEG files are accepted'}), 400
    if size > MAX_SIZE_MB * 1024 * 1024:
        return jsonify({'message': f'File too large. Max {MAX_SIZE_MB}MB.'}), 413
    if not SUPABASE_URL or not SUPABASE_KEY:
        return jsonify({'message': 'Cloud storage not configured on server.'}), 500

    if not label:
        label = requirement.replace('_', ' ').title()

    safe_name  = f"member_docs/{member_id}/{requirement}_{uuid.uuid4().hex}.{ext}"

    # Supabase signed upload URL (token valid for 60 s — enough for direct upload)
    sign_url = f"{SUPABASE_URL}/storage/v1/object/sign/{SUPABASE_BUCKET}/{safe_name}"
    headers  = {
        "apikey":        SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type":  "application/json",
    }
    try:
        resp = requests.post(sign_url, json={"expiresIn": 120}, headers=headers, timeout=10)
        if resp.status_code not in (200, 201):
            # Fall back: just return the regular object URL so Flutter can PUT directly
            upload_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"
        else:
            signed = resp.json()
            token  = signed.get('token') or signed.get('signedURL', '')
            # Build upload URL from token
            upload_url = (
                f"{SUPABASE_URL}/storage/v1/object/sign/{SUPABASE_BUCKET}/{safe_name}"
                if not token else
                f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"
            )
    except Exception:
        # Fallback: unauthenticated PUT to object URL (still requires service key header from client)
        upload_url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_name}"

    public_url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{safe_name}"
    return jsonify({
        'upload_url': upload_url,
        'public_url': public_url,
        'safe_name':  safe_name,
        'supabase_key': SUPABASE_KEY,   # client needs this to auth the PUT
    }), 200


@documents_bp.route('/confirm-upload', methods=['POST'])
@jwt_required()
def confirm_upload():
    """
    Called by Flutter after a successful direct upload to Supabase.
    Saves the DB record so admin can see the uploaded document.
    """
    member_id   = get_jwt_identity()
    data        = request.get_json() or {}
    requirement = data.get('requirement', '').strip()
    label       = data.get('label', '').strip()
    public_url  = data.get('public_url', '').strip()
    filename    = data.get('filename', '').strip()
    size        = int(data.get('size', 0))

    if not requirement or not public_url:
        return jsonify({'message': 'Missing requirement or public_url'}), 400
    if not label:
        label = requirement.replace('_', ' ').title()

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute(
                "SELECT id FROM member_documents WHERE member_id = %s AND requirement = %s",
                (member_id, requirement)
            )
            existing = cursor.fetchone()
            if existing:
                cursor.execute("""
                    UPDATE member_documents
                    SET file_url = %s, file_name = %s, file_size = %s,
                        status = 'pending', admin_note = NULL, uploaded_at = NOW()
                    WHERE id = %s
                """, (public_url, filename, size, existing['id']))
            else:
                cursor.execute("""
                    INSERT INTO member_documents
                        (member_id, requirement, label, file_url, file_name, file_size, status)
                    VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                """, (member_id, requirement, label, public_url, filename, size))
            conn.commit()
        return jsonify({'message': 'Document record saved'}), 200
    except Exception as e:
        logger.exception('[Documents] confirm_upload DB error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/submit-application', methods=['POST'])
@jwt_required()
def submit_application():
    """Member signals they are done uploading and ready for review."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT member_type FROM members WHERE id = %s", (member_id,))
            mem_row = cursor.fetchone()
            m_type = (mem_row.get('member_type') if mem_row else '') or 'corporate'
            reqs = _get_active_requirements(cursor, member_type=m_type, application_type='new')
            req_keys = [r['key'] for r in reqs if r.get('is_required', True)]

            if req_keys:
                cursor.execute(
                    "SELECT COUNT(DISTINCT requirement) as cnt FROM member_documents WHERE member_id = %s AND requirement = ANY(%s)",
                    (member_id, req_keys)
                )
                row = cursor.fetchone()
                uploaded = row['cnt'] if row else 0
                required = len(req_keys)
                if uploaded < required:
                    return jsonify({
                        'message': f'Please upload all {required} required documents first. You have uploaded {uploaded} of {required}.'
                    }), 400

            # Mark member as 'pending_review' so admin knows to check
            cursor.execute(
                "UPDATE members SET status = 'pending_review' WHERE id = %s AND status IN ('pending', 'pending_review')",
                (member_id,)
            )
            conn.commit()
        return jsonify({'message': 'Application submitted for review'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────────

@documents_bp.route('/admin/pending', methods=['GET'])
@documents_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('members')
def admin_pending_applications():
    """List members by status. Pass ?status=active for approved members."""
    status_filter = request.args.get('status', '').strip().lower()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            if status_filter == 'active':
                cursor.execute("""
                    SELECT m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at,
                        COUNT(d.id) AS docs_uploaded,
                        COUNT(d.id) FILTER (WHERE d.status = 'approved') AS docs_approved,
                        COUNT(d.id) FILTER (WHERE d.status = 'pending') AS docs_pending,
                        COUNT(d.id) FILTER (WHERE d.status = 'rejected') AS docs_rejected
                    FROM members m
                    LEFT JOIN member_documents d ON d.member_id = m.id
                    WHERE m.status = 'active'
                      AND LOWER(COALESCE(m.role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')
                    GROUP BY m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at
                    ORDER BY m.id DESC
                """)
            elif status_filter == 'pending':
                cursor.execute("""
                    SELECT m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at,
                        COUNT(d.id) AS docs_uploaded,
                        COUNT(d.id) FILTER (WHERE d.status = 'approved') AS docs_approved,
                        COUNT(d.id) FILTER (WHERE d.status = 'pending') AS docs_pending,
                        COUNT(d.id) FILTER (WHERE d.status = 'rejected') AS docs_rejected
                    FROM members m
                    LEFT JOIN member_documents d ON d.member_id = m.id
                    WHERE m.status IN ('pending', 'pending_review', 'suspended')
                      AND LOWER(COALESCE(m.role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')
                    GROUP BY m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at
                    ORDER BY m.id DESC
                """)
            else:
                cursor.execute("""
                    SELECT m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at,
                        COUNT(d.id) AS docs_uploaded,
                        COUNT(d.id) FILTER (WHERE d.status = 'approved') AS docs_approved,
                        COUNT(d.id) FILTER (WHERE d.status = 'pending') AS docs_pending,
                        COUNT(d.id) FILTER (WHERE d.status = 'rejected') AS docs_rejected
                    FROM members m
                    LEFT JOIN member_documents d ON d.member_id = m.id
                    WHERE LOWER(COALESCE(m.role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')
                    GROUP BY m.id, m.name, m.email, m.phone, m.company, m.status, m.membership_number, m.member_type, m.member_scale, m.fee_category, m.port_of_operation, m.created_at
                    ORDER BY m.id DESC
                """)
            members = cursor.fetchall()

            # Precalculate active requirement counts per category
            cursor.execute("""
                SELECT LOWER(member_type) as mtype, COUNT(*) as cnt
                FROM document_requirements
                WHERE deleted_at IS NULL AND is_active = TRUE AND LOWER(application_type) = 'new'
                GROUP BY LOWER(member_type)
            """)
            req_counts = {r['mtype']: int(r['cnt']) for r in cursor.fetchall()}

            result_members = []
            for m in members:
                m_dict = dict(m)
                raw_type = (m_dict.get('member_type') or 'corporate').strip().lower()
                if 'licentiate' in raw_type or 'individual' in raw_type:
                    cat_key = 'licentiate'
                elif 'associate' in raw_type or 'affiliate' in raw_type:
                    cat_key = 'associate'
                else:
                    cat_key = 'corporate'
                m_dict['total_required'] = req_counts.get(cat_key, 0)
                result_members.append(m_dict)

        return jsonify({'members': result_members}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()



@documents_bp.route('/admin/member/<int:member_id>', methods=['GET'])
@sub_admin_required('members')
def admin_get_member_docs(member_id):
    """Get all uploaded documents for a specific member."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("""
                SELECT id, name, email, phone, company, status, membership_number,
                       member_type, member_scale, fee_category, tin, digital_address, location,
                       port_of_operation, created_at
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()
            if not member:
                return jsonify({'message': 'Member not found'}), 404

            m_type = (member['member_type'] or '').lower() if isinstance(member, dict) and 'member_type' in member else ''
            reg_key = 'licentiate_reg_form_fee' if 'licentiate' in m_type else ('associate_reg_form_fee' if 'associate' in m_type else 'reg_form_fee')
            cursor.execute("""
                SELECT amount FROM fee_schedules 
                WHERE key = %s AND is_active = TRUE
                LIMIT 1
            """, (reg_key,))
            fee_row = cursor.fetchone()
            if not fee_row:
                cursor.execute("""
                    SELECT amount FROM fee_schedules 
                    WHERE (key = 'reg_form_fee' OR key = 'new_reg_fee' OR key ILIKE '%reg%') AND is_active = TRUE
                    LIMIT 1
                """)
                fee_row = cursor.fetchone()
            reg_fee = float(fee_row['amount']) if fee_row and fee_row['amount'] is not None else 0.0

            cursor.execute("""
                SELECT amount, payment_ref, momo_tx_id, description, status FROM payments 
                WHERE member_id = %s AND LOWER(status) IN ('completed', 'successful', 'paid', 'success')
                ORDER BY id DESC LIMIT 1
            """, (member_id,))
            pay_row = cursor.fetchone()
            has_paid = pay_row is not None

            member_dict = dict(member)
            for k, v in list(member_dict.items()):
                if hasattr(v, 'isoformat'):
                    member_dict[k] = v.isoformat()
                elif hasattr(v, 'strftime'):
                    member_dict[k] = str(v)

            member_dict['registration_fee_paid'] = has_paid
            member_dict['registration_fee_amount'] = reg_fee
            if pay_row:
                member_dict['last_payment_amount'] = float(pay_row['amount']) if pay_row['amount'] is not None else None
                member_dict['last_payment_ref'] = pay_row.get('momo_tx_id') or pay_row.get('payment_ref')

            cursor.execute(
                "SELECT * FROM member_documents WHERE member_id = %s ORDER BY uploaded_at ASC",
                (member_id,)
            )
            docs = cursor.fetchall()

            # Dynamic requirements based on member_type
            raw_m = (member.get('member_type') or 'corporate').strip().lower()
            if 'licentiate' in raw_m or 'individual' in raw_m:
                m_type_clean = 'licentiate'
            elif 'associate' in raw_m or 'affiliate' in raw_m:
                m_type_clean = 'associate'
            else:
                m_type_clean = 'corporate'
            reqs = _get_active_requirements(cursor, member_type=m_type_clean, application_type='new')

        # Merge with requirement list to show missing items too
        uploaded_map = {d['requirement']: dict(d) for d in docs}
        result = []
        for req in reqs:
            doc = uploaded_map.get(req['key'])
            result.append({
                'key':         req['key'],
                'label':       req['label'],
                'uploaded':    doc is not None,
                'id':          doc['id']         if doc else None,
                'file_url':    doc['file_url']    if doc else None,
                'file_name':   doc['file_name']   if doc else None,
                'status':      doc['status']       if doc else 'not_uploaded',
                'admin_note':  doc['admin_note']   if doc else None,
                'uploaded_at': str(doc['uploaded_at']) if doc and doc['uploaded_at'] else None,
            })

        # Summary counts
        total_req = len(result)
        total_upl = sum(1 for r in result if r['uploaded'])
        total_app = sum(1 for r in result if r['status'] == 'approved')
        total_rej = sum(1 for r in result if r['status'] == 'rejected')
        total_pen = sum(1 for r in result if r['uploaded'] and r['status'] == 'pending')

        return jsonify({
            'member':     member_dict,
            'documents':  result,
            'summary': {
                'total_required': total_req,
                'total_uploaded': total_upl,
                'total_approved': total_app,
                'total_rejected': total_rej,
                'total_pending':  total_pen,
            }
        }), 200
    except Exception as e:
        logger.exception('[Documents] admin_get_member_docs error')
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/review/<int:doc_id>', methods=['POST'])
@sub_admin_required('members')
def admin_review_doc(doc_id):
    """Admin approves or rejects a specific document."""
    data = request.get_json() or {}
    status     = data.get('status', '').strip().lower()
    admin_note = data.get('admin_note', '').strip() or None
    admin_id   = get_jwt_identity()

    if status not in ('approved', 'rejected', 'pending'):
        return jsonify({'message': 'Invalid status. Must be approved, rejected, or pending.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("""
                UPDATE member_documents
                SET status = %s, admin_note = %s, reviewed_at = NOW(), reviewed_by = %s
                WHERE id = %s
                RETURNING member_id
            """, (status, admin_note, admin_id, doc_id))
            row = cursor.fetchone()
            if not row:
                return jsonify({'message': 'Document not found'}), 404

            mid = row['member_id']

            # If all required docs are now approved, activate or approve member
            if status == 'approved':
                cursor.execute("""
                    SELECT member_type FROM members WHERE id = %s
                """, (mid,))
                mem = cursor.fetchone()
                m_type = mem['member_type'] if mem else 'corporate'
                reqs = _get_active_requirements(cursor, member_type=m_type, application_type='new')
                required_keys = [r['key'] for r in reqs if r.get('is_required', True)]

                if required_keys:
                    cursor.execute("""
                        SELECT COUNT(*) as unapproved_count
                        FROM member_documents
                        WHERE member_id = %s AND requirement = ANY(%s) AND status != 'approved'
                    """, (mid, required_keys))
                    chk = cursor.fetchone()
                    if chk and chk['unapproved_count'] == 0:
                        cursor.execute("""
                            UPDATE members
                            SET status = 'active', registration_fee_paid = TRUE, application_fee_paid = TRUE
                            WHERE id = %s
                        """, (mid,))
            
            conn.commit()
            cache.delete(f'me_{mid}')
            try:
                from socket_instance import socketio
                socketio.emit('member_documents_updated', {'member_id': mid, 'doc_id': doc_id, 'status': status})
                socketio.emit('documents_updated', {'member_id': mid, 'doc_id': doc_id, 'status': status})
                socketio.emit('member_updated', {'member_id': mid, 'status': 'active' if status == 'approved' else 'pending'})
                socketio.emit('tasks_updated', {'member_id': mid})
            except Exception:
                pass
        return jsonify({'message': f'Document {status}'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/member/<int:member_id>/approve-all', methods=['POST'])
@sub_admin_required('members')
def admin_approve_all(member_id):
    """Approve all uploaded documents for member registration and activate member."""
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Approve all docs
            cursor.execute("""
                UPDATE member_documents
                SET status = 'approved', reviewed_at = NOW(), reviewed_by = %s
                WHERE member_id = %s AND (status IS NULL OR status = 'pending')
            """, (admin_id, member_id))

            # Set member to active so dashboard opens immediately
            cursor.execute("""
                UPDATE members
                SET status = 'active', registration_fee_paid = TRUE, application_fee_paid = TRUE
                WHERE id = %s
            """, (member_id,))

            cache.delete(f'me_{member_id}')
            conn.commit()
            try:
                from socket_instance import socketio
                socketio.emit('member_documents_updated', {'member_id': member_id, 'status': 'approved'})
                socketio.emit('documents_updated', {'member_id': member_id, 'status': 'approved'})
                socketio.emit('member_updated', {'member_id': member_id, 'status': 'active'})
                socketio.emit('members_updated', {})
                socketio.emit('tasks_updated', {'member_id': member_id})
            except Exception:
                pass
        return jsonify({'message': 'All registration documents approved. Member registration is verified and activated.'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN REQUIREMENT MANAGEMENT ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────────

@documents_bp.route('/admin/requirements', methods=['GET'])
@sub_admin_required('members')
def admin_get_all_requirements():
    """List all configured document requirements for admin management."""
    member_type = request.args.get('member_type', '').strip().lower()
    app_type = request.args.get('application_type', '').strip().lower()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            query = """
                SELECT id, key, label, description, member_type, application_type, is_required, display_order, is_active, created_at
                FROM document_requirements
                WHERE deleted_at IS NULL
            """
            params = []
            if member_type:
                query += " AND LOWER(member_type) = %s"
                params.append(member_type)
            if app_type:
                query += " AND LOWER(application_type) = %s"
                params.append(app_type)
            query += " ORDER BY display_order ASC, id ASC"

            cursor.execute(query, tuple(params))
            rows = cursor.fetchall()
            return jsonify({'requirements': [dict(r) for r in rows]}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/requirements', methods=['POST'])
@sub_admin_required('members')
def admin_create_requirement():
    """Add a new document requirement."""
    data = request.get_json() or {}
    label = (data.get('label') or '').strip()
    key   = (data.get('key') or '').strip().lower().replace(' ', '_')
    description = (data.get('description') or '').strip()
    member_type = (data.get('member_type') or 'corporate').strip().lower()
    app_type    = (data.get('application_type') or 'new').strip().lower()
    is_required = bool(data.get('is_required', True))
    display_order = int(data.get('display_order', 0))

    if not label:
        return jsonify({'message': 'Requirement label is required'}), 400

    if not key:
        import re
        key = re.sub(r'[^a-z0-9_]', '', label.lower().replace(' ', '_'))

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("""
                INSERT INTO document_requirements (key, label, description, member_type, application_type, is_required, display_order, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, %s, TRUE)
                RETURNING id, key, label, description, member_type, application_type, is_required, display_order, is_active
            """, (key, label, description or None, member_type, app_type, is_required, display_order))
            new_req = cursor.fetchone()
            conn.commit()

            try:
                from socket_instance import socketio
                socketio.emit('document_rules_updated', {'member_type': member_type, 'application_type': app_type})
                socketio.emit('member_documents_updated', {})
            except Exception:
                pass

            return jsonify({'message': 'Requirement created successfully', 'requirement': dict(new_req)}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/requirements/<int:req_id>', methods=['PUT'])
@sub_admin_required('members')
def admin_update_requirement(req_id):
    """Edit an existing document requirement."""
    data = request.get_json() or {}
    label       = data.get('label')
    description = data.get('description')
    member_type = data.get('member_type')
    app_type    = data.get('application_type')
    is_required = data.get('is_required')
    display_order = data.get('display_order')
    is_active   = data.get('is_active')

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("SELECT * FROM document_requirements WHERE id = %s", (req_id,))
            req = cursor.fetchone()
            if not req:
                return jsonify({'message': 'Requirement not found'}), 404

            new_label       = label.strip() if label is not None else req['label']
            new_desc        = description.strip() if description is not None else req['description']
            new_mtype       = member_type.strip().lower() if member_type is not None else req.get('member_type', 'corporate')
            new_atype       = app_type.strip().lower() if app_type is not None else req.get('application_type', 'new')
            new_required    = bool(is_required) if is_required is not None else req['is_required']
            new_order       = int(display_order) if display_order is not None else req['display_order']
            new_active      = bool(is_active) if is_active is not None else req['is_active']

            cursor.execute("""
                UPDATE document_requirements
                SET label = %s, description = %s, member_type = %s, application_type = %s, is_required = %s, display_order = %s, is_active = %s
                WHERE id = %s
                RETURNING id, key, label, description, member_type, application_type, is_required, display_order, is_active
            """, (new_label, new_desc or None, new_mtype, new_atype, new_required, new_order, new_active, req_id))
            updated = cursor.fetchone()
            conn.commit()

            try:
                from socket_instance import socketio
                socketio.emit('document_rules_updated', {'member_type': new_mtype, 'application_type': new_atype})
                socketio.emit('member_documents_updated', {})
            except Exception:
                pass

            return jsonify({'message': 'Requirement updated successfully', 'requirement': dict(updated)}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/requirements/<int:req_id>', methods=['DELETE'])
@sub_admin_required('members')
def admin_delete_requirement(req_id):
    """Soft-delete a document requirement (preserves database history & past member files)."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("UPDATE document_requirements SET deleted_at = NOW(), is_active = FALSE WHERE id = %s", (req_id,))
            conn.commit()

            try:
                from socket_instance import socketio
                socketio.emit('document_rules_updated', {})
                socketio.emit('member_documents_updated', {})
            except Exception:
                pass

            return jsonify({'message': 'Requirement soft-deleted successfully'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@documents_bp.route('/admin/requirements/bulk-toggle', methods=['POST'])
@sub_admin_required('members')
def admin_bulk_toggle_requirements():
    """Bulk enable or disable all document requirements for a member_type and application_type."""
    data = request.get_json() or {}
    member_type = (data.get('member_type') or 'corporate').strip().lower()
    app_type = (data.get('application_type') or 'new').strip().lower()
    is_active = bool(data.get('is_active', True))

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            _ensure_table(cursor)
            cursor.execute("""
                UPDATE document_requirements
                SET is_active = %s
                WHERE deleted_at IS NULL
                  AND LOWER(member_type) = %s
                  AND LOWER(application_type) = %s
            """, (is_active, member_type, app_type))
            updated_cnt = cursor.rowcount
            conn.commit()

            try:
                from socket_instance import socketio
                socketio.emit('document_rules_updated', {'member_type': member_type, 'application_type': app_type, 'is_active': is_active})
                socketio.emit('member_documents_updated', {})
            except Exception:
                pass

            action_str = "enabled" if is_active else "disabled"
            return jsonify({
                'message': f'All {updated_cnt} document requirements for {member_type.title()} ({app_type}) {action_str} successfully.',
                'updated_count': updated_cnt,
                'is_active': is_active
            }), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

