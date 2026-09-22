// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../components/doc_preview_stub.dart'
    if (dart.library.html) '../components/doc_preview_web.dart'
    as doc_preview;
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRed = Color(0xFFef4444);
const _kDarkBg = Color(0xFF1A0F0A);
const _kCardDark = Color(0xFF281710);
const _kBorderDark = Color(0xFF4D2D20);
const _kTextDark = Color(0xFF2B211D);

Color _statusColor(String? s) {
  switch (s) {
    case 'approved':
      return _kGreen;
    case 'rejected':
      return _kRed;
    case 'awaiting_bill':
      return const Color(0xFF8B5CF6); // Purple/Violet
    case 'awaiting_payment':
    case 'payment_pending':
    case 'payment_submitted':
      return _kAmber;
    case 'partially_paid':
      return const Color(0xFFF59E0B);
    case 'under_review':
      return _kPrimary;
    case 'submitted':
      return _kAmber;
    case 'payment_confirmed':
      return _kGreen;
    case 'revision_requested':
      return _kAmber;
    default:
      return Colors.grey;
  }
}

String _statusLabel(String? s) {
  switch (s) {
    case 'draft':
      return 'Draft';
    case 'submitted':
      return 'Submitted';
    case 'awaiting_bill':
      return 'Awaiting Bill';
    case 'awaiting_payment':
    case 'payment_pending':
      return 'Awaiting Payment';
    case 'partially_paid':
      return 'Partially Paid';
    case 'payment_submitted':
      return 'Payment Submitted';
    case 'payment_confirmed':
      return 'Payment Confirmed';
    case 'under_review':
      return 'Under Review';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    case 'revision_requested':
      return 'Revision Requested';
    default:
      return s ?? '—';
  }
}

