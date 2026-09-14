import json
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import admin_required, log_admin_action, sub_admin_required
from config.cache import cache

admin_bp = Blueprint('admin', __name__)


@admin_bp.route('/dashboard', methods=['GET'])
@admin_required
def get_dashboard_stats():
    raw_cid = get_jwt_identity()
    caller_id = int(raw_cid) if raw_cid is not None else 0
    
    # 30-second per-admin cache — dashboard stats rarely change second-to-second
    cache_key = f'admin_dashboard_{caller_id}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Determine permissions
            cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
            user = cursor.fetchone()
            is_full_admin = user['role'] in ('admin', 'super_admin')

            perms = []
            if not is_full_admin:
                cursor.execute("SELECT permission_key FROM sub_admin_permissions WHERE sub_admin_id = %s AND granted = TRUE", (caller_id,))
                perms = [r['permission_key'] for r in cursor.fetchall()]

            def has_p(p): return is_full_admin or p in perms

            # Initialize metrics with default values
            total_members = 0
            active_members = 0
            pending_members = 0
            suspended_members = 0
            status_counts = {}
            type_counts = {}
            revenue = 0.0
            pending_revenue = 0.0
            failed_revenue = 0.0
            open_tickets = 0
            announcements_count = 0
            schedules_count = 0
            recent_members = []

            # ── Membership KPIs ──────────────────────────────────────────
            if has_p('members'):
                try:
                    cursor.execute("""
                        SELECT
                            COUNT(id) as total,
                            COUNT(id) FILTER (WHERE LOWER(status) = 'active') as active,
                            COUNT(id) FILTER (WHERE LOWER(status) = 'pending') as pending,
                            COUNT(id) FILTER (WHERE LOWER(status) = 'suspended') as suspended
                        FROM members
                    """)
                    row = cursor.fetchone()
                    total_members = int(row['total'] or 0)
                    active_members = int(row['active'] or 0)
                    pending_members = int(row['pending'] or 0)
                    suspended_members = int(row['suspended'] or 0)

                    # Member breakdown by status
                    cursor.execute("""
                        SELECT LOWER(TRIM(COALESCE(status, 'inactive'))) AS status, COUNT(id) as count
                        FROM members
                        GROUP BY LOWER(TRIM(COALESCE(status, 'inactive')))
                    """)
                    status_rows = cursor.fetchall()
                    status_counts = {'active': 0, 'pending': 0, 'suspended': 0, 'inactive': 0}
                    for r in status_rows:
                        status_key = str(r['status'] or 'inactive').strip().lower()
                        status_counts[status_key] = status_counts.get(status_key, 0) + int(r['count'])

                    # Member breakdown by type
                    cursor.execute("""
                        SELECT TRIM(COALESCE(member_type, 'Unknown')) AS member_type, COUNT(id) as count
                        FROM members
                        GROUP BY TRIM(COALESCE(member_type, 'Unknown'))
                    """)
                    type_rows = cursor.fetchall()
                    type_counts = {
                        'Licentiate': 0,
                        'Associate': 0,
                        'Corporate': 0,
                    }
                    for r in type_rows:
                        member_type = str(r['member_type'] or 'Unknown').strip()
                        type_counts[member_type] = type_counts.get(member_type, 0) + int(r['count'])
                except Exception as e:
                    print(f"[Admin Dashboard] Membership queries failed: {e}")

            # ── Financial KPIs ───────────────────────────────────────────
            if has_p('payments'):
                try:
                    cursor.execute("""
                        SELECT
                            COALESCE(SUM(amount) FILTER (WHERE LOWER(status) IN ('paid', 'success', 'completed')), 0) as paid,
                            COALESCE(SUM(amount) FILTER (WHERE LOWER(status) IN ('pending', 'processing', 'submitted')), 0) as pending,
                            COALESCE(SUM(amount) FILTER (WHERE LOWER(status) IN ('failed', 'overdue', 'cancelled', 'rejected')), 0) as failed
                        FROM payments
                    """)
                    row = cursor.fetchone()
                    revenue = float(row['paid'] or 0.0)
                    pending_revenue = float(row['pending'] or 0.0)
                    failed_revenue = float(row['failed'] or 0.0)
                except Exception as e:
                    print(f"[Admin Dashboard] Financial queries failed: {e}")

            # ── Operational KPIs ─────────────────────────────────────────
            if has_p('tickets'):
                try:
                    cursor.execute("SELECT COUNT(id) as count FROM support_tickets WHERE LOWER(status) != 'closed' AND deleted_at IS NULL")
                    open_tickets = int(cursor.fetchone()['count'] or 0)
                except Exception as e:
                    print(f"[Admin Dashboard] support_tickets query failed: {e}")

            if has_p('announcements'):
                try:
                    cursor.execute("SELECT COUNT(id) as count FROM announcements WHERE deleted_at IS NULL")
                    announcements_count = int(cursor.fetchone()['count'] or 0)
                except Exception as e:
                    print(f"[Admin Dashboard] announcements query failed: {e}")

            if has_p('schedules'):
                try:
                    cursor.execute("SELECT COUNT(id) as count FROM schedules")
                    schedules_count = int(cursor.fetchone()['count'] or 0)
                except Exception as e:
                    print(f"[Admin Dashboard] schedules query failed: {e}")

            if has_p('compliance') or has_p('members'):
                try:
                    cursor.execute("SELECT COUNT(id) as count FROM compliance_applications WHERE status NOT IN ('rejected')")
                    applications_count = int(cursor.fetchone()['count'] or 0)
                except Exception as e:
                    applications_count = 0

            documents_count = 0
            if has_p('members') or has_p('compliance'):
                try:
                    cursor.execute("SELECT COUNT(DISTINCT member_id) as count FROM member_documents WHERE status = 'pending'")
                    documents_count = int(cursor.fetchone()['count'] or 0)
                    if documents_count == 0:
                        cursor.execute("SELECT COUNT(DISTINCT member_id) as count FROM member_documents")
                        documents_count = int(cursor.fetchone()['count'] or 0)
                except Exception as e:
                    documents_count = 0

            # ── Recent members ───────────────────────────────────────────
            if has_p('members'):
                try:
                    cursor.execute("""
                        SELECT id, name, company, member_type, status, created_at
                        FROM members
                        ORDER BY created_at DESC LIMIT 5
                    """)
                    recent_members = cursor.fetchall()
                    for m in recent_members:
                        for key, value in list(m.items()):
                            if hasattr(value, 'isoformat'):
                                m[key] = value.isoformat()
                            elif hasattr(value, 'strftime'):
                                m[key] = str(value)
                except Exception as e:
                    print(f"[Admin Dashboard] Recent members query failed: {e}")

        result = {
            'kpis': {
                'total_members':    total_members,
                'active_members':   active_members,
                'pending_members':  pending_members,
                'suspended_members': suspended_members,
                'applications':     applications_count,
                'pending_documents': documents_count,
                'revenue':          revenue,
                'pending_revenue':  pending_revenue,
                'failed_revenue':   failed_revenue,
                'open_tickets':     open_tickets,
                'announcements':    announcements_count,
                'schedules':        schedules_count,
            },
            'status_counts': status_counts,
            'type_counts':   type_counts,
            'recent_members': recent_members
        }
        cache.set(cache_key, result, timeout=60)
        return jsonify(result), 200
    except Exception as e:
        import traceback
        print(f"[Admin Dashboard Critical Error] {e}")
        print(traceback.format_exc())
        return jsonify({
            'message': f"Critical dashboard error: {str(e)}",
            'error_details': str(e)
        }), 500
    finally:
        conn.close()

