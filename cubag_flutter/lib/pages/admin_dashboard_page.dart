import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';
import 'admin_dashboard/admin_overview.dart';
import '../utils/session_storage.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  String? _error;
  bool _prefetchStarted = false;

  // Stats Data
  /// Full GET /admin/dashboard response (kpis, queue, revenue_by_month, ...).
  Map<String, dynamic> _dash = {};
  List<dynamic> _rawMembers = [];
  Timer? _prefetchTimer;
  Map<String, String> _forex = {
    'USD': '15.45',
    'EUR': '16.80',
    'GBP': '19.50',
    'CNY': '2.15',
  };

  @override
  void initState() {
    super.initState();
    _fetchData();
    _prefetchAdminData();
    SocketService().socket?.on('member_updated', _onLiveUpdate);
    SocketService().socket?.on('payment_approved', _onLiveUpdate);
    SocketService().socket?.on('fees_updated', _onLiveUpdate);
    SocketService().socket?.on('tasks_updated', _onLiveUpdate);
  }

  void _onLiveUpdate(dynamic _) {
    if (mounted) _fetchData();
  }

  @override
  void dispose() {
    SocketService().socket?.off('member_updated', _onLiveUpdate);
    SocketService().socket?.off('payment_approved', _onLiveUpdate);
    SocketService().socket?.off('fees_updated', _onLiveUpdate);
    SocketService().socket?.off('tasks_updated', _onLiveUpdate);
    _prefetchTimer?.cancel();
    super.dispose();
  }

  void _prefetchAdminData() {
    if (_prefetchStarted) return;
    _prefetchStarted = true;

    final api = ApiService();
    // Stagger background pre-fetching by 1.5 seconds so initial dashboard stats load instantly
    _prefetchTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      try {
        await Future.wait([
          api.fetchDataWithCache(
            '/members/admin/all?page=1&limit=20',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/payments/admin/all?page=1&limit=20&search=&status=all',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/tickets/admin/all?page=1&per_page=10&status=inbox',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/announcements/admin/all?archived=false&page=1&limit=20',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/announcements/admin/all?archived=true&page=1&limit=20',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/schedules?status=All&page=1&per_page=10',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/events/admin/all?page=1&per_page=20&status=upcoming',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/events/admin/all?page=1&per_page=20&status=history',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/surveys/admin/all?page=1&per_page=20&status=active',
            (data, isCached, {bool hasError = false}) {},
          ),
          api.fetchDataWithCache(
            '/compliance/admin/applications',
            (data, isCached, {bool hasError = false}) {},
          ),
        ]);
      } catch (e, st) {
        AppLogger.error('admin_dashboard_page', e, st);
      }
    });
  }

  Future<void> _fetchData() async {
    if (_rawMembers.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final api = ApiService();
      await Future.wait([
        api.fetchDataWithCache('/admin/dashboard', (
          data,
          isCached, {
          bool hasError = false,
        }) {
          if (!mounted) return;
          if (hasError) {
            if (mounted) {
              setState(() {
                _error = 'Server error loading dashboard stats';
                _loading = false;
              });
            }
            return;
          }
          if (data is Map) {
            final dData = Map<String, dynamic>.from(data);
            if (mounted) setState(() => _dash = dData);
          }
        }),
        api.fetchDataWithCache(
          '/members/admin/all?page=1&limit=100&status=pending',
          (data, isCached, {bool hasError = false}) {
            if (!mounted) return;
            if (data != null) {
              final list = ApiService.ensureList(data);
              if (mounted) {
                setState(() => _rawMembers = list);
              }
              // Warm up cache for top 5 pending members' documents to prevent network connection saturation
              for (final m in list.take(5)) {
                final mId = m['id'];
                if (mId != null) {
                  api.fetchDataWithCache(
                    '/documents/admin/member/$mId',
                    (dData, dCached, {bool hasError = false}) {},
                  );
                }
              }
            }
          },
        ),
      ]);

      if (mounted) {
        setState(() => _loading = false);
      }

      api.getPublic('intelligence').then((res) {
        if (mounted && res is Map && res['forex'] is Map) {
          final fx = Map<String, dynamic>.from(res['forex']);
          setState(() {
            _forex = {
              'USD': fx['USD']?.toString() ?? _forex['USD']!,
              'EUR': fx['EUR']?.toString() ?? _forex['EUR']!,
              'GBP': fx['GBP']?.toString() ?? _forex['GBP']!,
              'CNY': fx['CNY']?.toString() ?? _forex['CNY']!,
            };
          });
        }
      }).catchError((_) {});

      if (!_prefetchStarted) {
        _prefetchAdminData();
      }
    } catch (e, st) {
      AppLogger.error('admin_dashboard_page', e, st);
      if (mounted) {
        setState(() {
          _error = 'Server error loading dashboard';
          _loading = false;
        });
      }
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '??';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '??';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  void _openReviewDialog(Map<String, dynamic> member) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _MemberReviewDialog(
        member: member,
        onApproved: () {
          setState(() {
            _rawMembers.removeWhere((m) => m['id'] == member['id']);
          });
          ApiService.deleteCacheKeysMatching('admin/dashboard');
          ApiService.deleteCacheKeysMatching('members/admin');
          _fetchData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.line;
    final textColor = isDark ? Colors.white : CubagColors.ink;
    final subTextColor = isDark ? Colors.white70 : CubagColors.muted;

    final pendingMembers = _rawMembers
        .where((m) {
          final st = m['status']?.toString().toLowerCase() ?? '';
          return st == 'pending' || st == 'pending_review';
        })
        .toList();

    return AppLayout(
      title: 'Dashboard',
      background: CubagColors.paper,
      hideSearch: false,
      scrollable: true,
      child: _loading
          ? const _AdminDashboardSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) _buildErrorBanner(isDark),
                      AdminOverview(
                        dashboard: _dash,
                        adminName: (SessionStorage.instance.getStringSync('cubag_name') ?? '')
                            .trim()
                            .split(' ')
                            .first,
                        onOpen: (route) => context.go(route),
                      ),
                      const SizedBox(height: CubagSpace.xxl),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final approvals = _buildPendingApprovalsCard(
                            context,
                            pendingMembers,
                            primary,
                            cardBg,
                            borderColor,
                            textColor,
                            subTextColor,
                          );
                          final counter = _buildCounterPaymentActionCard(context, isDark);
                          // Always stacked: the applications table needs ~700 px
                          // and collided with the counter card when side by side.
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [approvals, const SizedBox(height: CubagSpace.xl), counter],
                          );
                        },
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCounterPaymentActionCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1B2E24) : const Color(0xFFE8F5E9);
    final borderCol = CubagColors.valid.withAlpha(isDark ? 90 : 120);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CubagColors.valid.withAlpha(35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: CubagColors.valid,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secretariat Counter Desk',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1F1612),
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Walk-in payments: Cash, Cheque, POS card, Direct wire',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF5F6B7E) : CubagColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CubagColors.valid,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: () => context.go('/admin/payments?action=counter_payment'),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(
                '➕ Record Counter / Cash Payment',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CubagColors.lapsed.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CubagColors.lapsed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: CubagColors.lapsed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: CubagColors.lapsed,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: CubagColors.lapsed, size: 18),
            onPressed: _fetchData,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApprovalsCard(
    BuildContext context,
    List<dynamic> pendingMembers,
    Color primary,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark
        ? CubagColors.ink.withAlpha(150)
        : CubagColors.sand;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: kAdminOrange.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.pending_actions_rounded,
                        color: kAdminOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending Registration Approvals',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: textColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Review and verify newly submitted member applications',
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: kAdminOrange.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kAdminOrange.withAlpha(50)),
                      ),
                      child: Text(
                        pendingMembers.length > 5
                            ? 'Showing latest 5 of ${pendingMembers.length}'
                            : '${pendingMembers.length} awaiting review',
                        style: TextStyle(
                          color: AppColors.accentOrangeText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () =>
                          context.go('/admin/members?status=pending'),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: Text(
                        'View All',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (pendingMembers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 40.0,
                horizontal: 16,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.green,
                      size: 44,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'All caught up!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No members are currently waiting for registration approvals.',
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth < 700 ? 700 : constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(headerBg),
                        headingTextStyle: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: subTextColor,
                        ),
                        dataTextStyle: TextStyle(
                          fontSize: 14,
                          color: textColor,
                        ),
                        columnSpacing: 20,
                        horizontalMargin: 16,
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 76,
                        columns: const [
                          DataColumn(label: Text('Applicant / member')),
                          DataColumn(label: Text('Category')),
                          DataColumn(label: Text('Payment')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: pendingMembers.take(8).map((m) {
                          final name =
                              m['name']?.toString() ?? 'Unnamed Member';
                          final email = m['email']?.toString() ?? '—';
                          final company = m['company']?.toString() ?? '';
                          final type =
                              (m['member_type']?.toString().isNotEmpty == true)
                                  ? m['member_type'].toString()
                                  : 'Corporate';
                          final hasPayment =
                              m['payment_ref'] != null &&
                              m['payment_ref'].toString().isNotEmpty;
                          final paymentRef = m['payment_ref']?.toString() ?? '';
                          final date =
                              m['created_at']?.toString() ??
                              m['date']?.toString() ??
                              '—';

                          Color badgeColor = primary;
                          final typeLower = type.toLowerCase();
                          if (typeLower.contains('corp')) {
                            badgeColor = const Color(0xFF3B82F6); // Blue
                          } else if (typeLower.contains('assoc')) {
                            badgeColor = CubagColors.valid; // Green
                          } else if (typeLower.contains('licen')) {
                            badgeColor = CubagColors.action; // Orange
                          }

                          return DataRow(
                            cells: [
                              // 1. Applicant / Member
                              DataCell(
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 17,
                                        backgroundColor: primary.withAlpha(35),
                                        child: Text(
                                          _getInitials(name),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SelectableText(
                                            name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          SelectableText(
                                            company.isNotEmpty && company != name
                                                ? '$company • $email'
                                                : email,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: subTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 2. Category / Type
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: badgeColor.withAlpha(50),
                                    ),
                                  ),
                                  child: Text(
                                    type.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                              ),

                              // 3. Payment Status
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasPayment
                                        ? Colors.green.withAlpha(25)
                                        : Colors.amber.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: hasPayment
                                          ? Colors.green.withAlpha(60)
                                          : Colors.amber.withAlpha(60),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hasPayment
                                            ? Icons.check_circle_rounded
                                            : Icons.hourglass_top_rounded,
                                        size: 13,
                                        color: hasPayment
                                            ? Colors.green
                                            : Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 5),
                                      SelectableText(
                                        hasPayment
                                            ? 'Paid (${paymentRef.length > 8 ? paymentRef.substring(0, 8) : paymentRef})'
                                            : 'Unpaid / Pending',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: hasPayment
                                              ? Colors.green
                                              : Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 4. Registration Date
                              DataCell(
                                SelectableText(
                                  date.split('T').first,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),

                              // 5. Actions
                              DataCell(
                                ElevatedButton.icon(
                                  onPressed: () => _openReviewDialog(m),
                                  icon: const Icon(
                                    Icons.fact_check_rounded,
                                    size: 14,
                                  ),
                                  label: Text(
                                    'Review',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
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
        ],
      ),
    );
  }
}



class _AdminDashboardSkeleton extends StatelessWidget {
  const _AdminDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ShimmerLoader(
          width: double.infinity,
          height: 100,
          borderRadius: 16,
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(child: ShimmerListTile()),
            SizedBox(width: 12),
            Expanded(child: ShimmerListTile()),
            SizedBox(width: 12),
            Expanded(child: ShimmerListTile()),
          ],
        ),
        const SizedBox(height: 24),
        const ShimmerLoader(width: 180, height: 20, borderRadius: 8),
        const SizedBox(height: 16),
        ...List.generate(
          4,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerListTile(),
          ),
        ),
      ],
    );
  }
}

class _MemberReviewDialog extends StatefulWidget {
  final Map<String, dynamic> member;
  final VoidCallback onApproved;

  const _MemberReviewDialog({required this.member, required this.onApproved});

  @override
  State<_MemberReviewDialog> createState() => _MemberReviewDialogState();
}

class _MemberReviewDialogState extends State<_MemberReviewDialog> {
  bool _loadingDocs = true;
  List<dynamic> _documents = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
  }

  Future<void> _fetchDocuments() async {
    final memberId = widget.member['id'];
    if (memberId == null) return;

    try {
      await ApiService().fetchDataWithCache(
        '/documents/admin/member/$memberId',
        (data, isCached, {bool hasError = false}) {
          if (!mounted) return;
          if (data != null && data is Map && data.containsKey('documents')) {
            setState(() {
              _documents = ApiService.ensureList(data['documents']);
              _loadingDocs = false;
            });
          } else if (!isCached) {
            if (mounted) setState(() => _loadingDocs = false);
          }
        },
      );
    } catch (e, st) {
      AppLogger.error('admin_dashboard_page', e, st);
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _updateDocStatus(int docId, String status) async {
    final prevDocs = _documents.map((d) => Map<String, dynamic>.from(d as Map)).toList();
    // Instant optimistic update
    setState(() {
      for (var d in _documents) {
        if (d is Map && d['id'] == docId) {
          d['status'] = status;
        }
      }
    });

    try {
      final res = await ApiService().put(
        '/documents/admin/doc/$docId/status',
        data: {'status': status},
      );
      if (mounted && res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? '✅ Document approved'
                  : '❌ Document rejected',
            ),
            backgroundColor: status == 'approved' ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        await ApiService.deleteCacheKeysMatching('documents/admin');
        _fetchDocuments();
      } else if (mounted) {
        setState(() => _documents = prevDocs);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _documents = prevDocs);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _approveMember() async {
    if (_submitting) return;
    final memberId = widget.member['id'];
    final name = widget.member['name'] ?? 'Member';
    if (memberId == null) return;

    setState(() => _submitting = true);
    try {
      await ApiService().post('/documents/admin/member/$memberId/approve-all');
      final res = await ApiService().put(
        '/members/admin/status/$memberId',
        data: {'status': 'active'},
      );
      if (mounted) {
        if (res.statusCode == 200) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Member $name has been approved & activated!'),
              backgroundColor: CubagColors.valid,
              behavior: SnackBarBehavior.floating,
            ),
          );
          widget.onApproved();
        } else {
          final msg = res.data?['message'] ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Approval failed: $msg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error approving member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _rejectMember() async {
    if (_submitting) return;
    final memberId = widget.member['id'];
    final name = widget.member['name'] ?? 'Member';
    if (memberId == null) return;

    final noteCtrl = TextEditingController();
    bool dialogSubmitting = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Reject Member',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter reason for rejecting $name (e.g. invalid SSNIT certificate):',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  enabled: !dialogSubmitting,
                  decoration: InputDecoration(
                    hintText: 'Rejection reason...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: dialogSubmitting
                    ? null
                    : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: dialogSubmitting
                    ? null
                    : () {
                        setDialogState(() => dialogSubmitting = true);
                        Navigator.pop(ctx, true);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: dialogSubmitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Reject Application'),
              ),
            ],
          );
        },
      ),
    );

    noteCtrl.dispose();

    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      final res = await ApiService().put(
        '/members/admin/status/$memberId',
        data: {'status': 'rejected', 'admin_note': noteCtrl.text.trim()},
      );
      if (mounted) {
        if (res.statusCode == 200) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Member $name application rejected.'),
              backgroundColor: Colors.orange,
            ),
          );
          widget.onApproved();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openFile(String? urlStr) async {
    if (urlStr == null || urlStr.isEmpty) return;
    try {
      final uri = Uri.parse(urlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = m['name']?.toString() ?? 'Unnamed Member';
    final company = m['company']?.toString() ?? 'N/A';
    final email = m['email']?.toString() ?? 'N/A';
    final phone = m['phone']?.toString() ?? 'N/A';
    final type = m['member_type']?.toString() ?? 'Corporate';
    final tin = m['tin']?.toString() ?? 'N/A';
    final paymentRef = m['payment_ref']?.toString();
    final hasPayment = paymentRef != null && paymentRef.isNotEmpty;

    final uploadedCount = _documents.where((d) => d['uploaded'] == true).length;
    final approvedCount = _documents
        .where((d) => d['status'] == 'approved')
        .length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      color: CubagColors.valid,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Member Validation & Approval',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          'Validate documents and payment before activating license',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Main Content Scrollable
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Member Bio Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CubagColors.sand,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CubagColors.line),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'M',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$company • $type',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _infoItem(
                                  'Email',
                                  email,
                                  Icons.email_outlined,
                                ),
                              ),
                              Expanded(
                                child: _infoItem(
                                  'Phone',
                                  phone,
                                  Icons.phone_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _infoItem(
                                  'TIN',
                                  tin,
                                  Icons.numbers_outlined,
                                ),
                              ),
                              Expanded(
                                child: _infoItem(
                                  'Member Type',
                                  type,
                                  Icons.badge_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Payment Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hasPayment
                            ? Colors.green.withValues(alpha: 0.08)
                            : Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasPayment
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.amber.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasPayment
                                ? Icons.task_alt_rounded
                                : Icons.payment_outlined,
                            color: hasPayment
                                ? Colors.green
                                : Colors.amber.shade900,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasPayment
                                      ? 'Registration Payment Confirmed'
                                      : 'Payment Reference Pending',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: hasPayment
                                        ? Colors.green.shade900
                                        : Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasPayment
                                      ? 'Payment Reference: $paymentRef'
                                      : 'No dues or registration payment reference recorded yet.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: hasPayment
                                        ? Colors.green.shade800
                                        : Colors.amber.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Documents Checklist Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Registration Documents ($uploadedCount uploaded • $approvedCount approved)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 19,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push(
                              '/admin/documents/${widget.member['id']}',
                            );
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: const Text('Full Manager'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_loadingDocs)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 3,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            const ShimmerListTile(),
                      )
                    else if (_documents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'No registration document requirements found.',
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _documents.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = _documents[index];
                          final label = doc['label']?.toString() ?? 'Document';
                          final uploaded = doc['uploaded'] == true;
                          final status =
                              doc['status']?.toString() ?? 'not_uploaded';
                          final fileName = doc['file_name']?.toString();
                          final fileUrl = doc['file_url']?.toString();
                          final docId = doc['id'] as int?;

                          Color statusColor = Colors.grey;
                          String statusText = 'Not Uploaded';
                          if (status == 'approved') {
                            statusColor = Colors.green;
                            statusText = 'Approved';
                          } else if (status == 'rejected') {
                            statusColor = Colors.red;
                            statusText = 'Rejected';
                          } else if (uploaded) {
                            statusColor = Colors.blue;
                            statusText = 'Uploaded';
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  uploaded
                                      ? Icons.description_rounded
                                      : Icons.article_outlined,
                                  color: statusColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                        ),
                                      ),
                                      if (fileName != null)
                                        Text(
                                          fileName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (uploaded && fileUrl != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_red_eye_rounded,
                                      size: 18,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'View Document File',
                                    onPressed: () => _openFile(fileUrl),
                                  ),
                                if (docId != null && uploaded) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Approve Document',
                                    onPressed: () =>
                                        _updateDocStatus(docId, 'approved'),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.highlight_off_rounded,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Reject Document',
                                    onPressed: () =>
                                        _updateDocStatus(docId, 'rejected'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),

            // Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _rejectMember,
                  icon: const Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: Colors.red,
                  ),
                  label: Text(
                    'Reject Application',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _approveMember,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_rounded, size: 18),
                      label: Text(
                        'Approve Member',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CubagColors.valid,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(String label, String val, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              val,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
