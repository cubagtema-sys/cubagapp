import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/course_payment_policy.dart';

import '../services/socket_service.dart';
import 'package:go_router/go_router.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kBrown = Color(0xFF6B3E26);
const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = CubagColors.lapsed;

class CtiCoursesPage extends StatefulWidget {
  const CtiCoursesPage({super.key});

  @override
  State<CtiCoursesPage> createState() => _CtiCoursesPageState();
}

class _CtiCoursesPageState extends State<CtiCoursesPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _myEnrollments = [];
  bool _loading = true;
  bool _loadingMy = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedMode;

  Timer? _debounce;
  bool _failedDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_loadingMy) {
        _fetchMyEnrollments();
      }
    });
    _fetchCourses();
    SocketService().on('courses_updated', _onRealtimeCoursesUpdate);
    SocketService().on('payment_approved', _onRealtimePaymentApproved);
  }

  void _onRealtimeCoursesUpdate(dynamic _) {
    if (mounted) {
      _fetchCourses();
      if (_tabController.index == 1) {
        _fetchMyEnrollments();
      }
    }
  }

  void _onRealtimePaymentApproved(dynamic _) {
    if (mounted) {
      _fetchCourses();
      _fetchMyEnrollments();
    }
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = v);
      }
    });
  }

  @override
  void dispose() {
    SocketService().off('courses_updated', _onRealtimeCoursesUpdate);
    SocketService().off('payment_approved', _onRealtimePaymentApproved);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCourses() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('events/courses');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _courses = (res.data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
        return;
      }
    } catch (e) {
      AppLogger.error('fetch_courses', e);
    }

    if (mounted) {
      setState(() {
        _courses = [];
        _loading = false;
      });
    }
  }

  Future<void> _fetchMyEnrollments() async {
    setState(() => _loadingMy = true);
    try {
      final res = await _api.get('events/courses/my-enrollments');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _myEnrollments = (res.data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loadingMy = false;
        });
        return;
      }
    } catch (e) {
      AppLogger.error('fetch_my_enrollments', e);
    }
    if (mounted) setState(() => _loadingMy = false);
  }

  int? _getDaysRemaining(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final parts = dateStr.trim().split(' ');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]);
        final monthStr = parts[1].toLowerCase();
        final year = int.tryParse(parts[2]);
        const months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
        };
        final month = months[monthStr.substring(0, 3)];
        if (day != null && month != null && year != null) {
          final target = DateTime(year, month, day);
          return target.difference(DateTime.now()).inDays;
        }
      }
    } catch (_) {}
    return null;
  }

  void _openEnrollmentSheet(Map<String, dynamic> course) {
    final title = course['title']?.toString() ?? 'CTI Course';
    final feeStr = course['fee']?.toString() ?? 'GHS 1,500';
    final mode = course['mode']?.toString() ?? 'Hybrid';
    final startDate = course['start_date']?.toString() ?? 'TBD';
    final duration = course['duration']?.toString() ?? '4 Weeks';
    final courseId = course['id'];

    final cleanFeeNum = double.tryParse(feeStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final isFreeCourse = cleanFeeNum == 0.0;

    // Approved policy: on iOS, online/hybrid paid courses never open a payment flow.
    if (!isFreeCourse && !CoursePaymentPolicy.canPayInApp(course)) return;

    if (!isFreeCourse) {
      final feeParam = Uri.encodeComponent('CTI Course: $title');
      final amtParam = cleanFeeNum.toStringAsFixed(2);
      context.push('/payments?fee=$feeParam&amount=$amtParam&course_id=$courseId&redirect=/cti-courses').then((_) {
        if (mounted) {
          _fetchCourses();
          _fetchMyEnrollments();
        }
      });
      return;
    }

    String paymentMethod = 'free';
    String phone = '';
    String detectedNetwork = '';
    bool isSubmitting = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final sheetBg = isDark ? CubagColors.ink : Colors.white;
          final textCol = isDark ? CubagColors.sand : CubagColors.ink;
          final subTextCol = isDark ? const Color(0xFF5F6B7E) : CubagColors.muted;
          final borderCol = isDark ? const Color(0xFF281710) : CubagColors.line;
          final innerBox = isDark ? CubagColors.ink : CubagColors.sand;

          Color networkBadgeCol = _kOrange;
          String networkLabel = 'Enter MoMo phone number';
          if (detectedNetwork == 'MTN') {
            networkBadgeCol = const Color(0xFFEAB308);
            networkLabel = 'MTN Mobile Money';
          } else if (detectedNetwork == 'Telecel' || detectedNetwork == 'Vodafone') {
            networkBadgeCol = CubagColors.lapsed;
            networkLabel = 'Telecel Cash';
          } else if (detectedNetwork == 'AirtelTigo') {
            networkBadgeCol = const Color(0xFF3B82F6);
            networkLabel = 'AT Money';
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Enroll in Course',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textCol),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: isSubmitting ? null : () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.accentOrangeText)),
                    const SizedBox(height: 4),
                    Text('$startDate • $duration • $mode', style: TextStyle(fontSize: 13, color: subTextCol)),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: borderCol),
                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tuition Fee:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: subTextCol)),
                        Text(isFreeCourse ? 'FREE' : feeStr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textCol)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (!isFreeCourse) ...[
                      Text('Select mobile carrier', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: subTextCol, letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['MTN', 'Telecel', 'AirtelTigo'].map((net) {
                          final isSelected = detectedNetwork == net;
                          return ChoiceChip(
                            label: Text(net),
                            selected: isSelected,
                            selectedColor: _kOrange,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : textCol,
                            ),
                            onSelected: (v) {
                              if (v) setSheetState(() => detectedNetwork = net);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text('MoMo phone number', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: subTextCol, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextFormField(
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                        onChanged: (v) {
                          phone = v;
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          counterText: '',
                          fillColor: innerBox,
                          hintText: 'e.g. 0244123456',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      if (detectedNetwork.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('✓ Network: $networkLabel', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: networkBadgeCol)),
                      ],
                    ],

                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(errorMsg!, style: TextStyle(fontSize: 13, color: _kRed, fontWeight: FontWeight.bold)),
                    ],

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (!isFreeCourse && detectedNetwork.isEmpty) {
                                  setSheetState(() => errorMsg = 'Please select your mobile carrier (MTN, Telecel, or AirtelTigo)');
                                  return;
                                }
                                if (!isFreeCourse && phone.trim().length != 10) {
                                  setSheetState(() => errorMsg = 'Please enter a valid 10-digit phone number');
                                  return;
                                }

                                setSheetState(() {
                                  isSubmitting = true;
                                  errorMsg = null;
                                });

                                if (isFreeCourse) {
                                  try {
                                    final res = await _api.post('events/courses/$courseId/enroll', data: {'payment_method': 'free'});
                                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                    if (mounted) {
                                      _showEnrollmentSuccessModal(course, res.data);
                                      _fetchCourses();
                                      _fetchMyEnrollments();
                                    }
                                  } catch (e) {
                                    setSheetState(() {
                                      isSubmitting = false;
                                      errorMsg = 'Enrollment failed: $e';
                                    });
                                  }
                                  return;
                                }

                                try {
                                  final payRes = await _api.post('payments', data: {
                                    'amount': cleanFeeNum,
                                    'description': 'CTI Course: $title',
                                    'fee_key': 'course:$courseId',
                                    'method': paymentMethod,
                                    'network': detectedNetwork.isNotEmpty ? detectedNetwork : 'MTN',
                                    'phone': phone.trim(),
                                    'meta': {
                                      'type': 'cti_course',
                                      'course_id': courseId,
                                      'course_title': title,
                                    }
                                  });

                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);

                                  if (mounted) {
                                    final payData = payRes.data is Map ? payRes.data as Map : {};
                                    final paymentId = payData['payment_id'] ?? payData['id'];
                                    final txRef = payData['transaction_ref'] ?? payData['whitsun_ref'] ?? '';

                                    _showAwaitingApprovalModal(
                                      course: course,
                                      paymentId: paymentId,
                                      txRef: txRef.toString(),
                                      phone: phone.trim(),
                                      network: detectedNetwork.isNotEmpty ? detectedNetwork : 'MTN',
                                      amount: cleanFeeNum,
                                    );
                                  }
                                } catch (e) {
                                  setSheetState(() {
                                    isSubmitting = false;
                                    errorMsg = 'Payment initiation failed: $e';
                                  });
                                }
                              },
                        child: Text(
                          isSubmitting ? 'Processing...' : (isFreeCourse ? 'Confirm Free Enrollment' : 'Pay & Enroll ($feeStr)'),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAwaitingApprovalModal({
    required Map<String, dynamic> course,
    required dynamic paymentId,
    required String txRef,
    required String phone,
    required String network,
    required double amount,
  }) {
    int pollAttempt = 0;
    const int maxPollAttempts = 60; // 60 × 4s = 240s (4 minutes)
    Timer? pollTimer;
    bool isCompleted = false;
    bool isChecking = false;
    String statusMessage = 'Waiting for mobile money prompt...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF1E1B18) : Colors.white;
          final textCol = isDark ? CubagColors.sand : CubagColors.ink;
          final mutedCol = isDark ? const Color(0xFF5F6B7E) : CubagColors.muted;

          Future<void> checkStatus({bool isManual = false}) async {
            if (isCompleted || !mounted || isChecking) return;
            isChecking = true;
            if (dlgCtx.mounted) setDlgState(() {});

            try {
              dynamic statusRes;
              if (txRef.isNotEmpty) {
                statusRes = await _api.get('payments/verify/$txRef');
              } else if (paymentId != null) {
                statusRes = await _api.get('payments/status/$paymentId');
              }

              if (statusRes != null && statusRes.data is Map) {
                final status = (statusRes.data['status']?.toString() ?? '').toLowerCase();
                if (status == 'paid' || status == 'success' || status == 'completed') {
                  isCompleted = true;
                  pollTimer?.cancel();
                  try {
                    await _api.post('events/courses/${course['id']}/enroll', data: {
                      'payment_method': 'momo',
                      'payment_ref': txRef.isNotEmpty ? txRef : 'PAY-$paymentId',
                    });
                  } catch (_) {}

                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) {
                    _showEnrollmentSuccessModal(course, statusRes.data);
                    _fetchCourses();
                    _fetchMyEnrollments();
                  }
                  return;
                } else if (status == 'failed' || status == 'declined' || status == 'cancelled') {
                  isCompleted = true;
                  pollTimer?.cancel();
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) _showPaymentFailedDialog('Payment was declined or cancelled.');
                  return;
                }
              }
              if (isManual && dlgCtx.mounted) {
                statusMessage = 'Still awaiting authorization. Enter your PIN on phone and check again.';
              }
            } catch (_) {
              if (isManual && dlgCtx.mounted) {
                statusMessage = 'Checking gateway status... Please ensure your phone is connected.';
              }
            } finally {
              isChecking = false;
              if (dlgCtx.mounted) setDlgState(() {});
            }
          }

          pollTimer ??= Timer.periodic(const Duration(seconds: 4), (t) async {
            if (isCompleted || !mounted) {
              t.cancel();
              return;
            }
            pollAttempt++;

            if (pollAttempt >= maxPollAttempts) {
              t.cancel();
              if (dlgCtx.mounted) {
                setDlgState(() {
                  statusMessage = 'Telco prompt may take 2-3 minutes. If authorized on your phone, click Check Status below.';
                });
              }
              return;
            }

            await checkStatus(isManual: false);
          });

          // USSD tip per network
          String ussdTip = 'MTN: Dial *170# ➔ Option 6 (My Wallet) ➔ Option 3 (My Approvals) if prompt does not appear.';
          final netUpper = network.toUpperCase();
          if (netUpper.contains('VODA') || netUpper.contains('TELECEL')) {
            ussdTip = 'Telecel: Dial *110# ➔ Option 4 (Make Payment) ➔ Approvals to authorize.';
          } else if (netUpper.contains('AIRTEL') || netUpper.contains('TIGO') || netUpper.contains('AT')) {
            ussdTip = 'AT Money: Dial *110# ➔ Approvals to authorize.';
          }

          final isTimedOut = pollAttempt >= maxPollAttempts;

          return AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isTimedOut) ...[
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3.5, color: _kOrange),
                  ),
                  const SizedBox(height: 18),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.timer_outlined, size: 36, color: _kOrange),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  isTimedOut ? 'Awaiting Authorization' : 'Authorize MoMo Payment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textCol),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'GH₵ ${amount.toStringAsFixed(2)}  •  $network  •  $phone',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accentOrangeText),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Check your phone and enter your Mobile Money PIN to approve the enrollment fee.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: mutedCol, height: 1.45),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A231C) : CubagColors.sand,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF3E332A) : CubagColors.line,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: _kOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ussdTip,
                          style: TextStyle(fontSize: 11.5, color: mutedCol, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.accentOrangeText, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: isChecking ? null : () => checkStatus(isManual: true),
                    child: isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Check Status Now',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () {
                    isCompleted = true;
                    pollTimer?.cancel();
                    Navigator.pop(dlgCtx);
                  },
                  child: Text(
                    'Cancel Payment',
                    style: TextStyle(fontSize: 13, color: mutedCol, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentFailedDialog(String reason) {
    if (_failedDialogShowing || !mounted) return;
    _failedDialogShowing = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enrollment Incomplete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(reason, style: TextStyle(fontSize: 14)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      _failedDialogShowing = false;
    });
  }

  void _showEnrollmentSuccessModal(Map<String, dynamic> course, dynamic resData) {
    final title = course['title']?.toString() ?? 'CTI Course';
    final startDate = course['start_date']?.toString() ?? 'Upcoming';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Enrollment Confirmed!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are successfully enrolled in:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accentOrangeText)),
            const SizedBox(height: 8),
            Text('🗓️ Starts: $startDate', style: TextStyle(fontSize: 13.5, color: _kGreen, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              DateTime startDt = DateTime.tryParse(course['start_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 7));
              final success = await CalendarService.addEventToCalendar(
                title: 'CTI Course: $title',
                description: 'Accredited Customs Training: $title',
                location: 'Customs Training Institute (CTI)',
                startDate: startDt,
              );
              if (success && mounted) {
                scaffoldMessenger.showSnackBar(SnackBar(content: Text('Added to calendar!'), backgroundColor: _kGreen));
              }
            },
            child: const Text('Add to Calendar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
            child: const Text('View Enrolled'),
          ),
        ],
      ),
    );
  }

  String _enrollmentLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'pending':
      case 'pending_payment':
        return 'Enrolment pending';
      default:
        return 'Enrolled';
    }
  }

  Widget _buildMiniBadge(IconData icon, String text, Color color, {bool isDark = false}) {
    final borderCol = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final bgCol = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);
    final textCol = isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _kBrown),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textCol,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredCourses {
    var list = _courses;
    if (_selectedMode != null && _selectedMode != 'All') {
      list = list.where((c) => (c['mode']?.toString() ?? '').toLowerCase() == _selectedMode!.toLowerCase()).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) {
        final t = (c['title']?.toString() ?? '').toLowerCase();
        final d = (c['description']?.toString() ?? '').toLowerCase();
        return t.contains(q) || d.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF140C08) : CubagColors.sand;
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textPrimary = isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;
    final textMuted = isDark ? const Color(0xFFC8ADA0) : CubagColors.muted;

    return AppLayout(
      title: 'CTI Courses',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── CTI SYLLABUS HEADER ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border, width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: border, width: 1.0),
                    ),
                    child: const Icon(Icons.school_outlined, color: _kBrown, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customs Training Institute (CTI) Syllabus',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'GRA Customs Division accredited tariff classification and brokerage certification cohorts',
                          style: TextStyle(
                            fontSize: 12,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── TABS ──────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 1.0),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: _kOrange,
                labelColor: _kOrange,
                unselectedLabelColor: textMuted,
                indicatorWeight: 2.5,
                labelStyle: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                tabs: [
                  Tab(text: 'Catalog (${_courses.length})'),
                  Tab(text: 'My Enrolled (${_myEnrollments.length})'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── TAB VIEWS ─────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                if (_tabController.index == 0) {
                  return _buildCatalogView(isDark, cardBg, border, textPrimary, textMuted);
                } else {
                  return _buildMyEnrollmentsView(isDark, cardBg, border, textPrimary, textMuted);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogView(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final list = _filteredCourses;
    final modes = ['All', 'Hybrid', 'In-Person', 'Online'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Dedicated Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    _onSearchChanged(v);
                    setState(() {});
                  },
                  style: TextStyle(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search training courses, topics...',
                    hintStyle: TextStyle(fontSize: 13, color: textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: textMuted,
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Dedicated Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: modes.map((mode) {
              final isSelected = (_selectedMode == null && mode == 'All') || (_selectedMode == mode);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMode = mode == 'All' ? null : mode;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? _kOrange : (isDark ? const Color(0xFF281710) : Colors.white),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? _kOrange : border,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      mode == 'All' ? 'All Formats' : mode,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        if (_loading)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (_, index) => const ShimmerListTile(),
          )
        else if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: 1.0)),
            child: Center(
              child: Text('No courses found.', style: TextStyle(fontSize: 14, color: textMuted)),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, idx) => _buildCourseCard(list[idx], idx, isDark, cardBg, border, textPrimary, textMuted),
          ),
      ],
    );
  }

  Widget _buildCourseCard(
    Map<String, dynamic> course,
    int idx,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final title = course['title']?.toString() ?? 'Course';
    final fee = course['fee']?.toString() ?? 'GHS 1,500';
    final startDate = course['start_date']?.toString() ?? 'TBD';
    final duration = course['duration']?.toString() ?? '4 Weeks';
    final desc = course['description']?.toString() ?? '';
    final isEnrolled = course['is_enrolled'] == true;
    final enrollmentStatus = course['enrollment_status']?.toString();
    final deliveryMode = CoursePaymentPolicy.modeOf(course);
    final feeNum = double.tryParse(fee.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final isFree = feeNum == 0.0;
    final canPayInApp = CoursePaymentPolicy.canPayInApp(course);
    final canEnrollHere = isFree || canPayInApp;
    final modeIcon = deliveryMode == CourseDeliveryMode.online
        ? Icons.wifi_rounded
        : deliveryMode == CourseDeliveryMode.hybrid
            ? Icons.devices_rounded
            : deliveryMode == CourseDeliveryMode.inPerson
                ? Icons.location_on_rounded
                : Icons.help_outline_rounded;
    final daysLeft = _getDaysRemaining(startDate);
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);
    final indexStr = (idx + 1).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnrolled ? _kGreen.withValues(alpha: 0.5) : border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: border, width: 1.0),
                ),
                child: Center(
                  child: Text(
                    indexStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kBrown,
                      fontFeatures: [FontFeature.tabularFigures()],
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
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: TextStyle(fontSize: 13, color: textMuted, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildMiniBadge(Icons.calendar_today_rounded, startDate, _kBrown, isDark: isDark),
              _buildMiniBadge(Icons.schedule_rounded, duration, _kBrown, isDark: isDark),
              Semantics(
                label: 'Delivery mode: ${CoursePaymentPolicy.label(deliveryMode)}',
                child: _buildMiniBadge(modeIcon, CoursePaymentPolicy.label(deliveryMode), _kBrown, isDark: isDark),
              ),
              if (!isEnrolled && !isFree && canPayInApp)
                _buildMiniBadge(Icons.phone_iphone_rounded, 'Pay in app', _kGreen, isDark: isDark),
              if (daysLeft != null && daysLeft >= 0)
                _buildMiniBadge(Icons.alarm_on_rounded, 'Commences in $daysLeft d', _kGreen, isDark: isDark),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: border, height: 1.0),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fee,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentOrangeText,
                  letterSpacing: -0.3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (isEnrolled || canEnrollHere)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnrolled ? _kGreen : _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  onPressed: isEnrolled ? null : () => _openEnrollmentSheet(course),
                  child: Text(
                    isEnrolled ? _enrollmentLabel(enrollmentStatus) : 'Enroll Now',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                )
              else
                // iOS, online/hybrid: show enrolment status only (no payment
                // button, link or instructions — approved store policy).
                Container(
                  key: const Key('course-status-only'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: Text(
                    'Not enrolled',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyEnrollmentsView(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    if (_loadingMy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    if (_myEnrollments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: 1.0)),
        child: Center(
          child: Text('No active course enrollments yet.', style: TextStyle(fontSize: 14, color: textMuted)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _myEnrollments.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final en = _myEnrollments[idx];
        final title = en['title']?.toString() ?? 'CTI Course';
        final startDate = en['start_date']?.toString() ?? 'TBD';
        final duration = en['duration']?.toString() ?? '4 Weeks';
        final mode = en['mode']?.toString() ?? 'Hybrid';
        final fee = en['fee']?.toString() ?? 'GHS 1,500';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kGreen.withAlpha(80), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '$fee • Paid & Confirmed',
                          style: TextStyle(
                            fontSize: 13,
                            color: _kGreen,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add to Calendar',
                    icon: const Icon(Icons.event_available_rounded, size: 20, color: _kGreen),
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      DateTime startDt = DateTime.tryParse(startDate) ?? DateTime.now().add(const Duration(days: 7));
                      final success = await CalendarService.addEventToCalendar(
                        title: 'CTI Course: $title',
                        description: 'Accredited Customs Training: $title',
                        location: 'Customs Training Institute (CTI)',
                        startDate: startDt,
                      );
                      if (success && mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('Added to calendar!'), backgroundColor: _kGreen),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),
                  const SizedBox(width: 6),
                  _buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),
                  const SizedBox(width: 6),
                  _buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
