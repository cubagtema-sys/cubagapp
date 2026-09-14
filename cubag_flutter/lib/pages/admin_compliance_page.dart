// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
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
    case 'under_review':
      return _kPrimary;
    case 'submitted':
      return _kAmber;
    case 'payment_pending':
      return _kAmber;
    case 'payment_confirmed':
      return _kPrimary;
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
    case 'payment_pending':
      return 'Payment Pending';
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _kDarkBg : const Color(0xFFF8FAFC);
    final cardBg = isDark ? _kCardDark : Colors.white;
    final borderColor = isDark ? _kBorderDark : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : _kTextDark;

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
      title: 'Renewal Documents Verification',
      scrollable: false,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: AdminHeader(
                title: 'Renewal Documents Verification',
                subtitle:
                    'Review submitted member annual membership renewal applications, statutory filing verifications, and compliance audits.',
                actions: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAdminOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _fetch('renewal'),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      'Refresh',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 3 CATEGORY TABS (Corporate, Licentiate, Associate) ─────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildCategoryTab(
                      'Corporate Brokerage',
                      'corporate',
                      Icons.business_rounded,
                      _kPrimary,
                      corpApps.length,
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryTab(
                      'Licentiate Broker',
                      'licentiate',
                      Icons.badge_rounded,
                      const Color(0xFF6366F1),
                      licApps.length,
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryTab(
                      'Associate Member',
                      'associate',
                      Icons.handshake_rounded,
                      _kGreen,
                      assocApps.length,
                      isDark,
                    ),
                  ],
                ),
              ),
            ),

            // ── KPI SUMMARY CARDS FOR CURRENT CATEGORY ────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Total Renewals',
                      '$activeCategoryTotal',
                      Icons.folder_shared_rounded,
                      _kPrimary,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Under Review',
                      '$underReviewCount',
                      Icons.pending_actions_rounded,
                      const Color(0xFF3B82F6),
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Approved',
                      '$approvedCount',
                      Icons.verified_rounded,
                      _kGreen,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Submitted',
                      '$submittedCount',
                      Icons.send_rounded,
                      _kAmber,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Revision Needed',
                      '$revisionCount',
                      Icons.replay_rounded,
                      _kAmber,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Rejected',
                      '$rejectedCount',
                      Icons.cancel_rounded,
                      _kRed,
                      isDark,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search & Filter Controls Bar ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: AdminToolbar(
                searchHint: 'Search $_selectedCategory renewal dossiers by applicant, company, or ref...',
                onSearchChanged: (v) => setState(() => _renewalSearch = v),
                filters: [
                  _filterChip(
                    'All Statuses ($activeCategoryTotal)',
                    '',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                  ),
                  _filterChip(
                    'Under Review ($underReviewCount)',
                    'under_review',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                    color: const Color(0xFF3B82F6),
                  ),
                  _filterChip(
                    'Approved ($approvedCount)',
                    'approved',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                    color: _kGreen,
                  ),
                  _filterChip(
                    'Submitted ($submittedCount)',
                    'submitted',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                    color: _kAmber,
                  ),
                  _filterChip(
                    'Revision Requested ($revisionCount)',
                    'revision_requested',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                    color: _kAmber,
                  ),
                  _filterChip(
                    'Rejected ($rejectedCount)',
                    'rejected',
                    _statusFilters['renewal'] ?? '',
                    (s) => setState(() => _statusFilters['renewal'] = s),
                    isDark,
                    color: _kRed,
                  ),
                ],
              ),
            ),

            // ── Data Table Area ──────────────────────────────────────────────
            Expanded(
              child: _loading['renewal'] == true
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      itemCount: 6,
                      itemBuilder: (_, i) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: ShimmerListTile(),
                      ),
                    )
                  : currentList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No $_selectedCategory renewal applications found',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: constraints.maxWidth,
                                      ),
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(
                                          isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                                        ),
                                        headingTextStyle: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                          letterSpacing: 0.6,
                                        ),
                                        dataTextStyle: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                        columnSpacing: 28,
                                        horizontalMargin: 20,
                                        dataRowMinHeight: 64,
                                        dataRowMaxHeight: 74,
                                        columns: const [
                                          DataColumn(label: Text('REF ID')),
                                          DataColumn(label: Text('APPLICANT')),
                                          DataColumn(label: Text('CLASSIFICATION / ENTITY')),
                                          DataColumn(label: Text('RENEWAL DOCS')),
                                          DataColumn(label: Text('PAYMENT')),
                                          DataColumn(label: Text('ACTIONS')),
                                        ],
                                        rows: currentList.map((app) {
                                          final uploaded = (app['docs_uploaded'] as num?)?.toInt() ?? 0;
                                          final totalDocs = (app['docs_total'] as num?)?.toInt() ?? 0;
                                          final approved = (app['docs_approved'] as num?)?.toInt() ?? 0;
                                          final paymentRef = app['payment_ref']?.toString();
                                          final paymentAmount = app['payment_amount'];
                                          final hasPaid = paymentRef != null && paymentRef.isNotEmpty;
                                          final paymentLabel = hasPaid
                                              ? (paymentAmount != null ? 'Paid GH₵ $paymentAmount' : 'Paid')
                                              : 'Pending';

                                          return DataRow(
                                            cells: [
                                              // REF ID
                                              DataCell(
                                                Text(
                                                  '#COMP-${(app['id'] as int).toString().padLeft(5, '0')}',
                                                  style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: _kPrimary,
                                                  ),
                                                ),
                                              ),
                                              // APPLICANT
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 16,
                                                      backgroundColor: _kPrimary.withAlpha(40),
                                                      child: Text(
                                                        (app['member_name']?.toString() ?? 'M').substring(0, 1).toUpperCase(),
                                                        style: GoogleFonts.outfit(
                                                          color: _kPrimary,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          app['member_name']?.toString() ?? '—',
                                                          style: GoogleFonts.outfit(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                            color: textColor,
                                                          ),
                                                        ),
                                                        Text(
                                                          app['member_email']?.toString() ?? '—',
                                                          style: GoogleFonts.outfit(
                                                            fontSize: 11,
                                                            color: isDark ? Colors.white60 : Colors.grey,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // CLASSIFICATION / ENTITY
                                              DataCell(
                                                Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      app['member_company']?.toString() ?? 'Individual Practitioner',
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: _kPrimary.withAlpha(isDark ? 30 : 15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        _selectedCategory.toUpperCase(),
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: _kPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // RENEWAL DOCS
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: (approved == totalDocs && totalDocs > 0)
                                                        ? _kGreen.withAlpha(25)
                                                        : _kPrimary.withAlpha(25),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        (approved == totalDocs && totalDocs > 0)
                                                            ? Icons.check_circle_rounded
                                                            : Icons.description_outlined,
                                                        size: 13,
                                                        color: (approved == totalDocs && totalDocs > 0) ? _kGreen : _kPrimary,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        '$uploaded/$totalDocs ($approved approved)',
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: (approved == totalDocs && totalDocs > 0) ? _kGreen : _kPrimary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // PAYMENT
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: hasPaid ? _kGreen.withAlpha(25) : _kAmber.withAlpha(25),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        hasPaid ? Icons.verified_rounded : Icons.pending_rounded,
                                                        size: 13,
                                                        color: hasPaid ? _kGreen : _kAmber,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        paymentLabel,
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: hasPaid ? _kGreen : _kAmber,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // ACTIONS
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // Review Applicant Button
                                                    ElevatedButton.icon(
                                                      onPressed: () => _openDetail(app),
                                                      icon: const Icon(Icons.rate_review_rounded, size: 14),
                                                      label: Text(
                                                        'Review Applicant',
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: _kPrimary,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                        elevation: 0,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
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
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? color.withAlpha(40) : color.withAlpha(20)) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
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

  Widget _buildMetricCard(
    String label,
    String val,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  val,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String current,
    ValueChanged<String> onSelect,
    bool isDark, {
    Color? color,
  }) {
    final selected = current == value;
    final activeCol = color ?? _kPrimary;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelect(value),
        labelStyle: GoogleFonts.outfit(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          color: selected ? Colors.white : (isDark ? Colors.white70 : _kTextDark),
        ),
        selectedColor: activeCol,
        backgroundColor: isDark ? _kCardDark : Colors.white,
        side: BorderSide(
          color: selected ? activeCol : (isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> app) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminComplianceDetailPage(appId: app['id'] as int),
      ),
    );
    await _fetch('renewal');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DETAIL PAGE
// ─────────────────────────────────────────────────────────────────────────────
class AdminComplianceDetailPage extends StatefulWidget {
  final int appId;
  const AdminComplianceDetailPage({super.key, required this.appId});
  @override
  State<AdminComplianceDetailPage> createState() =>
      _AdminComplianceDetailPageState();
}

class _AdminComplianceDetailPageState extends State<AdminComplianceDetailPage> {
  bool _loading = true;
  Map<String, dynamic> _app = {};
  List<dynamic> _docs = [];
  bool _approving = false;
  bool _rejecting = false;
  bool _requestingRevision = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
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
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_compliance_detail', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateDocStatus(Map<String, dynamic> doc, String status) async {
    final docId = (doc['id'] as num?)?.toInt();
    if (docId == null) return;
    String? note;
    if (status == 'rejected') {
      note = await _promptNote(context, 'Rejection note for "${doc['label']}"');
      if (note == null) return;
    }
    try {
      await ApiService().put(
        '/compliance/admin/applications/${widget.appId}/doc/$docId/status',
        data: {'status': status, 'note': note ?? ''},
      );
      _showSnack(
        status == 'approved' ? 'Document approved' : 'Document rejected',
        color: status == 'approved' ? _kGreen : _kRed,
      );
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    }
  }

  Future<void> _approveAll() async {
    final note = await _promptNote(context, 'Approval note (optional)');
    if (!mounted) return;
    setState(() => _approving = true);
    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/approve',
        data: {'note': note ?? ''},
      );
      _showSnack('Application approved!', color: _kGreen);
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
          'Add Note',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx, _noteCtrl.text.trim()),
            child: Text(
              'Confirm',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _app['status']?.toString() ?? '';
    final appType = _app['type']?.toString() ?? '';
    final typeLabel = appType == 'renewal'
        ? 'Membership Renewal'
        : 'Member ID Application';
    final isResolved = status == 'approved' || status == 'rejected';

    return Scaffold(
      backgroundColor: isDark ? _kDarkBg : const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: _kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          typeLabel,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetch,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
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
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetch,
              color: _kPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Member Info Card ──────────────────────────────
                        _MemberInfoCard(app: _app, isDark: isDark),
                        const SizedBox(height: 16),

                        // ── Status Banner ─────────────────────────────────
                        _AdminStatusBanner(
                          status: status,
                          note: _app['admin_note']?.toString(),
                        ),
                        const SizedBox(height: 20),

                        // ── Documents ─────────────────────────────────────
                        Text(
                          'Required Documents',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._docs.map(
                          (d) => _AdminDocRow(
                            doc: d as Map<String, dynamic>,
                            isDark: isDark,
                            isResolved: isResolved,
                            onApprove: () => _updateDocStatus(d, 'approved'),
                            onReject: () => _updateDocStatus(d, 'rejected'),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Decision Buttons ──────────────────────────────
                        if (!isResolved &&
                            [
                              'under_review',
                              'payment_confirmed',
                              'submitted',
                              'revision_requested',
                            ].contains(status)) ...[
                          Text(
                            'Application Decision',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : _kTextDark,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Request Revision — amber middle option
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: _requestingRevision
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.edit_note_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                'Request Revision',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kAmber,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _requestingRevision
                                  ? null
                                  : _requestRevision,
                            ),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: AnimatedOpacity(
                                  opacity: isResolved ? 0.4 : 1.0,
                                  duration: const Duration(milliseconds: 400),
                                  child: ElevatedButton.icon(
                                    icon: _approving
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
                                          ),
                                    label: Text(
                                      'Approve All',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: (_approving || isResolved)
                                        ? null
                                        : _approveAll,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: _rejecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.cancel_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    'Reject',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kRed,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: (_rejecting || isResolved)
                                      ? null
                                      : _rejectAll,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
    final refId = '#COMP-${(app['id'] as int? ?? 0).toString().padLeft(5, '0')}';
    final cardBg = isDark ? _kCardDark : Colors.white;
    final borderColor = isDark ? _kBorderDark : const Color(0xFFE2E8F0);
    final fieldBg = isDark ? _kDarkBg : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : _kTextDark;
    final mutedText = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [_kPrimary, const Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFFF97316),
                  child: Text(
                    memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                          Expanded(
                            child: Text(
                              memberName,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF97316).withAlpha(50),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFF97316).withAlpha(120)),
                            ),
                            child: Text(
                              '$category MEMBER',
                              style: GoogleFonts.outfit(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFF97316),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$refId • $memberCompany',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Info Grid
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildGridItem(
                        icon: Icons.email_rounded,
                        label: 'EMAIL ADDRESS',
                        val: memberEmail,
                        fieldBg: fieldBg,
                        borderColor: borderColor,
                        textColor: textColor,
                        mutedText: mutedText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGridItem(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'FEE PAID',
                        val: paymentAmount != null ? 'GH₵ $paymentAmount' : 'Pending Verification',
                        fieldBg: fieldBg,
                        borderColor: borderColor,
                        textColor: paymentAmount != null ? _kGreen : _kAmber,
                        mutedText: mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildGridItem(
                  icon: Icons.calendar_today_rounded,
                  label: 'SUBMISSION TIMESTAMP',
                  val: _fmt(app['created_at']?.toString()),
                  fieldBg: fieldBg,
                  borderColor: borderColor,
                  textColor: textColor,
                  mutedText: mutedText,
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF97316)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: mutedText,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  val,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
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

  const _AdminDocRow({
    required this.doc,
    required this.isDark,
    required this.isResolved,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_AdminDocRow> createState() => _AdminDocRowState();
}

class _AdminDocRowState extends State<_AdminDocRow> {
  bool _showPreview = false;

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
                    color: _kPrimary,
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
                            child: CircularProgressIndicator(color: _kPrimary),
                          ),
                          errorWidget: const Center(
                            child: Text('Failed to load image preview.'),
                          ),
                        ),
                      )
                    : kIsWeb
                    ? doc_preview.buildDocPreview(
                        fileUrl,
                        'modal_${title.hashCode}',
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 48,
                              color: _kPrimary,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Open Document'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimary,
                              ),
                              onPressed: () async {
                                final uri = Uri.parse(fileUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                            ),
                          ],
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
    final uploaded = widget.doc['uploaded'] == true;
    final autoFilled = widget.doc['auto_filled'] == true;
    final status = widget.doc['status']?.toString() ?? 'not_uploaded';
    final label = widget.doc['label']?.toString() ?? '';
    final fileUrl = widget.doc['file_url']?.toString();
    final fileName = widget.doc['file_name']?.toString() ?? 'View Document';
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: uploaded
              ? sColor.withValues(alpha: 0.25)
              : (widget.isDark ? _kBorderDark : const Color(0xFFe2e8f0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sIcon, color: sColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: widget.isDark ? Colors.white : _kTextDark,
                  ),
                ),
              ),
              if (autoFilled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
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

          if (fileUrl != null && fileUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Inline Preview Toggle Button
                InkWell(
                  onTap: () => setState(() => _showPreview = !_showPreview),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _showPreview
                          ? _kPrimary.withValues(alpha: 0.15)
                          : _kPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _kPrimary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showPreview
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 14,
                          color: _kPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showPreview ? 'Hide Preview' : 'Preview Document',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: _kPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Full Modal Dialog Button
                InkWell(
                  onTap: () => _showDocPreviewModal(context, label, fileUrl),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.fullscreen_rounded,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Full View',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Open in External Tab
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse(fileUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fileName,
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Inline Document Preview Panel
            if (_showPreview) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: isImage ? 320 : 420,
                decoration: BoxDecoration(
                  color: widget.isDark ? _kDarkBg : const Color(0xFFf1f5f9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isDark
                        ? _kBorderDark
                        : const Color(0xFFcbd5e1),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: isImage
                      ? InteractiveViewer(
                          child: CorsImageWidget(
                            url: fileUrl,
                            fit: BoxFit.contain,
                            placeholder: const Center(
                              child: CircularProgressIndicator(
                                color: _kPrimary,
                              ),
                            ),
                            errorWidget: const Center(
                              child: Text('Failed to load image preview.'),
                            ),
                          ),
                        )
                      : kIsWeb
                      ? doc_preview.buildDocPreview(fileUrl, docKey)
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 40,
                                color: _kPrimary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'PDF preview available on Web.',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 14,
                                ),
                                label: const Text('Open Document'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kPrimary,
                                ),
                                onPressed: () async {
                                  final uri = Uri.parse(fileUrl);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ],

          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Note: $adminNote',
                style: GoogleFonts.outfit(fontSize: 11.5, color: _kRed),
              ),
            ),
          ],

          if (uploaded && !widget.isResolved) ...[
            const SizedBox(height: 10),
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
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
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