String _fmt(String? d) {
  if (d == null || d.isEmpty) return '—';
  try {
    final dt = DateTime.parse(d);
    final m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  } catch (_) {
    return d;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN LIST PAGE
// ─────────────────────────────────────────────────────────────────────────────
class AdminCompliancePage extends StatefulWidget {
  const AdminCompliancePage({super.key});
  @override
  State<AdminCompliancePage> createState() => _AdminCompliancePageState();
}

class _AdminCompliancePageState extends State<AdminCompliancePage> {
  final Map<String, List<dynamic>> _data = {'renewal': []};
  final Map<String, bool> _loading = {'renewal': true};
  final Map<String, int> _totals = {'renewal': 0};
  final Map<String, int> _page = {'renewal': 1};
  final Map<String, int> _perPage = {'renewal': 50};
  final Map<String, String> _statusFilters = {'renewal': ''};
  String _selectedCategory = 'corporate'; // 'corporate', 'licentiate', 'associate'
  String _renewalSearch = '';

  @override
  void initState() {
    super.initState();
    _fetch('renewal');
  }

  Future<void> _fetch(String type) async {
    setState(() => _loading[type] = true);
    try {
      final page = _page[type] ?? 1;
      final perPage = _perPage[type] ?? 50;
      final status = _statusFilters[type] ?? '';
      final params =
          'type=$type&page=$page&per_page=$perPage${status.isNotEmpty ? '&status=$status' : ''}';
      await ApiService().fetchDataWithCache(
        '/compliance/admin/applications?$params',
        (data, isCached, {bool hasError = false}) {
          if (!mounted) return;
          if (hasError) {
            if (!isCached) setState(() => _loading[type] = false);
            return;
          }
          if (data != null && data is Map) {
            final map = Map<String, dynamic>.from(data);
            final apps = ApiService.ensureList(map['applications']);
            final total = (map['total'] as num?)?.toInt() ?? apps.length;
            setState(() {
              _data[type] = apps;
              _totals[type] = total;
              _loading[type] = false;
            });
          }
        },
      );
    } catch (e, st) {
      AppLogger.error('admin_compliance_page', e, st);
    }
    if (mounted) setState(() => _loading[type] = false);
  }

  List<Map<String, dynamic>> _getAllApps() {
    return (_data['renewal'] ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getAppsForCategory(String category) {
    final all = _getAllApps();
    return all.where((a) {
      final mType = (a['member_type']?.toString().toLowerCase() ?? 'corporate');
      if (category == 'corporate') {
        return mType == 'corporate' || mType.isEmpty;
      }
      return mType == category;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredForCurrentCategory() {
    final list = _getAppsForCategory(_selectedCategory);
    final q = _renewalSearch.toLowerCase().trim();
    final status = (_statusFilters['renewal'] ?? '').toLowerCase();

    return list.where((a) {
      if (status.isNotEmpty) {
        final aStatus = (a['status']?.toString() ?? '').toLowerCase();
        if (aStatus != status) return false;
      }
      if (q.isNotEmpty) {
        final name = (a['member_name'] as String? ?? '').toLowerCase();
        final comp = (a['member_company'] as String? ?? '').toLowerCase();
        final email = (a['member_email'] as String? ?? '').toLowerCase();
        final id = a['id']?.toString() ?? '';
        return name.contains(q) || comp.contains(q) || email.contains(q) || id.contains(q);
      }
      return true;
    }).toList();
  }

  Widget _buildCategoryTab(
    String label,
    String key,
    IconData icon,
    Color color,
    int count,
    bool isDark,
  ) {
    final isSelected = _selectedCategory == key;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = key),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? color.withAlpha(40) : color.withAlpha(20)) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : (isDark ? Colors.white60 : const Color(0xFF64748B))),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
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
                    fontSize: 11.5,
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

  Widget _buildFilterChip(
    String label,
    String value,
    int count,
    IconData icon,
    Color activeColor,
    bool isDark,
  ) {
    final isSel = (_statusFilters['renewal'] ?? '') == value;
    return InkWell(
      onTap: () => setState(() => _statusFilters['renewal'] = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? activeColor.withAlpha(isDark ? 40 : 25) : (isDark ? _kCardDark : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel ? activeColor : (isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
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
                fontSize: 13,
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
                  fontSize: 11,
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
    final bg = isDark ? _kDarkBg : const Color(0xFFF8FAFC);
    final cardBg = isDark ? _kCardDark : Colors.white;
    final borderColor = isDark ? _kBorderDark : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final corpApps = _getAppsForCategory('corporate');
    final licApps = _getAppsForCategory('licentiate');
    final assocApps = _getAppsForCategory('associate');

    final currentList = _filteredForCurrentCategory();
    final activeCategoryTotal = _getAppsForCategory(_selectedCategory).length;
    final underReviewCount = _getAppsForCategory(_selectedCategory)
        .where((a) => (a['status']?.toString() ?? '').toLowerCase() == 'under_review')
        .length;
    final approvedCount = _getAppsForCategory(_selectedCategory)
        .where((a) => (a['status']?.toString() ?? '').toLowerCase() == 'approved')
        .length;
    final submittedCount = _getAppsForCategory(_selectedCategory)
        .where((a) => (a['status']?.toString() ?? '').toLowerCase() == 'submitted')
        .length;
    final revisionCount = _getAppsForCategory(_selectedCategory)
        .where((a) => (a['status']?.toString() ?? '').toLowerCase() == 'revision_requested')
        .length;
    final rejectedCount = _getAppsForCategory(_selectedCategory)
        .where((a) => (a['status']?.toString() ?? '').toLowerCase() == 'rejected')
        .length;

    return AppLayout(
      title: 'Compliance & Renewals',
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
                          'Renewal Compliance Centre',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review submitted annual renewals, compliance document audits, and fee billing.',
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
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _fetch('renewal'),
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
                  color: isDark ? _kCardDark : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildCategoryTab('Corporate Brokerage', 'corporate', Icons.business_rounded, _kPrimary, corpApps.length, isDark),
                    _buildCategoryTab('Licentiate Broker', 'licentiate', Icons.badge_rounded, const Color(0xFF6366F1), licApps.length, isDark),
                    _buildCategoryTab('Associate Member', 'associate', Icons.handshake_rounded, _kGreen, assocApps.length, isDark),
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
                  final isNarrow = constraints.maxWidth < 780;
                  final searchField = Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _renewalSearch = v),
                      style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by applicant, company, or application ID...',
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
                      _buildFilterChip('All', '', activeCategoryTotal, Icons.folder_copy_rounded, _kPrimary, isDark),
                      _buildFilterChip('Under Review', 'under_review', underReviewCount, Icons.pending_actions_rounded, const Color(0xFF3B82F6), isDark),
                      _buildFilterChip('Approved', 'approved', approvedCount, Icons.verified_rounded, _kGreen, isDark),
                      _buildFilterChip('Submitted', 'submitted', submittedCount, Icons.send_rounded, _kAmber, isDark),
                      _buildFilterChip('Revision Needed', 'revision_requested', revisionCount, Icons.replay_rounded, _kAmber, isDark),
                      _buildFilterChip('Rejected', 'rejected', rejectedCount, Icons.cancel_rounded, _kRed, isDark),
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

            // ── MAIN DATA TABLE / CARD LIST ──
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
                    child: _loading['renewal'] == true
                        ? ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: 6,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, _) => const ShimmerListTile(),
                          )
                        : currentList.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No $_selectedCategory renewal applications found',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          color: textMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth >= 900;
                                  if (!isWide) {
                                    // Mobile/Tablet responsive cards
                                    return ListView.separated(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: currentList.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                                      itemBuilder: (ctx, i) => _buildApplicationCard(
                                        currentList[i],
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
                                              width: 100,
                                              child: Text('REF ID', style: _tableHeaderStyle(textMuted)),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text('APPLICANT & FIRM', style: _tableHeaderStyle(textMuted)),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text('CATEGORY', style: _tableHeaderStyle(textMuted)),
                                            ),
                                            SizedBox(
                                              width: 170,
                                              child: Text('RENEWAL DOCS', style: _tableHeaderStyle(textMuted)),
                                            ),
                                            SizedBox(
                                              width: 140,
                                              child: Center(child: Text('PAYMENT', style: _tableHeaderStyle(textMuted))),
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
                                      // Table Rows
                                      Expanded(
                                        child: ListView.separated(
                                          padding: EdgeInsets.zero,
                                          itemCount: currentList.length,
                                          separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
                                          itemBuilder: (ctx, i) => _buildApplicationRow(
                                            currentList[i],
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

  TextStyle _tableHeaderStyle(Color textMuted) {
    return GoogleFonts.inter(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: textMuted,
    );
  }

  Widget _buildApplicationRow(
    Map<String, dynamic> app,
    bool isDark,
    Color cardBg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    final uploaded = (app['docs_uploaded'] as num?)?.toInt() ?? 0;
    final totalDocs = (app['docs_total'] as num?)?.toInt() ?? 0;
    final approved = (app['docs_approved'] as num?)?.toInt() ?? 0;
    final paymentRef = app['payment_ref']?.toString();
    final paymentAmount = app['payment_amount'];
    final appStatus = app['status']?.toString().toLowerCase() ?? '';
    final bool isPaid = app['payment_confirmed_at'] != null ||
        appStatus == 'payment_confirmed' ||
        appStatus == 'approved';
    final bool isSubmitted = !isPaid &&
        ((paymentRef != null && paymentRef.isNotEmpty) ||
            appStatus == 'payment_submitted');

    final String paymentLabel;
    final Color paymentColor;
    final IconData paymentIcon;

    if (isPaid) {
      paymentLabel = paymentAmount != null ? 'Paid GH₵ $paymentAmount' : 'Paid';
      paymentColor = _kGreen;
      paymentIcon = Icons.verified_rounded;
    } else if (isSubmitted) {
      paymentLabel = paymentAmount != null ? 'Submitted GH₵ $paymentAmount' : 'Submitted';
      paymentColor = _kAmber;
      paymentIcon = Icons.hourglass_top_rounded;
    } else {
      paymentLabel = 'Pending';
      paymentColor = const Color(0xFF94A3B8);
      paymentIcon = Icons.pending_rounded;
    }

    final name = app['member_name']?.toString() ?? 'Applicant';
    final company = app['member_company']?.toString() ?? 'Individual Practitioner';
    final email = app['member_email']?.toString() ?? '';
    final refId = '#COMP-${(app['id'] as int).toString().padLeft(5, '0')}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(app),
        hoverColor: _kPrimary.withAlpha(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  refId,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: _kPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: _kPrimary.withAlpha(30),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'M',
                        style: GoogleFonts.outfit(
                          color: _kPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textCol,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            name + (email.isNotEmpty ? ' • $email' : ''),
                            style: GoogleFonts.inter(fontSize: 12.5, color: subCol),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kPrimary.withAlpha(isDark ? 30 : 15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedCategory.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$uploaded / $totalDocs Docs',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: (approved == totalDocs && totalDocs > 0) ? _kGreen : textCol,
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
                    if (totalDocs > 0)
                      SizedBox(
                        width: 130,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (uploaded / totalDocs.toDouble()).clamp(0.0, 1.0),
                            backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0),
                            color: approved == totalDocs
                                ? _kGreen
                                : (uploaded >= (totalDocs / 2) ? _kPrimary : _kAmber),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: paymentColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: paymentColor.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          paymentIcon,
                          size: 12,
                          color: paymentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          paymentLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: paymentColor,
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
                    onPressed: () => _openDetail(app),
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
                        Icon(Icons.arrow_forward_rounded, size: 12, color: _kPrimary),
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

  Widget _buildApplicationCard(
    Map<String, dynamic> app,
    bool isDark,
    Color cardBg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    final uploaded = (app['docs_uploaded'] as num?)?.toInt() ?? 0;
    final totalDocs = (app['docs_total'] as num?)?.toInt() ?? 0;
    final approved = (app['docs_approved'] as num?)?.toInt() ?? 0;
    final paymentRef = app['payment_ref']?.toString();
    final paymentAmount = app['payment_amount'];
    final appStatus = app['status']?.toString().toLowerCase() ?? '';
    final bool isPaid = app['payment_confirmed_at'] != null ||
        appStatus == 'payment_confirmed' ||
        appStatus == 'approved';
    final bool isSubmitted = !isPaid &&
        ((paymentRef != null && paymentRef.isNotEmpty) ||
            appStatus == 'payment_submitted');

    final String paymentLabel;
    final Color paymentColor;
    final IconData paymentIcon;

    if (isPaid) {
      paymentLabel = paymentAmount != null ? 'Paid GH₵ $paymentAmount' : 'Paid';
      paymentColor = _kGreen;
      paymentIcon = Icons.verified_rounded;
    } else if (isSubmitted) {
      paymentLabel = paymentAmount != null ? 'Submitted GH₵ $paymentAmount' : 'Submitted';
      paymentColor = _kAmber;
      paymentIcon = Icons.hourglass_top_rounded;
    } else {
      paymentLabel = 'Pending';
      paymentColor = const Color(0xFF94A3B8);
      paymentIcon = Icons.pending_rounded;
    }

    final name = app['member_name']?.toString() ?? 'Applicant';
    final company = app['member_company']?.toString() ?? 'Individual Practitioner';
    final refId = '#COMP-${(app['id'] as int).toString().padLeft(5, '0')}';

    return InkWell(
      onTap: () => _openDetail(app),
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
                CircleAvatar(
                  radius: 17,
                  backgroundColor: _kPrimary.withAlpha(30),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'M',
                    style: GoogleFonts.outfit(
                      color: _kPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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
                        '$refId • $name',
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
                    color: paymentColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: paymentColor.withAlpha(60),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        paymentIcon,
                        size: 11,
                        color: paymentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        paymentLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: paymentColor,
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
                    color: _kPrimary.withAlpha(isDark ? 30 : 15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _selectedCategory.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$uploaded/$totalDocs Docs${approved > 0 ? ' ($approved ✓)' : ''}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: approved == totalDocs ? _kGreen : textCol,
                  ),
                ),
              ],
            ),
            if (totalDocs > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (uploaded / totalDocs.toDouble()).clamp(0.0, 1.0),
                  backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0),
                  color: approved == totalDocs ? _kGreen : _kPrimary,
                  minHeight: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> app) async {
    final id = app['id'];
    if (id != null) {
      context.go('/admin/compliance/$id');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DETAIL PAGE (SIMPLIFIED & INTEGRATED IN APP LAYOUT / SIDEBAR SHELL)
// ─────────────────────────────────────────────────────────────────────────────
class AdminComplianceDetailPage extends StatefulWidget {
  final int appId;
  const AdminComplianceDetailPage({super.key, required this.appId});
  @override
  State<AdminComplianceDetailPage> createState() =>
      _AdminComplianceDetailPageState();
}

class _BillItemController {
  final TextEditingController labelCtrl;
  final TextEditingController amountCtrl;

  _BillItemController({String label = '', dynamic amount = ''})
      : labelCtrl = TextEditingController(text: label),
        amountCtrl = TextEditingController(
          text: (amount != null && amount != '' && amount != '0' && amount != 0 && amount != '0.0')
              ? amount.toString()
              : (amount == 0 || amount == '0' || amount == '' ? '' : amount.toString()),
        );

  void dispose() {
    labelCtrl.dispose();
    amountCtrl.dispose();
  }

  String get label => labelCtrl.text.trim();
  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0.0;
}

class _AdminComplianceDetailPageState extends State<AdminComplianceDetailPage> {
  bool _loading = true;
  Map<String, dynamic> _app = {};
  Map<String, dynamic>? _payment;
  bool _confirmingPayment = false;
  List<dynamic> _docs = [];
  bool _approving = false;
  bool _rejecting = false;
  bool _requestingRevision = false;
  final _noteCtrl = TextEditingController();
  final _billTitleCtrl = TextEditingController(text: 'Annual Renewal Dues');

  final List<_BillItemController> _billItemControllers = [];
  DateTime? _paymentDeadline = DateTime.now().add(const Duration(days: 14));
  bool _savingBill = false;
  bool _allowInstallments = true;
  final _minInstallmentCtrl = TextEditingController(text: '0.00');
  List<dynamic> _installments = [];

  double get _calculatedTotal {
    double sum = 0;
    for (var item in _billItemControllers) {
      sum += item.amount;
    }
    return sum;
  }

  @override
  void initState() {
    super.initState();
    _billItemControllers.add(_BillItemController(label: 'Base Renewal Fee', amount: 500.0));
    _fetch();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _billTitleCtrl.dispose();
    _minInstallmentCtrl.dispose();
    for (final c in _billItemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get(
        '/compliance/admin/applications/${widget.appId}',
      );
      if (mounted && res.statusCode == 200) {
        setState(() {
          _loading = false;
          _app = Map<String, dynamic>.from(res.data['application'] ?? {});
          _docs = ApiService.ensureList(res.data['documents']);
          _payment = res.data['payment'] != null ? Map<String, dynamic>.from(res.data['payment']) : null;
          _installments = ApiService.ensureList(res.data['installments'] ?? _app['installments']);

          if (_app['allow_installments'] != null) {
            _allowInstallments = _app['allow_installments'] == true || _app['allow_installments'].toString().toLowerCase() == 'true';
          }
          if (_app['min_installment_amount'] != null) {
            final minAmt = double.tryParse(_app['min_installment_amount'].toString()) ?? 0.0;
            _minInstallmentCtrl.text = minAmt > 0 ? minAmt.toStringAsFixed(2) : '0.00';
          }

          if (_app['fee_breakdown'] != null) {
            try {
              final rawBreakdown = _app['fee_breakdown'] is String
                  ? jsonDecode(_app['fee_breakdown'])
                  : _app['fee_breakdown'];
              if (rawBreakdown is List && rawBreakdown.isNotEmpty) {
                for (final c in _billItemControllers) {
                  c.dispose();
                }
                _billItemControllers.clear();
                for (final e in rawBreakdown) {
                  if (e is Map) {
                    _billItemControllers.add(_BillItemController(
                      label: e['label']?.toString() ?? '',
                      amount: e['amount'],
                    ));
                  }
                }
              }
            } catch (_) {}
          }
          if (_app['bill_title'] != null && _app['bill_title'].toString().trim().isNotEmpty) {
            _billTitleCtrl.text = _app['bill_title'].toString().trim();
          }
          if (_app['payment_deadline'] != null) {
            _paymentDeadline = DateTime.tryParse(_app['payment_deadline'].toString()) ?? _paymentDeadline;
          }
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_compliance_detail', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAndIssueBill() async {
    final validItems = _billItemControllers
        .map((c) => {'label': c.label.isEmpty ? 'Renewal Fee' : c.label, 'amount': c.amount})
        .where((c) => (c['amount'] as double) > 0 || (c['label'] as String).isNotEmpty)
        .toList();

    if (validItems.isEmpty) {
      _showSnack('Please add at least one fee item with an amount.', color: _kRed);
      return;
    }
    if (_paymentDeadline == null) {
      _showSnack('Please select a payment deadline.', color: _kRed);
      return;
    }

    setState(() => _savingBill = true);
    try {
      final deadlineStr = "${_paymentDeadline!.year}-${_paymentDeadline!.month.toString().padLeft(2, '0')}-${_paymentDeadline!.day.toString().padLeft(2, '0')}";
      final billTitle = _billTitleCtrl.text.trim().isEmpty ? 'Annual Renewal Dues' : _billTitleCtrl.text.trim();
      final minAmt = double.tryParse(_minInstallmentCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      final res = await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/set-bill',
        data: {
          'bill_title': billTitle,
          'fee_breakdown': validItems,
          'payment_deadline': deadlineStr,
          'allow_installments': _allowInstallments,
          'min_installment_amount': minAmt,
        },
      );
      if (res.statusCode == 200) {
        _showSnack('Bill issued successfully!', color: _kGreen);
        _fetch();
      } else {
        _showSnack(res.data?['message'] ?? 'Failed to issue bill', color: _kRed);
      }
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _savingBill = false);
    }
  }

  Future<void> _updateDocStatus(Map<String, dynamic> doc, String status) async {
    final isBankSlip = doc['key'] == 'bank_deposit_slip' || doc['is_payment_receipt'] == true;
    final paymentId = doc['payment_id'] ?? _payment?['id'] ?? (doc['id'] is String ? int.tryParse((doc['id'] as String).replaceFirst('pay_', '')) : null);
    final rawDocId = doc['id'];
    final docId = rawDocId is int ? rawDocId : (rawDocId is num ? rawDocId.toInt() : null);

    if (docId == null && paymentId == null) return;

    String? note;
    if (status == 'rejected') {
      note = await _promptNote(context, 'Rejection note for "${doc['label']}"');
      if (note == null) return;
    }
    try {
      if (isBankSlip && paymentId != null) {
        if (status == 'approved') {
          await ApiService().post('/payments/admin/mark-paid/$paymentId');
        } else {
          await ApiService().post('/payments/admin/reject/$paymentId', data: {'reason': note ?? ''});
        }
      }

      if (docId != null) {
        await ApiService().put(
          '/compliance/admin/applications/${widget.appId}/doc/$docId/status',
          data: {'status': status, 'note': note ?? ''},
        );
      }

      setState(() {
        doc['status'] = status;
        if (isBankSlip && _payment != null) {
          _payment!['status'] = status == 'approved' ? 'paid' : 'rejected';
        }
      });
      _showSnack(
        status == 'approved'
            ? (isBankSlip ? 'Bank deposit payment approved & verified' : 'Document approved')
            : (isBankSlip ? 'Bank deposit payment rejected' : 'Document marked as rejected'),
        color: status == 'approved' ? _kGreen : _kRed,
      );
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    }
  }

  Future<void> _approveAll() async {
    final isRenewal = _app['type']?.toString().toLowerCase() == 'renewal';
    final actionName = isRenewal ? 'Renewal' : 'Application';
    final note = await _promptNote(context, '$actionName approval note (optional)');
    if (!mounted) return;
    setState(() => _approving = true);
    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/approve',
        data: {'note': note ?? ''},
      );
      _showSnack('$actionName approved successfully!', color: _kGreen);
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _rejectAll() async {
    final note = await _promptNote(context, 'Rejection reason (required)');
    if (note == null || note.isEmpty) return;
    if (!mounted) return;
    setState(() => _rejecting = true);
    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/reject',
        data: {'note': note},
      );
      _showSnack('Application rejected', color: _kRed);
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<void> _requestRevision() async {
    final note = await _promptNote(
      context,
      'Describe what the member needs to fix (required)',
    );
    if (note == null || note.isEmpty) return;
    if (!mounted) return;
    setState(() => _requestingRevision = true);
    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/request-revision',
        data: {'note': note},
      );
      _showSnack(
        'Revision requested. Member has been notified.',
        color: _kAmber,
      );
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _requestingRevision = false);
    }
  }

  Future<String?> _promptNote(BuildContext context, String hint) async {
    _noteCtrl.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Review Note',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, _noteCtrl.text.trim()),
            child: Text(
              'Confirm',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {Color color = _kDarkBg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showDocPreviewModal(BuildContext context, String title, String fileUrl) {
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
                  const Icon(Icons.description_rounded, color: _kPrimary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () async {
                      final resolved = ApiService.resolveImageUrl(fileUrl);
                      final uri = Uri.parse(resolved);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                            child: CircularProgressIndicator(color: _kPrimary),
                          ),
                          errorWidget: const Center(
                            child: Text('Failed to load image preview.'),
                          ),
                        ),
                      )
                    : doc_preview.buildDocPreview(fileUrl, 'modal_${title.hashCode}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeaderBar(bool isDark, String typeLabel, String status) {
    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/admin/compliance');
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15,
                color: isDark ? Colors.white : _kTextDark,
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
                    Text(
                      '#COMP-${widget.appId.toString().padLeft(5, '0')}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _kPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusLabel.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  typeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh Application',
            onPressed: _fetch,
          ),
        ],
      ),
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  Future<void> _confirmBankPayment(dynamic paymentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: _kGreen),
            SizedBox(width: 8),
            Text('Confirm Bank Payment'),
          ],
        ),
        content: const Text(
          'Are you sure you want to verify and confirm this bank deposit? This will mark the payment as PAID and confirm the member\'s renewal payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm & Verify'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _confirmingPayment = true);
    try {
      final res = await ApiService().post('/payments/admin/mark-paid/$paymentId');
      if (res.statusCode == 200) {
        _showSnack('Bank payment verified and confirmed successfully!', color: _kGreen);
        setState(() {
          if (_payment != null) {
            _payment!['status'] = 'paid';
          }
          for (var doc in _docs) {
            if (doc is Map<String, dynamic> &&
                (doc['key'] == 'bank_deposit_slip' || doc['is_payment_receipt'] == true)) {
              doc['status'] = 'approved';
            }
          }
        });
        await _fetch();
      } else {
        _showSnack(res.data?['message']?.toString() ?? 'Failed to confirm payment.', color: _kRed);
      }
    } catch (e, st) {
      AppLogger.error('admin_compliance_confirm_payment', e, st);
      _showSnack('Error confirming payment. Please try again.', color: _kRed);
    } finally {
      if (mounted) setState(() => _confirmingPayment = false);
    }
  }

  Widget _buildPaymentProofSection(bool isDark) {
    final pay = _payment;
    final payRef = pay?['payment_ref']?.toString() ?? _app['payment_ref']?.toString() ?? '';
    final rawReceiptUrl = pay?['receipt_url']?.toString() ?? '';
    final hasReceipt = rawReceiptUrl.trim().isNotEmpty;
    final receiptUrl = hasReceipt ? _resolveUrl(rawReceiptUrl) : '';
    final amount = double.tryParse(pay?['amount']?.toString() ?? _app['payment_amount']?.toString() ?? '0') ?? 0.0;
    final bankName = pay?['bank_name']?.toString() ?? 'GCB Bank Limited';
    final accountNum = pay?['account_number']?.toString() ?? '';
    final notes = pay?['notes']?.toString();
    final paymentId = pay?['id'] ?? pay?['tx_id'];
    final payStatus = pay?['status']?.toString().toLowerCase() ?? (_app['status'] == 'payment_confirmed' ? 'paid' : 'pending');
    final isPaid = payStatus == 'paid' || payStatus == 'success' || payStatus == 'completed';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPaid ? _kGreen.withValues(alpha: 0.4) : _kPrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isPaid ? _kGreen : _kPrimary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: isPaid ? _kGreen : _kPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank Deposit Slip & Payment Proof',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _kTextDark,
                      ),
                    ),
                    Text(
                      'Direct bank wire / branch deposit submitted by applicant',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPaid ? _kGreen : _kAmber).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isPaid ? _kGreen : _kAmber).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                      size: 13,
                      color: isPaid ? _kGreen : _kAmber,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPaid ? 'PAYMENT CONFIRMED' : 'VERIFICATION PENDING',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isPaid ? _kGreen : _kAmber,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Content body: receipt thumbnail + details
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Receipt Slip Preview
                  if (hasReceipt) ...[
                    GestureDetector(
                      onTap: () => _showDocPreviewModal(
                        context,
                        'Bank Deposit Slip · $payRef',
                        receiptUrl,
                      ),
                      child: Container(
                        width: isNarrow ? double.infinity : 170,
                        height: isNarrow ? 200 : 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? _kBorderDark : const Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                          color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CorsImageWidget(
                              url: receiptUrl,
                              fit: BoxFit.cover,
                              placeholder: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                              ),
                              errorWidget: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 28),
                                    const SizedBox(height: 4),
                                    Text('Receipt file', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Click to View',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 16 : 0),
                  ],

                  // Details
                  Expanded(
                    flex: isNarrow ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount Deposited',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'GH₵ ${amount.toStringAsFixed(2)}',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isPaid ? _kGreen : _kPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildPaymentDetailRow('Payment Reference', payRef, isDark),
                        _buildPaymentDetailRow('Receiving Bank', bankName, isDark),
                        if (accountNum.isNotEmpty)
                          _buildPaymentDetailRow('Account Number', accountNum, isDark),
                        if (notes != null && notes.isNotEmpty)
                          _buildPaymentDetailRow('Depositor Note', notes, isDark),
                        if (pay?['date'] != null || _app['created_at'] != null)
                          _buildPaymentDetailRow('Submitted At', _fmt(pay?['date']?.toString() ?? _app['created_at']?.toString()), isDark),

                        const SizedBox(height: 14),

                        // Admin Action Buttons
                        if (!isPaid && paymentId != null)
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _confirmingPayment ? null : () => _confirmBankPayment(paymentId),
                                icon: _confirmingPayment
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_circle_rounded, size: 18),
                                label: Text(
                                  _confirmingPayment ? 'Confirming...' : 'Verify & Confirm Payment',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                              if (hasReceipt)
                                OutlinedButton.icon(
                                  onPressed: () => _showDocPreviewModal(
                                    context,
                                    'Bank Deposit Slip · $payRef',
                                    receiptUrl,
                                  ),
                                  icon: const Icon(Icons.visibility_rounded, size: 16),
                                  label: Text(
                                    'Inspect Slip',
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                            ],
                          )
                        else if (isPaid)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded, color: _kGreen, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Payment Verified & Recorded in Ledger',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _kGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : _kTextDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection(bool isDark, bool isResolved) {
    final uploadedCount = _docs.where((d) => d['uploaded'] == true).length;
    final totalCount = _docs.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_shared_rounded, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Statutory Compliance Documents',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _kTextDark,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$uploadedCount of $totalCount Uploaded',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (_docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No statutory documents required for this profile.',
                  style: GoogleFonts.inter(color: Colors.grey, fontSize: 13.5),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final d = _docs[i] as Map<String, dynamic>;
                return _AdminDocRow(
                  doc: d,
                  isDark: isDark,
                  isResolved: isResolved,
                  onApprove: () => _updateDocStatus(d, 'approved'),
                  onReject: () => _updateDocStatus(d, 'rejected'),
                  onPreview: (title, url) => _showDocPreviewModal(context, title, url),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBillGenerationSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Itemized Renewal Bill',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _kTextDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Configure the fee breakdown and payment deadline for this member renewal.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _billTitleCtrl,
            decoration: InputDecoration(
              labelText: 'Bill Title / Category Description',
              hintText: 'e.g. Annual Renewal Dues',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),

          ..._billItemControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: item.labelCtrl,
                      decoration: InputDecoration(
                        labelText: 'Fee Description',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: GoogleFonts.outfit(fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Amount (GHS)',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: GoogleFonts.outfit(fontSize: 13.5),
                    ),
                  ),
                  if (_billItemControllers.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 18),
                      onPressed: () => setState(() {
                        final removed = _billItemControllers.removeAt(idx);
                        removed.dispose();
                      }),
                    ),
                ],
              ),
            );
          }),

          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _billItemControllers.add(_BillItemController(label: '', amount: ''))),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Fee Item'),
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Deadline: ',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _paymentDeadline ?? DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _paymentDeadline = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 14, color: _kPrimary),
                          const SizedBox(width: 4),
                          Text(
                            _paymentDeadline != null
                                ? "${_paymentDeadline!.year}-${_paymentDeadline!.month.toString().padLeft(2, '0')}-${_paymentDeadline!.day.toString().padLeft(2, '0')}"
                                : 'Pick Date',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: _kPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Part-Payment / Installment Option ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: _allowInstallments ? _kGreen : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Allow Part-Payments / Installments',
                            style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : _kTextDark,
                            ),
                          ),
                          Text(
                            'Allow member to pay bill in installments with balance tracking',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _allowInstallments,
                      activeThumbColor: _kGreen,
                      onChanged: (val) => setState(() => _allowInstallments = val),
                    ),
                  ],
                ),
                if (_allowInstallments) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _minInstallmentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Minimum Initial Deposit / Installment (GHS)',
                      hintText: '0.00 for no minimum',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.money_rounded, size: 16),
                    ),
                    style: GoogleFonts.outfit(fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Bill: GHS ${_calculatedTotal.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: _kPrimary),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _savingBill ? null : _saveAndIssueBill,
                icon: _savingBill
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 15),
                label: Text(
                  _savingBill ? 'Saving...' : 'Save & Issue Bill',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentsLedgerSection(bool isDark) {
    final double totalBilled = double.tryParse(_app['payment_amount']?.toString() ?? '0') ?? 0.0;
    final double totalPaid = double.tryParse(_app['amount_paid']?.toString() ?? '0') ?? 0.0;
    final double balanceDue = totalBilled > totalPaid ? (totalBilled - totalPaid) : 0.0;
    final double progress = totalBilled > 0 ? (totalPaid / totalBilled).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: _kPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Renewal Payment Ledger & Installments',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _kTextDark,
                      ),
                    ),
                    Text(
                      'Summary of bill settlement and received installments',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (balanceDue <= 0.01 && totalBilled > 0 ? _kGreen : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  balanceDue <= 0.01 && totalBilled > 0 ? 'SETTLED' : 'GHS ${balanceDue.toStringAsFixed(2)} DUE',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: balanceDue <= 0.01 && totalBilled > 0 ? _kGreen : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Financial Highlights ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL BILLED', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('GHS ${totalBilled.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL PAID', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: _kGreen)),
                      const SizedBox(height: 2),
                      Text('GHS ${totalPaid.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _kGreen)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (balanceDue > 0 ? const Color(0xFFF59E0B) : _kGreen).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BALANCE DUE', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: balanceDue > 0 ? const Color(0xFFF59E0B) : _kGreen)),
                      const SizedBox(height: 2),
                      Text('GHS ${balanceDue.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: balanceDue > 0 ? const Color(0xFFF59E0B) : _kGreen)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Progress Bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? _kGreen : _kPrimary),
            ),
          ),
          const SizedBox(height: 16),

          // ── Installments Transaction List ──
          if (_installments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'No payments recorded yet for this bill.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          else ...[
            Text(
              'Recorded Installments (${_installments.length})',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark),
            ),
            const SizedBox(height: 8),
            ..._installments.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final p = Map<String, dynamic>.from(entry.value is Map ? entry.value : {});
              final pAmt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
              final pStatus = p['status']?.toString().toLowerCase() ?? 'pending';
              final isPConfirmed = pStatus == 'paid' || pStatus == 'completed' || pStatus == 'success';
              final pMethod = (p['payment_method']?.toString() ?? 'momo').toUpperCase();
              final pDate = p['date']?.toString().split('T').first ?? p['created_at']?.toString().split('T').first ?? '';
              final pRef = p['payment_ref']?.toString() ?? p['ref_code']?.toString() ?? '—';
              final rawReceipt = p['receipt_url']?.toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: (isPConfirmed ? _kGreen : _kAmber).withValues(alpha: 0.15),
                      child: Text(
                        '#$idx',
                        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: isPConfirmed ? _kGreen : _kAmber),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'GHS ${pAmt.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isPConfirmed ? _kGreen : _kAmber).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isPConfirmed ? 'CONFIRMED' : 'PENDING',
                                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: isPConfirmed ? _kGreen : _kAmber),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$pMethod • $pDate • Ref: $pRef',
                            style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    if (rawReceipt != null && rawReceipt.trim().isNotEmpty)
                      IconButton(
                        tooltip: 'View Receipt',
                        icon: const Icon(Icons.receipt_rounded, size: 20, color: _kPrimary),
                        onPressed: () async {
                          final resolved = ApiService.resolveImageUrl(rawReceipt);
                          final uri = Uri.parse(resolved);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDecisionSection(bool isDark, bool isResolved) {
    final bool isRenewal = _app['type']?.toString().toLowerCase() == 'renewal';
    final bool allDocsApproved = _docs.isNotEmpty && _docs.every((d) => d['status'] == 'approved');
    final String approveBtnLabel = allDocsApproved
        ? (isRenewal ? 'Approve Renewal' : 'Approve Application')
        : (isRenewal ? 'Approve All Documents & Renewal' : 'Approve All Documents');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Application Review Actions',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : _kTextDark,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                icon: _requestingRevision
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Request Revision'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAmber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _requestingRevision ? null : _requestRevision,
              ),
              ElevatedButton.icon(
                icon: _approving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_rounded, size: 16),
                label: Text(approveBtnLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (_approving || isResolved) ? null : _approveAll,
              ),
              OutlinedButton.icon(
                icon: _rejecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))
                    : const Icon(Icons.cancel_rounded, size: 16),
                label: const Text('Reject Application'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kRed,
                  side: const BorderSide(color: _kRed),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (_rejecting || isResolved) ? null : _rejectAll,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _app['status']?.toString() ?? '';
    final memberName = _app['member_name']?.toString() ?? 'Applicant';
    final memberCompany = _app['member_company']?.toString() ?? '';
    final appType = _app['type']?.toString() ?? '';
    final typeLabel = appType == 'renewal'
        ? 'Membership Renewal'
        : 'Member ID Application';
    final isResolved = status == 'approved' || status == 'rejected';

    final pageTitle = memberCompany.isNotEmpty
        ? 'Review: $memberCompany'
        : 'Review: $memberName';

    return AppLayout(
      title: pageTitle,
      scrollable: true,
      child: Container(
        color: isDark ? _kDarkBg : const Color(0xFFF8FAFC),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _loading
            ? Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    children: List.generate(
                      4,
                      (_) => const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ShimmerListTile(),
                      ),
                    ),
                  ),
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Navigation / Back Bar ──
                      _buildTopHeaderBar(isDark, typeLabel, status),
                      const SizedBox(height: 16),

                      // ── Member & Application Overview Card ──
                      _MemberInfoCard(app: _app, isDark: isDark),
                      const SizedBox(height: 16),

                      // ── Status & Notes Banner (if rejected/revision/notes) ──
                      if (_app['admin_note'] != null && _app['admin_note'].toString().trim().isNotEmpty) ...[
                        _AdminStatusBanner(status: status, note: _app['admin_note']?.toString()),
                        const SizedBox(height: 16),
                      ],

                      // ── Bank Deposit Slip / Proof of Payment Attachment ──
                      if (_payment != null || (_app['payment_ref'] != null && _app['payment_ref'].toString().isNotEmpty)) ...[
                        _buildPaymentProofSection(isDark),
                        const SizedBox(height: 20),
                      ],

                      // ── Renewal Payment Ledger & Installments ──
                      if (_app['type'] == 'renewal' && (_installments.isNotEmpty || _app['amount_paid'] != null || status == 'partially_paid' || status == 'payment_confirmed')) ...[
                        _buildInstallmentsLedgerSection(isDark),
                        const SizedBox(height: 20),
                      ],

                      // ── Required Documents Section ──
                      _buildDocumentsSection(isDark, isResolved),
                      const SizedBox(height: 20),

                      // ── Profile-Specific Renewal Bill Section ──
                      _buildBillGenerationSection(isDark),
                      const SizedBox(height: 20),

                      // ── Decision Actions ──
                      if (!isResolved &&
                          [
                            'under_review',
                            'payment_confirmed',
                            'submitted',
                            'revision_requested',
                            'awaiting_bill',
                            'awaiting_payment',
                            'partially_paid',
                          ].contains(status))
                        _buildDecisionSection(isDark, isResolved),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _MemberInfoCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final bool isDark;
  const _MemberInfoCard({required this.app, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final memberName = app['member_name']?.toString() ?? 'Applicant';
    final memberCompany = app['member_company']?.toString() ?? 'N/A';
    final memberEmail = app['member_email']?.toString() ?? 'N/A';
    final memberPhone = app['member_phone']?.toString() ?? 'N/A';
    final category = (app['category']?.toString() ?? 'ASSOCIATE').toUpperCase();
    final paymentRef = app['payment_ref']?.toString() ?? 'Pending';
    final paymentAmount = app['payment_amount']?.toString();
    final appStatus = app['status']?.toString().toLowerCase() ?? '';
    final bool isPaid = app['payment_confirmed_at'] != null ||
        appStatus == 'payment_confirmed' ||
        appStatus == 'approved';
    final bool isSubmitted = !isPaid &&
        ((app['payment_ref'] != null && app['payment_ref'].toString().isNotEmpty) ||
            appStatus == 'payment_submitted');

    final String paymentStatusVal;
    final Color paymentStatusCol;
    if (isPaid) {
      paymentStatusVal = paymentAmount != null ? 'Paid (GH₵ $paymentAmount)' : 'Paid';
      paymentStatusCol = _kGreen;
    } else if (isSubmitted) {
      paymentStatusVal = paymentAmount != null ? 'Submitted GH₵ $paymentAmount (Awaiting Verification)' : 'Submitted (Awaiting Verification)';
      paymentStatusCol = _kAmber;
    } else {
      paymentStatusVal = 'Pending (Unpaid)';
      paymentStatusCol = const Color(0xFF94A3B8);
    }
    final cardBg = isDark ? _kCardDark : Colors.white;
    final borderColor = isDark ? _kBorderDark : const Color(0xFFE2E8F0);
    final fieldBg = isDark ? _kDarkBg : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : _kTextDark;
    final mutedText = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _kPrimary,
                child: Text(
                  memberCompany.isNotEmpty
                      ? memberCompany[0].toUpperCase()
                      : (memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M'),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
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
                    Text(
                      memberCompany.isNotEmpty ? memberCompany : memberName,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      memberName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$category MEMBER',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Responsive info grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final colWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 20) / 3;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: colWidth,
                    child: _buildGridItem(
                      icon: Icons.email_rounded,
                      label: 'EMAIL',
                      val: memberEmail,
                      fieldBg: fieldBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedText: mutedText,
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: _buildGridItem(
                      icon: Icons.phone_rounded,
                      label: 'TELEPHONE',
                      val: memberPhone,
                      fieldBg: fieldBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedText: mutedText,
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: _buildGridItem(
                      icon: Icons.receipt_long_rounded,
                      label: 'PAYMENT REFERENCE',
                      val: paymentRef,
                      fieldBg: fieldBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedText: mutedText,
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: _buildGridItem(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'PAYMENT STATUS',
                      val: paymentStatusVal,
                      fieldBg: fieldBg,
                      borderColor: borderColor,
                      textColor: paymentStatusCol,
                      mutedText: mutedText,
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: _buildGridItem(
                      icon: Icons.calendar_today_rounded,
                      label: 'SUBMITTED AT',
                      val: _fmt(app['created_at']?.toString()),
                      fieldBg: fieldBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedText: mutedText,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem({
    required IconData icon,
    required String label,
    required String val,
    required Color fieldBg,
    required Color borderColor,
    required Color textColor,
    required Color mutedText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _kPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: mutedText,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  val,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminStatusBanner extends StatelessWidget {
  final String status;
  final String? note;
  const _AdminStatusBanner({required this.status, this.note});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Status: ${_statusLabel(status)}${note != null && note!.isNotEmpty ? ' — $note' : ''}',
              style: GoogleFonts.outfit(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDocRow extends StatefulWidget {
  final Map<String, dynamic> doc;
  final bool isDark, isResolved;
  final VoidCallback onApprove, onReject;
  final Function(String title, String url) onPreview;

  const _AdminDocRow({
    required this.doc,
    required this.isDark,
    required this.isResolved,
    required this.onApprove,
    required this.onReject,
    required this.onPreview,
  });

  @override
  State<_AdminDocRow> createState() => _AdminDocRowState();
}

class _AdminDocRowState extends State<_AdminDocRow> {
  bool _showInlinePreview = false;

  @override
  Widget build(BuildContext context) {
    final uploaded = widget.doc['uploaded'] == true;
    final autoFilled = widget.doc['auto_filled'] == true;
    final status = widget.doc['status']?.toString() ?? 'not_uploaded';
    final label = widget.doc['label']?.toString() ?? 'Document';
    final fileUrl = widget.doc['file_url']?.toString();
    final fileName = widget.doc['file_name']?.toString() ?? 'Document.pdf';
    final adminNote = widget.doc['admin_note']?.toString();

    final isImage =
        fileUrl != null &&
        (fileUrl.toLowerCase().contains('.png') ||
            fileUrl.toLowerCase().contains('.jpg') ||
            fileUrl.toLowerCase().contains('.jpeg') ||
            fileUrl.toLowerCase().contains('.webp') ||
            fileUrl.toLowerCase().contains('.gif'));

    Color sColor = Colors.grey;
    IconData sIcon = Icons.radio_button_unchecked;
    if (!uploaded) {
      sColor = Colors.grey;
      sIcon = Icons.radio_button_unchecked;
    } else if (status == 'approved') {
      sColor = _kGreen;
      sIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      sColor = _kRed;
      sIcon = Icons.cancel_rounded;
    } else if (autoFilled) {
      sColor = _kAmber;
      sIcon = Icons.auto_fix_high_rounded;
    } else {
      sColor = _kAmber;
      sIcon = Icons.hourglass_empty_rounded;
    }

    final docKey = 'compliance_doc_${widget.doc['id'] ?? label.hashCode}';
    final isBankReceipt = widget.doc['is_payment_receipt'] == true || widget.doc['key'] == 'bank_deposit_slip';
    final paymentRef = widget.doc['payment_ref']?.toString();
    final paymentAmount = widget.doc['amount'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1410) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: uploaded
              ? sColor.withValues(alpha: 0.25)
              : (widget.isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isBankReceipt ? Icons.account_balance_rounded : sIcon, color: isBankReceipt ? const Color(0xFF0F766E) : sColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: widget.isDark ? Colors.white : _kTextDark,
                  ),
                ),
              ),
              if (isBankReceipt)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 11, color: Color(0xFF0F766E)),
                      const SizedBox(width: 4),
                      Text(
                        'Payment Slip',
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          color: const Color(0xFF0F766E),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (autoFilled)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Auto-filled',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: _kAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          if (isBankReceipt && (paymentRef != null || paymentAmount != null)) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF132321) : const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (paymentRef != null)
                    Text(
                      'Ref: $paymentRef',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F766E)),
                    ),
                  if (paymentRef != null && paymentAmount != null)
                    Text('  •  ', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey)),
                  if (paymentAmount != null)
                    Text(
                      'GHS ${(paymentAmount as num).toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kGreen),
                    ),
                ],
              ),
            ),
          ],

          if (fileUrl != null && fileUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'File: $fileName',
                    style: GoogleFonts.inter(fontSize: 12, color: widget.isDark ? Colors.white60 : const Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showInlinePreview = !_showInlinePreview),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(_showInlinePreview ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 13, color: _kPrimary),
                        const SizedBox(width: 4),
                        Text(
                          _showInlinePreview ? 'Hide' : 'Preview',
                          style: GoogleFonts.outfit(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => widget.onPreview(label, fileUrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.fullscreen_rounded, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Full View',
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    final resolved = ApiService.resolveImageUrl(fileUrl);
                    final uri = Uri.parse(resolved);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.open_in_new_rounded, size: 13, color: Colors.grey),
                  ),
                ),
              ],
            ),

            if (_showInlinePreview) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: isImage ? 280 : 380,
                decoration: BoxDecoration(
                  color: widget.isDark ? _kDarkBg : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.isDark ? _kBorderDark : const Color(0xFFCBD5E1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: isImage
                      ? InteractiveViewer(
                          child: CorsImageWidget(
                            url: fileUrl,
                            fit: BoxFit.contain,
                            placeholder: const Center(
                              child: CircularProgressIndicator(color: _kPrimary),
                            ),
                            errorWidget: const Center(
                              child: Text('Failed to load image preview.'),
                            ),
                          ),
                        )
                      : doc_preview.buildDocPreview(fileUrl, docKey),
                ),
              ),
            ],
          ],

          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Note: $adminNote',
                style: GoogleFonts.outfit(fontSize: 11.5, color: _kRed),
              ),
            ),
          ],

          if (uploaded && !widget.isResolved) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (status != 'approved')
                  _DocAction(
                    label: 'Approve',
                    color: _kGreen,
                    icon: Icons.check_rounded,
                    onTap: widget.onApprove,
                  ),
                const SizedBox(width: 8),
                if (status != 'rejected')
                  _DocAction(
                    label: 'Reject',
                    color: _kRed,
                    icon: Icons.close_rounded,
                    onTap: widget.onReject,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DocAction extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _DocAction({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}
