import os
import re

FLUTTER_DIR = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter"
BACKEND_DIR = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag-backend"

# 1. Update routes/payments.py to return real ref_code & payment_ref in admin/all
payments_py = os.path.join(BACKEND_DIR, "routes/payments.py")
with open(payments_py, "r", encoding="utf-8") as f:
    code = f.read()

# Replace query in get_all_payments_admin
old_q = """            data_query = f\"\"\"
                SELECT p.id as tx_id, p.amount, p.description, p.status,
                       p.payment_ref, p.created_at, m.name as member_name
                FROM payments p
                LEFT JOIN members m ON p.member_id = m.id
                {where_sql}
                ORDER BY p.created_at DESC
                LIMIT %s OFFSET %s
            \"\"\""""

new_q = """            data_query = f\"\"\"
                SELECT p.id as id, p.id as tx_id, p.amount, p.description, p.status,
                       p.payment_ref, p.created_at, m.name as member_name,
                       COALESCE(NULLIF(p.payment_ref, ''), CONCAT('TXN-', LPAD(p.id::text, 6, '0'))) as ref_code
                FROM payments p
                LEFT JOIN members m ON p.member_id = m.id
                {where_sql}
                ORDER BY p.created_at DESC
                LIMIT %s OFFSET %s
            \"\"\""""

if old_q in code:
    code = code.replace(old_q, new_q)
    print("Updated routes/payments.py data_query")
else:
    print("Could not match old_q in routes/payments.py")

# Update search in routes/payments.py
old_s = 'where_clauses.append("(LOWER(m.name) LIKE %s OR LOWER(p.description) LIKE %s)")'
new_s = 'where_clauses.append("(LOWER(m.name) LIKE %s OR LOWER(p.description) LIKE %s OR LOWER(COALESCE(p.payment_ref, \'\')) LIKE %s)")'
if old_s in code:
    code = code.replace(old_s, new_s)
    code = code.replace('params.extend([f"%{search}%", f"%{search}%"])', 'params.extend([f"%{search}%", f"%{search}%", f"%{search}%"])')
    print("Updated search in routes/payments.py")

with open(payments_py, "w", encoding="utf-8") as f:
    f.write(code)


# 2. Update admin_payments_page.dart
admin_pay_dart = os.path.join(FLUTTER_DIR, "lib/pages/admin_payments_page.dart")
with open(admin_pay_dart, "r", encoding="utf-8") as f:
    pdart = f.read()

# Replace txId extraction with real transaction ref
old_tx_extract = """                            final txId = tx['tx_id']?.toString() ?? '—';"""
new_tx_extract = """                            final rawRef = tx['payment_ref']?.toString().trim();
                            final refCode = tx['ref_code']?.toString().trim();
                            final txId = (rawRef != null && rawRef.isNotEmpty && rawRef != 'null' && rawRef != 'None')
                                ? rawRef
                                : (refCode != null && refCode.isNotEmpty && refCode != 'null')
                                    ? refCode
                                    : 'TXN-${(tx['tx_id'] ?? tx['id'] ?? '1').toString().padLeft(6, '0')}';"""

if old_tx_extract in pdart:
    pdart = pdart.replace(old_tx_extract, new_tx_extract)
    print("Updated admin_payments_page.dart txId to real transaction reference")

with open(admin_pay_dart, "w", encoding="utf-8") as f:
    f.write(pdart)


# 3. Update profile_page.dart with strict port abbreviation and clean KPI card
profile_dart = os.path.join(FLUTTER_DIR, "lib/pages/profile_page.dart")
with open(profile_dart, "r", encoding="utf-8") as f:
    prod = f.read()

old_port_func = """  String _formatPortAbbreviation(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.contains('KOTOKA') || s.contains('AIRPORT') || s == 'AIA' || s == 'KIA') return 'KIA';
    if (s.contains('TEMA')) return 'TEMA';
    if (s.contains('TAKORADI') || s == 'TKD') return 'TKD';
    if (s.contains('AFLAO')) return 'AFLAO';
    if (s.contains('ELUBO')) return 'ELUBO';
    if (s.contains('PAGA')) return 'PAGA';
    return s.replaceAll('PORT', '').trim();
  }"""

