import os

TARGET = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_documents_page.dart"

code = '''import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kSlate = Color(0xFF1E293B);

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
  String _selectedCategory = 'corporate'; // 'corporate', 'licentiate', 'associate'

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
    SocketService().socket?.on('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().socket?.on('member_documents_updated', _onRulesUpdatedSocket);
  }

  void _onRulesUpdatedSocket(dynamic _) {
    if (mounted) {
      ApiService.deleteCacheKeysMatching('documents/admin');
      _fetch(forceRefresh: true);
    }
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _search = v);
      }
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().socket?.off('member_documents_updated', _onRulesUpdatedSocket);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await ApiService.deleteCacheKeysMatching('documents/admin');
    }
    if (_members.isEmpty) setState(() => _loading = true);
    try {
      final res = await ApiService().get('/documents/admin/pending?status=all');
      if (mounted && res.statusCode == 200 && res.data is Map) {
        setState(() {
          _members = res.data['members'] ?? [];
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _getAllMembers() {
    return _members
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getMembersForCategory(String category) {
    final all = _getAllMembers();
    return all.where((m) {
      final mType = (m['member_type']?.toString().toLowerCase() ?? 'corporate');
      if (category == 'corporate') {
        return mType.contains('corporate') ||
            mType.contains('company') ||
            (!mType.contains('licentiate') && !mType.contains('associate'));
      } else if (category == 'licentiate') {
        return mType.contains('licentiate') ||
            (mType.contains('broker') && !mType.contains('corporate'));
      } else if (category == 'associate') {
        return mType.contains('associate');
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _getMembersForCategory(_selectedCategory);

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
      list = list
          .where((m) => (m['member_scale'] as String? ?? '') == 'sme')
          .toList();
    } else if (_filter == 'large_corporate') {
      list = list
          .where((m) => (m['member_scale'] as String? ?? '') == 'large_corporate')
          .toList();
    } else if (_filter == 'incomplete') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return totalReq > 0 && up < totalReq;
      }).toList();
    } else if (_filter == 'pending_review') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return totalReq > 0 && up >= totalReq && ap < totalReq;
      }).toList();
    } else if (_filter == 'fully_approved') {
      list = list.where((m) {
        final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return (totalReq > 0 && ap >= totalReq) || totalReq == 0;
      }).toList();
    }

    return list;
  }

  TextStyle _headerColStyle(Color textMuted) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: textMuted,
    );
  }

  Widget _buildCategoryButton({
    required String title,
    required String subtitle,
    required String category,
    required int count,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
  }) {
    final isSelected = _selectedCategory == category;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCategory = category;
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(isDark ? 35 : 20) : cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? color : Colors.grey),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E110A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF2B1910) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4A2E1F)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final corpMembers = _getMembersForCategory('corporate');
    final licMembers = _getMembersForCategory('licentiate');
    final assocMembers = _getMembersForCategory('associate');

    return AppLayout(
      title: 'Registration Hub',
      scrollable: false,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: AdminHeader(
                title: 'Registration',
                subtitle:
                    'Verify statutory CUBAG compliance certificates, review director vetting records, and approve membership.',
                actions: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.white
                          : const Color(0xFF1E293B),
                      side: BorderSide(color: borderColor, width: 1.2),
                      backgroundColor: cardBg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      context.push('/admin/document-rules').then((_) => _fetch(forceRefresh: true));
                    },
                    icon: const Icon(
                      Icons.rule_folder_rounded,
                      size: 18,
                      color: _kOrange,
                    ),
                    label: Text(
                      'Document Rules',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _fetch(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      'Refresh Dossiers',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  _buildCategoryButton(
                    title: 'Corporate Brokerages',
                    subtitle: 'Full Statutory Compliance',
                    category: 'corporate',
                    count: corpMembers.length,
                    icon: Icons.business_rounded,
                    color: _kIndigo,
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                  const SizedBox(width: 12),
                  _buildCategoryButton(
                    title: 'Licentiate Agents',
                    subtitle: 'Individual Licensed Brokers',
                    category: 'licentiate',
                    count: licMembers.length,
                    icon: Icons.badge_rounded,
                    color: _kOrange,
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                  const SizedBox(width: 12),
                  _buildCategoryButton(
                    title: 'Associate / Affiliates',
                    subtitle: 'Maritime Partners & Allied',
                    category: 'associate',
                    count: assocMembers.length,
                    icon: Icons.handshake_rounded,
                    color: _kGreen,
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        onChanged: _onSearchChanged,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search applicant dossiers by name, company, TIN or membership number...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: textMuted,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: textMuted,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterTab('All Dossiers', 'all', _getMembersForCategory(_selectedCategory).length, Icons.folder_copy_rounded),
                  const SizedBox(width: 8),
                  _buildFilterTab(
                    'Needs Review',
                    'pending_review',
                    _getMembersForCategory(_selectedCategory).where((m) {
                      final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
                      final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
                      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
                      return totalReq > 0 && up >= totalReq && ap < totalReq;
                    }).length,
                    Icons.hourglass_top_rounded,
                    activeColor: _kAmber,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterTab(
                    'Incomplete',
                    'incomplete',
                    _getMembersForCategory(_selectedCategory).where((m) {
                      final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
                      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
                      return totalReq > 0 && up < totalReq;
                    }).length,
                    Icons.upload_file_rounded,
                    activeColor: _kBlue,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterTab(
                    'Vetted',
                    'fully_approved',
                    _getMembersForCategory(_selectedCategory).where((m) {
                      final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
                      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
                      return (totalReq > 0 && ap >= totalReq) || totalReq == 0;
                    }).length,
                    Icons.check_circle_rounded,
                    activeColor: _kGreen,
                  ),
                ],
              ),
            ),

            // ── TABLE HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E110A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
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
                      child: Text(
                        'APPLICANT & CORPORATE FIRM',
                        style: _headerColStyle(textMuted),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CLASSIFICATION & SCOPE',
                        style: _headerColStyle(textMuted),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: Center(
                        child: Text(
                          'STATUTORY DOCS',
                          style: _headerColStyle(textMuted),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: Center(
                        child: Text(
                          'STATUS',
                          style: _headerColStyle(textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 130,
                      child: Center(
                        child: Text(
                          'DOSSIER ACTION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
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
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
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
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) => const ShimmerListTile(),
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
                                child: Icon(
                                  Icons.folder_off_rounded,
                                  size: 48,
                                  color: _kOrange.withAlpha(180),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No applicant dossiers found matching the criteria.',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Try adjusting your search keywords or switching filters.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _filtered.length,
                          separatorBuilder: (_, index) =>
                              Divider(height: 1, color: borderColor),
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

  Widget _buildFilterTab(
    String label,
    String key,
    int? count,
    IconData icon, {
    Color? activeColor,
  }) {
    final isSel = _filter == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = activeColor ?? _kOrange;

    return InkWell(
      onTap: () {
        setState(() {
          _filter = key;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSel
              ? color.withAlpha(isDark ? 35 : 20)
              : (isDark ? const Color(0xFF381F15) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel
                ? color.withAlpha(isDark ? 100 : 70)
                : (isDark ? const Color(0xFF4A2E1F) : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSel
                  ? color
                  : (isDark ? Colors.white70 : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel
                    ? color
                    : (isDark ? Colors.white : const Color(0xFF334155)),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSel
                      ? color
                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSel
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
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
    final status = (m['status'] as String?) ?? 'pending';
    final memNo = (m['membership_number'] as String?) ?? 'PENDING';
    final port = (m['port_of_operation'] as String?) ?? 'Tema Port';

    final rawUp = m['docs_uploaded'];
    final rawAp = m['docs_approved'];
    final uploaded = rawUp == null ? 0 : (rawUp as num).toInt();
    final approved = rawAp == null ? 0 : (rawAp as num).toInt();

    final memberType = (m['member_type'] as String? ?? 'Licentiate').trim();
    final isSme = ((m['member_scale'] as String? ?? 'sme').toLowerCase()) == 'sme';
    final isDual = ((m['fee_category'] as String? ?? 'cf_only').toLowerCase()) == 'cf_consolidation';
    final isConsol = ((m['fee_category'] as String? ?? 'cf_only').toLowerCase()) == 'consolidation';

    final totalExpected = (m['total_required'] as num?)?.toInt() ?? 0;

    Color typeColor = _kOrange;
    if (memberType.toLowerCase().contains('corporate')) {
      typeColor = _kIndigo;
    } else if (memberType.toLowerCase().contains('associate')) {
      typeColor = _kGreen;
    }

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    if (status == 'active') {
      statusColor = _kGreen;
      statusLabel = 'Active Good Standing';
      statusIcon = Icons.verified_rounded;
    } else if (totalExpected == 0) {
      statusColor = _kGreen;
      statusLabel = 'No Document Required';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (approved >= totalExpected && totalExpected > 0) {
      statusColor = _kGreen;
      statusLabel = '$totalExpected/$totalExpected Vetted';
      statusIcon = Icons.check_circle_rounded;
    } else if (uploaded >= totalExpected) {
      statusColor = _kAmber;
      statusLabel = 'In Review ($uploaded/$totalExpected)';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (uploaded > 0) {
      statusColor = _kBlue;
      statusLabel = 'Incomplete ($uploaded/$totalExpected)';
      statusIcon = Icons.upload_file_rounded;
    } else {
      statusColor = _kRed;
      statusLabel = '0/$totalExpected Uploaded';
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
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: subCol,
                  ),
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
                          colors: [typeColor, typeColor.withAlpha(180)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: typeColor.withAlpha(40),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          company.isNotEmpty
                              ? company[0].toUpperCase()
                              : (name.isNotEmpty ? name[0].toUpperCase() : 'C'),
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
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
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: textCol,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 12,
                                color: subCol,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: subCol,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (memNo.isNotEmpty && memNo != 'PENDING') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kOrange.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    memNo,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _kOrange,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: typeColor.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                size: 11,
                                color: typeColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                memberType.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: typeColor,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (memberType.toLowerCase().contains('corporate'))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (isSme ? _kOrange : _kIndigo).withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: (isSme ? _kOrange : _kIndigo).withAlpha(50),
                              ),
                            ),
                            child: Text(
                              isSme ? "SME (1 BRANCH)" : "LARGE CORP (2+)",
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isSme ? _kOrange : _kIndigo,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (memberType.toLowerCase().contains('corporate')) ...[
                      const SizedBox(height: 4),
                      Text(
                        isDual
                            ? 'Consolidation, Clearing & Forwarding'
                            : (isConsol
                                  ? 'Consolidation Scope'
                                  : 'Clearing & Forwarding Only'),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textCol,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                child: totalExpected == 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 13,
                                color: _kGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '0 / 0 Uploaded',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _kGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kGreen.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'No Document Required',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: _kGreen,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.upload_file_rounded,
                                size: 13,
                                color: uploaded >= totalExpected
                                    ? _kGreen
                                    : (uploaded > 0 ? _kOrange : _kRed),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$uploaded / $totalExpected Uploaded',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: uploaded >= totalExpected
                                      ? _kGreen
                                      : textCol,
                                ),
                              ),
                              if (approved > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '($approved ✓)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _kGreen,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (uploaded / totalExpected.toDouble())
                                    .clamp(0.0, 1.0),
                                backgroundColor: isDark
                                    ? const Color(0xFF4A2E1F)
                                    : const Color(0xFFE2E8F0),
                                color: uploaded >= totalExpected
                                    ? _kGreen
                                    : (uploaded >= (totalExpected / 2)
                                          ? _kOrange
                                          : _kRed),
                                minHeight: 5,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(
                width: 140,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
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
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
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
                    onPressed: () =>
                        context.push('/admin/documents/${m['id']}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF381F15)
                          : const Color(0xFFF1F5F9),
                      foregroundColor: textCol,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: border),
                      ),
                    ),
                    icon: const Icon(
                      Icons.folder_open_rounded,
                      size: 14,
                      color: _kOrange,
                    ),
                    label: Text(
                      'View Dossier',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REVIEW APPLICANT DOSSIER PAGE (FULL VIEW FOR AN APPLICANT)
// ─────────────────────────────────────────────────────────────────────────────
class ReviewApplicantPage extends StatefulWidget {
  final int memberId;
  const ReviewApplicantPage({super.key, required this.memberId});

  @override
  State<ReviewApplicantPage> createState() => _ReviewApplicantPageState();
}

class _ReviewApplicantPageState extends State<ReviewApplicantPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _hasError = false;
  Map<String, dynamic> _member = {};
  List<dynamic> _docs = [];
  late TabController _tab;
  final Map<int, bool> _actionLoading = {};
  final Map<String, TextEditingController> _noteCtrl = {};
  bool _approvingAll = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _fetch();
    SocketService().socket?.on('member_documents_updated', _onMemberDocsUpdatedSocket);
  }

  void _onMemberDocsUpdatedSocket(dynamic data) {
    if (mounted) {
      if (data is Map && data['member_id'] != null) {
        if (data['member_id'].toString() == widget.memberId.toString()) {
          _fetch(forceRefresh: true);
        }
      } else {
        _fetch(forceRefresh: true);
      }
    }
  }

  @override
  void dispose() {
    SocketService().socket?.off('member_documents_updated', _onMemberDocsUpdatedSocket);
    for (final c in _noteCtrl.values) {
      c.dispose();
    }
    _tab.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      if (forceRefresh) {
        await ApiService.deleteCacheKeysMatching('documents/admin/member/${widget.memberId}');
      }
      final res = await ApiService().get('/documents/admin/member/${widget.memberId}');
      if (mounted && res.statusCode == 200 && res.data != null) {
        final d = res.data is Map ? res.data : {};
        setState(() {
          _member = Map<String, dynamic>.from(d['member'] as Map? ?? {});
          _docs = d['documents'] is List ? d['documents'] : [];
          _loading = false;
          _hasError = false;
        });
        return;
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (_docs.isEmpty) _hasError = true;
      });
    }
  }

  Future<void> _setStatus(int docId, String status, String reqKey) async {
    setState(() => _actionLoading[docId] = true);
    try {
      final res = await ApiService().post(
        '/documents/admin/review/$docId',
        data: {'status': status, 'admin_note': _noteCtrl[reqKey]?.text.trim() ?? ''},
      );
      if (mounted) {
        _snack(
          status == 'approved'
              ? 'Certificate approved successfully'
              : 'Certificate marked as rejected with feedback',
          status == 'approved' ? _kGreen : _kRed,
        );
        if (res.statusCode == 200) _fetch(forceRefresh: true);
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
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: _kGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verify & Approve Dossier',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'This will approve all uploaded documents and verify the applicant for membership. Continue?',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve Dossier'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _approvingAll = true);
    try {
      final res = await ApiService().post(
        '/documents/admin/member/${widget.memberId}/approve-all',
      );
      if (mounted) {
        if (res.statusCode == 200) {
          _snack('All application documents approved and verified!', _kGreen);
          _fetch(forceRefresh: true);
        } else {
          _snack('Failed to approve documents. Try again.', _kRed);
        }
      }
    } catch (_) {
      if (mounted) _snack('Network error while approving dossier', _kRed);
    }
    if (mounted) setState(() => _approvingAll = false);
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Map<String, dynamic>> _safeDocs(List<dynamic> list) =>
      list.map((d) => Map<String, dynamic>.from(d as Map)).toList();

  List<Map<String, dynamic>> get _pendingReview => _safeDocs(
    _docs,
  ).where((d) => d['uploaded'] == true && d['status'] == 'pending').toList();
  List<Map<String, dynamic>> get _approved =>
      _safeDocs(_docs).where((d) => d['status'] == 'approved').toList();
  List<Map<String, dynamic>> get _rejectedOrMissing => _safeDocs(
    _docs,
  ).where((d) => d['uploaded'] != true || d['status'] == 'rejected').toList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E110A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF4A2E1F) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF2B1910) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark
        ? Colors.white
        : const Color(0xFF64748B);

    final name = ((_member['name'] as String?) ?? 'Applicant').trim();
    final company = ((_member['company'] as String?) ?? 'Company / Enterprise')
        .trim();
    final phone = (_member['phone'] as String?) ?? '';
    final tin = (_member['tin'] as String?) ?? '';
    final port = (_member['port_of_operation'] as String?) ?? 'Tema Port';
    final memberType = ((_member['member_type'] as String?) ?? 'Licentiate').trim();
    final isCorporate = memberType.toLowerCase().contains('corporate');
    Color headerTypeColor = _kOrange;
    if (isCorporate) {
      headerTypeColor = _kIndigo;
    } else if (memberType.toLowerCase().contains('associate')) {
      headerTypeColor = _kGreen;
    }
    final scale = (_member['member_scale'] as String? ?? 'sme').toLowerCase();
    final hasPaid = _member['registration_fee_paid'] == true;
    final regFeeRaw = _member['registration_fee_amount'];
    final regFeeAmt = regFeeRaw != null ? (double.tryParse(regFeeRaw.toString()) ?? 0.0) : 0.0;
    final lastPaymentRaw = _member['last_payment_amount'];
    final lastPaymentAmt = lastPaymentRaw != null ? (double.tryParse(lastPaymentRaw.toString()) ?? 0.0) : null;

    final safeList = _safeDocs(_docs);
    final uploaded = safeList.where((d) => d['uploaded'] == true).length;
    final approved = safeList.where((d) => d['status'] == 'approved').length;
    final pending = safeList
        .where((d) => d['uploaded'] == true && d['status'] == 'pending')
        .length;
    final total = safeList.length;

    final isApproved =
        (_member['status'] as String?) == 'active' ||
        (_member['status'] as String?) == 'approved' ||
        (total > 0 && approved == total);

    return AppLayout(
      title: 'Review Applicant — $company',
      scrollable: false,
      child: Container(
        color: bg,
        child: _loading
            ? ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: 6,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (_, index) => const ShimmerListTile(),
              )
            : _hasError && _docs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
                          const SizedBox(height: 14),
                          Text(
                            'Unable to load applicant documents.',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retry Loading'),
                            onPressed: () => _fetch(forceRefresh: true),
                          ),
                        ],
                      ),
                    ),
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
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 40 : 8),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
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
                                    color: isDark
                                        ? const Color(0xFF381F15)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 16,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [headerTypeColor, headerTypeColor.withAlpha(180)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    company.isNotEmpty
                                        ? company[0].toUpperCase()
                                        : 'C',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
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
                                            style: GoogleFonts.outfit(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: headerTypeColor.withAlpha(25),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: headerTypeColor.withAlpha(60),
                                            ),
                                          ),
                                          child: Text(
                                            memberType.toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: headerTypeColor,
                                            ),
                                          ),
                                        ),
                                        if (isCorporate) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (scale == 'sme' ? _kOrange : _kIndigo).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: (scale == 'sme' ? _kOrange : _kIndigo).withAlpha(50),
                                              ),
                                            ),
                                            child: Text(
                                              scale == 'sme' ? "SME (1 BRANCH)" : "LARGE CORPORATE",
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: scale == 'sme' ? _kOrange : _kIndigo,
                                              ),
                                            ),
                                          ),
                                        ],
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
                                            Icon(
                                              Icons.person_rounded,
                                              size: 13,
                                              color: textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              name,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (phone.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.phone_rounded,
                                                size: 13,
                                                color: textMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                phone,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (tin.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.tag_rounded,
                                                size: 13,
                                                color: textMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'TIN: $tin',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.anchor_rounded,
                                              size: 13,
                                              color: textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              port,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: hasPaid
                                      ? _kGreen.withAlpha(20)
                                      : _kAmber.withAlpha(20),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: (hasPaid ? _kGreen : _kAmber)
                                        .withAlpha(60),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'REGISTRATION STATUS',
                                      style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: hasPaid ? _kGreen : _kAmber,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      hasPaid
                                          ? (lastPaymentAmt != null && lastPaymentAmt > 0
                                              ? 'PAID (GHS ${lastPaymentAmt.toStringAsFixed(2)})'
                                              : 'PAID IN FULL')
                                          : (regFeeAmt > 0
                                              ? 'UNPAID (GHS ${regFeeAmt.toStringAsFixed(2)})'
                                              : 'UNPAID'),
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: hasPaid ? _kGreen : _kAmber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              ElevatedButton.icon(
                                onPressed: (isApproved || _approvingAll)
                                    ? null
                                    : _approveAll,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isApproved
                                      ? Colors.grey.shade700
                                      : _kGreen,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey
                                      .withAlpha(120),
                                  disabledForegroundColor: Colors.white70,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: isApproved
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                      )
                                    : (_approvingAll
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.verified_rounded,
                                              size: 18,
                                            )),
                                label: Text(
                                  isApproved
                                      ? 'Dossier Verified'
                                      : (_approvingAll
                                            ? 'Activating...'
                                            : (total > 0
                                                  ? 'Approve All ($total/$total)'
                                                  : 'Approve Application')),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              _buildMiniPill(
                                'Total Required',
                                '$total Docs',
                                _kSlate,
                                border,
                                isDark,
                              ),
                              const SizedBox(width: 8),
                              _buildMiniPill(
                                'Uploaded',
                                total > 0 ? '$uploaded / $total' : '0 / 0 (None Req)',
                                _kBlue,
                                border,
                                isDark,
                              ),
                              const SizedBox(width: 8),
                              _buildMiniPill(
                                'Awaiting Review',
                                '$pending',
                                _kAmber,
                                border,
                                isDark,
                              ),
                              const SizedBox(width: 8),
                              _buildMiniPill(
                                'Approved & Vetted',
                                '$approved',
                                _kGreen,
                                border,
                                isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── TABS ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: border)),
                      ),
                      child: TabBar(
                        controller: _tab,
                        indicatorColor: _kOrange,
                        labelColor: _kOrange,
                        unselectedLabelColor: textMuted,
                        labelStyle: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        tabs: [
                          Tab(text: 'Awaiting Action (${_pendingReview.length})'),
                          Tab(text: 'Approved Files (${_approved.length})'),
                          Tab(text: 'Incomplete / Rejected (${_rejectedOrMissing.length})'),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _buildDocList(_pendingReview, isDark, cardBg, border, textPrimary, textMuted),
                        _buildDocList(_approved, isDark, cardBg, border, textPrimary, textMuted),
                        _buildDocList(_rejectedOrMissing, isDark, cardBg, border, textPrimary, textMuted),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMiniPill(
    String label,
    String value,
    Color accent,
    Color border,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF381F15) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocList(
    List<Map<String, dynamic>> items,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 48, color: textMuted.withAlpha(100)),
            const SizedBox(height: 12),
            Text(
              'No statutory documents in this section.',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final d = items[i];
        final id = d['id'] as int?;
        final label = (d['label'] as String?) ?? 'Certificate Document';
        final key = (d['key'] as String?) ?? 'doc';
        final status = (d['status'] as String?) ?? 'not_uploaded';
        final fileUrl = d['file_url'] as String?;
        final fileName = (d['file_name'] as String?) ?? 'Document.pdf';
        final uploadedAt = d['uploaded_at'] as String?;
        final isUploaded = d['uploaded'] == true && fileUrl != null;

        _noteCtrl.putIfAbsent(key, () => TextEditingController(text: d['admin_note'] as String? ?? ''));

        Color pillColor = _kRed;
        String pillLabel = 'Not Uploaded';
        if (status == 'approved') {
          pillColor = _kGreen;
          pillLabel = 'Approved & Verified';
        } else if (status == 'rejected') {
          pillColor = _kRed;
          pillLabel = 'Rejected / Resubmission Required';
        } else if (isUploaded) {
          pillColor = _kAmber;
          pillLabel = 'Awaiting Secretariat Vetting';
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pillColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUploaded ? Icons.description_rounded : Icons.warning_amber_rounded,
                  color: pillColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: pillColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: pillColor.withAlpha(50)),
                          ),
                          child: Text(
                            pillLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: pillColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUploaded
                          ? 'File: $fileName • Uploaded: ${uploadedAt ?? "Recently"}'
                          : 'Applicant has not uploaded this statutory certificate yet.',
                      style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                    ),
                    if (isUploaded) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kOrange,
                              side: const BorderSide(color: _kOrange),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: const Text('View Document'),
                            onPressed: () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textMuted,
                              side: BorderSide(color: border),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 14),
                            label: const Text('Download'),
                            onPressed: () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),

              if (id != null && isUploaded)
                Column(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'approved', key),
                      icon: const Icon(Icons.check_rounded, size: 14),
                      label: const Text('Approve'),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: const BorderSide(color: _kRed),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'rejected', key),
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text('Reject'),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
'''

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(code)

print("Generated clean admin_documents_page.dart successfully!")
