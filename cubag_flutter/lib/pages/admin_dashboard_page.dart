import '../components/admin_dialog.dart';
import '../components/admin_list.dart';
import '../components/cubag_ui.dart';
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
                      'Office desk',
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
                          'New members to approve',
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
                        'See all',
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
                              m['name']?.toString() ?? 'New member';
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
                  ? 'Document approved'
                  : 'Document rejected',
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
              content: Text('$name is approved and active.'),
              backgroundColor: CubagColors.valid,
              behavior: SnackBarBehavior.floating,
            ),
          );
          widget.onApproved();
        } else {
          final msg = res.data?['message'] ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not approve: $msg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not approve the member. Try again.'),
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdminDialog(
        title: 'Reject this application?',
        subtitle: '$name is told it was not accepted and why.',
        maxWidth: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CubagColors.lapsed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject application'),
          ),
        ],
        children: [
          AdminField(
            label: 'Reason (the applicant sees it)',
            child: TextField(
              controller: noteCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'For example: The SSNIT certificate has expired'),
            ),
          ),
        ],
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
              content: Text("$name's application was rejected."),
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
      // SEC-04: private documents open through a short-lived signed link.
      final uri = Uri.parse(await ApiService.signedDocumentUrl(urlStr));
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
    String v(String k) {
      final x = m[k]?.toString() ?? '';
      return x == 'null' ? '' : x;
    }

    final name = v('name').isEmpty ? 'New member' : v('name');
    final paymentRef = v('payment_ref');
    final hasPayment = paymentRef.isNotEmpty;
    final uploaded = _documents.where((d) => d['uploaded'] == true).length;
    final approved = _documents.where((d) => d['status'] == 'approved').length;

    return AdminDialog(
      title: name,
      subtitle: 'Check the documents and the payment, then approve to activate the membership.',
      maxWidth: 680,
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: CubagColors.lapsed),
          onPressed: _submitting ? null : _rejectMember,
          child: const Text('Reject application'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _approveMember,
          child: Text(_submitting ? 'Approving…' : 'Approve member'),
        ),
      ],
      children: [
        AdminDetailRow('Company', v('company')),
        AdminDetailRow('Email', v('email')),
        AdminDetailRow('Phone', v('phone')),
        AdminDetailRow('TIN', v('tin')),
        AdminDetailRow('Member type', v('member_type').isEmpty ? 'Corporate' : v('member_type')),
        const SizedBox(height: CubagSpace.md),
        Container(
          padding: const EdgeInsets.all(CubagSpace.sm),
          decoration: BoxDecoration(
            color: hasPayment ? CubagColors.validTint : CubagColors.dueTint,
            borderRadius: BorderRadius.circular(CubagRadius.control),
          ),
          child: Row(
            children: [
              Icon(hasPayment ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 20, color: hasPayment ? CubagColors.valid : CubagColors.due),
              const SizedBox(width: CubagSpace.xs),
              Expanded(
                child: Text(
                  hasPayment ? 'Registration paid. Reference $paymentRef.' : 'No registration payment recorded yet.',
                  style: CubagType.small.copyWith(color: hasPayment ? CubagColors.valid : CubagColors.due),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CubagSpace.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Documents · $uploaded uploaded, $approved approved',
                style: CubagType.headline,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/admin/documents/${widget.member['id']}');
              },
              child: const Text('Open in Applications'),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.xs),
        if (_loadingDocs)
          Column(
            children: List.generate(3, (_) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
          )
        else if (_documents.isEmpty)
          Text('No documents are required for this application.', style: CubagType.small)
        else
          AdminRowGroup(
            dividerIndent: 68,
            children: [
              for (final raw in _documents)
                () {
                  final doc = raw as Map;
                  final up = doc['uploaded'] == true;
                  final status = doc['status']?.toString() ?? 'not_uploaded';
                  final fileUrl = doc['file_url']?.toString();
                  final docId = doc['id'] as int?;
                  final (label, kind) = switch (status) {
                    'approved' => ('Approved', StatusKind.good),
                    'rejected' => ('Rejected', StatusKind.bad),
                    _ => up ? ('To check', StatusKind.pending) : ('Not uploaded', StatusKind.neutral),
                  };
                  return AdminListRow(
                    leading: AdminRowMark(icon: up ? Icons.description_outlined : Icons.article_outlined),
                    title: doc['label']?.toString() ?? 'Document',
                    subtitle: doc['file_name']?.toString(),
                    status: StatusChip(label, kind: kind),
                    onTap: up && fileUrl != null ? () => _openFile(fileUrl) : null,
                    trailing: up && docId != null
                        ? PopupMenuButton<String>(
                            tooltip: 'Decide',
                            icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
                            onSelected: (a) {
                              if (a == 'view' && fileUrl != null) _openFile(fileUrl);
                              if (a == 'approve') _updateDocStatus(docId, 'approved');
                              if (a == 'reject') _updateDocStatus(docId, 'rejected');
                            },
                            itemBuilder: (_) => [
                              if (fileUrl != null) const PopupMenuItem(value: 'view', child: Text('Open the file')),
                              const PopupMenuItem(value: 'approve', child: Text('Approve document')),
                              PopupMenuItem(value: 'reject', child: Text('Reject document', style: TextStyle(color: CubagColors.lapsed))),
                            ],
                          )
                        : const SizedBox(width: CubagSpace.xs),
                  );
                }(),
            ],
          ),
      ],
    );
  }
}
