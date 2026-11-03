import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';
import '../services/theme_service.dart';
import '../utils/session_storage.dart';

// Balanced CUBAG Brand Palette & Editorial Tokens
bool get _isDark => ThemeService.instance.isDark;
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kGreen = Color(0xFF10B981); // Emerald Green
Color get _kCardBg => _isDark ? const Color(0xFF1E130D) : const Color(0xFFFFFFFF);
Color get _kSurfaceRaised => _isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);
Color get _kBorder => _isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
Color get _kText => _isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
Color get _kMuted => _isDark ? const Color(0xFFC8ADA0) : const Color(0xFF6F625B);

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
    'USD': '—',
    'EUR': '—',
    'GBP': '—',
    'CNY': '—',
  };
  Map<String, dynamic> _user = {};
  static String? _lastShownBillId;

  @override
  void initState() {
    super.initState();
    unawaited(PushNotificationService().requestPermissionsAndSyncToken());
    final cachedName = SessionStorage.instance.getStringSync('cubag_name');
    if (cachedName != null && cachedName.isNotEmpty) {
      final isPkgPaid = SessionStorage.instance.getStringSync('cubag_package_fee_paid') == 'true';
      final isGood = SessionStorage.instance.getStringSync('cubag_good_standing') == 'true' || isPkgPaid;
      final isRegPaid = SessionStorage.instance.getStringSync('cubag_registration_fee_paid') == 'true';
      _user = {
        'name': cachedName,
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
      _loading = false;
    }
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
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: _kOrange,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Annual Renewal Dues Ready',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
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
                    style: GoogleFonts.inter(
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
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'GHS $amtStr',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _kOrange,
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
                              style: GoogleFonts.inter(
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
                                      style: GoogleFonts.inter(fontSize: 12.5, color: subTextColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'GHS $itemAmt',
                                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
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
                        style: GoogleFonts.outfit(
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
                        style: GoogleFonts.outfit(
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
    if (_surveys.isEmpty) {
      setState(() => _loadingSurveys = true);
    }
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
      if (data != null &&
          data is Map &&
          data['forex'] != null &&
          data['forex'] is Map) {
        final forexMap = data['forex'] as Map;
        final usd = forexMap['USD']?.toString() ?? '—';
        final eur = forexMap['EUR']?.toString() ?? '—';
        final gbp = forexMap['GBP']?.toString() ?? '—';
        final cny = forexMap['CNY']?.toString() ?? '—';
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
    String statusBadge;
    Color statusBadgeBg;
    Color statusBadgeInk;
    String btnLabel;
    IconData btnIcon;
    VoidCallback btnAction;

    if (isPackagePending) {
      statusBadge = 'PACKAGE SETTLEMENT REQUIRED';
      statusBadgeBg = const Color(0xFFFEF3C7);
      statusBadgeInk = const Color(0xFF92400E);
      statusText = 'Registration fee settled. Finalize membership entrance package to activate voting & good standing.';
      if (!_loadingTasks && pending.isNotEmpty) {
        btnLabel = 'View Tasks (${pending.length})';
        btnIcon = Icons.assignment_turned_in_outlined;
        btnAction = () => context.go('/tasks');
      } else {
        btnLabel = 'Pay Package Fee';
        btnIcon = Icons.payment_rounded;
        btnAction = () => context.go('/payments?fee=Membership%20Entrance%20Package');
      }
    } else if (daysLeft != null && daysLeft < 0) {
      statusBadge = 'MEMBERSHIP EXPIRED';
      statusBadgeBg = const Color(0xFFFEE2E2);
      statusBadgeInk = const Color(0xFF991B1B);
      statusText = 'Annual membership expired on ${_formatDate(expiry)}. Submit renewal documents for compliance verification.';
      btnLabel = 'Submit Renewal (Step 1)';
      btnIcon = Icons.warning_amber_rounded;
      btnAction = () => context.go('/compliance');
    } else if (daysLeft != null && daysLeft <= 30) {
      statusBadge = 'EXPIRES IN $daysLeft DAYS';
      statusBadgeBg = const Color(0xFFFEE2E2);
      statusBadgeInk = const Color(0xFF991B1B);
      statusText = 'Urgent: $daysLeft days remaining until membership expires on ${_formatDate(expiry)}. Submit renewal now.';
      btnLabel = 'Submit Renewal (Step 1)';
      btnIcon = Icons.autorenew_rounded;
      btnAction = () => context.go('/compliance');
    } else if (daysLeft != null && daysLeft <= 90) {
      statusBadge = 'RENEWAL WINDOW OPEN';
      statusBadgeBg = const Color(0xFFFEF3C7);
      statusBadgeInk = const Color(0xFF92400E);
      statusText = 'Annual membership renewal window is open. Expiring on ${_formatDate(expiry)} ($daysLeft days remaining).';
      btnLabel = 'Renew Membership';
      btnIcon = Icons.autorenew_rounded;
      btnAction = () => context.go('/compliance');
    } else {
      statusBadge = 'ACTIVE IN GOOD STANDING';
      statusBadgeBg = const Color(0xFFDCFCE7);
      statusBadgeInk = const Color(0xFF166534);
      statusText = 'Verified Customs Broker & Freight Forwarder';
      if (!_loadingTasks && pending.isNotEmpty) {
        btnLabel = 'View Tasks (${pending.length})';
        btnIcon = Icons.assignment_turned_in_outlined;
        btnAction = () => context.go('/tasks');
      } else {
        btnLabel = 'Member Profile';
        btnIcon = Icons.badge_outlined;
        btnAction = () => context.go('/profile');
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isDark ? 30 : 6),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kBrown,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: GoogleFonts.inter(
                        color: _kMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            firstName,
                            style: GoogleFonts.outfit(
                              color: _kText,
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (role.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kBrown.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _kBrown.withAlpha(40), width: 0.8),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: _kBrown,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: statusBadgeBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusBadge,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusBadgeInk,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (memNo.isNotEmpty)
                          Text(
                            'ID: $memNo',
                            style: GoogleFonts.outfit(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _kMuted,
                            ),
                          ),
                        if (expiry != null)
                          Text(
                            '• Valid until ${_formatDate(expiry)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _kMuted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _kMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: btnAction,
                  icon: Icon(btnIcon, size: 15),
                  label: Text(btnLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: btnAction,
                icon: Icon(btnIcon, size: 15),
                label: Text(btnLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiLedgerGrid(List<dynamic> pending, bool isMobile) {
    final bool isPkgPaid = _user['package_fee_paid'] == true;
    final bool isGoodStanding = isPkgPaid &&
        (_user['is_good_standing'] == true ||
            _user['good_standing'] == true ||
            _user['status'] == 'active' ||
            _user['status'] == 'approved');
    final activeSurveys = _surveys.where(_isSurveyActive).length;

    final items = [
      {
        'title': 'ROLL STATUS',
        'value': isGoodStanding ? 'Good Standing' : 'Pending',
        'sub': isGoodStanding ? 'Secretariat Verified' : 'Dues Required',
        'color': isGoodStanding ? _kGreen : _kOrange,
        'icon': isGoodStanding ? Icons.verified_user_outlined : Icons.shield_outlined,
        'isStatus': true,
        'isGood': isGoodStanding,
        'action': () => context.go('/profile'),
      },
      {
        'title': 'PRIORITY TASKS',
        'value': '${pending.length}',
        'sub': pending.isEmpty ? 'All tasks complete' : '${pending.length} pending items',
        'color': pending.isEmpty ? _kMuted : _kOrange,
        'icon': Icons.task_alt_outlined,
        'isStatus': false,
        'isGood': pending.isEmpty,
        'action': () => context.go('/tasks'),
      },
      {
        'title': 'OFFICIAL USD/GHS',
        'value': _forex['USD'] != null && _forex['USD'] != '—' ? '${_forex['USD']}' : '—',
        'sub': 'Bank of Ghana Indicative',
        'color': _kBrown,
        'icon': Icons.currency_exchange_rounded,
        'isStatus': false,
        'isGood': true,
        'action': () => context.go('/live-data'),
      },
      {
        'title': 'ACTIVE BALLOTS',
        'value': '$activeSurveys',
        'sub': activeSurveys > 0 ? '$activeSurveys polls open' : 'No active votes',
        'color': activeSurveys > 0 ? const Color(0xFF8B5CF6) : _kMuted,
        'icon': Icons.how_to_vote_outlined,
        'isStatus': false,
        'isGood': true,
        'action': () => context.go('/surveys'),
      },
    ];

    final gridContent = isMobile
        ? GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.28,
            ),
            itemBuilder: (ctx, i) => _kpiTile(items[i], isMobile: true),
          )
        : Row(
            children: items.map((it) {
              final isLast = it == items.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 12),
                  child: _kpiTile(it, isMobile: false),
                ),
              );
            }).toList(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: (isGoodStanding ? _kGreen : _kOrange).withAlpha(24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.speed_rounded,
                size: 14,
                color: isGoodStanding ? _kGreen : _kOrange,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'MEMBER STATUS & OVERSIGHT',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.8,
                color: _kText,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isGoodStanding
                    ? _kGreen.withAlpha(18)
                    : _kOrange.withAlpha(18),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: isGoodStanding
                      ? _kGreen.withAlpha(45)
                      : _kOrange.withAlpha(45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isGoodStanding ? _kGreen : _kOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isGoodStanding ? 'Verified Active' : 'Action Needed',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isGoodStanding ? _kGreen : _kOrange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        gridContent,
      ],
    );
  }

  Widget _kpiTile(Map<String, dynamic> item, {bool isMobile = false}) {
    final isStatus = item['isStatus'] == true;
    final color = item['color'] as Color? ?? _kText;
    final isGood = item['isGood'] == true;

    return InkWell(
      onTap: item['action'] as VoidCallback?,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: _isDark ? const Color(0xFF1C130E) : const Color(0xFFFBF8F5),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isStatus
                  ? (isGood ? _kGreen : _kOrange)
                  : color,
              width: 3.5,
            ),
            top: BorderSide(
              color: isStatus && isGood ? _kGreen.withAlpha(60) : _kBorder.withAlpha(130),
              width: 1,
            ),
            right: BorderSide(
              color: isStatus && isGood ? _kGreen.withAlpha(60) : _kBorder.withAlpha(130),
              width: 1,
            ),
            bottom: BorderSide(
              color: isStatus && isGood ? _kGreen.withAlpha(60) : _kBorder.withAlpha(130),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_isDark ? 20 : 4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (item['icon'] != null) ...[
                  Icon(item['icon'] as IconData, size: 12, color: color),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    item['title'] as String,
                    style: GoogleFonts.outfit(
                      color: _kMuted,
                      fontSize: isMobile ? 10 : 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isStatus) ...[
                    Icon(
                      isGood ? Icons.verified_rounded : Icons.pending_rounded,
                      size: isMobile ? 15 : 17,
                      color: isGood ? _kGreen : _kOrange,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    item['value'] as String,
                    style: GoogleFonts.outfit(
                      color: isStatus && isGood ? _kGreen : _kText,
                      fontSize: isStatus ? (isMobile ? 15.5 : 17) : (isMobile ? 19 : 20),
                      fontWeight: FontWeight.w800,
                      letterSpacing: isStatus ? -0.2 : -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item['sub'] as String,
              style: GoogleFonts.inter(
                color: _kMuted,
                fontSize: isMobile ? 10.5 : 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageSettlementPromptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withAlpha(_isDark ? 30 : 15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: _kOrange,
                  size: 20,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Upfront Registration Fee Paid • Settle Entrance Dues',
                      style: GoogleFonts.inter(
                        color: _kMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your upfront registration fee is settled! Please complete your New Membership Dues package to receive your official Membership ID and activate Active Good Standing privileges.',
            style: GoogleFonts.inter(
              color: _kText,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/payments?fee=New%20Membership%20Dues'),
              icon: const Icon(Icons.payment_rounded, size: 16),
              label: const Text('Pay New Membership Dues Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityTasksSection(List<dynamic> pending, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isDark ? 20 : 4),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Text(
                  'PRIORITY TASKS',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _kText,
                    letterSpacing: 0.8,
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${pending.length}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: _kOrange,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/tasks'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _kBrown,
                  ),
                  child: Text(
                    'View All →',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _kBorder),
          if (_loadingTasks && _tasks.isEmpty)
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
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 32,
                      color: _kGreen,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'All tasks completed',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your filings and membership compliance are up to date.',
                      style: GoogleFonts.inter(
                        color: _kMuted,
                        fontSize: 13,
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
              separatorBuilder: (context, i) => Divider(height: 1, color: _kBorder),
              itemBuilder: (context, i) {
                final task = pending[i];
                final bool overdue = task['due_date'] != null &&
                    DateTime.tryParse(task['due_date'].toString())?.isBefore(DateTime.now()) == true;
                return InkWell(
                  onTap: () async {
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: overdue ? const Color(0xFFFEE2E2) : _kSurfaceRaised,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: overdue ? const Color(0xFFFCA5A5) : _kBorder,
                            ),
                          ),
                          child: Icon(
                            overdue ? Icons.warning_amber_rounded : Icons.receipt_long_outlined,
                            color: overdue ? const Color(0xFFDC2626) : _kBrown,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task['title'] ?? '',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _kText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                overdue
                                    ? 'Overdue • ${task['due_date']}'
                                    : 'Due: ${task['due_date'] ?? 'No deadline'}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: overdue ? FontWeight.bold : FontWeight.w500,
                                  color: overdue ? const Color(0xFFDC2626) : _kMuted,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: _kMuted,
                        ),
                      ],
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

  Widget _buildForexSection(ThemeData theme, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isDark ? 20 : 4),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Text(
                  'OFFICIAL FOREX RATES',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _kText,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'BOG INDICATIVE',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: _kGreen,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _forexRow('\$', 'USD/GHS', _forex['USD'] ?? '—', 'US Dollar'),
                const SizedBox(height: 8),
                _forexRow('€', 'EUR/GHS', _forex['EUR'] ?? '—', 'Euro'),
                const SizedBox(height: 8),
                _forexRow('£', 'GBP/GHS', _forex['GBP'] ?? '—', 'British Pound'),
                const SizedBox(height: 8),
                _forexRow('¥', 'CNY/GHS', _forex['CNY'] ?? '—', 'Chinese Yuan'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/live-data'),
                    icon: const Icon(Icons.analytics_outlined, size: 16),
                    label: Text(
                      'Trade Intelligence Hub →',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                      side: BorderSide(color: _kBorder, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      foregroundColor: _kText,
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

  Widget _forexRow(String symbol, String pair, String rate, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _kBorder, width: 0.6),
            ),
            alignment: Alignment.center,
            child: Text(
              symbol,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _kBrown,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pair,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: _kText,
                  ),
                ),
                Text(
                  name,
                  style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
                ),
              ],
            ),
          ),
          Text(
            rate,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _kText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(bool isMobile) {
    final isPkgPaid = _user['package_fee_paid'] == true ||
        _user['package_fee_paid'] == 1 ||
        _user['membership_status'] == 'active';

    final actions = [
      {
        'icon': Icons.school_outlined,
        'label': 'CTI Courses',
        'sub': 'Accredited training cohorts',
        'route': '/courses',
        'badge': 'ACCREDITED',
        'highlight': true,
      },
      {
        'icon': Icons.payments_outlined,
        'label': 'Pay Dues',
        'sub': isPkgPaid ? 'Annual renewal dues' : 'Entrance dues package',
        'route': '/payments',
        'badge': isPkgPaid ? 'ANNUAL' : 'PACKAGE',
        'highlight': false,
      },
      {
        'icon': Icons.how_to_vote_outlined,
        'label': 'Surveys & Polls',
        'sub': 'Stakeholder ballots',
        'route': '/surveys',
        'badge': 'ELECTIONS',
        'highlight': false,
      },
      {
        'icon': Icons.receipt_long_outlined,
        'label': 'Statement',
        'sub': 'Audited payment receipts',
        'route': '/payment-history',
        'badge': 'RECEIPTS',
        'highlight': false,
      },
      {
        'icon': Icons.headset_mic_outlined,
        'label': 'Support Desk',
        'sub': 'Inquiries & dispute tickets',
        'route': '/engagement',
        'badge': 'HELPDESK',
        'highlight': false,
      },
      {
        'icon': Icons.badge_outlined,
        'label': 'Broker Network',
        'sub': 'Accredited clearing roll',
        'route': '/networking',
        'badge': 'DIRECTORY',
        'highlight': false,
      },
    ];

    final gridContent = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: isMobile ? 1.4 : 1.55,
      ),
      itemBuilder: (ctx, i) {
        final a = actions[i];
        final isHL = a['highlight'] == true;
        return InkWell(
          onTap: () => context.go(a['route'] as String),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isHL
                  ? _kOrange.withAlpha(_isDark ? 28 : 12)
                  : (_isDark ? const Color(0xFF140D09) : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isHL
                    ? _kOrange
                    : _kBorder.withAlpha(_isDark ? 100 : 160),
                width: isHL ? 1.2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(_isDark ? 22 : 5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isHL
                            ? _kOrange.withAlpha(28)
                            : _kBrown.withAlpha(16),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        a['icon'] as IconData,
                        size: 17,
                        color: isHL ? _kOrange : _kBrown,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isHL
                                ? _kOrange.withAlpha(25)
                                : _kSurfaceRaised,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isHL
                                  ? _kOrange.withAlpha(80)
                                  : _kBorder,
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            a['badge'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isHL ? _kOrange : _kMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10,
                          color: isHL
                              ? _kOrange
                              : _kMuted.withAlpha(130),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a['label'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a['sub'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: _kMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 15,
                color: _kOrange,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'QUICK ACTIONS & SERVICES',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.8,
                color: _kText,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kSurfaceRaised,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                '${actions.length} Portals',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        gridContent,
      ],
    );
  }

  Widget _buildActiveSurveysSection(Color primary) {
    final activeSurveys = _surveys.where(_isSurveyActive).toList();

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isDark ? 20 : 4),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Text(
                  'ASSOCIATION POLLS & SURVEYS',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _kText,
                    letterSpacing: 0.8,
                  ),
                ),
                if (activeSurveys.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${activeSurveys.length}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF8B5CF6),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/surveys'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _kBrown,
                  ),
                  child: Text(
                    'View All →',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _kBorder),
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
          else if (activeSurveys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.how_to_vote_outlined,
                      size: 32,
                      color: _kMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No active association polls right now',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upcoming elections and surveys will appear here.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _kMuted,
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
              itemCount: activeSurveys.take(3).length,
              separatorBuilder: (context, i) => Divider(height: 1, color: _kBorder),
              itemBuilder: (context, i) {
                final s = activeSurveys[i];
                final type = (s['type'] ?? 'Survey').toString().toUpperCase();
                final title = s['title']?.toString() ?? 'Community Survey';
                final deadline = s['deadline']?.toString();
                final hasVoted = s['has_voted'] == true || s['has_responded'] == true;

                return InkWell(
                  onTap: () => context.go('/surveys'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hasVoted
                                ? _kGreen.withAlpha(20)
                                : const Color(0xFF8B5CF6).withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            hasVoted ? Icons.check_circle_outline_rounded : Icons.how_to_vote_outlined,
                            color: hasVoted ? _kGreen : const Color(0xFF8B5CF6),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      type,
                                      style: GoogleFonts.outfit(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF8B5CF6),
                                      ),
                                    ),
                                  ),
                                  if (hasVoted) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: _kGreen.withAlpha(20),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'VOTED',
                                        style: GoogleFonts.outfit(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: _kGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (deadline != null && deadline.isNotEmpty) ...[
                                    const Spacer(),
                                    Text(
                                      'Closes $deadline',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        color: _kMuted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
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
                                  fontSize: 14,
                                  color: _kText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: _kMuted,
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
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
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 16,
                        vertical: MediaQuery.sizeOf(context).width < 600 ? 12 : 16,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 950;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildWelcomeBanner(
                                firstName,
                                role,
                                pending,
                                primary,
                                !isWide,
                              ),
                              const SizedBox(height: 14),
                              _buildKpiLedgerGrid(pending, !isWide),
                              const SizedBox(height: 22),
                              if (isPackagePending) ...[
                                _buildPackageSettlementPromptCard(),
                                const SizedBox(height: 22),
                              ],
                              if (isWide) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 62,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildPriorityTasksSection(pending, primary),
                                          const SizedBox(height: 20),
                                          _buildActiveSurveysSection(primary),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 38,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildQuickActionsGrid(false),
                                          const SizedBox(height: 20),
                                          _buildForexSection(theme, primary),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                _buildQuickActionsGrid(true),
                                const SizedBox(height: 20),
                                _buildPriorityTasksSection(pending, primary),
                                const SizedBox(height: 20),
                                _buildActiveSurveysSection(primary),
                                const SizedBox(height: 20),
                                _buildForexSection(theme, primary),
                              ],
                            ],
                          );
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
