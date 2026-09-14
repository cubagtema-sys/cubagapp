import os
from flask import Blueprint, jsonify, request, send_from_directory, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from config.db import get_db
from routes.admin import log_admin_action
from utils import admin_required, sub_admin_required

tasks_bp = Blueprint('tasks', __name__)

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'uploads', 'task_submissions')
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'mp4', 'mov', 'avi', 'txt'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def _query_license(conn, member_id):
    """Fetch member license status for priority task synthesis."""
    tasks = []
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT status, license_expiry_date
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()
        if member:
            from datetime import datetime, date
            status = (member.get('status') or 'active').lower()
            raw_expiry = member.get('license_expiry_date')
            days_left = None
            expiry_str = None
            if raw_expiry:
                if isinstance(raw_expiry, str):
                    try:
                        exp_date = datetime.strptime(raw_expiry, '%Y-%m-%d').date()
                    except Exception:
                        exp_date = None
                elif isinstance(raw_expiry, (datetime, date)):
                    exp_date = raw_expiry if isinstance(raw_expiry, date) else raw_expiry.date()
                else:
                    exp_date = None
                if exp_date:
                    days_left = (exp_date - date.today()).days
                    expiry_str = exp_date.isoformat()
            if status in ('pending', 'pending_payment', 'inactive'):
                tasks.append({
                    'id': 'sys_license_activate',
                    'title': '🔴 License Activation Payment Required',
                    'description': 'Your membership license payment is pending. Complete payment now to activate full CUBAG member privileges.',
                    'due_date': 'Immediate',
                    'priority': 'Urgent',
                    'category': 'License & Payments',
                    'done': False,
                    'action_url': '/compliance',
                    'action_label': 'Pay Now',
                    'is_system': True,
                    'system_type': 'payment'
                })
            elif days_left is not None and days_left <= 90:
                is_expired = days_left < 0
                tasks.append({
                    'id': 'sys_license_renewal',
                    'title': f'🔴 License Expired ({abs(days_left)} days ago)' if is_expired else f'🟡 Annual License Renewal Window Open ({days_left} days left)',
                    'description': f'Your license expired on {expiry_str}. Complete renewal immediately to maintain active standing.' if is_expired else f'Your annual license expires on {expiry_str}. The renewal window is now open.',
                    'due_date': expiry_str or 'Immediate',
                    'priority': 'Urgent' if (is_expired or days_left <= 30) else 'High',
                    'category': 'License & Payments',
                    'done': False,
                    'action_url': '/compliance',
                    'action_label': 'Renew License Now' if is_expired else 'Submit Renewal',
                    'is_system': True,
                    'system_type': 'renewal'
                })
    except Exception:
        pass
    return tasks


