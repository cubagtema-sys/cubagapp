import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../components/doc_preview_stub.dart'
    if (dart.library.html) '../components/doc_preview_web.dart'
    as doc_preview;

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
    SocketService().on('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().on('member_documents_updated', _onRulesUpdatedSocket);
    SocketService().on('documents_updated', _onRulesUpdatedSocket);
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
    SocketService().off('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().off('member_documents_updated', _onRulesUpdatedSocket);
    SocketService().off('documents_updated', _onRulesUpdatedSocket);
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
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: textMuted,
    );
  }

  Widget _buildCategoryTab(String title, String category, int count, IconData icon, Color color, bool isDark, Color cardBg, Color borderColor) {
    final isSelected = _selectedCategory == category;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = category),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? color.withAlpha(45) : color.withAlpha(20)) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: isSelected ? color : (isDark ? Colors.white60 : const Color(0xFF64748B))),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? (isDark ? Colors.white : color) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, int count, IconData icon, Color activeColor, bool isDark) {
    final isSel = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? activeColor.withAlpha(isDark ? 40 : 25) : (isDark ? const Color(0xFF281710) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel ? activeColor : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSel ? activeColor : (isDark ? Colors.white60 : const Color(0xFF64748B))),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                color: isSel ? activeColor : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? activeColor : (isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final corpMembers = _getMembersForCategory('corporate');
    final licMembers = _getMembersForCategory('licentiate');
    final assocMembers = _getMembersForCategory('associate');

    final currentCategoryMembers = _getMembersForCategory(_selectedCategory);
    final countAll = currentCategoryMembers.length;
    final countNeedsReview = currentCategoryMembers.where((m) {
      final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
      final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
      return totalReq > 0 && up >= totalReq && ap < totalReq;
    }).length;
    final countIncomplete = currentCategoryMembers.where((m) {
      final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
      return totalReq > 0 && up < totalReq;
    }).length;
    final countVetted = currentCategoryMembers.where((m) {
      final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
      final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
      return (totalReq > 0 && ap >= totalReq) || totalReq == 0;
    }).length;

    return AppLayout(
      title: 'Registration Hub',
      scrollable: false,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Applicant Dossiers',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review statutory compliance certificates, company records, and membership vetting.',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(color: borderColor),
                      backgroundColor: cardBg,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      context.push('/admin/document-rules').then((_) => _fetch(forceRefresh: true));
                    },
                    icon: const Icon(Icons.rule_folder_rounded, size: 16, color: _kOrange),
                    label: Text(
                      'Document Rules',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _fetch(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      'Refresh',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),

            // ── CATEGORY SEGMENTS ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF281710) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildCategoryTab('Corporate Brokerages', 'corporate', corpMembers.length, Icons.business_rounded, _kIndigo, isDark, cardBg, borderColor),
                    _buildCategoryTab('Licentiate Agents', 'licentiate', licMembers.length, Icons.badge_rounded, _kOrange, isDark, cardBg, borderColor),
                    _buildCategoryTab('Associates / Allied', 'associate', assocMembers.length, Icons.handshake_rounded, _kGreen, isDark, cardBg, borderColor),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── SEARCH & FILTER CONTROLS ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 750;
                  final searchField = Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: TextField(
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by company, applicant name, TIN, or member ID...',
                        hintStyle: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: textMuted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                      ),
                    ),
                  );

                  final filterChips = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildFilterChip('All', 'all', countAll, Icons.folder_copy_rounded, _kOrange, isDark),
                      _buildFilterChip('Needs Review', 'pending_review', countNeedsReview, Icons.hourglass_top_rounded, _kAmber, isDark),
                      _buildFilterChip('Incomplete', 'incomplete', countIncomplete, Icons.upload_file_rounded, _kBlue, isDark),
                      _buildFilterChip('Vetted', 'fully_approved', countVetted, Icons.check_circle_rounded, _kGreen, isDark),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 8),
                        filterChips,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      filterChips,
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── MAIN CONTENT (TABLE OR CARDS) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _loading
                        ? ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: 6,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (_, index) => const ShimmerListTile(),
                          )
                        : _filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: _kOrange.withAlpha(15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.folder_off_rounded, size: 40, color: _kOrange.withAlpha(180)),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No dossiers found',
                                        style: GoogleFonts.outfit(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Try adjusting your search query or switching filters.',
                                        style: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth >= 900;
                                  if (!isWide) {
                                    // Mobile/Tablet responsive card list
                                    return ListView.separated(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: _filtered.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                                      itemBuilder: (ctx, i) => _buildApplicantCard(
                                        _filtered[i],
                                        isDark,
                                        cardBg,
                                        borderColor,
                                        textPrimary,
                                        textMuted,
                                      ),
                                    );
                                  }

                                  // Desktop Table
                                  return Column(
                                    children: [
                                      // Table Header
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1F120B) : const Color(0xFFF1F5F9),
                                          border: Border(bottom: BorderSide(color: borderColor)),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 36,
                                              child: Text('#', style: _headerColStyle(textMuted)),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text('APPLICANT & FIRM', style: _headerColStyle(textMuted)),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text('TYPE & PORT', style: _headerColStyle(textMuted)),
                                            ),
                                            SizedBox(
                                              width: 180,
                                              child: Text('STATUTORY DOCS', style: _headerColStyle(textMuted)),
                                            ),
                                            SizedBox(
                                              width: 140,
                                              child: Center(child: Text('STATUS', style: _headerColStyle(textMuted))),
                                            ),
                                            const SizedBox(
                                              width: 100,
                                              child: Align(
                                                alignment: Alignment.centerRight,
                                                child: Text(
                                                  'ACTION',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.6,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Table Body
                                      Expanded(
                                        child: ListView.separated(
                                          padding: EdgeInsets.zero,
                                          itemCount: _filtered.length,
                                          separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
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
                                    ],
                                  );
                                },
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
      statusLabel = 'Active';
      statusIcon = Icons.verified_rounded;
    } else if (totalExpected == 0) {
      statusColor = _kGreen;
      statusLabel = 'Exempt';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (approved >= totalExpected && totalExpected > 0) {
      statusColor = _kGreen;
      statusLabel = 'Fully Vetted';
      statusIcon = Icons.check_circle_rounded;
    } else if (uploaded >= totalExpected) {
      statusColor = _kAmber;
      statusLabel = 'Needs Review';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (uploaded > 0) {
      statusColor = _kBlue;
      statusLabel = 'Incomplete';
      statusIcon = Icons.upload_file_rounded;
    } else {
      statusColor = _kRed;
      statusLabel = 'Pending Upload';
      statusIcon = Icons.warning_amber_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/admin/documents/${m['id']}'),
        hoverColor: _kOrange.withAlpha(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '$index',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: subCol,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: typeColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: typeColor.withAlpha(60)),
                      ),
                      child: Center(
                        child: Text(
                          company.isNotEmpty
                              ? company[0].toUpperCase()
                              : (name.isNotEmpty ? name[0].toUpperCase() : 'C'),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company,
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: textCol,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.inter(fontSize: 13, color: subCol),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (memNo.isNotEmpty && memNo != 'PENDING') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _kOrange.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    memNo,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            memberType.toLowerCase().contains('corporate')
                                ? (isSme ? 'Corporate • SME' : 'Large Corporate')
                                : memberType,
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      port,
                      style: GoogleFonts.inter(fontSize: 12, color: subCol),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 180,
                child: totalExpected == 0
                    ? Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 14, color: _kGreen),
                          const SizedBox(width: 5),
                          Text('No Docs Required', style: GoogleFonts.inter(fontSize: 12.5, color: _kGreen, fontWeight: FontWeight.w600)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$uploaded / $totalExpected Docs',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: uploaded >= totalExpected ? _kGreen : textCol,
                                ),
                              ),
                              if (approved > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '($approved ✓)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _kGreen,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (uploaded / totalExpected.toDouble()).clamp(0.0, 1.0),
                                backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0),
                                color: uploaded >= totalExpected
                                    ? _kGreen
                                    : (uploaded >= (totalExpected / 2) ? _kOrange : _kRed),
                                minHeight: 4,
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
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
                        Text(
                          statusLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => context.push('/admin/documents/${m['id']}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                      foregroundColor: textCol,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: border),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Review', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 12, color: _kOrange),
                      ],
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

  Widget _buildApplicantCard(
    Map<String, dynamic> m,
    bool isDark,
    Color cardBg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    final name = ((m['name'] as String?) ?? 'Applicant').trim();
    final company = ((m['company'] as String?) ?? 'Unnamed Enterprise').trim();
    final memNo = (m['membership_number'] as String?) ?? 'PENDING';
    final port = (m['port_of_operation'] as String?) ?? 'Tema Port';

    final rawUp = m['docs_uploaded'];
    final rawAp = m['docs_approved'];
    final uploaded = rawUp == null ? 0 : (rawUp as num).toInt();
    final approved = rawAp == null ? 0 : (rawAp as num).toInt();

    final memberType = (m['member_type'] as String? ?? 'Licentiate').trim();
    final isSme = ((m['member_scale'] as String? ?? 'sme').toLowerCase()) == 'sme';
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
    if (totalExpected == 0) {
      statusColor = _kGreen;
      statusLabel = 'Exempt';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (approved >= totalExpected && totalExpected > 0) {
      statusColor = _kGreen;
      statusLabel = 'Vetted';
      statusIcon = Icons.check_circle_rounded;
    } else if (uploaded >= totalExpected) {
      statusColor = _kAmber;
      statusLabel = 'Needs Review';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (uploaded > 0) {
      statusColor = _kBlue;
      statusLabel = 'Incomplete';
      statusIcon = Icons.upload_file_rounded;
    } else {
      statusColor = _kRed;
      statusLabel = 'Pending';
      statusIcon = Icons.warning_amber_rounded;
    }

    return InkWell(
      onTap: () => context.push('/admin/documents/${m['id']}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: typeColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeColor.withAlpha(60)),
                  ),
                  child: Center(
                    child: Text(
                      company.isNotEmpty ? company[0].toUpperCase() : (name.isNotEmpty ? name[0].toUpperCase() : 'C'),
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: typeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company,
                        style: GoogleFonts.outfit(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: textCol,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        name + (memNo.isNotEmpty && memNo != 'PENDING' ? ' • $memNo' : ''),
                        style: GoogleFonts.inter(fontSize: 12.5, color: subCol),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    memberType.toLowerCase().contains('corporate')
                        ? (isSme ? 'Corporate • SME' : 'Large Corporate')
                        : memberType,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(port, style: GoogleFonts.inter(fontSize: 12, color: subCol)),
                const Spacer(),
                Text(
                  totalExpected == 0 ? 'Exempt' : '$uploaded/$totalExpected Docs${approved > 0 ? ' ($approved ✓)' : ''}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: uploaded >= totalExpected ? _kGreen : textCol,
                  ),
                ),
              ],
            ),
            if (totalExpected > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (uploaded / totalExpected.toDouble()).clamp(0.0, 1.0),
                  backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0),
                  color: uploaded >= totalExpected ? _kGreen : (uploaded >= (totalExpected / 2) ? _kOrange : _kRed),
                  minHeight: 4,
                ),
              ),
            ],
          ],
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

  void _showDocPreviewModal(
    BuildContext context,
    String title,
    String fileUrl,
  ) {
    final isImage =
        fileUrl.toLowerCase().contains('.png') ||
        fileUrl.toLowerCase().contains('.jpg') ||
        fileUrl.toLowerCase().contains('.jpeg') ||
        fileUrl.toLowerCase().contains('.webp') ||
        fileUrl.toLowerCase().contains('.gif');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 900,
          height: 680,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () async {
                      final uri = Uri.parse(fileUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    tooltip: 'Open in new tab',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: isImage
                    ? InteractiveViewer(
                        child: CorsImageWidget(
                          url: fileUrl,
                          fit: BoxFit.contain,
                          placeholder: const Center(
                            child: CircularProgressIndicator(color: _kOrange),
                          ),
                          errorWidget: const Center(
                            child: Text('Failed to load image preview.'),
                          ),
                        ),
                      )
                    : doc_preview.buildDocPreview(
                        fileUrl,
                        'modal_${title.hashCode}',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
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
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
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
                  // ── APPLICANT HEADER CARD ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
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
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF4D2D20)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 15,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              CircleAvatar(
                                radius: 22,
                                backgroundColor: headerTypeColor,
                                child: Text(
                                  company.isNotEmpty
                                      ? company[0].toUpperCase()
                                      : 'C',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

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
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
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
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: headerTypeColor,
                                            ),
                                          ),
                                        ),
                                        if (isCorporate) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (scale == 'sme' ? _kOrange : _kIndigo).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              scale == 'sme' ? "SME" : "LARGE CORP",
                                              style: GoogleFonts.outfit(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: scale == 'sme' ? _kOrange : _kIndigo,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(name, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: textMuted)),
                                          ],
                                        ),
                                        if (phone.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.phone_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text(phone, style: GoogleFonts.inter(fontSize: 12.5, color: textMuted)),
                                            ],
                                          ),
                                        if (tin.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.tag_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text('TIN: $tin', style: GoogleFonts.inter(fontSize: 12.5, color: textMuted)),
                                            ],
                                          ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.anchor_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(port, style: GoogleFonts.inter(fontSize: 12.5, color: textMuted)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasPaid ? _kGreen.withAlpha(20) : _kAmber.withAlpha(20),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: (hasPaid ? _kGreen : _kAmber).withAlpha(50)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'FEE STATUS',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: hasPaid ? _kGreen : _kAmber,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Text(
                                      hasPaid
                                          ? (lastPaymentAmt != null && lastPaymentAmt > 0
                                                ? 'PAID (GH₵ ${lastPaymentAmt.toStringAsFixed(0)})'
                                                : 'PAID')
                                          : (regFeeAmt > 0
                                                ? 'UNPAID (GH₵ ${regFeeAmt.toStringAsFixed(0)})'
                                                : 'UNPAID'),
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: hasPaid ? _kGreen : _kAmber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              ElevatedButton.icon(
                                onPressed: (isApproved || _approvingAll)
                                    ? null
                                    : _approveAll,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isApproved
                                      ? Colors.grey.shade700
                                      : _kGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: isApproved
                                    ? const Icon(Icons.check_circle_rounded, size: 16)
                                    : (_approvingAll
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.verified_rounded, size: 16)),
                                label: Text(
                                  isApproved
                                      ? 'Dossier Verified'
                                      : (_approvingAll
                                            ? 'Verifying...'
                                            : (total > 0
                                                  ? 'Approve All ($total/$total)'
                                                  : 'Approve Application')),
                                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              _buildMiniPill('Required', '$total', _kSlate, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Uploaded', '$uploaded', _kBlue, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Awaiting Review', '$pending', _kAmber, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Approved', '$approved', _kGreen, border, isDark),
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
                          fontSize: 13.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
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
            Icon(Icons.folder_open_rounded, size: 40, color: textMuted.withAlpha(100)),
            const SizedBox(height: 10),
            Text(
              'No statutory documents in this section.',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
          pillLabel = 'Approved';
        } else if (status == 'rejected') {
          pillColor = _kRed;
          pillLabel = 'Rejected';
        } else if (isUploaded) {
          pillColor = _kAmber;
          pillLabel = 'Awaiting Vetting';
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: pillColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isUploaded ? Icons.description_rounded : Icons.warning_amber_rounded,
                  color: pillColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

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
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: pillColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: pillColor.withAlpha(50)),
                          ),
                          child: Text(
                            pillLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: pillColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUploaded
                          ? 'File: $fileName • Uploaded: ${uploadedAt ?? "Recently"}'
                          : 'Applicant has not uploaded this statutory certificate yet.',
                      style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                    ),
                    if (isUploaded) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _showDocPreviewModal(context, label, fileUrl),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.remove_red_eye_rounded, size: 13, color: _kOrange),
                                  const SizedBox(width: 4),
                                  Text('Preview', style: GoogleFonts.outfit(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 13, color: textMuted),
                                  const SizedBox(width: 4),
                                  Text('Open in Tab', style: GoogleFonts.outfit(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),

              if (id != null && isUploaded)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'approved', key),
                      icon: const Icon(Icons.check_rounded, size: 13),
                      label: Text('Approve', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: const BorderSide(color: _kRed),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'rejected', key),
                      icon: const Icon(Icons.close_rounded, size: 13),
                      label: Text('Reject', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
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

class AdminMemberDocumentsPage extends StatelessWidget {
  final String memberId;
  const AdminMemberDocumentsPage({super.key, required this.memberId});

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(memberId) ?? 0;
    return ReviewApplicantPage(memberId: id);
  }
}