new_port_func = """  String _formatPortAbbreviation(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty || s == 'NULL' || s == 'NONE') return 'KIA';
    if (s.contains('KOTOKA') || s.contains('AIRPORT') || s.contains('ACCRA') || s == 'AIA' || s == 'KIA') return 'KIA';
    if (s.contains('TEMA')) return 'TEMA';
    if (s.contains('TAKORADI') || s == 'TKD' || s.contains('SEKONDI')) return 'TKD';
    if (s.contains('AFLAO')) return 'AFLAO';
    if (s.contains('ELUBO')) return 'ELUBO';
    if (s.contains('PAGA')) return 'PAGA';
    if (s.contains('SUNYANI')) return 'SUN';
    if (s.contains('KUMASI')) return 'KMS';
    final cleaned = s.replaceAll('PORT', '').replaceAll('BORDER', '').replaceAll('CHAPTER', '').trim();
    if (cleaned.length > 5) return cleaned.substring(0, 4);
    return cleaned.isNotEmpty ? cleaned : 'KIA';
  }"""

if old_port_func in prod:
    prod = prod.replace(old_port_func, new_port_func)
    print("Updated _formatPortAbbreviation in profile_page.dart")

# Also update metric box for port to have short subtitle 'Chapter'
prod = prod.replace("_buildMetricBox('Operating Port', portStr, 'Chapter Assignment'", "_buildMetricBox('Operating Port', portStr, 'Chapter'")

# Replace 'Licencing & Standing Status' with 'Membership & Standing Status'
prod = prod.replace("'Licencing & Standing Status'", "'Membership & Standing Status'")
prod = prod.replace("'• License renewal status:", "'• Membership validity status:")

with open(profile_dart, "w", encoding="utf-8") as f:
    f.write(prod)


# 4. Replace "Customs License" / "Customs Licence" with "Member ID" across frontend and backend
replacements = [
    (os.path.join(FLUTTER_DIR, "lib/pages/admin_settings_page.dart"), "Active Valid Customs License (pts)", "Active Valid Member ID (pts)"),
    (os.path.join(FLUTTER_DIR, "lib/pages/compliance_centre_page.dart"), "Customs Licence Application", "Member ID Application"),
    (os.path.join(FLUTTER_DIR, "lib/pages/compliance_centre_page.dart"), "Manage your license renewal & customs licence applications", "Manage your membership renewal & Member ID applications"),
    (os.path.join(FLUTTER_DIR, "lib/pages/admin_compliance_page.dart"), "Customs Licence Application", "Member ID Application"),
    (os.path.join(FLUTTER_DIR, "lib/pages/guest_service_request_page.dart"), "Customs License #", "Member ID #"),
    (os.path.join(FLUTTER_DIR, "lib/pages/admin_sub_admins_page.dart"), "Review customs licensing renewal applications and scores", "Review Member ID renewal applications and scores"),
    (os.path.join(FLUTTER_DIR, "lib/pages/admin_sub_admins_page.dart"), "Customs licence, renewals & document inspection", "Member ID, renewals & document inspection"),
    (os.path.join(FLUTTER_DIR, "lib/pages/payment_history_page.dart"), "Customs License #", "Member ID #"),
    (os.path.join(FLUTTER_DIR, "lib/pages/payments_page.dart"), "Customs Licence Application", "Member ID Application"),
    (os.path.join(BACKEND_DIR, "routes/compliance.py"), "Customs Licence Application", "Member ID Application"),
    (os.path.join(BACKEND_DIR, "routes/payments.py"), "Customs Licence Application", "Member ID Application"),
    (os.path.join(BACKEND_DIR, "routes/tasks.py"), "Customs Licence Application", "Member ID Application"),
]

for file_path, old_str, new_str in replacements:
    if os.path.exists(file_path):
        with open(file_path, "r", encoding="utf-8") as f:
            c = f.read()
        if old_str in c:
            c = c.replace(old_str, new_str)
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(c)
            print(f"Replaced '{old_str}' -> '{new_str}' in {os.path.basename(file_path)}")

print("All batch updates applied successfully!")
