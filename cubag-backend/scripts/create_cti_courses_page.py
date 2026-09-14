import os

FLUTTER_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/cti_courses_page.dart"

CODE = '''import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _fetchMyEnrollments();
      }
    });
    _fetchCourses();
  }

  @override
  void dispose() {
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

    // Fallback default CTI courses if offline/empty
    setState(() {
      _courses = [
        {
          'id': 1,
          'title': 'Freight Forwarding Fundamentals',
          'start_date': '25 Aug 2026',
          'duration': '4 Weeks',
          'mode': 'Hybrid',
          'fee': 'GHS 1,980',
          'description': 'Foundational customs clearance and brokerage procedures, tariff classification, and cargo documentation.',
          'is_enrolled': false,
        },
        {
          'id': 2,
          'title': 'Customs Declarations & ICUMS 2.0',
          'start_date': '15 Sep 2026',
          'duration': '3 Weeks',
          'mode': 'In-Person',
          'fee': 'GHS 1,500',
          'description': 'Hands-on declaration classification, valuation, CCVR handling, and ICUMS 2.0 electronic processing workflow.',
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
    setState(() => _loadingMy = false);
  }

  // Calculate days remaining to course start date
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

  Future<void> _startEnrollment(Map<String, dynamic> course) async {
    final title = course['title']?.toString() ?? 'CTI Course';
    final fee = course['fee']?.toString() ?? 'GHS 1,500';
    final mode = course['mode']?.toString() ?? 'Hybrid';
    final startDate = course['start_date']?.toString() ?? 'TBD';
    final duration = course['duration']?.toString() ?? '4 Weeks';
    final courseId = course['id'];

    String paymentMethod = 'momo';
    final phoneCtrl = TextEditingController();
    bool isSubmitting = false;
    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
          final textCol = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
          final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.school_rounded, color: _kOrange, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CTI Course Enrollment', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textCol)),
                              Text('CUBAG Training Institute Professional Certification', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                            ],
                          ),
                        ),
                        if (!isSubmitting)
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(dlgCtx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Course Summary Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: _kOrange)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildMiniBadge(Icons.calendar_today_rounded, startDate, _kBlue),
                              const SizedBox(width: 8),
                              _buildMiniBadge(Icons.timelapse_rounded, duration, _kIndigo),
                              const SizedBox(width: 8),
                              _buildMiniBadge(Icons.location_on_outlined, mode, _kPurple),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total Enrollment Tariff:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                              Text(fee, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: _kOrange)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scheduled Reminders Note
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kGreen.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kGreen.withAlpha(50)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_outlined, color: _kGreen, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Automated push reminders will notify you 7 days, 3 days & 1 day before course commencement.',
                              style: GoogleFonts.inter(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text('PAYMENT METHOD', style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.phone_android_rounded, size: 14),
                                const SizedBox(width: 6),
                                Text('Mobile Money', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            selected: paymentMethod == 'momo',
                            selectedColor: _kOrange,
                            labelStyle: TextStyle(color: paymentMethod == 'momo' ? Colors.white : textCol),
                            onSelected: (v) {
                              if (v) setDlgState(() => paymentMethod = 'momo');
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.credit_card_rounded, size: 14),
                                const SizedBox(width: 6),
                                Text('Bank Card', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            selected: paymentMethod == 'card',
                            selectedColor: _kIndigo,
                            labelStyle: TextStyle(color: paymentMethod == 'card' ? Colors.white : textCol),
                            onSelected: (v) {
                              if (v) setDlgState(() => paymentMethod = 'card');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.outfit(fontSize: 13, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                        labelText: paymentMethod == 'momo' ? 'MoMo Number (MTN / Telecel / AT)' : 'Card Holder Phone / Email',
                        hintText: '024XXXXXXX',
                        prefixIcon: const Icon(Icons.payment_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),

                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(errorMsg!, style: GoogleFonts.inter(fontSize: 11.5, color: _kRed, fontWeight: FontWeight.bold)),
                    ],

                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isSubmitting)
                          TextButton(
                            onPressed: () => Navigator.pop(dlgCtx),
                            child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                          ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 1,
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  setDlgState(() {
                                    isSubmitting = true;
                                    errorMsg = null;
                                  });

                                  try {
                                    final res = await _api.post('events/courses/$courseId/enroll', data: {
                                      'payment_method': paymentMethod,
                                      'phone': phoneCtrl.text.trim(),
                                    });

                                    if (mounted) {
                                      Navigator.pop(dlgCtx);
                                      _showEnrollmentSuccessModal(course, res.data);
                                      _fetchCourses();
                                      _fetchMyEnrollments();
                                    }
                                  } catch (e) {
                                    setDlgState(() {
                                      isSubmitting = false;
                                      errorMsg = 'Enrollment failed: $e';
                                    });
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.lock_outline_rounded, size: 16),
                          label: Text(
                            isSubmitting ? 'Processing Payment...' : 'Pay & Confirm Enrollment ($fee)',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    phoneCtrl.dispose();
  }

  void _showEnrollmentSuccessModal(Map<String, dynamic> course, dynamic resData) {
    final title = course['title']?.toString() ?? 'CTI Course';
    final startDate = course['start_date']?.toString() ?? 'Upcoming';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _kGreen, size: 28),
            const SizedBox(width: 12),
            Text('Enrollment Confirmed!', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Congratulations! You are officially enrolled in:', style: GoogleFonts.inter(fontSize: 13)),
            const SizedBox(height: 6),
            Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: _kOrange)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🗓️ Start Date: $startDate', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: _kGreen)),
                  const SizedBox(height: 4),
                  Text('🔔 Reminders: The CUBAG App will notify you when this course is due to start.', style: GoogleFonts.inter(fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
            child: const Text('View My Enrolled Courses'),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
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
    final bg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
    final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AppLayout(
      title: 'CUBAG Training Institute (CTI)',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HERO BANNER ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF281710), Color(0xFF140B07)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'CUBAG Training Institute (CTI)',
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: _kOrange.withAlpha(50), borderRadius: BorderRadius.circular(6), border: Border.all(color: _kOrange)),
                              child: Text('OFFICIAL CERTIFICATION', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: _kOrange)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Advance your career with industry-accredited customs brokerage, ICUMS 2.0 workflow, and maritime port logistics courses.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white.withAlpha(200)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── TAB CONTROLLER ────────────────────────────────────────────────
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
                labelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Available Courses Catalog'),
                  Tab(icon: Icon(Icons.bookmark_added_rounded, size: 18), text: 'My Enrolled Courses & Reminders'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── TAB CONTENT ──────────────────────────────────────────────────
            SizedBox(
              height: 750,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // TAB 1: ALL AVAILABLE COURSES
                  _buildCatalogTab(isDark, cardBg, border, textPrimary, textMuted),

                  // TAB 2: MY ENROLLED COURSES
                  _buildMyEnrollmentsTab(isDark, cardBg, border, textPrimary, textMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogTab(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final list = _filteredCourses;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Toolbar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF10141E) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.outfit(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search course by title, mode, or syllabus topic...',
                        hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                        prefixIcon: Icon(Icons.search_rounded, size: 17, color: textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedMode ?? 'All',
                  dropdownColor: cardBg,
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All Modes')),
                    DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                    DropdownMenuItem(value: 'In-Person', child: Text('In-Person')),
                    DropdownMenuItem(value: 'Online', child: Text('Online')),
                  ],
                  onChanged: (v) => setState(() => _selectedMode = v == 'All' ? null : v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_loading)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (_, index) => const ShimmerListTile(),
            )
          else if (list.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
              child: Center(
                child: Text('No CTI courses matching your search criteria.', style: GoogleFonts.outfit(fontSize: 14, color: textMuted)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, index) => const SizedBox(height: 14),
              itemBuilder: (context, idx) => _buildCourseCard(list[idx], isDark, cardBg, border, textPrimary, textMuted),
            ),
        ],
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isEnrolled ? _kGreen.withAlpha(120) : border, width: isEnrolled ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isEnrolled ? _kGreen.withAlpha(25) : _kOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(isEnrolled ? Icons.verified_rounded : Icons.menu_book_rounded, color: isEnrolled ? _kGreen : _kOrange, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textPrimary)),
                        ),
                        if (isEnrolled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(6)),
                            child: Text('ENROLLED', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(desc, style: GoogleFonts.inter(fontSize: 12.5, color: textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          Row(
            children: [
              _buildMiniBadge(Icons.calendar_today_rounded, startDate, _kBlue),
              const SizedBox(width: 8),
              _buildMiniBadge(Icons.timelapse_rounded, duration, _kIndigo),
              const SizedBox(width: 8),
              _buildMiniBadge(Icons.location_on_outlined, mode, _kPurple),
              if (daysLeft != null && daysLeft >= 0) ...[
                const SizedBox(width: 8),
                _buildMiniBadge(Icons.alarm_on_rounded, 'Starts in $daysLeft day${daysLeft == 1 ? '' : 's'}', _kGreen),
              ],
              const Spacer(),
              Text(fee, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: _kOrange)),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEnrolled ? _kGreen : _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: isEnrolled ? null : () => _startEnrollment(course),
                icon: Icon(isEnrolled ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded, size: 15),
                label: Text(isEnrolled ? 'Enrolled' : 'Enroll Now', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyEnrollmentsTab(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    if (_loadingMy) {
      return Center(child: CircularProgressIndicator(color: _kOrange));
    }

    if (_myEnrollments.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 48, color: textMuted),
              const SizedBox(height: 12),
              Text('You have not enrolled in any CTI course yet.', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
              const SizedBox(height: 6),
              Text('Explore the available courses catalog to enroll in certification programs.', style: GoogleFonts.inter(fontSize: 12.5, color: textMuted)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('Browse Course Catalog'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _myEnrollments.length,
      separatorBuilder: (_, index) => const SizedBox(height: 14),
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGreen.withAlpha(80), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _kGreen.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.school_rounded, color: _kGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textPrimary)),
                        Text('Payment Ref: $ref • $fee (PAID)', style: GoogleFonts.inter(fontSize: 11.5, color: textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(8)),
                    child: Text('ACTIVE ENROLLMENT', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Row(
                children: [
                  _buildMiniBadge(Icons.calendar_today_rounded, startDate, _kBlue),
                  const SizedBox(width: 8),
                  _buildMiniBadge(Icons.timelapse_rounded, duration, _kIndigo),
                  const SizedBox(width: 8),
                  _buildMiniBadge(Icons.location_on_outlined, mode, _kPurple),
                  const Spacer(),
                  if (daysLeft != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (daysLeft <= 3 ? _kRed : _kOrange).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (daysLeft <= 3 ? _kRed : _kOrange).withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_rounded, size: 14, color: daysLeft <= 3 ? _kRed : _kOrange),
                          const SizedBox(width: 6),
                          Text(
                            daysLeft == 0 ? 'Course Starts Today!' : 'Starts in $daysLeft days',
                            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: daysLeft <= 3 ? _kRed : _kOrange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
'''

with open(FLUTTER_FILE, "w", encoding="utf-8") as f:
    f.write(CODE)

print(f"Successfully generated {len(CODE.splitlines())} lines to {FLUTTER_FILE}")
