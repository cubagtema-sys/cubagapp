import os

PROFILE_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/profile_page.dart"

with open(PROFILE_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add port abbreviation helper
port_helper = """  String _formatPortAbbreviation(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.contains('KOTOKA') || s.contains('AIRPORT') || s == 'AIA' || s == 'KIA') return 'KIA';
    if (s.contains('TEMA')) return 'TEMA';
    if (s.contains('TAKORADI') || s == 'TKD') return 'TKD';
    if (s.contains('AFLAO')) return 'AFLAO';
    if (s.contains('ELUBO')) return 'ELUBO';
    if (s.contains('PAGA')) return 'PAGA';
    return s.replaceAll('PORT', '').trim();
  }"""

if "String _formatPortAbbreviation(String raw)" not in content:
    content = content.replace("  String _formatDate(String? str) {", port_helper + "\n\n  String _formatDate(String? str) {")

# 2. Update portStr in build()
content = content.replace(
    "final portStr = (_user['port_of_operation'] ?? _user['port'] ?? 'Tema Port').toString();",
    "final portRaw = (_user['port_of_operation'] ?? _user['port'] ?? 'Tema Port').toString();\n    final portStr = _formatPortAbbreviation(portRaw);"
)

# 3. Update KPI card from Licence Expiry to Member Expire
content = content.replace(
    "_buildMetricBox('Licence Expiry',",
    "_buildMetricBox('Member Expire',"
)

# 4. Update _buildComplianceCard: change Customs Licence PIN to Membership ID, and Licence Expiry to Member Expire
content = content.replace(
    "_itemRow('Customs Licence PIN', _user['license_number']?.toString() ?? _membershipId, Icons.confirmation_number_outlined, textPrimary, textMuted),",
    "_itemRow('Membership ID', _membershipId, Icons.badge_outlined, textPrimary, textMuted),"
)
content = content.replace(
    "_itemRow('Licence Expiry', expiry != null ? _formatDate(expiry) : 'Active & Valid', Icons.calendar_month_outlined, textPrimary, textMuted),",
    "_itemRow('Member Expire', expiry != null ? _formatDate(expiry) : 'Active & Valid', Icons.calendar_month_outlined, textPrimary, textMuted),"
)

# 5. In Digital ID card, update LICENCE PIN to CHAPTER / PORT and VALID UNTIL to MEMBER EXPIRE
old_id_box = """                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBERSHIP ID', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('LICENCE PIN', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_user['license_number']?.toString() ?? _membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('VALID UNTIL', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(expiry != null ? _formatDate(expiry) : 'Active / Valid', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),"""

new_id_box = """                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBERSHIP ID', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CHAPTER / PORT', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_formatPortAbbreviation((_user['port_of_operation'] ?? _user['port'] ?? 'Tema').toString()), style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBER EXPIRE', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(expiry != null ? _formatDate(expiry) : 'Active / Valid', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),"""

if old_id_box in content:
    content = content.replace(old_id_box, new_id_box)
    print("Replaced digital id box successfully")
else:
    print("Could not match old_id_box")

with open(PROFILE_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated profile_page.dart with all requested changes")