def _query_rejections(conn, member_id):
    """Fetch rejected compliance documents for priority task synthesis."""
    tasks = []
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT ca.id, ca.type, ca.status as app_status, ca.admin_note as app_note,
                       cd.requirement, cd.label as doc_label, cd.status as doc_status, cd.admin_note as doc_note
                FROM compliance_applications ca
                LEFT JOIN compliance_documents cd ON cd.application_id = ca.id
                WHERE ca.member_id = %s
                  AND (ca.status IN ('rejected', 'revision_requested') OR cd.status = 'rejected')
            """, (member_id,))
            rejected_rows = cursor.fetchall()
        seen_apps = set()
        for row in rejected_rows:
            app_id = row['id']
            app_type = row['type']
            type_label = 'License Renewal' if app_type == 'renewal' else 'Member ID Application'
            note = row['doc_note'] or row['app_note'] or 'Admin requested revision or re-upload for rejected files.'
            if app_id not in seen_apps:
                seen_apps.add(app_id)
                tasks.append({
                    'id': f'sys_compliance_reject_{app_id}',
                    'title': f'🔴 Action Required: {type_label} Document Rejected',
                    'description': f'Admin Note: {note}',
                    'due_date': 'Immediate',
                    'priority': 'Urgent',
                    'category': 'Compliance Revisions',
                    'done': False,
                    'action_url': '/compliance',
                    'action_label': 'Re-upload Documents',
                    'is_system': True,
                    'system_type': 'rejection'
                })
    except Exception:
        pass
    return tasks


def _query_surveys(conn, member_id):
    """Fetch active elections & surveys for priority task synthesis."""
    tasks = []
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT s.id, s.title, s.description, s.type, s.deadline, s.expiry
                FROM surveys s
                WHERE s.active = TRUE
                  AND (s.deleted_at IS NULL)
                  AND (s.expiry IS NULL OR s.expiry >= CURRENT_DATE)
                  AND (s.deadline IS NULL OR s.deadline >= CURRENT_DATE)
                  AND s.id NOT IN (
                      SELECT survey_id FROM survey_responses WHERE member_id = %s
                  )
                ORDER BY s.created_at DESC
            """, (member_id,))
            active_surveys = cursor.fetchall()
        for s in active_surveys:
            survey_id = s['id']
            s_type = (s.get('type') or 'Survey').upper()
            due = str(s.get('deadline') or s.get('expiry') or 'Active')
            tasks.append({
                'id': f'sys_survey_{survey_id}',
                'title': f'🗳️ {s_type}: {s["title"]}',
                'description': s.get('description') or f'Official CUBAG {s_type.lower()} open for member participation.',
                'due_date': due,
                'priority': 'High' if s_type == 'ELECTION' else 'Medium',
                'category': 'Elections & Surveys',
                'done': False,
                'action_url': '/surveys',
                'action_label': 'Cast Vote',
                'is_system': True,
                'system_type': 'survey'
            })
    except Exception:
        pass
    return tasks


def _query_onboarding_docs(conn, member_id):
    """Fetch onboarding document count for priority task synthesis."""
    tasks = []
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT status, member_type FROM members WHERE id = %s", (member_id,))
            mem = cursor.fetchone()
            if not mem:
                return tasks
            status = str(mem.get('status') or '').lower()
            if status in ('active', 'approved'):
                return tasks  # Fully approved/active member has completed onboarding

            raw_type = str(mem.get('member_type') or 'corporate').lower()
            if 'licentiate' in raw_type or 'individual' in raw_type:
                expected_cnt = 7
            elif 'associate' in raw_type or 'affiliate' in raw_type:
                expected_cnt = 6
            else:
                expected_cnt = 11

            cursor.execute("""
                SELECT COUNT(*) as uploaded_cnt
                FROM member_documents
                WHERE member_id = %s AND status != 'rejected'
            """, (member_id,))
            doc_res = cursor.fetchone()
            uploaded_cnt = doc_res['uploaded_cnt'] if doc_res else 0
            if uploaded_cnt < expected_cnt:
                tasks.append({
                    'id': 'sys_onboarding_docs',
                    'title': f'📋 Complete {expected_cnt} Mandatory Clearance Documents',
                    'description': f'You have uploaded {uploaded_cnt} of {expected_cnt} mandatory onboarding clearance documents.',
                    'due_date': 'Pending Registration',
                    'priority': 'High',
                    'category': 'Onboarding Documents',
                    'done': False,
                    'action_url': '/tasks',
                    'action_label': 'Upload Documents',
                    'is_system': True,
                    'system_type': 'documents'
                })
    except Exception:
        pass
    return tasks


