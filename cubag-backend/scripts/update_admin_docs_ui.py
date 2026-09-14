import os

FLUTTER_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_documents_page.dart"

parts = []

parts.append('''import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/shimmer_loader.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../components/doc_preview_stub.dart'
    if (dart.library.html) '../components/doc_preview_web.dart' as doc_preview;
import '../utils/app_logger.dart';

const _kOrange      = Color(0xFFFF5000);
const _kDarkOrange  = Color(0xFFC25E17);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);
const _kAmber       = Color(0xFFF59E0B);
const _kBlue        = Color(0xFF3B82F6);
const _kIndigo      = Color(0xFF6366F1);
const _kSlate       = Color(0xFF1E293B);

// ─────────────────────────────────────────────────────────────────────────────
// 1. APPLICATION DOSSIERS DIRECTORY (LIST PAGE)
// ─────────────────────────────────────────────────────────────────────────────
class AdminDocumentsPage extends StatefulWidget {
  const AdminDocumentsPage({super.key});
  @override
  State<AdminDocumentsPage> createState() => _AdminDocumentsPageState();
}

class _AdminDocumentsPageState extends State<AdminDocumentsPage> {
  bool _loading = true;
  List<dynamic> _members = [];
  String _search = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_members.isEmpty) setState(() => _loading = true);
    try {
      final url = _filter == 'active'
          ? '/documents/admin/pending?status=active'
          : '/documents/admin/pending';
      await ApiService().fetchDataWithCache(
        url,
        (data, isCached, {hasError = false}) {
          if (mounted && data != null) {
            setState(() {
              _members = data['members'] ?? [];
              _loading = false;
            });
          }
        },
      );
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _members.map((m) => Map<String, dynamic>.from(m as Map)).toList();

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) {
        final name = (m['name'] as String? ?? '').toLowerCase();
        final comp = (m['company'] as String? ?? '').toLowerCase();
        final memNo = (m['membership_number'] as String? ?? '').toLowerCase();
        final email = (m['email'] as String? ?? '').toLowerCase();
        return name.contains(q) || comp.contains(q) || memNo.contains(q) || email.contains(q);
      }).toList();
    }

    if (_filter == 'sme') {
      list = list.where((m) => (m['member_scale'] as String? ?? '') == 'sme').toList();
    } else if (_filter == 'large_corporate') {
      list = list.where((m) => (m['member_scale'] as String? ?? '') == 'large_corporate').toList();
    } else if (_filter == 'incomplete') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        return up < 11;
      }).toList();
    } else if (_filter == 'pending_review') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
        return up >= 11 && ap < 11;
      }).toList();
    } else if (_filter != 'all' && _filter != 'active') {
      list = list.where((m) => (m['status'] as String?) == _filter).toList();
    }
    return list;
  }

  int get _totalCount => _members.length;
  int get _activeCount => _members.where((m) => m['status'] == 'active').length;
  int get _readyReviewCount => _members.where((m) {
    final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
    final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
    return up >= 11 && ap < 11;
  }).length;
  int get _incompleteCount => _members.where((m) {
    final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
    return up < 11;
  }).length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
    final borderColor = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AppLayout(
      title: 'Application Documents Hub',
      scrollable: false,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: AdminHeader(
                title: 'Corporate Dossiers & Licensing Hub',
                subtitle: 'Verify the 11 statutory CUBAG compliance certificates, review director vetting records, and approve membership.',
                actions: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                      side: BorderSide(color: borderColor, width: 1.2),
                      backgroundColor: cardBg,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => const _ManageRequirementsDialog(),
                      ).then((_) => _fetch());
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18, color: _kOrange),
                    label: Text(
                      'Manage 11 Rules',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      shadowColor: _kOrange.withAlpha(80),
                    ),
                    onPressed: _fetch,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  return isWide
                      ? Row(
                          children: [
                            Expanded(child: _buildMetricCard('Total Dossiers', '$_totalCount', 'All registered applicants', Icons.folder_shared_rounded, _kIndigo, cardBg, borderColor, textPrimary, textMuted)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMetricCard('Ready for Vetting', '$_readyReviewCount', '11/11 uploaded, pending review', Icons.hourglass_top_rounded, _kAmber, cardBg, borderColor, textPrimary, textMuted)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMetricCard('Incomplete Uploads', '$_incompleteCount', 'Less than 11 documents', Icons.pending_actions_rounded, _kBlue, cardBg, borderColor, textPrimary, textMuted)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMetricCard('Active & Approved', '$_activeCount', 'Good standing credentials', Icons.verified_rounded, _kGreen, cardBg, borderColor, textPrimary, textMuted)),
                          ],
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              SizedBox(width: 220, child: _buildMetricCard('Total Dossiers', '$_totalCount', 'All registered', Icons.folder_shared_rounded, _kIndigo, cardBg, borderColor, textPrimary, textMuted)),
                              const SizedBox(width: 10),
                              SizedBox(width: 220, child: _buildMetricCard('Ready for Review', '$_readyReviewCount', '11/11 uploaded', Icons.hourglass_top_rounded, _kAmber, cardBg, borderColor, textPrimary, textMuted)),
                              const SizedBox(width: 10),
                              SizedBox(width: 220, child: _buildMetricCard('Incomplete', '$_incompleteCount', '< 11 documents', Icons.pending_actions_rounded, _kBlue, cardBg, borderColor, textPrimary, textMuted)),
                              const SizedBox(width: 10),
                              SizedBox(width: 220, child: _buildMetricCard('Active & Vetted', '$_activeCount', 'Approved', Icons.verified_rounded, _kGreen, cardBg, borderColor, textPrimary, textMuted)),
                            ],
                          ),
                        );
                },
              ),
            ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F121A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _search = v),
                              style: GoogleFonts.outfit(fontSize: 13, color: textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search applicant company, director name, membership number or email...',
                                hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: textMuted),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                                suffixIcon: _search.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 16),
                                        onPressed: () => setState(() => _search = ''),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterTab('All Applicants', 'all', _totalCount, Icons.dashboard_rounded),
                          const SizedBox(width: 8),
                          _buildFilterTab('Ready for Review (11/11)', 'pending_review', _readyReviewCount, Icons.assignment_late_rounded, activeColor: _kAmber),
                          const SizedBox(width: 8),
                          _buildFilterTab('Incomplete Submissions', 'incomplete', _incompleteCount, Icons.hourglass_empty_rounded, activeColor: _kBlue),
                          const SizedBox(width: 8),
                          _buildFilterTab('Active & Approved', 'active', _activeCount, Icons.verified_user_rounded, activeColor: _kGreen),
                          const SizedBox(width: 8),
                          _buildFilterTab("SME's (1 Branch)", 'sme', null, Icons.storefront_rounded),
                          const SizedBox(width: 8),
                          _buildFilterTab('Large Corporate (2+)', 'large_corporate', null, Icons.corporate_fare_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141824) : const Color(0xFFF1F5F9),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text('#', style: _headerColStyle(textMuted)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('APPLICANT & CORPORATE FIRM', style: _headerColStyle(textMuted)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('CLASSIFICATION & SCOPE', style: _headerColStyle(textMuted)),
                    ),
                    SizedBox(
                      width: 170,
                      child: Center(
                        child: Text('11 STATUTORY DOCS', style: _headerColStyle(textMuted)),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Center(
                        child: Text('STATUS', style: _headerColStyle(textMuted)),
                      ),
                    ),
                    const SizedBox(width: 130, child: Center(child: Text('DOSSIER ACTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFF94A3B8))))),
                  ],
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    border: Border(
                      left: BorderSide(color: borderColor),
                      right: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
                    ),
                  ),
                  child: _loading
                      ? ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: 5,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, __) => const ShimmerListTile(),
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: _kOrange.withAlpha(15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.folder_off_rounded, size: 48, color: _kOrange.withAlpha(180)),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No applicant dossiers found matching the criteria.',
                                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Try adjusting your search keywords or switching filters.',
                                    style: GoogleFonts.inter(fontSize: 13, color: textMuted),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                              itemBuilder: (ctx, i) => _buildApplicantRow(
                                _filtered[i],
                                i + 1,
                                isDark,
                                cardBg,
                                borderColor,
                                textPrimary,
                                textMuted,
                              ),
                            ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    String desc,
    IconData icon,
    Color accentColor,
    Color bg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withAlpha(40)),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: textCol)),
                const SizedBox(height: 1),
                Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
                Text(desc, style: GoogleFonts.inter(fontSize: 10, color: subCol), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, String key, int? count, IconData icon, {Color? activeColor}) {
    final isSel = _filter == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = activeColor ?? _kOrange;

    return InkWell(
      onTap: () {
        setState(() {
          _filter = key;
          _members = [];
        });
        _fetch();
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? color.withAlpha(isDark ? 40 : 25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? color : (isDark ? const Color(0xFF2E3548) : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSel ? color : (isDark ? Colors.white70 : const Color(0xFF64748B))),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? color : (isDark ? Colors.white : const Color(0xFF334155)),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSel ? color : (isDark ? Colors.white12 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApplicantRow(
    Map<String, dynamic> m,
    int index,
    bool isDark,
    Color cardBg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    final name = ((m['name'] as String?) ?? 'Applicant').trim();
    final company = ((m['company'] as String?) ?? 'Unnamed Enterprise').trim();
    final email = (m['email'] as String?) ?? '';
    final phone = (m['phone'] as String?) ?? '';
    final scale = (m['member_scale'] as String? ?? 'sme').toLowerCase();
    final feeCat = (m['fee_category'] as String? ?? 'cf_only').toLowerCase();
    final status = (m['status'] as String?) ?? 'pending';
    final memNo = (m['membership_number'] as String?) ?? 'PENDING';
    final port = (m['port_of_operation'] as String?) ?? 'Tema Port';

    final rawUp = m['docs_uploaded'];
    final rawAp = m['docs_approved'];
    final uploaded = rawUp == null ? 0 : (rawUp as num).toInt();
    final approved = rawAp == null ? 0 : (rawAp as num).toInt();

    final isSme = scale == 'sme';
    final isDual = feeCat == 'cf_consolidation';
    final isConsol = feeCat == 'consolidation';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    if (status == 'active') {
      statusColor = _kGreen;
      statusLabel = 'Active Good Standing';
      statusIcon = Icons.verified_rounded;
    } else if (approved >= 11) {
      statusColor = _kGreen;
      statusLabel = '11/11 Vetted';
      statusIcon = Icons.check_circle_rounded;
    } else if (uploaded >= 11) {
      statusColor = _kAmber;
      statusLabel = 'In Review (11/11)';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (uploaded > 0) {
      statusColor = _kBlue;
      statusLabel = 'Incomplete ($uploaded/11)';
      statusIcon = Icons.upload_file_rounded;
    } else {
      statusColor = _kRed;
      statusLabel = '0/11 Uploaded';
      statusIcon = Icons.warning_amber_rounded;
    }

    return Material(
      color: cardBg,
      child: InkWell(
        onTap: () => context.push('/admin/documents/${m['id']}'),
        hoverColor: _kOrange.withAlpha(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '$index',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: subCol),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSme ? [_kOrange, _kDarkOrange] : [_kIndigo, const Color(0xFF3730A3)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: (isSme ? _kOrange : _kIndigo).withAlpha(40), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          company.isNotEmpty ? company[0].toUpperCase() : (name.isNotEmpty ? name[0].toUpperCase() : 'C'),
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company,
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textCol),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 12, color: subCol),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  name,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: subCol),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (email.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(width: 3, height: 3, decoration: BoxDecoration(color: subCol, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    email,
                                    style: GoogleFonts.inter(fontSize: 11, color: subCol),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              if (phone.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text('• $phone', style: GoogleFonts.inter(fontSize: 11, color: subCol)),
                              ],
                            ],
                          ),
                          if (memNo != 'PENDING' && memNo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('ID: $memNo', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: _kOrange)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSme ? _kOrange.withAlpha(25) : _kIndigo.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: (isSme ? _kOrange : _kIndigo).withAlpha(60)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isSme ? Icons.storefront_rounded : Icons.corporate_fare_rounded, size: 11, color: isSme ? _kOrange : _kIndigo),
                              const SizedBox(width: 4),
                              Text(
                                isSme ? "SME (1 BRANCH)" : "LARGE CORPORATE (2+)",
                                style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: isSme ? _kOrange : _kIndigo, letterSpacing: 0.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDual
                          ? 'Consolidation, Clearing & Forwarding'
                          : (isConsol ? 'Consolidation Scope' : 'Clearing & Forwarding Only'),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: textCol),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Port: $port',
                      style: GoogleFonts.inter(fontSize: 10, color: subCol),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_rounded, size: 13, color: uploaded >= 11 ? _kGreen : (uploaded > 0 ? _kOrange : _kRed)),
                        const SizedBox(width: 4),
                        Text(
                          '$uploaded / 11 Uploaded',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: uploaded >= 11 ? _kGreen : textCol,
                          ),
                        ),
                        if (approved > 0) ...[
                          const SizedBox(width: 8),
                          Text('($approved ✓)', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kGreen)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (uploaded / 11.0).clamp(0.0, 1.0),
                          backgroundColor: isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0),
                          color: uploaded >= 11 ? _kGreen : (uploaded >= 6 ? _kOrange : _kRed),
                          minHeight: 5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 130,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/admin/documents/${m['id']}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF242A3E) : const Color(0xFFF1F5F9),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                      side: BorderSide(color: _kOrange.withAlpha(120), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 14, color: _kOrange),
                    label: Text(
                      'Review Dossier',
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextStyle _headerColStyle(Color color) => GoogleFonts.outfit(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: 0.8,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. APPLICANT DOSSIER REVIEWER (DETAIL PAGE)
// ─────────────────────────────────────────────────────────────────────────────
class AdminMemberDocumentsPage extends StatefulWidget {
  final String memberId;
  const AdminMemberDocumentsPage({super.key, required this.memberId});
  @override
  State<AdminMemberDocumentsPage> createState() => _AdminMemberDocumentsPageState();
}

class _AdminMemberDocumentsPageState extends State<AdminMemberDocumentsPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _approvingAll = false;
  Map<String, dynamic> _member = {};
  List<dynamic> _docs = [];
  final Map<int, bool> _actionLoading = {};
  final Map<String, bool> _previewOpen = {};
  final Map<String, TextEditingController> _noteCtrl = {};
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    for (final c in _noteCtrl.values) {
      c.dispose();
    }
    _tab.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_docs.isEmpty) setState(() => _loading = true);
    try {
      await ApiService().fetchDataWithCache(
        '/documents/admin/member/${widget.memberId}',
        (data, isCached, {hasError = false}) {
          if (mounted && data != null) {
            setState(() {
              _member = Map<String, dynamic>.from(data['member'] as Map? ?? {});
              _docs = data['documents'] ?? [];
              _loading = false;
            });
          }
        },
      );
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(int docId, String status, String reqKey) async {
    setState(() => _actionLoading[docId] = true);
    try {
      final res = await ApiService().put(
        '/documents/admin/doc/$docId/status',
        data: {'status': status, 'note': _noteCtrl[reqKey]?.text.trim() ?? ''},
      );
      if (mounted) {
        _snack(
          status == 'approved' ? 'Certificate approved successfully' : 'Certificate marked as rejected with feedback',
          status == 'approved' ? _kGreen : _kRed,
        );
        if (res.statusCode == 200) _fetch();
      }
    } catch (_) {
      if (mounted) _snack('Network error updating document status', _kRed);
    }
    if (mounted) setState(() => _actionLoading[docId] = false);
  }

  Future<void> _approveAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kGreen.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified_rounded, color: _kGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Approve Entire Dossier (11/11)', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to approve all 11 statutory documents and verify ${_member['company'] ?? _member['name']} for official membership?',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text('Approve & Verify', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _approvingAll = true);
    try {
      final res = await ApiService().post('/documents/admin/member/${widget.memberId}/approve-all');
      if (mounted) {
        _snack(
          res.statusCode == 200
              ? 'Dossier approved! Membership verified: ${_member['membership_number'] ?? widget.memberId}'
              : (res.data['message'] ?? 'Failed'),
          res.statusCode == 200 ? _kGreen : _kRed,
        );
        if (res.statusCode == 200) _fetch();
      }
    } catch (_) {
      if (mounted) _snack('Network error', _kRed);
    }
    if (mounted) setState(() => _approvingAll = false);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(color == _kGreen ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13))),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  List<Map<String, dynamic>> _safeDocs(List<dynamic> raw) =>
      raw.map((d) => Map<String, dynamic>.from(d as Map)).toList();

  List<Map<String, dynamic>> get _all => _safeDocs(_docs);
  List<Map<String, dynamic>> get _pending =>
      _safeDocs(_docs).where((d) => d['uploaded'] == true && d['status'] == 'pending').toList();
  List<Map<String, dynamic>> get _approved =>
      _safeDocs(_docs).where((d) => d['status'] == 'approved').toList();
  List<Map<String, dynamic>> get _rejectedOrMissing =>
      _safeDocs(_docs).where((d) => d['uploaded'] != true || d['status'] == 'rejected').toList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final name = ((_member['name'] as String?) ?? 'Applicant').trim();
    final company = ((_member['company'] as String?) ?? 'Company / Enterprise').trim();
    final phone = (_member['phone'] as String?) ?? '';
    final tin = (_member['tin'] as String?) ?? '';
    final port = (_member['port_of_operation'] as String?) ?? 'Tema Port';
    final scale = (_member['member_scale'] as String? ?? 'sme').toLowerCase();
    final memNo = (_member['membership_number'] as String?) ?? 'PENDING';
    final hasPaid = _member['registration_fee_paid'] == true;

    final safeList = _safeDocs(_docs);
    final uploaded = safeList.where((d) => d['uploaded'] == true).length;
    final approved = safeList.where((d) => d['status'] == 'approved').length;
    final pending = safeList.where((d) => d['uploaded'] == true && d['status'] == 'pending').length;
    final total = safeList.length;

    final isApproved = (_member['status'] as String?) == 'active' ||
        (_member['status'] as String?) == 'approved' ||
        (total > 0 && approved == total);

    return AppLayout(
      title: 'Review Dossier — $company',
      scrollable: false,
      child: Container(
        color: bg,
        child: _loading
            ? ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, __) => const ShimmerListTile(),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border, width: 1.2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(isDark ? 40 : 8), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/admin/documents');
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF242A3E) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: textPrimary),
                                ),
                              ),
                              const SizedBox(width: 14),

                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: scale == 'sme' ? [_kOrange, _kDarkOrange] : [_kIndigo, const Color(0xFF3730A3)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    company.isNotEmpty ? company[0].toUpperCase() : 'C',
                                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            company,
                                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: scale == 'sme' ? _kOrange.withAlpha(25) : _kIndigo.withAlpha(25),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: (scale == 'sme' ? _kOrange : _kIndigo).withAlpha(60)),
                                          ),
                                          child: Text(
                                            scale == 'sme' ? "SME (1 BRANCH)" : "LARGE CORPORATE",
                                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: scale == 'sme' ? _kOrange : _kIndigo),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted)),
                                          ],
                                        ),
                                        if (phone.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.phone_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text(phone, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                            ],
                                          ),
                                        if (tin.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.tag_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text('TIN: $tin', style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                            ],
                                          ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.anchor_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(port, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: hasPaid ? _kGreen.withAlpha(20) : _kAmber.withAlpha(20),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: (hasPaid ? _kGreen : _kAmber).withAlpha(60)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('REGISTRATION FEE', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: hasPaid ? _kGreen : _kAmber, letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(hasPaid ? 'PAID IN FULL' : 'UNPAID (GHS 600)', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: hasPaid ? _kGreen : _kAmber)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              ElevatedButton.icon(
                                onPressed: (isApproved || _approvingAll) ? null : _approveAll,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isApproved ? Colors.grey.shade700 : _kGreen,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.withAlpha(120),
                                  disabledForegroundColor: Colors.white70,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: isApproved
                                    ? const Icon(Icons.check_circle_rounded, size: 18)
                                    : (_approvingAll
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.verified_rounded, size: 18)),
                                label: Text(
                                  isApproved ? 'Dossier Verified' : (_approvingAll ? 'Activating...' : 'Approve All (11/11)'),
                                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              _buildMiniPill('Total Required', '$total Docs', _kSlate, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Uploaded', '$uploaded / 11', _kBlue, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Awaiting Review', '$pending', _kAmber, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Approved & Vetted', '$approved', _kGreen, border, isDark),
                              const Spacer(),
                              if (memNo.isNotEmpty && memNo != 'PENDING')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _kOrange.withAlpha(20),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _kOrange.withAlpha(60)),
                                  ),
                                  child: Text('OFFICIAL ID: $memNo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: _kOrange)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        border: Border(
                          top: BorderSide(color: border),
                          left: BorderSide(color: border),
                          right: BorderSide(color: border),
                        ),
                      ),
                      child: TabBar(
                        controller: _tab,
                        isScrollable: false,
                        labelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800),
                        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                        labelColor: _kOrange,
                        unselectedLabelColor: textMuted,
                        indicatorColor: _kOrange,
                        indicatorWeight: 3,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: 'All Requirements (${_all.length})'),
                          Tab(text: 'Pending Review (${_pending.length})'),
                          Tab(text: 'Approved (${_approved.length})'),
                          Tab(text: 'Missing / Rejected (${_rejectedOrMissing.length})'),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                          border: Border.all(color: border),
                        ),
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _DocTable(docs: _all, isDark: isDark, border: border, cardBg: cardBg, previewOpen: _previewOpen, noteCtrl: _noteCtrl, actionLoading: _actionLoading, onStatus: _setStatus, onPreview: (k) => setState(() => _previewOpen[k] = !(_previewOpen[k] ?? false))),
                            _DocTable(docs: _pending, isDark: isDark, border: border, cardBg: cardBg, previewOpen: _previewOpen, noteCtrl: _noteCtrl, actionLoading: _actionLoading, onStatus: _setStatus, onPreview: (k) => setState(() => _previewOpen[k] = !(_previewOpen[k] ?? false))),
                            _DocTable(docs: _approved, isDark: isDark, border: border, cardBg: cardBg, previewOpen: _previewOpen, noteCtrl: _noteCtrl, actionLoading: _actionLoading, onStatus: _setStatus, onPreview: (k) => setState(() => _previewOpen[k] = !(_previewOpen[k] ?? false))),
                            _DocTable(docs: _rejectedOrMissing, isDark: isDark, border: border, cardBg: cardBg, previewOpen: _previewOpen, noteCtrl: _noteCtrl, actionLoading: _actionLoading, onStatus: _setStatus, onPreview: (k) => setState(() => _previewOpen[k] = !(_previewOpen[k] ?? false))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _buildMiniPill(String label, String value, Color color, Color border, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white70 : const Color(0xFF475569))),
          Text(value, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. REUSABLE DOCUMENT TABLE
// ─────────────────────────────────────────────────────────────────────────────
class _DocTable extends StatelessWidget {
  final List<Map<String, dynamic>> docs;
  final bool isDark;
  final Color border, cardBg;
  final Map<String, bool> previewOpen;
  final Map<String, TextEditingController> noteCtrl;
  final Map<int, bool> actionLoading;
  final void Function(int docId, String status, String reqKey) onStatus;
  final void Function(String reqKey) onPreview;

  const _DocTable({
    required this.docs,
    required this.isDark,
    required this.border,
    required this.cardBg,
    required this.previewOpen,
    required this.noteCtrl,
    required this.actionLoading,
    required this.onStatus,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 40, color: border),
            const SizedBox(height: 10),
            Text('No documents in this view', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: docs.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: border),
      itemBuilder: (ctx, i) {
        final doc = docs[i];
        final reqKey = (doc['key'] as String?) ?? 'doc_$i';
        noteCtrl.putIfAbsent(reqKey, () => TextEditingController());
        return _DocRow(
          doc: doc,
          reqKey: reqKey,
          index: i + 1,
          isDark: isDark,
          cardBg: cardBg,
          border: border,
          previewOpen: previewOpen[reqKey] == true,
          noteCtrl: noteCtrl[reqKey]!,
          actionLoading: actionLoading,
          onStatus: onStatus,
          onPreview: () => onPreview(reqKey),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. DOCUMENT CARD ROW
// ─────────────────────────────────────────────────────────────────────────────
class _DocRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  final String reqKey;
  final int index;
  final bool isDark, previewOpen;
  final Color cardBg, border;
  final TextEditingController noteCtrl;
  final Map<int, bool> actionLoading;
  final void Function(int, String, String) onStatus;
  final VoidCallback onPreview;

  const _DocRow({
    required this.doc,
    required this.reqKey,
    required this.index,
    required this.isDark,
    required this.previewOpen,
    required this.cardBg,
    required this.border,
    required this.noteCtrl,
    required this.actionLoading,
    required this.onStatus,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = doc['uploaded'] == true;
    final status = (doc['status'] as String?) ?? 'not_uploaded';
    final rawId = doc['id'];
    final docId = rawId == null ? null : (rawId as num).toInt();
    final fileUrl = doc['file_url'] as String?;
    final fileName = doc['file_name'] as String?;
    final adminNote = doc['admin_note'] as String?;
    final uploadedAt = doc['uploaded_at'] as String?;

    final ext = (fileName ?? fileUrl ?? '').split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = _kGreen;
        statusLabel = 'Approved';
        statusIcon = Icons.verified_rounded;
        break;
      case 'rejected':
        statusColor = _kRed;
        statusLabel = 'Rejected';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'pending':
        statusColor = _kAmber;
        statusLabel = 'Pending Review';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      default:
        statusColor = const Color(0xFF94A3B8);
        statusLabel = 'Not Uploaded';
        statusIcon = Icons.cloud_upload_outlined;
    }

    return Column(
      children: [
        Container(
          color: cardBg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF242A3E) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8)),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doc['label'] ?? '',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                          ),
                        ),
                        if (doc['is_required'] != false) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: _kRed.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                            child: Text('MANDATORY', style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: _kRed)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (uploaded && fileName != null)
                      Row(
                        children: [
                          Icon(isImage ? Icons.image_rounded : Icons.picture_as_pdf_rounded, size: 14, color: isImage ? _kBlue : _kRed),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              fileName,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (uploadedAt != null) ...[
                            const SizedBox(width: 8),
                            Text('• $uploadedAt', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                          ],
                        ],
                      )
                    else
                      Text('Awaiting member upload on onboarding portal', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic)),
                    if (adminNote != null && adminNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Note: $adminNote', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: status == 'rejected' ? _kRed : _kGreen)),
                    ],
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusLabel, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              if (uploaded && fileUrl != null) ...[
                OutlinedButton.icon(
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: previewOpen ? Colors.white : _kBlue,
                    backgroundColor: previewOpen ? _kBlue : Colors.transparent,
                    side: BorderSide(color: _kBlue.withAlpha(120)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                  ),
                  icon: Icon(previewOpen ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 14),
                  label: Text(previewOpen ? 'Hide' : 'Preview', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Open in new browser tab',
                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF64748B)),
                  onPressed: () async {
                    final uri = Uri.tryParse(fileUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ],

              if (status == 'pending' && docId != null) ...[
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'Reject',
                  icon: Icons.close_rounded,
                  color: _kRed,
                  loading: actionLoading[docId] == true,
                  onTap: () => onStatus(docId, 'rejected', reqKey),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  color: _kGreen,
                  loading: actionLoading[docId] == true,
                  onTap: () => onStatus(docId, 'approved', reqKey),
                ),
              ],
            ],
          ),
        ),

        if (status == 'pending' && docId != null)
          Container(
            color: isDark ? const Color(0xFF141722) : const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(62, 0, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: noteCtrl,
                    style: GoogleFonts.inter(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Enter feedback note if rejecting (e.g. "Expired GRA clearance", "Illegible certificate scan")...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E2436) : Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),

        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _PreviewPanel(
            fileUrl: fileUrl,
            isImage: isImage,
            reqKey: reqKey,
            isDark: isDark,
            border: border,
          ),
          crossFadeState: previewOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
        minimumSize: Size.zero,
      ),
      icon: loading
          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 14),
      label: Text(label, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final String? fileUrl;
  final bool isImage, isDark;
  final String reqKey;
  final Color border;

  const _PreviewPanel({
    required this.fileUrl,
    required this.isImage,
    required this.isDark,
    required this.reqKey,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    if (fileUrl == null) return const SizedBox.shrink();
    final viewKey = '${reqKey}_${fileUrl.hashCode}';

    return Container(
      margin: const EdgeInsets.fromLTRB(62, 0, 20, 14),
      height: isImage ? null : 480,
      constraints: isImage ? const BoxConstraints(maxHeight: 420) : null,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F121A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          ? InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: CorsImageWidget(
                url: fileUrl!,
                fit: BoxFit.contain,
                width: double.infinity,
                placeholder: const Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 2)),
                errorWidget: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_rounded, size: 36, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 6),
                      Text('Could not load image preview', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              ),
            )
          : kIsWeb
              ? doc_preview.buildDocPreview(fileUrl!, viewKey)
              : Center(child: Text('PDF embedded preview supported on web platform.', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. MANAGE REQUIREMENTS MODAL DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _ManageRequirementsDialog extends StatefulWidget {
  const _ManageRequirementsDialog();
  @override
  State<_ManageRequirementsDialog> createState() => _ManageRequirementsDialogState();
}

class _ManageRequirementsDialogState extends State<_ManageRequirementsDialog> {
  bool _loading = true;
  List<dynamic> _requirements = [];
  final _labelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final bool _isRequired = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/documents/admin/requirements');
      if (mounted && res.statusCode == 200 && res.data is Map) {
        setState(() {
          _requirements = res.data['requirements'] ?? [];
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addRequirement() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    setState(() => _saving = true);
    try {
      final res = await ApiService().post('/documents/admin/requirements', data: {
        'label': label,
        'description': _descCtrl.text.trim(),
        'is_required': _isRequired,
        'display_order': _requirements.length + 1,
      });
      if (mounted && res.statusCode == 201) {
        _labelCtrl.clear();
        _descCtrl.clear();
        _fetch();
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggleActive(int id, bool currentActive) async {
    try {
      await ApiService().put('/documents/admin/requirements/$id', data: {
        'is_active': !currentActive,
      });
      _fetch();
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
  }

  Future<void> _deleteRequirement(int id) async {
    try {
      setState(() {
        _requirements.removeWhere((r) => r['id'] == id);
      });
      final res = await ApiService().delete('/documents/admin/requirements/$id');
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Requirement deleted successfully'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _fetch();
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF181C28) : Colors.white;
    final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.tune_rounded, color: _kOrange, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Application Document Rules', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text('Configure the statutory documents required from corporate applicants.', style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2536) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add New Statutory Requirement', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _labelCtrl,
                            style: GoogleFonts.outfit(fontSize: 13, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: 'e.g. Proof of Port Operations Concession',
                              hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                              isDense: true,
                              filled: true,
                              fillColor: isDark ? const Color(0xFF141724) : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _addRequirement,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _saving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.add_rounded, size: 18),
                          label: Text('Add Rule', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text('Mandatory CUBAG Licensing Requirements (${_requirements.length})', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 10),

              Expanded(
                child: _loading
                    ? ListView.separated(
                        itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, __) => const ShimmerListTile(),
                      )
                    : _requirements.isEmpty
                        ? Center(child: Text('No requirements configured.', style: GoogleFonts.outfit(color: textMuted)))
                        : ListView.separated(
                            itemCount: _requirements.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final item = Map<String, dynamic>.from(_requirements[i] as Map);
                              final id = item['id'] as int;
                              final label = item['label'] as String;
                              final isActive = item['is_active'] == true;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1F2536) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(color: _kOrange.withAlpha(25), shape: BoxShape.circle),
                                      child: Center(child: Text('${i + 1}', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: _kOrange))),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          decoration: isActive ? null : TextDecoration.lineThrough,
                                          color: isActive ? textPrimary : textMuted,
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: isActive,
                                      activeThumbColor: _kGreen,
                                      onChanged: (_) => _toggleActive(id, isActive),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _kRed),
                                      onPressed: () => _deleteRequirement(id),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''')

final_code = "".join(parts)
with open(FLUTTER_FILE, "w", encoding="utf-8") as f:
    f.write(final_code)

print(f"Successfully generated {len(final_code.splitlines())} lines to {FLUTTER_FILE}")
