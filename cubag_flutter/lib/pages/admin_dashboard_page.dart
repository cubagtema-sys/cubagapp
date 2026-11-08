import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';

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
  int _totalMembers = 0;
  int _openTickets = 0;
  double _revenue = 0.0;
  int _applicationsCount = 0;
  List<dynamic> _rawMembers = [];
  Timer? _prefetchTimer;
  Map<String, String> _forex = {
    'USD': '15.45',
    'EUR': '16.80',
    'GBP': '19.50',
    'CNY': '2.15',
  };
  int _activeWorkspaceIndex = 0; // 0: Vetting Queue, 1: Maritime & FX, 2: Counter POS Desk

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
            final stats = dData['kpis'] is Map
                ? Map<String, dynamic>.from(dData['kpis'])
                : <String, dynamic>{};
            if (mounted) {
              setState(() {
                _totalMembers =
                    int.tryParse(stats['total_members']?.toString() ?? '') ?? 0;
                _openTickets =
                    int.tryParse(stats['open_tickets']?.toString() ?? '') ?? 0;
                _revenue =
                    double.tryParse(stats['revenue']?.toString() ?? '') ?? 0.0;
                _applicationsCount =
                    int.tryParse(stats['applications']?.toString() ?? '') ?? 0;
              });
            }
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
        : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF2B211D);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6F625B);

    final pendingMembers = _rawMembers
        .where((m) {
          final st = m['status']?.toString().toLowerCase() ?? '';
          return st == 'pending' || st == 'pending_review';
        })
        .toList();

    return AppLayout(
      title: 'Admin Dashboard',
      hideSearch: false,
      scrollable: true,
      child: _loading
          ? const _AdminDashboardSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) _buildErrorBanner(isDark),
                      _buildTypographicKpiLedger(
                        context,
                        pendingMembers.length,
                        isDark,
                      ),
                      const SizedBox(height: 18),
                      _buildWorkspaceTabs(context, isDark, pendingMembers.length),
                      const SizedBox(height: 16),
                      _buildActiveWorkspaceContent(
                        context,
                        pendingMembers,
                        primary,
                        cardBg,
                        borderColor,
                        textColor,
                        subTextColor,
                        isDark,
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
    );
  }



  Widget _buildTypographicKpiLedger(
    BuildContext context,
    int pendingCount,
    bool isDark,
  ) {
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);
    final subInk = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    final revParts = _revenue.toStringAsFixed(2).split('.');
    final revWhole = revParts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    final revenueLabel = 'GH₵ $revWhole.${revParts[1]}';

    final totalPending =
        _applicationsCount > 0 ? _applicationsCount : pendingCount;

    final items = [
      {
        'label': 'PENDING VETTING',
        'value': '$totalPending',
        'badge': totalPending > 0 ? 'Action Required' : 'Queue Clear',
        'badgeColor': totalPending > 0 ? kAdminOrange : const Color(0xFF10b981),
        'onTap': () => setState(() => _activeWorkspaceIndex = 0),
      },
      {
        'label': 'ACCREDITED MEMBERS',
        'value': '$_totalMembers',
        'badge': 'Active Registry',
        'badgeColor': const Color(0xFF6B3E26),
        'onTap': () => context.go('/admin/members'),
      },
      {
        'label': 'SETTLED REVENUE',
        'value': revenueLabel,
        'badge': 'FY 2026 Settled',
        'badgeColor': const Color(0xFF10b981),
        'onTap': () => context.go('/admin/payments'),
      },
      {
        'label': 'OPEN GRIEVANCES',
        'value': '$_openTickets',
        'badge': 'Disputes Desk',
        'badgeColor': const Color(0xFF2563EB),
        'onTap': () => context.go('/admin/tickets'),
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 750;
          if (isSmall) {
            return Column(
              children: items.asMap().entries.map((entry) {
                final idx = entry.key;
                final it = entry.value;
                return Column(
                  children: [
                    _buildKpiItem(it, isDark, textInk, subInk),
                    if (idx < items.length - 1)
                      Divider(height: 1, color: borderCol, thickness: 1),
                  ],
                );
              }).toList(),
            );
          }

          return Row(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: idx < items.length - 1
                        ? Border(right: BorderSide(color: borderCol, width: 1.0))
                        : null,
                  ),
                  child: _buildKpiItem(it, isDark, textInk, subInk),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildKpiItem(
    Map<String, dynamic> it,
    bool isDark,
    Color textInk,
    Color subInk,
  ) {
    final badgeColor = it['badgeColor'] as Color;
    return InkWell(
      onTap: it['onTap'] as VoidCallback?,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  it['label'] as String,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: subInk,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    it['badge'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              it['value'] as String,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textInk,
                letterSpacing: -0.4,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceTabs(BuildContext context, bool isDark, int pendingCount) {
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);
    final subInk = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    final tabs = [
      {
        'index': 0,
        'label': 'Applications & Vetting Queue',
        'icon': Icons.pending_actions_rounded,
        'badge': '$pendingCount',
        'badgeColor': pendingCount > 0 ? kAdminOrange : const Color(0xFF10b981),
      },
      {
        'index': 1,
        'label': 'Maritime Port & Forex Feeds',
        'icon': Icons.anchor_rounded,
        'badge': 'LIVE',
        'badgeColor': const Color(0xFF10b981),
      },
      {
        'index': 2,
        'label': 'Counter Walk-in POS Desk',
        'icon': Icons.point_of_sale_rounded,
        'badge': 'COUNTER',
        'badgeColor': const Color(0xFF2563EB),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E120B) : const Color(0xFFEDE5DC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 700;
          if (isSmall) {
            return Column(
              children: tabs.map((t) => _buildTabItem(t, isDark, textInk, subInk)).toList(),
            );
          }

          return Row(
            children: tabs
                .map((t) => Expanded(child: _buildTabItem(t, isDark, textInk, subInk)))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildTabItem(
    Map<String, dynamic> t,
    bool isDark,
    Color textInk,
    Color subInk,
  ) {
    final idx = t['index'] as int;
    final isSelected = _activeWorkspaceIndex == idx;
    final badgeColor = t['badgeColor'] as Color;
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final activeBg = isDark ? const Color(0xFF2A170F) : Colors.white;

    return InkWell(
      onTap: () => setState(() => _activeWorkspaceIndex = idx),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: borderCol, width: 1.0) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 25 : 8),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              t['icon'] as IconData,
              size: 16,
              color: isSelected ? kAdminOrange : subInk,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t['label'] as String,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? textInk : subInk,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? badgeColor.withAlpha(25)
                    : (isDark ? Colors.white10 : Colors.black.withAlpha(12)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t['badge'] as String,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? badgeColor : subInk,
                ).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveWorkspaceContent(
    BuildContext context,
    List<dynamic> pendingMembers,
    Color primary,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    switch (_activeWorkspaceIndex) {
      case 0:
        return _buildPendingApprovalsCard(
          context,
          pendingMembers,
          primary,
          cardBg,
          borderColor,
          textColor,
          subTextColor,
        );
      case 1:
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 850;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 55, child: _buildPortOperationalDeskCard(context, isDark)),
                  const SizedBox(width: 16),
                  Expanded(flex: 45, child: _buildForexDeskCard(context, isDark)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPortOperationalDeskCard(context, isDark),
                const SizedBox(height: 16),
                _buildForexDeskCard(context, isDark),
              ],
            );
          },
        );
      case 2:
      default:
        return _buildCounterPaymentActionCard(context, isDark);
    }
  }



  Widget _buildCounterPaymentActionCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1B2E24) : const Color(0xFFE8F5E9);
    final borderCol = const Color(0xFF10b981).withAlpha(isDark ? 90 : 120);

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
                  color: const Color(0xFF10b981).withAlpha(35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Color(0xFF10b981),
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
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1F1612),
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Walk-in payments: Cash, Cheque, POS card, Direct wire',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94a3b8) : const Color(0xFF64748b),
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
                backgroundColor: const Color(0xFF10b981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: () => context.go('/admin/payments?action=counter_payment'),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(
                '➕ Record Counter / Cash Payment',
                style: GoogleFonts.inter(
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

  Widget _buildPortOperationalDeskCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.anchor_rounded, size: 16, color: kAdminOrange),
                    const SizedBox(width: 8),
                    Text(
                      'PORT OPERATIONS DESK',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textInk,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10b981).withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE STATUS',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF10b981),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: borderCol),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildPortStatusRow('Tema Port (MPS Terminal 3)', 'Operational', 'Berth Normal', const Color(0xFF10b981), isDark),
                const SizedBox(height: 8),
                _buildPortStatusRow('Takoradi Maritime Terminal', 'Operational', 'Clearance Active', const Color(0xFF10b981), isDark),
                const SizedBox(height: 8),
                _buildPortStatusRow('Kotoka Cargo Village (KIA)', 'Operational', 'Air Waybills Active', const Color(0xFF10b981), isDark),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/admin/port-news'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textInk,
                      side: BorderSide(color: borderCol),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(
                      'Manage Port Bulletins →',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortStatusRow(String name, String status, String note, Color color, bool isDark) {
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);
    final subInk = isDark ? const Color(0xFF9E8F84) : const Color(0xFF6B5E55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF170C08) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  note,
                  style: GoogleFonts.inter(fontSize: 10.5, color: subInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForexDeskCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.currency_exchange_rounded, size: 16, color: const Color(0xFF6B3E26)),
                    const SizedBox(width: 8),
                    Text(
                      'OFFICIAL CUSTOMS FX RATES',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textInk,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10b981).withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'INDICATIVE',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF10b981),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: borderCol),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildFxRateRow('\$', 'USD / GHS', _forex['USD'] ?? '15.45', isDark),
                const SizedBox(height: 6),
                _buildFxRateRow('€', 'EUR / GHS', _forex['EUR'] ?? '16.80', isDark),
                const SizedBox(height: 6),
                _buildFxRateRow('£', 'GBP / GHS', _forex['GBP'] ?? '19.50', isDark),
                const SizedBox(height: 6),
                _buildFxRateRow('¥', 'CNY / GHS', _forex['CNY'] ?? '2.15', isDark),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/admin/intelligence'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textInk,
                      side: BorderSide(color: borderCol),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(
                      'Update FX Tariffs & News →',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFxRateRow(String symbol, String pair, String rate, bool isDark) {
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textInk = isDark ? Colors.white : const Color(0xFF1F1612);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF170C08) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF22140E) : const Color(0xFFF4EFEA),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  symbol,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B3E26),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pair,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textInk,
                ),
              ),
            ],
          ),
          Text(
            rate,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: textInk,
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
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
        color: const Color(0xFFef4444).withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFef4444).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFef4444)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.inter(
                color: const Color(0xFFef4444),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFef4444), size: 18),
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
        ? const Color(0xFF1A0F0A).withAlpha(150)
        : const Color(0xFFF8F4F0);

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
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: textColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Review and verify newly submitted member applications',
                          style: GoogleFonts.inter(
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
                        style: GoogleFonts.inter(
                          color: kAdminOrange,
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
                        style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No members are currently waiting for registration approvals.',
                      style: GoogleFonts.inter(
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
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(headerBg),
                        headingTextStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: subTextColor,
                          letterSpacing: 0.5,
                        ),
                        dataTextStyle: GoogleFonts.inter(
                          fontSize: 15,
                          color: textColor,
                        ),
                        columnSpacing: 24,
                        horizontalMargin: 20,
                        dataRowMinHeight: 62,
                        dataRowMaxHeight: 74,
                        columns: const [
                          DataColumn(label: Text('APPLICANT / MEMBER')),
                          DataColumn(label: Text('CATEGORY / TYPE')),
                          DataColumn(label: Text('PAYMENT STATUS')),
                          DataColumn(label: Text('REGISTRATION DATE')),
                          DataColumn(label: Text('ACTIONS')),
                        ],
                        rows: pendingMembers.take(5).map((m) {
                          final name =
                              m['name']?.toString() ?? 'Unnamed Member';
                          final email = m['email']?.toString() ?? '—';
                          final company = m['company']?.toString() ?? '';
                          final type =
                              (m['member_type']?.toString().isNotEmpty == true)
                                  ? m['member_type'].toString()
                                  : 'Licentiate';
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
                            badgeColor = const Color(0xFF10B981); // Green
                          } else if (typeLower.contains('licen')) {
                            badgeColor = const Color(0xFFFF5000); // Orange
                          }

                          return DataRow(
                            cells: [
                              // 1. Applicant / Member
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: primary.withAlpha(35),
                                      child: Text(
                                        _getInitials(name),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
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
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            color: textColor,
                                          ),
                                        ),
                                        Text(
                                          company.isNotEmpty && company != name
                                              ? '$company • $email'
                                              : email,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: subTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 2. Category / Type
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
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
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                              ),

                              // 3. Payment Status
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasPayment
                                        ? Colors.green.withAlpha(25)
                                        : Colors.amber.withAlpha(25),
                                    borderRadius: BorderRadius.circular(8),
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
                                      Text(
                                        hasPayment
                                            ? 'Paid (${paymentRef.length > 8 ? paymentRef.substring(0, 8) : paymentRef})'
                                            : 'Unpaid / Pending',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
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
                                Text(
                                  date.split('T').first,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
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
                                    'Review & Approve',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
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
              backgroundColor: const Color(0xFF10b981),
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
                  style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
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
    final type = m['member_type']?.toString() ?? 'Licentiate';
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
                      color: Color(0xFF10b981),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Member Validation & Approval',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          'Validate documents and payment before activating license',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
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
                        color: const Color(0xFFf8fafc),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
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
                                  style: GoogleFonts.inter(
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
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$company • $type',
                                      style: GoogleFonts.inter(
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
                                  style: GoogleFonts.inter(
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
                                  style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                        ),
                                      ),
                                      if (fileName != null)
                                        Text(
                                          fileName,
                                          style: GoogleFonts.inter(
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
                                    style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10b981),
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
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              val,
              style: GoogleFonts.inter(
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