def _query_package_fee(conn, member_id):
    """Fetch Membership Entrance Package fee status for task synthesis."""
    tasks = []
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT status, fee_category, member_scale, member_type, role, good_standing,
                       COALESCE(package_fee_paid, FALSE) as package_fee_paid,
                       COALESCE(registration_fee_paid, FALSE) as reg_fee_paid
                FROM members WHERE id = %s
            """, (member_id,))
            mem = cursor.fetchone()
            if not mem or mem.get('role') in ('admin', 'sub_admin'):
                return tasks
            if str(mem.get('status') or '').lower() in ('active', 'approved'):
                return tasks  # Active / approved member is cleared

            # Check if package fee has already been paid in payments table
            cursor.execute("""
                SELECT id FROM payments
                WHERE member_id = %s
                  AND LOWER(COALESCE(status, '')) IN ('success', 'paid', 'completed')
                  AND (
                    LOWER(COALESCE(description, '')) LIKE '%%package%%'
                    OR LOWER(COALESCE(description, '')) LIKE '%%entrance%%'
                    OR LOWER(COALESCE(description, '')) LIKE '%%clearing & forwarding only%%'
                    OR LOWER(COALESCE(description, '')) LIKE '%%consolidation%%'
                    OR LOWER(COALESCE(description, '')) LIKE '%%new member%%'
                  )
                LIMIT 1
            """, (member_id,))
            pkg_paid_row = cursor.fetchone()

            is_pkg_paid = mem.get('package_fee_paid') is True or (pkg_paid_row is not None)
            if not is_pkg_paid:
                fee_cat = (mem.get('fee_category') or 'cf_only').lower()
                member_scale = str(mem.get('member_scale') or 'sme').lower().strip()
                is_large = member_scale in ('large_corporate', 'large', 'corporate')

                cat_title = 'Clearing & Forwarding Only'
                if fee_cat == 'consolidation':
                    cat_title = 'Consolidation'
                elif fee_cat == 'cf_consolidation':
                    cat_title = 'Consolidation, Clearing & Forwarding'

                cursor.execute("SELECT key, amount FROM fee_schedules WHERE is_active = TRUE")
                comp_rows = {r['key']: float(r['amount']) for r in cursor.fetchall()}
                sub_fee = 300.0 if is_large else comp_rows.get('new_sub_fee', 120.0)
                vet_fee = comp_rows.get('new_vetting_fee', 750.0)
                dist_fee = comp_rows.get('new_district_fee', 250.0)
                cf_fee = comp_rows.get('new_cf_fee', 500.0)
                con_fee = comp_rows.get('new_consolidation_fee', 600.0)

                if is_large:
                    computed_amt = comp_rows.get('new_cf_consolidation', 2220.0)
                elif fee_cat == 'consolidation':
                    computed_amt = comp_rows.get('new_consolidation', sub_fee + vet_fee + dist_fee + con_fee)
                elif fee_cat == 'cf_consolidation':
                    computed_amt = comp_rows.get('new_cf_consolidation', sub_fee + vet_fee + dist_fee + con_fee + cf_fee)
                else:
                    computed_amt = comp_rows.get('new_cf_only', sub_fee + vet_fee + dist_fee + cf_fee)

                pkg_amount_str = f"{computed_amt:.2f}"

                tasks.append({
                    'id': 'sys_membership_package_fee',
                    'title': f'💳 Settle Membership Entrance Package ({cat_title} - GHS {pkg_amount_str})',
                    'description': f'Your upfront registration fee is processed. Please settle your Membership Entrance Package fee of GHS {pkg_amount_str} ({cat_title}) to activate full Good Standing privileges.',
                    'due_date': 'Pending Activation',
                    'priority': 'Urgent',
                    'category': 'Membership Activation',
                    'done': False,
                    'action_url': '/payments?fee=New%20Membership%20Dues',
                    'action_label': f'Pay New Membership Dues (GHS {pkg_amount_str})',
                    'is_system': True,
                    'system_type': 'package_payment'
                })
    except Exception as e:
        print(f"[Tasks] _query_package_fee error: {e}")
    return tasks


def _synthesize_system_tasks(cursor, member_id):
    """Run all priority-task queries concurrently for speed."""
    from concurrent.futures import ThreadPoolExecutor, as_completed
    from config.db import get_db as _get_db

    def _run(fn):
        conn2 = _get_db()
        try:
            return fn(conn2, member_id)
        finally:
            conn2.close()

    results = []
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [
            pool.submit(_run, _query_license),
            pool.submit(_run, _query_rejections),
            pool.submit(_run, _query_surveys),
            pool.submit(_run, _query_onboarding_docs),
            pool.submit(_run, _query_package_fee),
        ]
        for fut in as_completed(futures):
            try:
                results.extend(fut.result())
            except Exception:
                pass

    # Sort: Urgent first, then High, then Medium
    priority_order = {'Urgent': 0, 'High': 1, 'Medium': 2, 'Low': 3}
    results.sort(key=lambda t: priority_order.get(t.get('priority', 'Low'), 3))
    return results


# ─── GET /tasks ───────────────────────────────────────────────────────────────
@tasks_bp.route('/', methods=['GET'])
@jwt_required()
def get_tasks():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            system_tasks = _synthesize_system_tasks(cursor, member_id)

            cursor.execute("""
                SELECT t.*, 
                       s.id as submission_id,
                       s.admin_verified,
                       s.submitted_at,
                       s.completion_note
                FROM tasks t
                LEFT JOIN task_submissions s ON t.id = s.task_id AND s.member_id = %s
                WHERE t.member_id = %s
                ORDER BY t.due_date ASC
            """, (member_id, member_id))
            data = cursor.fetchall()

            # Stringify dates
            for item in data:
                if hasattr(item.get('due_date'), 'isoformat'):
                    item['due_date'] = item['due_date'].isoformat()
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
                if hasattr(item.get('submitted_at'), 'isoformat'):
                    item['submitted_at'] = item['submitted_at'].isoformat()

            all_tasks = system_tasks + list(data)

        return jsonify({'items': all_tasks, 'total': len(all_tasks)}), 200
    finally:
        conn.close()


# ─── GET /tasks/summary ───────────────────────────────────────────────────────
@tasks_bp.route('/summary', methods=['GET'])
@jwt_required()
def tasks_summary():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            system_tasks = _synthesize_system_tasks(cursor, member_id)
            pending_system = len([t for t in system_tasks if not t.get('done')])

            cursor.execute("SELECT COUNT(*) as pending FROM tasks WHERE member_id = %s AND done = FALSE", (member_id,))
            result = cursor.fetchone()
            total_pending = pending_system + (result['pending'] if result else 0)

        return jsonify({'pending': total_pending}), 200
    finally:
        conn.close()


# ─── PATCH /tasks/<id>/complete ───────────────────────────────────────────────
@tasks_bp.route('/<int:task_id>/complete', methods=['PATCH'])
@jwt_required()
def complete_task(task_id):
    member_id = get_jwt_identity()  # BUG-B26 fix: ownership check
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "UPDATE tasks SET done = TRUE WHERE id = %s AND member_id = %s",
                (task_id, member_id)
            )
            if cursor.rowcount == 0:
                return jsonify({'message': 'Task not found or not yours'}), 404
            conn.commit()
        return jsonify({'message': 'Task marked complete'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': 'Failed to update task'}), 500
    finally:
        conn.close()


# ─── POST /tasks/<id>/submit ─ User submits completion evidence ───────────────
@tasks_bp.route('/<int:task_id>/submit', methods=['POST'])
@jwt_required()
def submit_task(task_id):
    member_id = get_jwt_identity()
    note = request.form.get('note', '')
    files = request.files.getlist('files')

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # BUG-B27 fix: verify ownership before allowing submission
            cursor.execute(
                "SELECT id FROM tasks WHERE id = %s AND member_id = %s",
                (task_id, member_id)
            )
            if not cursor.fetchone():
                return jsonify({'message': 'Task not found or not assigned to you'}), 404

            # BUG-B29 fix: prevent duplicate submissions
            cursor.execute(
                "SELECT id FROM task_submissions WHERE task_id = %s AND member_id = %s",
                (task_id, member_id)
            )
            if cursor.fetchone():
                return jsonify({'message': 'You have already submitted this task'}), 409

            # Create submission record
            cursor.execute("""
                INSERT INTO task_submissions (task_id, member_id, completion_note)
                VALUES (%s, %s, %s)
                RETURNING id
            """, (task_id, member_id, note))
            submission_id = cursor.fetchone()['id']

            # Save uploaded files
            saved = []
            for f in files:
                if f and f.filename and allowed_file(f.filename):
                    safe_name = f"{submission_id}_{secure_filename(f.filename)}"
                    path = os.path.join(UPLOAD_FOLDER, safe_name)
                    f.save(path)
                    file_size = os.path.getsize(path)
                    cursor.execute("""
                        INSERT INTO task_submission_files (submission_id, filename, original_name, file_type, file_size)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (submission_id, safe_name, f.filename, f.content_type, file_size))
                    saved.append(f.filename)

            # Mark task as submitted (done = TRUE pending admin verify)
            cursor.execute("UPDATE tasks SET done = TRUE WHERE id = %s AND member_id = %s", (task_id, member_id))
            conn.commit()

        return jsonify({'message': 'Submission received', 'submission_id': submission_id, 'files': saved}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'message': 'Submission failed. Please try again.'}), 500
    finally:
        conn.close()


