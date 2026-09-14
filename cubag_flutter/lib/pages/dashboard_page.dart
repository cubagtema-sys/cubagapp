import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/session_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kDarkBrown = Color(0xFF3E2418); // Deep Dark Contrast

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // _loading is only true on absolute first load with zero cache.
  // The UI renders immediately from SessionStorage; API calls refresh in background.
  bool _loading = true;
  bool _loadingTasks = true;
  bool _loadingSurveys = false;
  List<dynamic> _tasks = [];
  List<dynamic> _surveys = [];
  Map<String, String> _forex = {
    'USD': '15.45',
    'EUR': '16.80',
    'GBP': '19.50',
    'CNY': '2.15',
  };
  Map<String, dynamic> _user = {};

  @override
  void initState() {
    super.initState();
    _loadInstantCache();
    SocketService().on('member_updated', _onLiveUpdate);
    SocketService().on('member_approved', _onLiveUpdate);
    SocketService().on('payment_approved', _onLiveUpdate);
    SocketService().on('fees_updated', _onLiveUpdate);
    SocketService().on('tasks_updated', _onLiveUpdate);
    SocketService().on('documents_updated', _onLiveUpdate);
    SocketService().on('member_documents_updated', _onLiveUpdate);
    SocketService().dataUpdateNotifier.addListener(_onGlobalNotifier);
  }

  void _onGlobalNotifier() {
    final event = SocketService().dataUpdateNotifier.value;
    if (!mounted || event == null) return;
    if (event.contains('member') ||
        event.contains('payment') ||
        event.contains('task') ||
        event.contains('document') ||
        event.contains('fee')) {
      _onLiveUpdate(null);
    }
  }

  void _onLiveUpdate(dynamic _) {
    if (mounted) {
      ApiService.deleteCacheKeysMatching('auth/me');
      ApiService.deleteCacheKeysMatching('tasks');
      unawaited(_refreshFromNetwork());
    }
  }

  @override
  void dispose() {
    SocketService().off('member_updated', _onLiveUpdate);
    SocketService().off('member_approved', _onLiveUpdate);
    SocketService().off('payment_approved', _onLiveUpdate);
    SocketService().off('fees_updated', _onLiveUpdate);
    SocketService().off('tasks_updated', _onLiveUpdate);
    SocketService().off('documents_updated', _onLiveUpdate);
    SocketService().off('member_documents_updated', _onLiveUpdate);
    SocketService().dataUpdateNotifier.removeListener(_onGlobalNotifier);
    super.dispose();
  }

  /// Step 1 – runs synchronously from local cache: shows the UI in < 5 ms.
  Future<void> _loadInstantCache() async {
    // Read all session keys in one parallel batch
    final sessionResults = await Future.wait([
      SessionStorage.instance.getString('cubag_name'),
      SessionStorage.instance.getString('cubag_role'),
      SessionStorage.instance.getString('cubag_expiry'),
      SessionStorage.instance.getString('cubag_status'),
      SessionStorage.instance.getString('cubag_license_number'),
      SessionStorage.instance.getString('cubag_membership_number'),
      SessionStorage.instance.getString('cubag_package_fee_paid'),
      SessionStorage.instance.getString('cubag_good_standing'),
      SessionStorage.instance.getString('cubag_registration_fee_paid'),
      SessionStorage.instance.getString('cubag_id'),
    ]);

    if (!mounted) return;
    final isPkgPaid = sessionResults[6] == 'true';
    final isGood = sessionResults[7] == 'true' || isPkgPaid;
    final isRegPaid = sessionResults[8] == 'true';

    setState(() {
      _loading = false; // ← show UI immediately with accurate good standing status
      _user = {
        'name': sessionResults[0] ?? 'Member',
        'role': sessionResults[1] ?? '',
        'license_expiry_date': sessionResults[2],
        'status': sessionResults[3] ?? 'pending',
        'license_number': sessionResults[4],
        'membership_number': sessionResults[5],
        'package_fee_paid': isPkgPaid,
        'good_standing': isGood,
        'is_good_standing': isGood,
        'registration_fee_paid': isRegPaid,
        'id': sessionResults[9] != null ? int.tryParse(sessionResults[9]!) : null,
      };
    });

    // Step 2 – refresh from network in the background (non-blocking)
    unawaited(_refreshFromNetwork());
  }

  /// Step 2 – background network refresh (does NOT block rendering)
  Future<void> _refreshFromNetwork() async {
    try {
      // Fire all requests in parallel; each updates state independently as it lands
      await Future.wait([
        _fetchTasks(),
        _fetchSurveys(),
        _fetchUserProfile(),
      ]);
    } catch (e) {
      debugPrint('Dashboard background refresh error: $e');
    }
    // Forex rates are lowest priority
    unawaited(_fetchForex());
  }

  Future<void> _fetchUserProfile() async {
    await ApiService().fetchDataWithCache('/auth/me', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null && data is Map) {
        setState(() {
          _user = Map<String, dynamic>.from(data);
        });
        if (data['license_expiry_date'] != null) {
          SessionStorage.instance.setString(
            'cubag_expiry',
            data['license_expiry_date'].toString(),
          );
        }
        if (data['status'] != null) {
          SessionStorage.instance.setString(
            'cubag_status',
            data['status'].toString(),
          );
        }
        if (data['license_number'] != null) {
          SessionStorage.instance.setString(
            'cubag_license_number',
            data['license_number'].toString(),
          );
        }
        if (data['membership_number'] != null) {
          SessionStorage.instance.setString(
            'cubag_membership_number',
            data['membership_number'].toString(),
          );
        }
        if (data['package_fee_paid'] != null) {
          SessionStorage.instance.setString(
            'cubag_package_fee_paid',
            (data['package_fee_paid'] == true).toString(),
          );
        }
        if (data['good_standing'] != null || data['is_good_standing'] != null) {
          final isG = data['good_standing'] == true || data['is_good_standing'] == true;
          SessionStorage.instance.setString(
            'cubag_good_standing',
            isG.toString(),
          );
        }
      }
    });
  }

  String _formatDate(String? str) {
    if (str == null) return '—';
    final d = DateTime.tryParse(str);
    if (d == null) return '—';
    return '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  }

  Future<void> _fetchTasks() async {
    await ApiService().fetchDataWithCache('/tasks', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _tasks = ApiService.ensureList(data);
          _loadingTasks = false;
        });
      }
    });
  }



  Future<void> _fetchSurveys() async {
    setState(() => _loadingSurveys = true);
    await ApiService().fetchDataWithCache('/surveys', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _surveys = ApiService.ensureList(data);
          _loadingSurveys = false;
        });
      }
    });
    if (mounted) setState(() => _loadingSurveys = false);
  }

  Future<void> _fetchForex() async {
    await ApiService().fetchDataWithCache('intelligence', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data != null &&
          data is Map &&
          data['forex'] != null &&
          data['forex'] is Map) {
        final forexMap = data['forex'] as Map;
        final usd = forexMap['USD']?.toString() ?? '15.45';
        final eur = forexMap['EUR']?.toString() ?? '16.80';
        final gbp = forexMap['GBP']?.toString() ?? '19.50';
        final cny = forexMap['CNY']?.toString() ?? '2.15';
        setState(() {
          _forex = {'USD': usd, 'EUR': eur, 'GBP': gbp, 'CNY': cny};
        });
      }
    });
  }

  Widget _buildWelcomeBanner(
    String firstName,
    String role,
    List<dynamic> pending,
    Color primary,
    bool isMobile,
  ) {
    final rawExpiry = _user['license_expiry_date']?.toString();
    final expiry =
        (rawExpiry == null ||
            rawExpiry == 'None' ||
            rawExpiry == 'null' ||
            rawExpiry.isEmpty)
        ? null
        : rawExpiry;
    final daysLeft = expiry != null
        ? DateTime.tryParse(expiry)?.difference(DateTime.now()).inDays
        : null;
    final bool isPkgPaid = _user['package_fee_paid'] == true;
    final bool isPackagePending = !isPkgPaid &&
        (role != 'admin' && role != 'sub_admin' && role != 'super_admin');
    final bool isGoodStanding = isPkgPaid &&
        (_user['is_good_standing'] == true ||
            _user['good_standing'] == true ||
            _user['status'] == 'active' ||
            _user['status'] == 'approved');
    final memNo = isGoodStanding
        ? (_user['membership_number']?.toString().trim().isNotEmpty == true &&
                !_user['membership_number'].toString().toLowerCase().contains('pending')
            ? _user['membership_number'].toString().trim()
            : (_user['license_number']?.toString().trim().isNotEmpty == true &&
                    !_user['license_number'].toString().toLowerCase().contains('pending')
                ? _user['license_number'].toString().trim()
                : (_user['id'] != null ? 'CUBAG-${_user['id'].toString().padLeft(4, '0')}' : '')))
        : 'PENDING SETTLEMENT';

    String statusText;
    String btnLabel;
    IconData btnIcon;
    VoidCallback btnAction;

    if (daysLeft != null && daysLeft < 0) {
      statusText =
          '🔴 Membership Expired: Your annual membership expired on ${_formatDate(expiry)}. Renew immediately to restore Active Standing.';
      btnLabel = 'Pay Renewal';
      btnIcon = Icons.warning_amber_rounded;
      btnAction = () => context.go('/payments');
    } else if (daysLeft != null && daysLeft <= 30) {
      statusText =
          '🔴 Urgent Reminder: Only $daysLeft days remaining until membership expires on ${_formatDate(expiry)}! Renew now to avoid suspension.';
      btnLabel = 'Renew Now';
      btnIcon = Icons.autorenew_rounded;
      btnAction = () => context.go('/payments');
    } else if (daysLeft != null && daysLeft <= 60) {
      statusText =
          '🟠 Formal Notice: Approx. 2 months ($daysLeft days) remaining until membership expires on ${_formatDate(expiry)}. Please submit renewal.';
      btnLabel = 'Renew Soon';
      btnIcon = Icons.autorenew_rounded;
      btnAction = () => context.go('/payments');
    } else if (daysLeft != null && daysLeft <= 90) {
      statusText =
          '🟡 Early Notice: Your annual membership expires in 3 months ($daysLeft days). The renewal window is open.';
      btnLabel = 'Renew Membership';
      btnIcon = Icons.autorenew_rounded;
      btnAction = () => context.go('/payments');
    } else if (isPackagePending) {
      statusText =
          '🟡 Registration Fee Paid • Membership Entrance Package Pending Settlement ($memNo)';
      if (!_loadingTasks && pending.isNotEmpty) {
        btnLabel = 'View Tasks (${pending.length})';
        btnIcon = Icons.assignment_turned_in_outlined;
        btnAction = () => context.go('/tasks');
      } else {
        btnLabel = 'Pay Package Fee';
        btnIcon = Icons.payment_rounded;
        btnAction = () => context.go('/payments?fee=Membership%20Entrance%20Package');
      }
    } else {
      // Stable Good Standing Identity
      statusText =
          '🟢 Active in Good Standing • Membership ID: $memNo ${expiry != null ? '• Valid until ${_formatDate(expiry)}' : ''}';
      if (!_loadingTasks && pending.isNotEmpty) {
        btnLabel = 'View Tasks (${pending.length})';
        btnIcon = Icons.assignment_turned_in_outlined;
        btnAction = () => context.go('/tasks');
      } else {
        btnLabel = 'View Profile';
        btnIcon = Icons.badge_outlined;
        btnAction = () => context.go('/profile');
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBrown, _kDarkBrown],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kDarkBrown.withAlpha(45),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(80),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good day, $firstName!',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            style: GoogleFonts.outfit(
              color: Colors.white.withAlpha(230),
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: btnAction,
            icon: Icon(btnIcon, size: 15),
            label: Text(btnLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageSettlementPromptCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF4D2D20), const Color(0xFF281710)]
              : [const Color(0xFFFFF8F2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kOrange, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withAlpha(isDark ? 40 : 25),
            blurRadius: 14,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notification_important_rounded,
                  color: _kOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEMBERSHIP ENTRANCE PACKAGE REQUIRED',
                      style: GoogleFonts.outfit(
                        color: _kOrange,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Upfront Registration Fee Paid • Settle Entrance Dues',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Your upfront registration fee is settled! Settle your New Membership Dues package to unlock your official Membership ID and activate full Active Good Standing privileges.',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/payments?fee=New%20Membership%20Dues'),
                  icon: const Icon(Icons.payment_rounded, size: 18),
                  label: const Text('Pay New Membership Dues Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityTasksSection(List<dynamic> pending, Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);
    final dividerColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);
    final itemBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf8fafc);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: _kOrange,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Priority Tasks',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          if (_loadingTasks)
            const Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ShimmerListTile(),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ShimmerListTile(),
                ),
              ],
            )
          else if (pending.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: itemBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 36,
                        color: Color(0xFFcbd5e1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No pending tasks!',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: subTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are completely up to date.',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF64748b) : Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pending.length,
              separatorBuilder: (context, i) =>
                  Divider(height: 1, color: dividerColor),
              itemBuilder: (context, i) {
                final task = pending[i];
                bool overdue =
                    task['due_date'] != null &&
                    DateTime.tryParse(
                          task['due_date'].toString(),
                        )?.isBefore(DateTime.now()) ==
                        true;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: overdue
                          ? (isDark
                                ? Colors.red.shade900.withAlpha(60)
                                : Colors.red.shade50)
                          : itemBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      color: overdue
                          ? (isDark ? Colors.red.shade300 : Colors.red.shade600)
                          : subTextColor,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    task['title'] ?? '',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                  subtitle: Text(
                    overdue
                        ? '⚠ Overdue: ${task['due_date']}'
                        : 'Due: ${task['due_date'] ?? 'No deadline'}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: overdue
                          ? (isDark ? Colors.red.shade300 : Colors.red.shade600)
                          : subTextColor,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      task['action_label']?.toString() ?? 'Action Required',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _kOrange,
                      ),
                    ),
                  ),
                  onTap: () async {
                    final router = GoRouter.of(context);
                    final rawUrl = task['action_url']?.toString().trim();
                    if (rawUrl != null && rawUrl.isNotEmpty) {
                      if (rawUrl.startsWith('http://') ||
                          rawUrl.startsWith('https://')) {
                        final uri = Uri.tryParse(rawUrl);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                          return;
                        }
                      } else if (rawUrl.startsWith('/')) {
                        if (!mounted) return;
                        try {
                          router.go(rawUrl);
                          return;
                        } catch (_) {
                          if (mounted) router.go('/tasks');
                          return;
                        }
                      }
                    }
                    if (!mounted) return;
                    router.go('/tasks');
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }





  Widget _buildForexSection(ThemeData theme, Color primary) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF10b981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Official Forex Rates',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.verified_rounded,
                size: 14,
                color: Color(0xFF10b981),
              ),
              const SizedBox(width: 4),
              Text(
                'OFFICIAL',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: subTextColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _forexRow(
            '\$',
            'USD/GHS',
            _forex['USD'] ?? '15.45',
            isDark ? const Color(0xFFf59e0b) : _kBrown,
            'US Dollar',
          ),
          const SizedBox(height: 10),
          _forexRow(
            '€',
            'EUR/GHS',
            _forex['EUR'] ?? '16.80',
            const Color(0xFF3b82f6),
            'Euro',
          ),
          const SizedBox(height: 10),
          _forexRow(
            '£',
            'GBP/GHS',
            _forex['GBP'] ?? '19.50',
            const Color(0xFF8b5cf6),
            'British Pound',
          ),
          const SizedBox(height: 10),
          _forexRow(
            '¥',
            'CNY/GHS',
            _forex['CNY'] ?? '2.15',
            const Color(0xFFec4899),
            'Chinese Yuan',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.go('/live-data'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: borderColor, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              foregroundColor: subTextColor,
            ),
            child: const Text('View Full Data Hub'),
          ),
        ],
      ),
    );
  }

  Widget _forexRow(
    String symbol,
    String pair,
    String rate,
    Color color,
    String name,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf8fafc);
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              symbol,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pair,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(fontSize: 13, color: Color(0xFF94a3b8)),
              ),
            ],
          ),
          const Spacer(),
          Text(
            rate,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(bool isMobile) {
    return Column(
      children: [
        // Row 1: CTI Courses (Featured warm accent) & Pay Dues (Emerald badge)
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _quickAction(
                context,
                Icons.school_rounded,
                'CTI Courses',
                '/courses',
                color: const Color(0xFFFF5000),
                badgeText: 'ACCREDITED',
                subtext: 'Certifications',
                isFeatured: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: _quickAction(
                context,
                Icons.payments_outlined,
                'Pay Dues',
                '/payments',
                color: const Color(0xFF10b981),
                badgeText: 'ANNUAL',
                subtext: 'Membership renewal dues',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 2: Surveys & Polls & Statement Receipts
        Row(
          children: [
            Expanded(
              child: _quickAction(
                context,
                Icons.how_to_vote_rounded,
                'Surveys & Polls',
                '/surveys',
                color: const Color(0xFF8b5cf6),
                badgeText: 'ELECTIONS',
                subtext: 'Cast your ballot',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickAction(
                context,
                Icons.receipt_long_outlined,
                'Statement',
                '/payment-history',
                color: const Color(0xFFef4444),
                badgeText: 'RECEIPTS',
                subtext: 'Audit transaction log',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 3: Support Hub & Networking Directory
        Row(
          children: [
            Expanded(
              child: _quickAction(
                context,
                Icons.support_agent_rounded,
                'Support Hub',
                '/engagement',
                color: const Color(0xFF0284c7),
                badgeText: '24/7 HELPDESK',
                subtext: 'Submit inquiry ticket',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickAction(
                context,
                Icons.group_rounded,
                'Network',
                '/networking',
                color: const Color(0xFF0d9488),
                badgeText: 'DIRECTORY',
                subtext: 'Find broker members',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveSurveysSection(Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);
    final dividerColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5000).withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.how_to_vote_rounded,
                    color: Color(0xFF8b5cf6),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active Surveys & Elections${_surveys.isNotEmpty ? ' (${_surveys.length})' : ''}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/surveys'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8b5cf6),
                    textStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          if (_loadingSurveys && _surveys.isEmpty)
            const Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ShimmerListTile(),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ShimmerListTile(),
                ),
              ],
            )
          else if (_surveys.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.how_to_vote_outlined,
                      size: 32,
                      color: subTextColor.withAlpha(120),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No active association polls right now.',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upcoming elections and surveys will be listed here.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: subTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _surveys.take(3).length,
              separatorBuilder: (context, i) =>
                  Divider(height: 1, color: dividerColor),
              itemBuilder: (context, i) {
                final s = _surveys[i];
                final type = (s['type'] ?? 'Survey').toString().toUpperCase();
                final title = s['title']?.toString() ?? 'Community Survey';
                final deadline = s['deadline']?.toString();
                final hasVoted =
                    s['has_voted'] == true || s['has_responded'] == true;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/surveys'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color:
                                  (hasVoted
                                          ? const Color(0xFF10b981)
                                          : const Color(0xFF8b5cf6))
                                      .withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              hasVoted
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.how_to_vote_outlined,
                              color: hasVoted
                                  ? const Color(0xFF10b981)
                                  : const Color(0xFF8b5cf6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF8b5cf6,
                                        ).withAlpha(20),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        type,
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: const Color(0xFF8b5cf6),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (hasVoted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF10b981,
                                          ).withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'VOTED',
                                          style: GoogleFonts.outfit(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF10b981),
                                          ),
                                        ),
                                      ),
                                    if (deadline != null &&
                                        deadline.isNotEmpty) ...[
                                      const Spacer(),
                                      Text(
                                        'Closes $deadline',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: subTextColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: subTextColor.withAlpha(120),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String label,
    String route, {
    required Color color,
    String? badgeText,
    String? subtext,
    bool isFeatured = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextColor = isDark ? const Color(0xFF94a3b8) : const Color(0xFF64748b);
    final cardBg = isDark
        ? Color.lerp(const Color(0xFF1A0F0A), color, 0.12)!
        : Color.lerp(Colors.white, color, 0.05)!;

    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withAlpha(isDark ? 90 : 50),
            width: isFeatured ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(isDark ? 25 : 12),
              blurRadius: isFeatured ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 35 : 22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withAlpha(60)),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withAlpha(isDark ? 35 : 20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withAlpha(70)),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.outfit(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtext != null) ...[
              const SizedBox(height: 2),
              Text(
                subtext,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: subTextColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final firstName = (_user['name'] as String? ?? 'Member').split(' ').first;
    final role = _user['role'] as String? ?? '';
    final pending = _tasks.where((t) => t['done'] != true).toList();
    final bool isPkgPaid = _user['package_fee_paid'] == true;
    final bool isPackagePending = !isPkgPaid &&
        (role != 'admin' && role != 'sub_admin' && role != 'super_admin');

    return AppLayout(
      title: 'Dashboard',
      scrollable: false,
      child: _loading && _tasks.isEmpty
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: _refreshFromNetwork,
              color: _kOrange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 950;

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildWelcomeBanner(
                                        firstName,
                                        role,
                                        pending,
                                        primary,
                                        false,
                                      ),
                                      if (isPackagePending) ...[
                                        const SizedBox(height: 16),
                                        _buildPackageSettlementPromptCard(),
                                      ],
                                      const SizedBox(height: 20),
                                      _buildPriorityTasksSection(
                                        pending,
                                        primary,
                                      ),
                                      const SizedBox(height: 20),
                                      _buildActiveSurveysSection(primary),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildForexSection(theme, primary),
                                      const SizedBox(height: 20),
                                      Text(
                                        'QUICK ACTIONS',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: const Color(0xFF64748b),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _buildQuickActionsGrid(false),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildWelcomeBanner(
                                  firstName,
                                  role,
                                  pending,
                                  primary,
                                  true,
                                ),
                                if (isPackagePending) ...[
                                  const SizedBox(height: 16),
                                  _buildPackageSettlementPromptCard(),
                                ],
                                const SizedBox(height: 20),
                                Text(
                                  'QUICK ACTIONS',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: const Color(0xFF64748b),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildQuickActionsGrid(true),
                                const SizedBox(height: 20),
                                _buildPriorityTasksSection(pending, primary),
                                const SizedBox(height: 20),
                                _buildActiveSurveysSection(primary),
                                const SizedBox(height: 20),
                                _buildForexSection(theme, primary),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class BlinkingDot extends StatefulWidget {
  const BlinkingDot({super.key});

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF10b981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