@admin_bp.route('/audit-log', methods=['GET'])
@admin_required
def get_audit_log():
    caller_id = get_jwt_identity()

    # Build cache key from all filter params
    limit = request.args.get('limit', 30, type=int)
    offset = request.args.get('offset', 0, type=int)
    target_type = request.args.get('target_type', '').strip()
    action_type = request.args.get('action_type', '').strip()
    date_from = request.args.get('date_from', '').strip()
    date_to = request.args.get('date_to', '').strip()
    actor_id = request.args.get('actor_id', '').strip()

    cache_key = f'audit_log_{caller_id}_{limit}_{offset}_{target_type}_{action_type}_{date_from}_{date_to}_{actor_id}'
    cached = cache.get(cache_key)
    if cached is not None:
        return jsonify(cached), 200

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Check permission
            cursor.execute("SELECT role FROM members WHERE id = %s", (caller_id,))
            user = cursor.fetchone()
            if user['role'] not in ('admin', 'super_admin'):
                cursor.execute("SELECT 1 FROM sub_admin_permissions WHERE sub_admin_id = %s AND permission_key = 'audit_log' AND granted = TRUE", (caller_id,))
                if not cursor.fetchone():
                    return jsonify({'message': 'Permission denied'}), 403

            # Build WHERE clauses
            conditions = []
            params = []
            if target_type:
                conditions.append("LOWER(a.target_type) = LOWER(%s)")
                params.append(target_type)
            if action_type:
                conditions.append("LOWER(a.action) LIKE LOWER(%s)")
                params.append(f"%{action_type}%")
            if date_from:
                conditions.append("a.created_at >= %s::date")
                params.append(date_from)
            if date_to:
                conditions.append("a.created_at < (%s::date + INTERVAL '1 day')")
                params.append(date_to)
            if actor_id:
                conditions.append("a.admin_id = %s")
                params.append(actor_id)

            where = ("WHERE " + " AND ".join(conditions)) if conditions else ""

            # Total count
            cursor.execute(f"SELECT COUNT(*) as cnt FROM audit_log a {where}", params)
            total = int(cursor.fetchone()['cnt'] or 0)

            # Fetch logs with admin info
            cursor.execute(f"""
                SELECT a.id, a.admin_id, a.action, a.target_type, a.target_id, a.target_name, a.details,
                       COALESCE(a.ip_address, '127.0.0.1') as ip_address, a.created_at,
                       m.name as admin_name, m.email as admin_email, m.role as admin_role
                FROM audit_log a
                LEFT JOIN members m ON a.admin_id = m.id
                {where}
                ORDER BY a.created_at DESC
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            logs = cursor.fetchall()
            for l in logs:
                if hasattr(l.get('created_at'), 'isoformat'):
                    l['created_at'] = l['created_at'].isoformat()

            # Filter options — cached for 5 minutes to avoid heavy table scans on every page request
            filter_opts = cache.get('audit_log_filter_options')
            if filter_opts is None:
                cursor.execute("SELECT DISTINCT target_type FROM audit_log WHERE target_type IS NOT NULL ORDER BY target_type")
                target_types = [r['target_type'] for r in cursor.fetchall()]

                cursor.execute("""
                    SELECT DISTINCT a.admin_id as id, m.name, m.role
                    FROM audit_log a
                    JOIN members m ON a.admin_id = m.id
                    WHERE a.admin_id IS NOT NULL
                    ORDER BY m.name
                """)
                actors = [{'id': r['id'], 'name': r['name'] or 'Unknown', 'role': r['role'] or 'admin'} for r in cursor.fetchall()]
                filter_opts = {'target_types': target_types, 'actors': actors}
                cache.set('audit_log_filter_options', filter_opts, timeout=300)

            result = {
                'logs': logs,
                'total': total,
                'filter_options': filter_opts
            }
            cache.set(cache_key, result, timeout=30)
            return jsonify(result), 200
    except Exception as e:
        import traceback
        print(f"[Audit Log Error] {e}")
        print(traceback.format_exc())
        return jsonify({'message': str(e), 'logs': [], 'total': 0, 'filter_options': {'target_types': [], 'actors': []}}), 500
    finally:
        conn.close()


@admin_bp.route('/fees', methods=['GET'])
@sub_admin_required('fees')
def get_admin_fees():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("CREATE TABLE IF NOT EXISTS platform_settings (config_key VARCHAR(100) PRIMARY KEY, config_value JSONB, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
            cursor.execute("CREATE TABLE IF NOT EXISTS compliance_settings (id SERIAL PRIMARY KEY)")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")

            cursor.execute("SELECT renewal_fee, customs_licence_fee FROM compliance_settings ORDER BY id DESC, updated_at DESC NULLS LAST LIMIT 1")
            cs_row = cursor.fetchone()
            comp_renewal_fee = float(cs_row['renewal_fee']) if cs_row and cs_row.get('renewal_fee') is not None else 500.00
            comp_customs_fee = float(cs_row['customs_licence_fee']) if cs_row and cs_row.get('customs_licence_fee') is not None else 750.00

            cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = 'cubag_fees_v2'")
            row = cursor.fetchone()
            fees = None
            if row and row.get('config_value'):
                val = row['config_value']
                if isinstance(val, str):
                    try:
                        fees = json.loads(val)
                    except Exception:
                        fees = None
                elif isinstance(val, list):
                    fees = val

            default_items = [
                # Section 1: Upfront Registration Fee
                {'id': 'reg_form_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'Registration Fee', 'amount': '600.00', 'frequency': 'One-Time', 'description': 'Mandatory initial registration fee paid upon onboarding before document vetting.'},

                # Section 1: Membership Entrance Package Summaries (is_summary: True)
                {'id': 'new_cf_only', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Clearing & Forwarding Only (SMEs)', 'amount': '1620.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + C&F 500 = Total GHS 1,620.00'},
                {'id': 'new_consolidation', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Consolidation Only (SMEs)', 'amount': '1720.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + Consolidation 600 = Total GHS 1,720.00'},
                {'id': 'new_cf_consolidation', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Consolidation, Clearing & Forwarding (SMEs)', 'amount': '2220.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + Consolidation 600 + C&F 500 = Total GHS 2,220.00'},
                {'id': 'new_large_cf_only', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Clearing & Forwarding Only (Large Corporate)', 'amount': '2220.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + Corporate Operational Scope 1100 = Total GHS 2,220.00'},
                {'id': 'new_large_consolidation', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Consolidation Only (Large Corporate)', 'amount': '2320.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + Corporate Operational Scope 1200 = Total GHS 2,320.00'},
                {'id': 'new_large_cf_consolidation', 'section': 'new_membership', 'is_summary': True, 'label': 'New Member Package: Consolidation, Clearing & Forwarding (Large Corporate)', 'amount': '2820.00', 'frequency': 'One-Time', 'description': 'Subscription 120 + Vetting 750 + District 250 + Corporate Consolidation & C&F Scope = Total GHS 2,820.00'},

                # Section 1: New Membership Isolated Breakdown Items (is_summary: False)
                {'id': 'new_sub_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'Subscription Fee (New Member)', 'amount': '120.00', 'frequency': 'One-Time', 'description': 'Annual Subscription component for new onboarding members'},
                {'id': 'new_vetting_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'Vetting & Dossier Verification Fee', 'amount': '750.00', 'frequency': 'One-Time', 'description': 'Document vetting and Secretariat inspection fee'},
                {'id': 'new_district_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'District / Branch Development Levy', 'amount': '250.00', 'frequency': 'One-Time', 'description': 'Local port district chapter development allocation'},
                {'id': 'new_cf_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'Clearing & Forwarding Component Tariff', 'amount': '500.00', 'frequency': 'One-Time', 'description': 'Customs broker and forwarder clearance operations tariff'},
                {'id': 'new_consolidation_fee', 'section': 'new_membership', 'is_summary': False, 'label': 'Consolidation Component Tariff', 'amount': '600.00', 'frequency': 'One-Time', 'description': 'Cargo consolidation operations tariff'},

                # Section 2: Renewal Summaries (is_summary: True)
                {'id': 'renewal_sme_without_consolidation', 'section': 'renewal', 'is_summary': True, 'label': 'Annual Renewal Dues - SMEs (Without Consolidation)', 'amount': '2170.00', 'frequency': 'Annual', 'description': 'Sub 120 + Welfare 300 + Admin 200 + Legal 100 + AGM 500 + Bond 350 + CTI 600 = Total GHS 2,170.00'},
                {'id': 'renewal_large_corporate_without_consolidation', 'section': 'renewal', 'is_summary': True, 'label': 'Annual Renewal Dues - Large Corporate (Without Consolidation)', 'amount': '4795.00', 'frequency': 'Annual', 'description': 'Sub 1545 + Welfare 400 + Admin 300 + Legal 500 + AGM 500 + Bond 350 + CTI 1200 = Total GHS 4,795.00'},
                {'id': 'renewal_sme_with_consolidation', 'section': 'renewal', 'is_summary': True, 'label': 'Annual Renewal Dues - SMEs (With Consolidation)', 'amount': '3456.00', 'frequency': 'Annual', 'description': 'Base 2,170 + Consolidation 1,286 = Total GHS 3,456.00'},
                {'id': 'renewal_large_corporate_with_consolidation', 'section': 'renewal', 'is_summary': True, 'label': 'Annual Renewal Dues - Large Corporate (With Consolidation)', 'amount': '6081.00', 'frequency': 'Annual', 'description': 'Base 4,795 + Consolidation 1,286 = Total GHS 6,081.00'},

                # Section 2: Renewal Isolated Breakdown Items (is_summary: False)
                {'id': 'renewal_sub_sme', 'section': 'renewal', 'is_summary': False, 'label': 'Subscription Fee - SMEs', 'amount': '120.00', 'frequency': 'Annual', 'description': 'Annual Subscription portion for SMEs'},
                {'id': 'renewal_sub_large', 'section': 'renewal', 'is_summary': False, 'label': 'Subscription Fee - Large Corporate', 'amount': '1545.00', 'frequency': 'Annual', 'description': 'Annual Subscription portion for Large Corporate'},
                {'id': 'renewal_welfare_sme', 'section': 'renewal', 'is_summary': False, 'label': 'Welfare Dues - SMEs', 'amount': '300.00', 'frequency': 'Annual', 'description': 'Welfare dues portion for SMEs'},
                {'id': 'renewal_welfare_large', 'section': 'renewal', 'is_summary': False, 'label': 'Welfare Dues - Large Corporate', 'amount': '400.00', 'frequency': 'Annual', 'description': 'Welfare dues portion for Large Corporates'},
                {'id': 'renewal_consolidation', 'section': 'renewal', 'is_summary': False, 'label': 'Consolidation Fee - Large Corporate & SMEs', 'amount': '1286.00', 'frequency': 'Annual', 'description': 'Consolidation operational category tariff'},
                {'id': 'renewal_admin_sme', 'section': 'renewal', 'is_summary': False, 'label': 'Administrative Fee - SMEs', 'amount': '200.00', 'frequency': 'Annual', 'description': 'Admin fee portion for SMEs'},
                {'id': 'renewal_admin_large', 'section': 'renewal', 'is_summary': False, 'label': 'Administrative Fee - Large Corporate', 'amount': '300.00', 'frequency': 'Annual', 'description': 'Admin fee portion for Large Corporate'},
                {'id': 'renewal_legal_sme', 'section': 'renewal', 'is_summary': False, 'label': 'Legal & Audit Fee - SMEs', 'amount': '100.00', 'frequency': 'Annual', 'description': 'Legal & Audit portion for SMEs'},
                {'id': 'renewal_legal_large', 'section': 'renewal', 'is_summary': False, 'label': 'Legal & Audit Fee - Large Corporate', 'amount': '500.00', 'frequency': 'Annual', 'description': 'Legal & Audit portion for Large Corporate'},
                {'id': 'renewal_agm', 'section': 'renewal', 'is_summary': False, 'label': 'AGM Levy', 'amount': '500.00', 'frequency': 'Annual', 'description': 'Annual General Meeting Levy'},
                {'id': 'renewal_bond', 'section': 'renewal', 'is_summary': False, 'label': 'Customs Bond Fee (SIC)', 'amount': '350.00', 'frequency': 'Annual', 'description': 'SIC Customs Bond Fee'},
                {'id': 'renewal_cti_sme', 'section': 'renewal', 'is_summary': False, 'label': 'CTI Training - SMEs', 'amount': '600.00', 'frequency': 'Annual', 'description': 'CTI Training portion for SMEs'},
                {'id': 'renewal_cti_large', 'section': 'renewal', 'is_summary': False, 'label': 'CTI Training - Large Corporate', 'amount': '1200.00', 'frequency': 'Annual', 'description': 'CTI Training portion for Large Corporate'},

                # Section 3: Associate Membership Breakdown Items
                {'id': 'associate_reg_form_fee', 'section': 'associate', 'is_summary': False, 'label': 'Registration Fee – Associate', 'amount': '0.00', 'frequency': 'One-Time', 'description': 'Mandatory initial onboarding registration fee for Associate members.'},
                {'id': 'associate_sub_fee', 'section': 'associate', 'is_summary': False, 'label': 'Subscription Fee – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual base subscription fee for Associate members (Renewed).'},
                {'id': 'associate_vetting_fee', 'section': 'associate', 'is_summary': False, 'label': 'Vetting Fee – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual document vetting fee for Associate members (Renewed).'},
                {'id': 'associate_district_fee', 'section': 'associate', 'is_summary': False, 'label': 'District – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual district chapter dues for Associate members (Renewed).'},
                {'id': 'associate_welfare_dues', 'section': 'associate', 'is_summary': False, 'label': 'Welfare Dues – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual welfare fund dues for Associate members (Renewed).'},
                {'id': 'associate_legal_audit_fee', 'section': 'associate', 'is_summary': False, 'label': 'Legal & Audit Fee – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual legal representation & audit retainer for Associate members (Renewed).'},
                {'id': 'associate_agm_levy', 'section': 'associate', 'is_summary': False, 'label': 'AGM Levy – Associate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual General Meeting logistics levy for Associate members (Renewed).'},

                # Section 4: Licentiate Membership Breakdown Items
                {'id': 'licentiate_reg_form_fee', 'section': 'licentiate', 'is_summary': False, 'label': 'Registration Fee – Licentiate', 'amount': '0.00', 'frequency': 'One-Time', 'description': 'Mandatory initial onboarding registration fee for Licentiate members.'},
                {'id': 'licentiate_sub_fee', 'section': 'licentiate', 'is_summary': False, 'label': 'Subscription Fee – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual base subscription fee for Licentiate members (Renewed).'},
                {'id': 'licentiate_vetting_fee', 'section': 'licentiate', 'is_summary': False, 'label': 'Vetting Fee – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual document vetting fee for Licentiate members (Renewed).'},
                {'id': 'licentiate_district_fee', 'section': 'licentiate', 'is_summary': False, 'label': 'District – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual district chapter dues for Licentiate members (Renewed).'},
                {'id': 'licentiate_welfare_dues', 'section': 'licentiate', 'is_summary': False, 'label': 'Welfare Dues – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual welfare fund dues for Licentiate members (Renewed).'},
                {'id': 'licentiate_legal_audit_fee', 'section': 'licentiate', 'is_summary': False, 'label': 'Legal & Audit Fee – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual legal representation & audit retainer for Licentiate members (Renewed).'},
                {'id': 'licentiate_agm_levy', 'section': 'licentiate', 'is_summary': False, 'label': 'AGM Levy – Licentiate', 'amount': '0.00', 'frequency': 'Annual', 'description': 'Annual General Meeting logistics levy for Licentiate members (Renewed).'},
            ]

            if fees is None:
                fees = default_items

            return jsonify(fees), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@admin_bp.route('/fees', methods=['POST', 'PUT'])
@sub_admin_required('fees')
def update_admin_fees():
    data = request.get_json()
    if not isinstance(data, list):
        return jsonify({'message': 'Data must be a list of fee objects'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO platform_settings (config_key, config_value)
                VALUES ('cubag_fees_v2', %s)
                ON CONFLICT (config_key) 
                DO UPDATE SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP
            """, (json.dumps(data),))

            cursor.execute("CREATE TABLE IF NOT EXISTS fee_schedules (key VARCHAR(100) PRIMARY KEY, amount NUMERIC(10,2) DEFAULT 0.00, is_active BOOLEAN DEFAULT TRUE, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")

            customs_fee = None
            renewal_fee = None
            posted_keys = set()

            for item in data:
                f_id = str(item.get('id', '')).strip()
                if not f_id:
                    continue
                posted_keys.add(f_id)
                lbl = str(item.get('label', ''))
                sec = str(item.get('section', 'new_membership'))
                desc = str(item.get('description', ''))
                amt_str = str(item.get('amount', '0')).replace(',', '').strip()
                try:
                    amt_val = float(amt_str)
                except ValueError:
                    amt_val = 0.0

                cursor.execute("""
                    INSERT INTO fee_schedules (key, fee_type, name, amount, description, is_active)
                    VALUES (%s, %s, %s, %s, %s, TRUE)
                    ON CONFLICT (key) 
                    DO UPDATE SET fee_type = EXCLUDED.fee_type, name = EXCLUDED.name, 
                                  amount = EXCLUDED.amount, description = EXCLUDED.description, 
                                  is_active = TRUE
                """, (f_id, sec, lbl, amt_val, desc))

            # Deactivate keys not in posted list
            if posted_keys:
                cursor.execute("UPDATE fee_schedules SET is_active = FALSE WHERE key NOT IN %s", (tuple(posted_keys),))

            cursor.execute("CREATE TABLE IF NOT EXISTS compliance_settings (id SERIAL PRIMARY KEY)")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            cursor.execute("SELECT COUNT(*) FROM compliance_settings")
            if cursor.fetchone()['count'] == 0:
                cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")

            cursor.execute("SELECT id FROM compliance_settings ORDER BY id DESC LIMIT 1")
            row = cursor.fetchone()
            target_id = row['id'] if row else None

            if customs_fee is not None or renewal_fee is not None:
                updates = []
                params = []
                if customs_fee is not None:
                    updates.append("customs_licence_fee = %s")
                    params.append(customs_fee)
                if renewal_fee is not None:
                    updates.append("renewal_fee = %s")
                    params.append(renewal_fee)
                updates.append("updated_at = CURRENT_TIMESTAMP")
                params.append(target_id)

                sql = f"UPDATE compliance_settings SET {', '.join(updates)} WHERE id = %s"
                cursor.execute(sql, tuple(params))

            conn.commit()
            cache.clear()
            log_admin_action(get_jwt_identity(), 'update_fees', 'platform_settings', None, 'cubag_fees_v2', {'fee_count': len(data)})
            try:
                from socket_instance import socketio
                socketio.emit('fees_updated', {'fee_count': len(data)})
                socketio.emit('tasks_updated', {})
            except Exception as se:
                logger.warning(f"Socket emission for fees_updated failed: {se}")
            return jsonify({'message': 'Fees updated successfully'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@admin_bp.route('/fees/<fee_id>', methods=['DELETE'])
@sub_admin_required('fees')
def delete_admin_fee(fee_id):
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = 'cubag_fees_v2'")
            row = cursor.fetchone()
            fees = []
            if row and row.get('config_value'):
                val = row['config_value']
                if isinstance(val, str):
                    try:
                        fees = json.loads(val)
                    except Exception:
                        fees = []
                elif isinstance(val, list):
                    fees = val

            updated_fees = [f for f in fees if str(f.get('id', '')).strip() != str(fee_id).strip()]

            cursor.execute("""
                INSERT INTO platform_settings (config_key, config_value)
                VALUES ('cubag_fees_v2', %s)
                ON CONFLICT (config_key) 
                DO UPDATE SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP
            """, (json.dumps(updated_fees),))

            cursor.execute("UPDATE fee_schedules SET is_active = FALSE WHERE key = %s", (str(fee_id).strip(),))

            conn.commit()
            cache.clear()
            log_admin_action(get_jwt_identity(), 'delete_fee', 'platform_settings', None, str(fee_id), {'deleted_fee_id': fee_id, 'remaining_count': len(updated_fees)})
            try:
                from socket_instance import socketio
                socketio.emit('fees_updated', {'fee_count': len(updated_fees)})
                socketio.emit('tasks_updated', {})
            except Exception as se:
                logger.warning(f"Socket emission for fees_updated failed: {se}")
            return jsonify({'message': f'Fee {fee_id} deleted successfully', 'fees': updated_fees}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@admin_bp.route('/members/<int:member_id>/approve', methods=['POST'])
@sub_admin_required('members')
def approve_member_application(member_id):
    """Approves a member application, auto-generating CUBAG-2026-XXXX and LIC-CUBAG-2026-XXXX."""
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, name, company, membership_number, license_number FROM members WHERE id = %s FOR UPDATE", (member_id,))
            m = cursor.fetchone()
            if not m:
                return jsonify({'message': 'Member not found'}), 404

            # Generate Membership Number & License Number if missing (Distinct formats)
            old_status = m.get('status') or 'pending'
            old_mem_no = m.get('membership_number')
            old_lic_no = m.get('license_number')

            mem_no = old_mem_no or f"CUBAG-2026-{member_id:04d}"
            lic_no = old_lic_no or f"LIC-CUBAG-2026-{member_id:04d}"
            expiry = datetime.date(datetime.date.today().year, 12, 31)

            cursor.execute("""
                UPDATE members 
                SET status = 'active',
                    membership_number = %s,
                    license_number = %s,
                    license_expiry_date = %s
                WHERE id = %s
            """, (mem_no, lic_no, expiry, member_id))

            # Audit logging with old_value, new_value, IP/device info
            import json
            old_val_json = json.dumps({'status': old_status, 'membership_number': old_mem_no, 'license_number': old_lic_no})
            new_val_json = json.dumps({'status': 'active', 'membership_number': mem_no, 'license_number': lic_no})
            
            date_str = datetime.date.today().strftime('%d %b %Y')
            formatted_details = (
                f"Admin approved membership\n"
                f"Member ID: {member_id}\n"
                f"Previous status: {old_status}\n"
                f"New status: Active\n"
                f"Membership No: {mem_no}\n"
                f"License No: {lic_no}\n"
                f"Date: {date_str}"
            )
            ip_addr = request.remote_addr or '127.0.0.1'

            cursor.execute("""
                INSERT INTO admin_audit_logs (admin_id, action, target_type, target_id, target_name, old_value, new_value, details, ip_address)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (caller_id, 'approve_membership', 'member', member_id, m.get('company') or m.get('name'), old_val_json, new_val_json, formatted_details, ip_addr))

            conn.commit()
            cache.clear()

            try:
                from config.socket import socketio
                socketio.emit('member_updated', {'member_id': member_id, 'status': 'active', 'good_standing': True})
                socketio.emit('member_approved', {'member_id': member_id, 'status': 'active', 'good_standing': True})
                socketio.emit('tasks_updated', {'member_id': member_id})
                socketio.emit('documents_updated', {'member_id': member_id})
            except Exception as sock_err:
                logger.warning("Socket emit error on approve member: %s", sock_err)

        return jsonify({
            'message': 'Member approved successfully!',
            'membership_number': mem_no,
            'license_number': lic_no,
            'status': 'active'
        }), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error approving member: %s", e)
        return jsonify({'message': 'Failed to approve member'}), 500
    finally:
        conn.close()


@admin_bp.route('/ports', methods=['GET'])
@sub_admin_required('members')
def get_admin_ports():
    """Fetch all ports of operation for admin management."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, name, code, is_active, created_at FROM ports_of_operation ORDER BY id ASC")
            ports = cursor.fetchall()
            for p in ports:
                if p.get('created_at') and hasattr(p['created_at'], 'isoformat'):
                    p['created_at'] = p['created_at'].isoformat()
        return jsonify(ports), 200
    except Exception as e:
        logger.exception("Error fetching admin ports: %s", e)
        return jsonify({'message': 'Failed to fetch ports'}), 500
    finally:
        conn.close()

@admin_bp.route('/ports', methods=['POST'])
@sub_admin_required('members')
def add_admin_port():
    """Add a new Port of Operation."""
    caller_id = get_jwt_identity()
    data = request.get_json() or {}
    name = data.get('name', '').strip()
    code = data.get('code', '').strip()

    if not name:
        return jsonify({'message': 'Port name is required.'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO ports_of_operation (name, code, is_active)
                VALUES (%s, %s, TRUE)
                RETURNING id, name, code, is_active
            """, (name, code))
            new_port = cursor.fetchone()
            
            # Audit log
            log_admin_action(caller_id, 'add_port_of_operation', 'port', new_port['id'], name, f"Added new Port of Operation: {name} ({code})")
            conn.commit()

        return jsonify({'message': 'Port added successfully!', 'port': new_port}), 201
    except Exception as e:
        conn.rollback()
        logger.exception("Error adding port: %s", e)
        return jsonify({'message': 'Failed to add port. Name may already exist.'}), 500
    finally:
        conn.close()

@admin_bp.route('/ports/<int:port_id>', methods=['PUT'])
@sub_admin_required('members')
def update_admin_port(port_id):
    """Update or toggle active status of a Port of Operation."""
    caller_id = get_jwt_identity()
    data = request.get_json() or {}
    name = data.get('name', '').strip()
    code = data.get('code', '').strip()
    is_active = data.get('is_active', True)

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE ports_of_operation 
                SET name = COALESCE(NULLIF(%s, ''), name),
                    code = COALESCE(NULLIF(%s, ''), code),
                    is_active = %s
                WHERE id = %s
                RETURNING id, name, code, is_active
            """, (name, code, is_active, port_id))
            updated = cursor.fetchone()
            if not updated:
                return jsonify({'message': 'Port not found'}), 404
            
            log_admin_action(caller_id, 'update_port_of_operation', 'port', port_id, updated['name'], f"Updated Port of Operation #{port_id}: active={is_active}")
            conn.commit()

        return jsonify({'message': 'Port updated successfully!', 'port': updated}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error updating port: %s", e)
        return jsonify({'message': 'Failed to update port'}), 500
    finally:
        conn.close()

@admin_bp.route('/ports/<int:port_id>', methods=['DELETE'])
@sub_admin_required('members')
def delete_admin_port(port_id):
    """Deactivates a Port of Operation."""
    caller_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE ports_of_operation SET is_active = FALSE WHERE id = %s RETURNING id, name", (port_id,))
            port = cursor.fetchone()
            if not port:
                return jsonify({'message': 'Port not found'}), 404
            log_admin_action(caller_id, 'deactivate_port_of_operation', 'port', port_id, port['name'], f"Deactivated Port of Operation: {port['name']}")
            conn.commit()
        return jsonify({'message': 'Port deactivated successfully!'}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error deactivating port: %s", e)
        return jsonify({'message': 'Failed to deactivate port'}), 500
    finally:
        conn.close()

