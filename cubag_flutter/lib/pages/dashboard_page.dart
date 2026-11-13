import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';
import '../services/theme_service.dart';
import '../utils/session_storage.dart';
import '../utils/intelligence_data.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';
import '../components/home/licence_card.dart';
import '../components/home/licence_status.dart';
import '../components/home/home_sections.dart';

const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA

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
  List<dynamic> _tasks = [];
  List<dynamic> _surveys = [];
  Map<String, String> _forex = {
    'USD': '—',
    'EUR': '—',
    'GBP': '—',
    'CNY': '—',
  };
  bool _forexIsSample = false;
  Map<String, dynamic> _user = {};
  static String? _lastShownBillId;

  @override
  void initState() {
    super.initState();
    unawaited(PushNotificationService().requestPermissionsAndSyncToken());
    final cachedName = SessionStorage.instance.getStringSync('cubag_name');
    final isPkgPaid = SessionStorage.instance.getStringSync('cubag_package_fee_paid') == 'true';
    final isGood = SessionStorage.instance.getStringSync('cubag_good_standing') == 'true' || isPkgPaid;
    final isRegPaid = SessionStorage.instance.getStringSync('cubag_registration_fee_paid') == 'true';
    _user = {
      'name': (cachedName != null && cachedName.isNotEmpty) ? cachedName : 'Member',
      'role': SessionStorage.instance.getStringSync('cubag_role') ?? '',
      'license_expiry_date': SessionStorage.instance.getStringSync('cubag_expiry'),
      'status': SessionStorage.instance.getStringSync('cubag_status') ?? 'pending',
      'license_number': SessionStorage.instance.getStringSync('cubag_license_number'),
      'membership_number': SessionStorage.instance.getStringSync('cubag_membership_number'),
      'package_fee_paid': isPkgPaid,
      'good_standing': isGood,
      'is_good_standing': isGood,
      'registration_fee_paid': isRegPaid,
      'id': int.tryParse(SessionStorage.instance.getStringSync('cubag_id') ?? ''),
    };

    // Instant 0ms synchronous Hive cache paint
    final cachedMe = ApiService.getCachedSync('/auth/me');
    if (cachedMe is Map) {
      _user = {..._user, ...Map<String, dynamic>.from(cachedMe)};
    }
    final cachedTasks = ApiService.getCachedSync('/tasks');
    if (cachedTasks != null) {
      _tasks = ApiService.ensureList(cachedTasks);
      _loadingTasks = false;
    }
    final cachedSurveys = ApiService.getCachedSync('/surveys');
    if (cachedSurveys != null) {
      _surveys = ApiService.ensureList(cachedSurveys);
    }
    final cachedForex =
        ForexSnapshot.fromIntelligence(ApiService.getCachedSync('intelligence'));
    if (cachedForex != null) {
      _forex = cachedForex.rates;
      _forexIsSample = cachedForex.isSample;
    }
    _loading = false;

    _loadInstantCache();
    SocketService().on('member_updated', _onLiveUpdate);
    SocketService().on('member_approved', _onLiveUpdate);
    SocketService().on('payment_approved', _onLiveUpdate);
    SocketService().on('fees_updated', _onLiveUpdate);
    SocketService().on('tasks_updated', _onLiveUpdate);
    SocketService().on('documents_updated', _onLiveUpdate);
    SocketService().on('member_documents_updated', _onLiveUpdate);
    SocketService().on('renewal_bill_issued', _onRenewalBillReceived);
    SocketService().dataUpdateNotifier.addListener(_onGlobalNotifier);
  }

  void _onRenewalBillReceived(dynamic data) {
    if (!mounted) return;
    _onLiveUpdate(null);
    final isPkgPaid = _user['package_fee_paid'] == true || _user['package_fee_paid'] == 1 || _user['membership_status'] == 'active';
    if (!isPkgPaid) return;
    final submitted = SessionStorage.instance.getStringSync('cubag_renewal_submitted');
    if (submitted == 'true') return;
    if (_user['renewal_payment_submitted'] == true ||
        _user['compliance_app_status'] == 'payment_submitted' ||
        _user['compliance_app_status'] == 'approved' ||
        _user['compliance_app_status'] == 'completed') {
      return;
    }
    if (data is Map) {
      final taskId = data['id']?.toString() ?? '';
      if (taskId.isNotEmpty) {
        final dismissed = SessionStorage.instance.getStringSync('cubag_bill_dismissed_$taskId');
        if (dismissed == 'true') return;
      }
      _showRenewalBillPopup(Map<String, dynamic>.from(data));
    }
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
    SocketService().off('renewal_bill_issued', _onRenewalBillReceived);
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
        if (data['renewal_payment_submitted'] == true ||
            data['compliance_app_status'] == 'payment_submitted' ||
            data['compliance_app_status'] == 'approved' ||
            data['compliance_app_status'] == 'completed') {
          SessionStorage.instance.setStringSync('cubag_renewal_submitted', 'true');
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

  Future<void> _fetchTasks() async {
    await ApiService().fetchDataWithCache('/tasks', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        final taskList = ApiService.ensureList(data);
        setState(() {
          _tasks = taskList;
          _loadingTasks = false;
        });
        // ONLY check renewal bill alert when fresh network data lands (isCached == false)
        // so that stale offline cache never pops up an old bill on app launch!
        if (!isCached) {
          _checkRenewalBillAlert(taskList);
        }
      }
    });
  }

  void _checkRenewalBillAlert(List<dynamic> tasks) {
    if (!mounted) return;
    final isPkgPaid = _user['package_fee_paid'] == true || _user['package_fee_paid'] == 1 || _user['membership_status'] == 'active';
    if (!isPkgPaid) return;
    // Suppress immediately if renewal payment was submitted or is under review
    final submitted = SessionStorage.instance.getStringSync('cubag_renewal_submitted');
    if (submitted == 'true') return;
    if (_user['renewal_payment_submitted'] == true ||
        _user['compliance_app_status'] == 'payment_submitted' ||
        _user['compliance_app_status'] == 'approved' ||
        _user['compliance_app_status'] == 'completed') {
      return;
    }

    for (final t in tasks) {
      if (t is Map && t['system_type'] == 'renewal_bill' && t['done'] != true) {
        final taskId = t['id']?.toString() ?? '';
        final dismissed = SessionStorage.instance.getStringSync('cubag_bill_dismissed_$taskId');
        if (dismissed == 'true') continue;

        if (_lastShownBillId != taskId) {
          _lastShownBillId = taskId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showRenewalBillPopup(Map<String, dynamic>.from(t));
            }
          });
        }
        break;
      }
    }
  }

  void _showRenewalBillPopup(Map<String, dynamic> billData) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF2B211D);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6F625B);
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE8DED6);

    final rawAmount = billData['amount'] ?? billData['payment_amount'];
    final amount = double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
    final deadline = billData['deadline']?.toString() ?? billData['payment_deadline']?.toString() ?? 'Immediate';
    final amtStr = amount > 0 ? amount.toStringAsFixed(2) : '2,170.00';

    List<dynamic> breakdown = [];
    try {
      final rawBd = billData['fee_breakdown'];
      if (rawBd != null) {
        breakdown = rawBd is String ? jsonDecode(rawBd) : rawBd;
      }
    } catch (_) {}

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: cardBg,
          elevation: 16,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor, width: 1.2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _kOrange.withAlpha(25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: _kOrange,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'OFFICIAL BILL ISSUED',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.accentOrangeText,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Annual Renewal Dues Ready',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () {
                          final bId = billData['id']?.toString() ?? '';
                          if (bId.isNotEmpty) {
                            SessionStorage.instance.setStringSync('cubag_bill_dismissed_$bId', 'true');
                          }
                          Navigator.of(dialogCtx).pop();
                        },
                        icon: Icon(Icons.close_rounded, color: subTextColor, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your annual statutory compliance documents have been vetted and approved. The CUBAG secretariat has calculated and issued your official annual renewal bill.',
                    style: TextStyle(
                      fontSize: 14,
                      color: subTextColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF352016) : const Color(0xFFFBF7F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kOrange.withAlpha(50)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount Due:',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'GHS $amtStr',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accentOrangeText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 14, color: subTextColor),
                            const SizedBox(width: 6),
                            Text(
                              'Payment Deadline: $deadline',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                        if (breakdown.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          ...breakdown.take(4).map((item) {
                            final label = item['label']?.toString() ?? 'Fee';
                            final itemAmt = item['amount']?.toString() ?? '0.00';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(fontSize: 12.5, color: subTextColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'GHS $itemAmt',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final bId = billData['id']?.toString() ?? '';
                        if (bId.isNotEmpty) {
                          SessionStorage.instance.setStringSync('cubag_bill_dismissed_$bId', 'true');
                        }
                        Navigator.of(dialogCtx).pop();
                        context.go('/payments?fee=Annual%20Renewal%20Dues&amount=$amtStr');
                      },
                      icon: const Icon(Icons.payment_rounded, size: 18),
                      label: Text(
                        'Pay Renewal Dues (GHS $amtStr)',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrown,
                        side: const BorderSide(color: _kBrown, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                        context.go('/compliance');
                      },
                      child: Text(
                        'View Full Details in Compliance',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }



  Future<void> _fetchSurveys() async {
    await ApiService().fetchDataWithCache('/surveys', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _surveys = ApiService.ensureList(data);
        });
      }
    });
  }

  bool _isSurveyActive(dynamic s) {
    if (s is! Map) return false;
    final activeVal = s['active'];
    final isActive = activeVal == true || activeVal == 1 || activeVal == 'true' || activeVal == null;
    if (!isActive) return false;
    final deadlineStr = s['deadline'] ?? s['expiry'];
    if (deadlineStr == null || deadlineStr.toString().isEmpty) return true;
    final d = DateTime.tryParse(deadlineStr.toString());
    if (d == null) return true;
    return DateTime(d.year, d.month, d.day, 23, 59, 59).isAfter(DateTime.now());
  }

  Future<void> _fetchForex() async {
    await ApiService().fetchDataWithCache('intelligence', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      final snap = ForexSnapshot.fromIntelligence(data);
      if (snap != null) {
        setState(() {
          _forex = snap.rates;
          _forexIsSample = snap.isSample;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final role = _user['role'] as String? ?? '';
    final isAdmin = role == 'admin' || role == 'sub_admin' || role == 'super_admin';
    final pending = _tasks.where((t) => t['done'] != true).toList();
    final fullName = (_user['name'] as String? ?? 'Member').trim();
    final firstName = fullName.split(' ').first;
    final expiry = parseExpiry(_user['license_expiry_date']);
    final status = licenceStatus(
      packagePaid: isAdmin || _user['package_fee_paid'] == true,
      expiry: expiry,
      pendingTasks: _loadingTasks ? 0 : pending.length,
    );
    final activeSurveys = _surveys.where(_isSurveyActive).length;

    return AppLayout(
      title: 'Home',
      scrollable: false,
      background: CubagColors.paper,
      showMobileTitle: false,
      child: _loading && _tasks.isEmpty
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: _refreshFromNetwork,
              color: CubagColors.action,
              child: LayoutBuilder(
                builder: (context, box) {
                  final twoColumns = box.maxWidth >= 860;
                  final greeting = Text(
                    '${greetingFor(DateTime.now())}, $firstName',
                    style: CubagType.display,
                  );
                  final licence = LicenceCard(
                    name: fullName,
                    company: _user['company']?.toString(),
                    licenceNumber: _licenceNumber(),
                    expiry: expiry,
                    status: status,
                    onOpen: () => context.go('/profile'),
                    onAction: status.actionRoute == null
                        ? null
                        : () => context.go(status.actionRoute!),
                  );
                  final todo = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeSectionHeader(
                        'To do',
                        linkLabel: pending.length > 3 ? 'See all ${pending.length}' : null,
                        onLink: () => context.go('/tasks'),
                      ),
                      HomeGroup(
                        children: _loadingTasks && pending.isEmpty
                            ? [const QuietRow(icon: Icons.hourglass_empty_rounded, text: 'Loading your tasks…')]
                            : pending.isEmpty
                                ? [const QuietRow(icon: Icons.check_circle_rounded, text: 'You\'re all caught up.')]
                                : [for (final t in pending.take(3)) _taskRow(t)],
                      ),
                    ],
                  );
                  final services = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const HomeSectionHeader('Services'),
                      ShortcutGrid(
                        items: const [
                          Shortcut(Icons.payments_outlined, 'Pay dues', '/payments'),
                          Shortcut(Icons.receipt_long_outlined, 'Statement', '/payment-history'),
                          Shortcut(Icons.school_outlined, 'Courses', '/courses'),
                          Shortcut(Icons.groups_outlined, 'Member network', '/networking'),
                          Shortcut(Icons.how_to_vote_outlined, 'Polls', '/surveys'),
                          Shortcut(Icons.support_agent_outlined, 'Support', '/engagement'),
                        ],
                        onOpen: (r) => context.go(r),
                      ),
                    ],
                  );
                  final polls = activeSurveys > 0
                      ? HomeGroup(
                          children: [
                            TaskRow(
                              title: activeSurveys == 1
                                  ? '1 poll is open for your vote'
                                  : '$activeSurveys polls are open for your vote',
                              onTap: () => context.go('/surveys'),
                            ),
                          ],
                        )
                      : null;
                  final rates = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeSectionHeader(
                        'Exchange rates',
                        linkLabel: 'More',
                        onLink: () => context.go('/live-data'),
                      ),
                      if (_forexIsSample)
                        Padding(
                          padding: const EdgeInsets.only(bottom: CubagSpace.xs),
                          child: Text(ForexSnapshot.sampleNotice, style: CubagType.small),
                        ),
                      HomeGroup(
                        children: const [
                          ('USD', 'US dollar'),
                          ('EUR', 'Euro'),
                          ('GBP', 'British pound'),
                          ('CNY', 'Chinese yuan'),
                        ].map((c) => RateRow(code: c.$1, name: c.$2, value: _forex[c.$1] ?? '—')).toList(),
                      ),
                    ],
                  );
                  const gap = SizedBox(height: CubagSpace.xxl);

                  final body = twoColumns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 11,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [greeting, const SizedBox(height: CubagSpace.lg), licence, gap, services],
                              ),
                            ),
                            const SizedBox(width: CubagSpace.xxl),
                            Expanded(
                              flex: 9,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 52), // aligns with the card's top
                                  todo,
                                  if (polls != null) ...[const SizedBox(height: CubagSpace.lg), polls],
                                  gap,
                                  rates,
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            greeting,
                            const SizedBox(height: CubagSpace.lg),
                            licence,
                            gap,
                            todo,
                            gap,
                            services,
                            if (polls != null) ...[const SizedBox(height: CubagSpace.xl), polls],
                            gap,
                            rates,
                          ],
                        );

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      twoColumns ? CubagSpace.xxl : CubagSpace.lg,
                      CubagSpace.lg,
                      twoColumns ? CubagSpace.xxl : CubagSpace.lg,
                      CubagSpace.xxxl,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: twoColumns ? 1100 : 640),
                          child: body,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  /// Licence number to show on the card: the issued licence, else the
  /// membership number; never a "pending" placeholder.
  String? _licenceNumber() {
    for (final k in ['license_number', 'membership_number']) {
      final v = _user[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && !v.toLowerCase().contains('pending') && v != 'None') return v;
    }
    return null;
  }

  Widget _taskRow(dynamic task) {
    final due = DateTime.tryParse(task['due_date']?.toString() ?? '');
    final overdue = due != null && due.isBefore(DateTime.now());
    return TaskRow(
      // Older servers prefix titles with status emoji (🔴 🟡); the row
      // already shows status, so drop them.
      title: (task['title']?.toString() ?? 'Task')
          .replaceFirst(RegExp(r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\s]+', unicode: true), ''),
      due: due == null
          ? null
          : (overdue ? 'Overdue since ${formatLicenceDate(due)}' : 'Due ${formatLicenceDate(due)}'),
      overdue: overdue,
      onTap: () => _openTask(task),
    );
  }

  Future<void> _openTask(dynamic task) async {
    final router = GoRouter.of(context);
    final rawUrl = task['action_url']?.toString().trim();
    if (rawUrl != null && rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        final uri = Uri.tryParse(rawUrl);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (rawUrl.startsWith('/')) {
        if (!mounted) return;
        router.go(rawUrl);
        return;
      }
    }
    if (mounted) router.go('/tasks');
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