# ─── GET /tasks/uploads/<filename> ─ Serve uploaded files (auth required) ──────
@tasks_bp.route('/uploads/<filename>', methods=['GET'])
@jwt_required()  # BUG-B28 fix: was unauthenticated
def serve_file(filename):
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Verify the file belongs to a submission by this member (or an admin)
            cursor.execute("SELECT role FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            is_admin = member and member.get('role') in ('admin', 'sub_admin', 'super_admin')
            if not is_admin:
                # Check member owns the submission this file belongs to
                cursor.execute("""
                    SELECT tsf.id FROM task_submission_files tsf
                    JOIN task_submissions ts ON tsf.submission_id = ts.id
                    WHERE tsf.filename = %s AND ts.member_id = %s
                """, (filename, member_id))
                if not cursor.fetchone():
                    return jsonify({'message': 'Unauthorised'}), 403
    finally:
        conn.close()
    return send_from_directory(UPLOAD_FOLDER, filename)


# ─── GET /tasks/admin/all ─────────────────────────────────────────────────────
@tasks_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('members')
def get_all_tasks_admin():
    try:
        page = max(1, int(request.args.get('page', 1)))
        per_page = int(request.args.get('per_page', 20))
        per_page = max(1, min(per_page, 200))
        offset = (page - 1) * per_page
        task_status = request.args.get('status', 'all').lower()

        where_clause = ""
        if task_status == 'pending':
            where_clause = "WHERE t.done = FALSE AND (s.id IS NULL OR s.admin_verified = FALSE)" # pending or submitted without submission? Wait, pending is NOT done.
            where_clause = "WHERE t.done = FALSE AND s.id IS NULL"
        elif task_status == 'submitted':
            where_clause = "WHERE t.done = TRUE AND (s.admin_verified IS NULL OR s.admin_verified = FALSE)"
        elif task_status == 'verified':
            where_clause = "WHERE s.admin_verified = TRUE"

        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute(f"""
                SELECT t.*, m.name as member_name,
                       s.id as submission_id, s.completion_note, s.admin_verified,
                       s.admin_verified_at, s.admin_notes, s.submitted_at
                FROM tasks t
                LEFT JOIN members m ON t.member_id = m.id
                LEFT JOIN task_submissions s ON t.id = s.task_id
                {where_clause}
                ORDER BY t.created_at DESC
                LIMIT %s OFFSET %s
            """, (per_page, offset))
            tasks = cursor.fetchall()

            cursor.execute(f"""
                SELECT COUNT(*) as total
                FROM tasks t
                LEFT JOIN task_submissions s ON t.id = s.task_id
                {where_clause}
            """)
            total = cursor.fetchone().get('total', 0)

            # Attach files for each submission using one bulk query
            submission_ids = [t['submission_id'] for t in tasks if t.get('submission_id')]
            files_by_submission = {}
            if submission_ids:
                placeholders = ', '.join(['%s'] * len(submission_ids))
                cursor.execute(f"""
                    SELECT id, submission_id, original_name, file_type, file_size, filename
                    FROM task_submission_files
                    WHERE submission_id IN ({placeholders})
                """, submission_ids)
                all_files = cursor.fetchall()
                for file_row in all_files:
                    sub_id = file_row['submission_id']
                    if sub_id not in files_by_submission:
                        files_by_submission[sub_id] = []
                    file_item = dict(file_row)
                    del file_item['submission_id']
                    files_by_submission[sub_id].append(file_item)

            for task in tasks:
                sub_id = task.get('submission_id')
                task['files'] = files_by_submission.get(sub_id, [])

                # Ensure dates are stringified
                for date_field in ['due_date', 'created_at', 'submitted_at', 'admin_verified_at']:
                    if hasattr(task.get(date_field), 'isoformat'):
                        task[date_field] = task[date_field].isoformat()

        return jsonify({'data': tasks, 'page': page, 'per_page': per_page, 'total': total}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        if 'conn' in locals():
            conn.close()


# ─── POST /tasks/admin/create ─────────────────────────────────────────────
@tasks_bp.route('/admin/create', methods=['POST'])
@sub_admin_required('members')
def create_task_admin():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    member_id = data.get('member_id')
    title = (data.get('title') or '').strip()
    description = data.get('description', '')
    due_date = data.get('due_date')

    # BUG-B30 fix: validate required fields
    if not title:
        return jsonify({'message': 'Task title is required'}), 400
    if not member_id:
        return jsonify({'message': 'Member ID is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if member_id == 'all':
                # Include both active and pending members so new registrants get compliance tasks immediately
                cursor.execute("SELECT id FROM members WHERE status IN ('active', 'pending')")
                members = cursor.fetchall()
                for m in members:
                    cursor.execute("""
                        INSERT INTO tasks (member_id, title, description, due_date)
                        VALUES (%s, %s, %s, %s)
                    """, (m['id'], title, description, due_date))
                target_name = f'All active members ({len(members)})'
            else:
                cursor.execute("""
                    INSERT INTO tasks (member_id, title, description, due_date)
                    VALUES (%s, %s, %s, %s)
                """, (member_id, title, description, due_date))
                cursor.execute("SELECT name FROM members WHERE id = %s", (member_id,))
                m = cursor.fetchone()
                target_name = m['name'] if m else f'Member #{member_id}'
            conn.commit()

        # Audit log
        log_admin_action(admin_id, 'Assigned task', 'task', None, target_name, f'Task: {title}')

        return jsonify({'message': 'Task assigned successfully'}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'message': 'Failed to create task'}), 500
    finally:
        conn.close()


# ─── PATCH /tasks/admin/<id>/verify ─ Admin ticks task as verified ────────────
@tasks_bp.route('/admin/<int:submission_id>/verify', methods=['PATCH'])
@sub_admin_required('members')
def verify_task_submission(submission_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    admin_notes = data.get('admin_notes', '')
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Get task and member info for audit
            cursor.execute("""
                SELECT ts.task_id, t.title, m.name as member_name
                FROM task_submissions ts
                JOIN tasks t ON ts.task_id = t.id
                LEFT JOIN members m ON ts.member_id = m.id
                WHERE ts.id = %s
            """, (submission_id,))
            info = cursor.fetchone()

            cursor.execute("""
                UPDATE task_submissions
                SET admin_verified = TRUE,
                    admin_verified_at = CURRENT_TIMESTAMP,
                    admin_notes = %s
                WHERE id = %s
            """, (admin_notes, submission_id))
            conn.commit()

        # Audit log
        if info:
            log_admin_action(admin_id, 'Verified task submission', 'task', info.get('task_id'), info.get('member_name'), f'Task: {info.get("title")}')

        return jsonify({'message': 'Task submission verified'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
