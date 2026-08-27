import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

import '../services/socket_service.dart';
import '../services/whitsun_pay_service.dart';

const _kOrange = Color(0xFFFF5000);
const _kDarkBrown = Color(0xFF1A0F0A);
const _kBrown = Color(0xFF4D2D20);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = Color(0xFFEF4444);

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
  String? _selectedMode;
  final Set<int> _expandedCourseIds = {};

  Timer? _debounce;

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
  }

  void _onRealtimeCoursesUpdate(dynamic _) {
    if (mounted) {
      _fetchCourses();
      if (_tabController.index == 1) {
        _fetchMyEnrollments();
      }
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
    _debounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _detectNetworkFromPhone(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 3) return '';
    final prefix = clean.substring(0, 3);

    // MTN: 024, 025, 053, 054, 055, 059
    if (['024', '025', '053', '054', '055', '059'].contains(prefix)) {
      return 'MTN';
    }
    // Telecel (Vodafone): 020, 050
    if (['020', '050'].contains(prefix)) {
      return 'Vodafone';
    }
    // AT (AirtelTigo): 026, 056, 027, 057
    if (['026', '056', '027', '057'].contains(prefix)) {
      return 'AirtelTigo';
    }
    return '';
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
        _courses = [
          {
            'id': 1,
            'title': 'Freight Forwarding Fundamentals',
            'start_date': '25 Aug 2026',
            'duration': '4 Weeks',
            'mode': 'Hybrid',
            'fee': 'GHS 1,980',
            'description': 'Foundational customs clearance and brokerage procedures, tariff classification, and international cargo documentation.',
            'syllabus': [
              'Customs Act 891 Compliance & Broker Licensing',
              'Harmonized System (HS) Tariff Classification',
              'Bonded Warehousing & Transit Cargo Regulations',
              'Bill of Lading & Commercial Invoicing Verification',
            ],
            'is_enrolled': false,
          },
          {
            'id': 2,
            'title': 'Customs Declarations & ICUMS 2.0',
            'start_date': '15 Sep 2026',
            'duration': '3 Weeks',
            'mode': 'In-Person',
            'fee': 'GHS 1,500',
            'description': 'Hands-on declaration classification, valuation, CCVR handling, and ICUMS 2.0 electronic clearance processing workflow.',
            'syllabus': [
              'ICUMS 2.0 Portal Navigation & Sandbox Entry',
              'Bill of Entry (BOE) Submission & Assessment',
              'CCVR Valuation & Risk Profiling Mitigation',
              'Post-Clearance Audit & Dispute Resolution',
            ],
            'is_enrolled': false,
          },
          {
            'id': 3,
            'title': 'Port Operations & Logistics Management',
            'start_date': '10 Oct 2026',
            'duration': '6 Weeks',
            'mode': 'Online',
            'fee': 'GHS 2,200',
            'description': 'Advanced multimodal logistics, terminal gate operations, demurrage mitigation, and maritime shipping law.',
            'syllabus': [
              'MPS Terminal 3 Gate & Berth Procedures',
              'Shipping Line Container Guarantee & Return Protocols',
              'Demurrage & Storage Calculation Safeguards',
              'AfCFTA Rules of Origin & Corridor Transit',
            ],
            'is_enrolled': false,
          },
        ];
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

    // Clean numeric fee
    final cleanFeeNum = double.tryParse(feeStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final isFreeCourse = cleanFeeNum == 0.0;

    String paymentMethod = 'momo';
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
          final sheetBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
          final textCol = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
          final subTextCol = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
          final borderCol = isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0);
          final innerBox = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);

          Color networkBadgeCol = _kOrange;
          String networkLabel = 'Enter MoMo phone number';
          if (detectedNetwork == 'MTN') {
            networkBadgeCol = const Color(0xFFEAB308);
            networkLabel = 'MTN Mobile Money';
          } else if (detectedNetwork == 'Vodafone') {
            networkBadgeCol = const Color(0xFFEF4444);
            networkLabel = 'Telecel (Vodafone) Cash';
          } else if (detectedNetwork == 'AirtelTigo') {
            networkBadgeCol = const Color(0xFF3B82F6);
            networkLabel = 'AT (AirtelTigo) Money';
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top drag pill
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.school_rounded, color: _kOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CTI Course Enrollment',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: textCol,
                                ),
                              ),
                              Text(
                                'CUBAG Training Institute Certification',
                                style: GoogleFonts.inter(fontSize: 11, color: subTextCol),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: isSubmitting ? null : () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: borderCol),
                    const SizedBox(height: 14),

                    // Course Summary Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: innerBox,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderCol),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: _kOrange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),
                              _buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),
                              _buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tuition Fee Tariff:',
                                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: subTextCol),
                              ),
                              Text(
                                isFreeCourse ? 'FREE' : feeStr,
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: _kOrange),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (!isFreeCourse) ...[
                      // Automated Push Reminder Notice
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _kGreen.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kGreen.withAlpha(50)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.notifications_active_rounded, color: _kGreen, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A real-time MoMo prompt will be sent to your phone. Enrollment is confirmed once payment succeeds.',
                                style: GoogleFonts.inter(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'PAYMENT METHOD',
                        style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w900, color: subTextCol, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setSheetState(() => paymentMethod = 'momo'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: paymentMethod == 'momo' ? _kOrange.withAlpha(20) : innerBox,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: paymentMethod == 'momo' ? _kOrange : borderCol,
                                    width: paymentMethod == 'momo' ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.phone_android_rounded, size: 16, color: paymentMethod == 'momo' ? _kOrange : subTextCol),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Mobile Money',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: paymentMethod == 'momo' ? _kOrange : textCol,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setSheetState(() => paymentMethod = 'card'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: paymentMethod == 'card' ? _kIndigo.withAlpha(20) : innerBox,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: paymentMethod == 'card' ? _kIndigo : borderCol,
                                    width: paymentMethod == 'card' ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.credit_card_rounded, size: 16, color: paymentMethod == 'card' ? _kIndigo : subTextCol),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Bank Card',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: paymentMethod == 'card' ? _kIndigo : textCol,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Phone Input with Live Auto-Detection Badge
                      TextFormField(
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textCol),
                        onChanged: (v) {
                          phone = v;
                          final net = _detectNetworkFromPhone(v);
                          setSheetState(() {
                            detectedNetwork = net;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          counterText: '',
                          fillColor: innerBox,
                          labelText: paymentMethod == 'momo' ? 'Mobile Money Phone Number' : 'Card Holder Phone',
                          hintText: 'e.g. 0244123456',
                          prefixIcon: const Icon(Icons.smartphone_rounded, size: 18),
                          suffixIcon: detectedNetwork.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: networkBadgeCol.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: networkBadgeCol),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 12, color: networkBadgeCol),
                                        const SizedBox(width: 4),
                                        Text(
                                          detectedNetwork == 'Vodafone' ? 'Telecel' : detectedNetwork,
                                          style: GoogleFonts.outfit(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: networkBadgeCol,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),

                      if (detectedNetwork.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '✓ Network auto-detected: $networkLabel',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: networkBadgeCol),
                        ),
                      ],
                    ],

                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(errorMsg!, style: GoogleFonts.inter(fontSize: 11.5, color: _kRed, fontWeight: FontWeight.bold)),
                    ],

                    const SizedBox(height: 18),

                    // Submit CTA
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
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
                                    final res = await _api.post('events/courses/$courseId/enroll', data: {
                                      'payment_method': 'free',
                                    });
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

                                // ── 1. Initiate Real MoMo Payment Prompt via Backend ──
                                try {
                                  final payRes = await _api.post('payments', data: {
                                    'amount': cleanFeeNum,
                                    'description': 'CTI Course: $title',
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

                                    // Directly dispatch prompt to phone via WhitsunPay (bypasses Cloudflare data center block)
                                    WhitsunPayService().dispatchPrompt(
                                      txRef: txRef.toString(),
                                      phone: phone.trim(),
                                      network: detectedNetwork.isNotEmpty ? detectedNetwork : 'MTN',
                                      amount: cleanFeeNum,
                                      description: 'CTI Course: $title',
                                      serverDispatchData: payData['gateway_dispatch'] is Map
                                          ? Map<String, dynamic>.from(payData['gateway_dispatch'] as Map)
                                          : null,
                                    );

                                    // Open Active MoMo Approval & Polling Modal
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
                        icon: isSubmitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.lock_outline_rounded, size: 17),
                        label: Text(
                          isSubmitting
                              ? 'Sending Prompt...'
                              : (isFreeCourse ? 'Confirm Free Enrollment' : 'Send MoMo Prompt ($feeStr)'),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13.5),
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

  // ── Awaiting MoMo Approval Modal with Auto-Polling ─────────────────────────
  void _showAwaitingApprovalModal({
    required Map<String, dynamic> course,
    required dynamic paymentId,
    required String txRef,
    required String phone,
    required String network,
    required double amount,
  }) {
    int pollAttempt = 0;
    const int maxPollAttempts = 24; // 24 * 2.5s = 60s
    Timer? pollTimer;
    bool isCompleted = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
          final textCol = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

          String noticeText = 'If the prompt does not pop up, dial *170# → Option 6 → Option 3 to approve.';
          if (network == 'Vodafone') {
            noticeText = 'If the prompt does not pop up, dial *110# → Option 4 → Option 5 to approve.';
          } else if (network == 'AirtelTigo') {
            noticeText = 'If the prompt does not pop up, dial *110# → Option 5 to approve.';
          }

          // Start Polling Timer if not active
          pollTimer ??= Timer.periodic(const Duration(milliseconds: 2500), (t) async {
            if (isCompleted || !mounted) {
              t.cancel();
              return;
            }
            pollAttempt++;

            try {
              // Poll payment status or verify reference
              dynamic statusRes;
              if (txRef.isNotEmpty) {
                statusRes = await _api.get('payments/verify/$txRef');
              } else if (paymentId != null) {
                statusRes = await _api.get('payments/status/$paymentId');
              }

              bool isPaidNow = false;
              dynamic responsePayload = statusRes?.data;
              if (statusRes != null && statusRes.data is Map) {
                final status = (statusRes.data['status']?.toString() ?? '').toLowerCase();
                if (status == 'paid' || status == 'success' || status == 'completed') {
                  isPaidNow = true;
                }
              }

              // Direct client verification check with WhitsunPay to bypass Cloudflare
              if (!isPaidNow && txRef.isNotEmpty) {
                final direct = await WhitsunPayService().checkStatus(txRef);
                if (direct['isPaid'] == true) {
                  isPaidNow = true;
                  responsePayload = direct['raw'];
                  try {
                    await _api.post('payments/verify-code', data: {
                      'payment_id': paymentId,
                      'transaction_ref': txRef,
                      'whitsun_ref': txRef,
                      'client_verified': true,
                      'client_tx_id': direct['txId'] ?? '',
                    });
                  } catch (_) {}
                }
              }

              if (isPaidNow) {
                isCompleted = true;
                t.cancel();

                // Official enrollment in backend
                try {
                  await _api.post('events/courses/${course['id']}/enroll', data: {
                    'payment_method': 'momo',
                    'payment_ref': txRef.isNotEmpty ? txRef : 'PAY-$paymentId',
                  });
                } catch (_) {}

                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                if (mounted) {
                  _showEnrollmentSuccessModal(course, responsePayload is Map ? responsePayload : {});
                  _fetchCourses();
                  _fetchMyEnrollments();
                }
                return;
              } else if (statusRes != null && statusRes.data is Map) {
                final status = (statusRes.data['status']?.toString() ?? '').toLowerCase();
                if (status == 'failed' || status == 'declined' || status == 'cancelled') {
                  isCompleted = true;
                  t.cancel();
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) {
                    _showPaymentFailedDialog('Payment was declined or cancelled. Enrollment was not processed.');
                  }
                  return;
                }
              }
            } catch (err) {
              AppLogger.error('momo_poll_check', err);
            }

            if (pollAttempt >= maxPollAttempts) {
              isCompleted = true;
              t.cancel();
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              if (mounted) {
                _showPaymentFailedDialog('Payment authorization timed out. Please verify on your phone and try again.');
              }
            } else {
              setDlgState(() {});
            }
          });

          final progress = pollAttempt / maxPollAttempts;

          return AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_android_rounded, color: _kOrange, size: 34),
                ),
                const SizedBox(height: 16),
                Text(
                  'Awaiting MoMo Approval',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textCol),
                ),
                const SizedBox(height: 8),
                Text(
                  'A prompt of GHS ${amount.toStringAsFixed(2)} has been dispatched to $phone ($network).\n\nPlease check your phone and enter your Mobile Money PIN.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 14),

                // USSD guide box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kOrange.withAlpha(35)),
                  ),
                  child: Text(
                    noticeText,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: _kOrange, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 18),

                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: _kOrange.withAlpha(30),
                  valueColor: const AlwaysStoppedAnimation<Color>(_kOrange),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                Text(
                  'Auto-verifying transaction... (${pollAttempt * 2}s / 60s)',
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCompleted = true;
                  pollTimer?.cancel();
                  Navigator.pop(dlgCtx);
                },
                child: const Text('Cancel & Close', style: TextStyle(color: Color(0xFF64748B))),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentFailedDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 24),
            const SizedBox(width: 10),
            Text('Enrollment Incomplete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          '$reason\n\nNote: You have NOT been enrolled in the course. No charges were made.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEnrollmentSuccessModal(Map<String, dynamic> course, dynamic resData) {
    final title = course['title']?.toString() ?? 'CTI Course';
    final startDate = course['start_date']?.toString() ?? 'Upcoming';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kGreen.withAlpha(20), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: _kGreen, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enrollment Confirmed!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are successfully enrolled and payment is verified for:', style: GoogleFonts.inter(fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w900, color: _kOrange)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🗓️ Starts: $startDate', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5, color: _kGreen)),
                  const SizedBox(height: 4),
                  Text('🔔 Reminders: The CUBAG App will send you automated push notifications as the course commencement approaches.', style: GoogleFonts.inter(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kGreen,
              side: const BorderSide(color: _kGreen, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              DateTime startDt = DateTime.tryParse(course['start_date']?.toString() ?? '') ??
                  DateTime.now().add(const Duration(days: 7));
              DateTime? endDt = DateTime.tryParse(course['end_date']?.toString() ?? '');
              final success = await CalendarService.addEventToCalendar(
                title: 'CTI Course: $title',
                description: 'Accredited Customs Training: $title\n\n'
                    'Schedule: ${course['schedule'] ?? 'As scheduled'}\n'
                    'Enrolled via CUBAG Member Portal',
                location: course['venue']?.toString() ?? course['location']?.toString() ?? 'Customs Training Institute (CTI)',
                startDate: startDt,
                endDate: endDt,
              );
              if (success && mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added "$title" to your calendar!',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: _kGreen,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            icon: const Icon(Icons.calendar_today_rounded, size: 15),
            label: const Text('Add to Calendar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
            child: const Text('View Enrolled Courses'),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text, Color color, {bool isDark = false}) {
    final effectiveColor = isDark ? Colors.white : color;
    final effectiveBg = isDark ? Colors.white.withAlpha(20) : color.withAlpha(18);
    final effectiveBorder = isDark ? Colors.white.withAlpha(45) : color.withAlpha(45);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: effectiveBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: effectiveColor),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w700, color: effectiveColor)),
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
        final m = (c['mode']?.toString() ?? '').toLowerCase();
        return t.contains(q) || d.contains(q) || m.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final border = isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AppLayout(
      title: 'CTI Courses',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── COMPACT RESPONSIVE HERO BANNER ────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kDarkBrown, _kBrown],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 8, offset: const Offset(0, 3)),
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
                          color: _kOrange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUBAG Training Institute (CTI)',
                              style: GoogleFonts.outfit(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Accredited Brokerage & ICUMS 2.0 Certifications',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white.withAlpha(190),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Quick stats row
                  Row(
                    children: [
                      _buildHeroStat('${_courses.length} Available', Icons.grid_view_rounded, _kOrange),
                      const SizedBox(width: 8),
                      _buildHeroStat('Certification', Icons.verified_rounded, _kGreen),
                      const SizedBox(width: 8),
                      _buildHeroStat('FCM Alerts', Icons.notifications_active_rounded, Colors.white),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── SEGMENTED TAB BAR ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: _kOrange,
                labelColor: _kOrange,
                unselectedLabelColor: textMuted,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    text: 'Catalog (${_courses.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.bookmark_added_rounded, size: 16),
                    text: 'My Enrolled (${_myEnrollments.length})',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── BODY CONTENT BASED ON ACTIVE TAB ──────────────────────────────
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

  Widget _buildHeroStat(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogView(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final list = _filteredCourses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.outfit(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search title, ICUMS, mode...',
                    hintStyle: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedMode ?? 'All',
                dropdownColor: cardBg,
                style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold, color: textPrimary),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All')),
                  DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                  DropdownMenuItem(value: 'In-Person', child: Text('In-Person')),
                  DropdownMenuItem(value: 'Online', child: Text('Online')),
                ],
                onChanged: (v) => setState(() => _selectedMode = v == 'All' ? null : v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
            child: Center(
              child: Text('No courses found matching your query.', style: GoogleFonts.outfit(fontSize: 13, color: textMuted)),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, idx) => _buildCourseMobileCard(list[idx], isDark, cardBg, border, textPrimary, textMuted),
          ),
      ],
    );
  }

  Widget _buildCourseMobileCard(Map<String, dynamic> course, bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final courseId = course['id'] is int ? course['id'] as int : int.tryParse(course['id']?.toString() ?? '0') ?? 0;
    final title = course['title']?.toString() ?? 'Course';
    final fee = course['fee']?.toString() ?? 'GHS 1,500';
    final mode = course['mode']?.toString() ?? 'Hybrid';
    final startDate = course['start_date']?.toString() ?? 'TBD';
    final duration = course['duration']?.toString() ?? '4 Weeks';
    final desc = course['description']?.toString() ?? '';
    final isEnrolled = course['is_enrolled'] == true;
    final isExpanded = _expandedCourseIds.contains(courseId);
    final daysLeft = _getDaysRemaining(startDate);

    final syllabusList = course['syllabus'] is List
        ? (course['syllabus'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnrolled ? _kGreen.withAlpha(120) : border,
          width: isEnrolled ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isEnrolled ? _kGreen.withAlpha(20) : _kOrange.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEnrolled ? Icons.verified_rounded : Icons.menu_book_rounded,
                        color: isEnrolled ? _kGreen : _kOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                            maxLines: isExpanded ? null : 2,
                            overflow: isExpanded ? null : TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Meta Badges
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),
                    _buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),
                    _buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),
                    if (daysLeft != null && daysLeft >= 0)
                      _buildMiniBadge(Icons.alarm_on_rounded, 'Starts in $daysLeft d', _kGreen),
                  ],
                ),

                // Expanded Syllabus Accordion
                if (isExpanded && syllabusList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Syllabus Modules:', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kOrange)),
                        const SizedBox(height: 6),
                        ...syllabusList.map((mod) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: _kOrange, fontWeight: FontWeight.bold)),
                              Expanded(child: Text(mod, style: GoogleFonts.inter(fontSize: 11, color: textPrimary))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          Divider(height: 1, color: border),

          // Bottom Action Strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCourseIds.remove(courseId);
                      } else {
                        _expandedCourseIds.add(courseId);
                      }
                    });
                  },
                  child: Row(
                    children: [
                      Text(
                        isExpanded ? 'Less' : 'Syllabus',
                        style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kOrange),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: _kOrange,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  fee,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: _kOrange),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnrolled ? _kGreen : _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: isEnrolled ? null : () => _openEnrollmentSheet(course),
                  icon: Icon(isEnrolled ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 14),
                  label: Text(
                    isEnrolled ? 'Enrolled' : 'Enroll',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyEnrollmentsView(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    if (_loadingMy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    if (_myEnrollments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 40, color: textMuted),
            const SizedBox(height: 10),
            Text(
              'No active course enrollments yet.',
              style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Browse the CTI catalog and enroll in accredited customs courses.',
              style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.search_rounded, size: 15),
              label: const Text('Browse Catalog'),
            ),
          ],
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
        final daysLeft = _getDaysRemaining(startDate);
        final ref = en['payment_ref']?.toString() ?? 'N/A';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGreen.withAlpha(80), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _kGreen.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.school_rounded, color: _kGreen, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text('Ref: $ref • $fee (PAID)', style: GoogleFonts.inter(fontSize: 10.5, color: textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(6)),
                    child: Text('ACTIVE', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Add to Calendar',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.event_available_rounded, size: 20, color: _kGreen),
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      DateTime startDt = DateTime.tryParse(startDate) ?? DateTime.now().add(const Duration(days: 7));
                      final success = await CalendarService.addEventToCalendar(
                        title: 'CTI Course: $title',
                        description: 'Accredited Customs Training: $title\n\nDuration: $duration • Mode: $mode\nRef: $ref\nEnrolled via CUBAG Member Portal',
                        location: 'Customs Training Institute (CTI)',
                        startDate: startDt,
                      );
                      if (success && mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added "$title" to your calendar!',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _kGreen,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: border),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),
                  const SizedBox(width: 6),
                  _buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),
                  const SizedBox(width: 6),
                  _buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),
                  const Spacer(),
                  if (daysLeft != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (daysLeft <= 3 ? _kRed : _kOrange).withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_rounded, size: 12, color: daysLeft <= 3 ? _kRed : _kOrange),
                          const SizedBox(width: 4),
                          Text(
                            daysLeft == 0 ? 'Starts Today!' : 'Starts in $daysLeft d',
                            style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.bold, color: daysLeft <= 3 ? _kRed : _kOrange),
                          ),
                        ],
                      ),
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
