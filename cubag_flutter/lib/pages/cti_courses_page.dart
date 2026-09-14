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

const _kOrange = Color(0xFFFF5000);
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
    if (['024', '025', '053', '054', '055', '059'].contains(prefix)) {
      return 'MTN';
    }
    if (['020', '050'].contains(prefix)) {
      return 'Vodafone';
    }
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
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textCol),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: isSubmitting ? null : () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _kOrange)),
                    const SizedBox(height: 4),
                    Text('$startDate • $duration • $mode', style: GoogleFonts.inter(fontSize: 13, color: subTextCol)),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: borderCol),
                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tuition Fee:', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: subTextCol)),
                        Text(isFreeCourse ? 'FREE' : feeStr, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textCol)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (!isFreeCourse) ...[
                      Text('MOMO PHONE NUMBER', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w900, color: subTextCol, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextFormField(
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                        onChanged: (v) {
                          phone = v;
                          final net = _detectNetworkFromPhone(v);
                          setSheetState(() => detectedNetwork = net);
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
                        Text('✓ Network: $networkLabel', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: networkBadgeCol)),
                      ],
                    ],

                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(errorMsg!, style: GoogleFonts.inter(fontSize: 13, color: _kRed, fontWeight: FontWeight.bold)),
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
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
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
    const int maxPollAttempts = 24;
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

          pollTimer ??= Timer.periodic(const Duration(milliseconds: 2500), (t) async {
            if (isCompleted || !mounted) {
              t.cancel();
              return;
            }
            pollAttempt++;

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
                  t.cancel();
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
                  t.cancel();
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) _showPaymentFailedDialog('Payment was declined or cancelled.');
                  return;
                }
              }
            } catch (_) {}

            if (pollAttempt >= maxPollAttempts) {
              isCompleted = true;
              t.cancel();
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              if (mounted) _showPaymentFailedDialog('Payment verification timed out.');
            } else {
              setDlgState(() {});
            }
          });

          return AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: _kOrange),
                const SizedBox(height: 16),
                Text('Approve MoMo Payment', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textCol)),
                const SizedBox(height: 8),
                Text('Check your phone ($phone) and enter your PIN to complete enrolment.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B))),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCompleted = true;
                  pollTimer?.cancel();
                  Navigator.pop(dlgCtx);
                },
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enrollment Incomplete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(reason, style: GoogleFonts.inter(fontSize: 14)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Enrollment Confirmed!', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are successfully enrolled in:', style: GoogleFonts.inter(fontSize: 14)),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: _kOrange)),
            const SizedBox(height: 8),
            Text('🗓️ Starts: $startDate', style: GoogleFonts.inter(fontSize: 13.5, color: _kGreen, fontWeight: FontWeight.bold)),
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

  Widget _buildMiniBadge(IconData icon, String text, Color color, {bool isDark = false}) {
    final effectiveColor = isDark ? Colors.white : color;
    final effectiveBg = isDark ? Colors.white.withAlpha(20) : color.withAlpha(15);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: effectiveColor),
          const SizedBox(width: 3),
          Text(text, style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: effectiveColor)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── SIMPLE HEADER ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CTI Training Courses', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textPrimary)),
                    const SizedBox(height: 2),
                    Text('Accredited brokerage & ICUMS certifications', style: GoogleFonts.inter(fontSize: 13.5, color: textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── TABS ──────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: _kOrange,
                labelColor: _kOrange,
                unselectedLabelColor: textMuted,
                indicatorWeight: 2.5,
                labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Simple search and filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.outfit(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search courses...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: textMuted),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _selectedMode ?? 'All',
                dropdownColor: cardBg,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
            child: Center(
              child: Text('No courses found.', style: GoogleFonts.outfit(fontSize: 14.5, color: textMuted)),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, idx) => _buildCourseCard(list[idx], isDark, cardBg, border, textPrimary, textMuted),
          ),
      ],
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final title = course['title']?.toString() ?? 'Course';
    final fee = course['fee']?.toString() ?? 'GHS 1,500';
    final mode = course['mode']?.toString() ?? 'Hybrid';
    final startDate = course['start_date']?.toString() ?? 'TBD';
    final duration = course['duration']?.toString() ?? '4 Weeks';
    final desc = course['description']?.toString() ?? '';
    final isEnrolled = course['is_enrolled'] == true;
    final daysLeft = _getDaysRemaining(startDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isEnrolled ? _kGreen.withAlpha(100) : border, width: isEnrolled ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ),
              Text(
                fee,
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: _kOrange),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: GoogleFonts.inter(fontSize: 13.5, color: textMuted, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),
              const SizedBox(width: 6),
              _buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),
              const SizedBox(width: 6),
              _buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),
              if (daysLeft != null && daysLeft >= 0) ...[
                const SizedBox(width: 6),
                _buildMiniBadge(Icons.alarm_on_rounded, 'In $daysLeft d', _kGreen),
              ],
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEnrolled ? _kGreen : _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: isEnrolled ? null : () => _openEnrollmentSheet(course),
                child: Text(isEnrolled ? 'Enrolled' : 'Enroll Now', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5)),
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
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Center(
          child: Text('No active course enrollments yet.', style: GoogleFonts.outfit(fontSize: 14.5, color: textMuted)),
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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGreen.withAlpha(80), width: 1.2),
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
                        Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 2),
                        Text('$fee • Paid & Confirmed', style: GoogleFonts.inter(fontSize: 13, color: _kGreen, fontWeight: FontWeight.w600)),
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
