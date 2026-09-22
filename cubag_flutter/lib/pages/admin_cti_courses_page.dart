import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kRed = Color(0xFFEF4444);
const _kSlate = Color(0xFF64748B);

class AdminCtiCoursesPage extends StatefulWidget {
  const AdminCtiCoursesPage({super.key});

  @override
  State<AdminCtiCoursesPage> createState() => _AdminCtiCoursesPageState();
}

class _AdminCtiCoursesPageState extends State<AdminCtiCoursesPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<dynamic> _courses = [];
  List<dynamic> _enrollments = [];
  List<dynamic> _guestEnrollments = [];
  bool _loading = true;
  bool _loadingEnrollments = false;
  bool _loadingGuestEnrollments = false;

  // Catalog filters
  String _searchQuery = '';
  int _filterTab = 0; // 0: All, 1: Active, 2: Archived

  // Member enrollments filter
  String _enrollmentCourseFilter = 'all';
  String _enrollmentSearchQuery = '';

  // Guest enrollments filter
  String _guestStatusFilter = 'all';
  String _guestCourseFilter = 'all';
  String _guestSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _enrollments.isEmpty && !_loadingEnrollments) {
        _fetchEnrollments();
      } else if (_tabController.index == 2 && _guestEnrollments.isEmpty && !_loadingGuestEnrollments) {
        _fetchGuestEnrollments();
      }
    });
    _fetchAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    _fetchCourses();
    _fetchEnrollments();
    _fetchGuestEnrollments();
  }

  Future<void> _fetchCourses() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/events/admin/courses');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _courses = res.data['items'];
          _loading = false;
        });
      } else if (mounted && res.data is List) {
        setState(() {
          _courses = res.data;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_cti_courses', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchEnrollments() async {
    setState(() => _loadingEnrollments = true);
    try {
      final res = await _api.get('/events/admin/courses/enrollments');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _enrollments = res.data['items'];
          _loadingEnrollments = false;
        });
      }
    } catch (e) {
      AppLogger.error('admin_cti_enrollments', e);
      if (mounted) setState(() => _loadingEnrollments = false);
    }
  }

  Future<void> _fetchGuestEnrollments() async {
    setState(() => _loadingGuestEnrollments = true);
    try {
      final res = await _api.get('/events/admin/courses/guest-enrollments');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _guestEnrollments = res.data['items'];
          _loadingGuestEnrollments = false;
        });
      }
    } catch (e) {
      AppLogger.error('admin_guest_enrollments', e);
      if (mounted) setState(() => _loadingGuestEnrollments = false);
    }
  }

  Future<void> _markGuestPaid(String ref) async {
    try {
      await _api.post('/events/admin/courses/guest-enrollments/$ref/mark-paid');
      _fetchGuestEnrollments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guest enrollment $ref marked as paid!'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<dynamic> _getEnrollmentsForCourse(dynamic course) {
    final cId = course['id']?.toString();
    final cTitle = (course['title']?.toString() ?? '').toLowerCase();
    return _enrollments.where((e) {
      final eCourseId = e['course_id']?.toString();
      final eCourseTitle = (e['course_title']?.toString() ?? '').toLowerCase();
      if (cId != null && eCourseId != null && cId == eCourseId) return true;
      if (cTitle.isNotEmpty && eCourseTitle.isNotEmpty && cTitle == eCourseTitle) {
        return true;
      }
      return false;
    }).toList();
  }

  List<dynamic> get _filteredCourses {
    var list = _courses;
    if (_filterTab == 1) {
      list = list.where((c) => c['is_active'] == true).toList();
    } else if (_filterTab == 2) {
      list = list.where((c) => c['is_active'] == false).toList();
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

  List<dynamic> get _filteredEnrollments {
    var list = _enrollments;
    if (_enrollmentCourseFilter != 'all') {
      list = list.where((e) {
        final eCourseId = e['course_id']?.toString();
        final eCourseTitle = (e['course_title']?.toString() ?? '').toLowerCase();
        return eCourseId == _enrollmentCourseFilter ||
            eCourseTitle == _enrollmentCourseFilter.toLowerCase();
      }).toList();
    }
    if (_enrollmentSearchQuery.isNotEmpty) {
      final q = _enrollmentSearchQuery.toLowerCase();
      list = list.where((e) {
        final name = (e['member_name']?.toString() ?? '').toLowerCase();
        final comp = (e['company']?.toString() ?? '').toLowerCase();
        final email = (e['email']?.toString() ?? '').toLowerCase();
        final phone = (e['phone']?.toString() ?? '').toLowerCase();
        final ref = (e['payment_ref']?.toString() ?? '').toLowerCase();
        final cTitle = (e['course_title']?.toString() ?? '').toLowerCase();
        return name.contains(q) ||
            comp.contains(q) ||
            email.contains(q) ||
            phone.contains(q) ||
            ref.contains(q) ||
            cTitle.contains(q);
      }).toList();
    }
    return list;
  }

  List<dynamic> get _filteredGuestEnrollments {
    var list = _guestEnrollments;
    if (_guestStatusFilter != 'all') {
      list = list.where((e) {
        final st = (e['status'] ?? '').toString().toLowerCase();
        if (_guestStatusFilter == 'paid') {
          return st == 'paid' || st == 'completed' || st == 'success';
        } else if (_guestStatusFilter == 'pending') {
          return st != 'paid' && st != 'completed' && st != 'success';
        }
        return st == _guestStatusFilter;
      }).toList();
    }
    if (_guestCourseFilter != 'all') {
      list = list.where((e) {
        final cTitle = (e['course_title'] ?? '').toString().toLowerCase();
        return cTitle == _guestCourseFilter.toLowerCase();
      }).toList();
    }
    if (_guestSearchQuery.isNotEmpty) {
      final q = _guestSearchQuery.toLowerCase();
      list = list.where((e) {
        final name = (e['guest_name'] ?? '').toString().toLowerCase();
        final phone = (e['phone'] ?? '').toString().toLowerCase();
        final email = (e['email'] ?? '').toString().toLowerCase();
        final ref = (e['reference_no'] ?? '').toString().toLowerCase();
        final cTitle = (e['course_title'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || email.contains(q) || ref.contains(q) || cTitle.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final total = _courses.length;
    final active = _courses.where((c) => c['is_active'] == true).length;

    return AppLayout(
      title: 'CTI Courses',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          AdminHeader(
            title: 'CUBAG Training Institute (CTI)',
            subtitle: 'Manage professional training courses, curricula, and student enrollment registries.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _fetchAll,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => _showCourseDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('New Course', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Streamlined KPI Cards
          _buildKPIRow(isDark, cardBg, borderColor, textColor, subTextColor, total, active),
          const SizedBox(height: 16),

          // Clean Tab Bar
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: _kOrange,
              labelColor: _kOrange,
              unselectedLabelColor: subTextColor,
              labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.school_rounded, size: 16),
                  text: 'Course Catalog ($total)',
                ),
                Tab(
                  icon: const Icon(Icons.people_alt_rounded, size: 16),
                  text: 'Member Enrolled (${_enrollments.length})',
                ),
                Tab(
                  icon: const Icon(Icons.person_pin_rounded, size: 16),
                  text: 'Guest Enrolled & Paid (${_guestEnrollments.length})',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index == 0) {
                return _buildCoursesTab(total, active, isDark, cardBg, borderColor, textColor, subTextColor);
              } else if (_tabController.index == 1) {
                return _buildEnrollmentsTab(isDark, cardBg, borderColor, textColor, subTextColor);
              } else {
                return _buildGuestEnrollmentsTab(isDark, cardBg, borderColor, textColor, subTextColor);
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildKPIRow(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
    int total,
    int active,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 750;
        final cards = [
          _kpiStat('Total Courses', '$total', Icons.school_outlined, _kIndigo, cardBg, borderColor, textColor, subTextColor),
          _kpiStat('Active Catalog', '$active', Icons.check_circle_outline_rounded, _kGreen, cardBg, borderColor, textColor, subTextColor),
          _kpiStat('Member Enrolled', '${_enrollments.length}', Icons.people_alt_outlined, _kBlue, cardBg, borderColor, textColor, subTextColor),
          _kpiStat('Guest Enrolled', '${_guestEnrollments.length}', Icons.person_pin_circle_outlined, _kOrange, cardBg, borderColor, textColor, subTextColor),
        ];

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((c) => Container(width: 160, margin: const EdgeInsets.only(right: 8), child: c)).toList(),
          ),
        );
      },
    );
  }

  Widget _kpiStat(
    String label,
    String value,
    IconData icon,
    Color color,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: textColor),
                ),
                Text(
                  label,
                  style: GoogleFonts.outfit(fontSize: 11.5, color: subTextColor, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 1: COURSE CATALOG ──────────────────────────────────────────────────
  Widget _buildCoursesTab(
    int total,
    int active,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final courses = _filteredCourses;
    final inactive = total - active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Filter Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search courses by title, mode, or keywords...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: subTextColor),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterPill('All ($total)', _filterTab == 0, () => setState(() => _filterTab = 0), borderColor, textColor),
                    const SizedBox(width: 6),
                    _filterPill('Active ($active)', _filterTab == 1, () => setState(() => _filterTab = 1), borderColor, textColor, activeColor: _kGreen),
                    const SizedBox(width: 6),
                    _filterPill('Archived ($inactive)', _filterTab == 2, () => setState(() => _filterTab = 2), borderColor, textColor, activeColor: _kSlate),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_loading)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(3, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
            ),
          )
        else if (courses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.school_outlined, size: 36, color: subTextColor),
                  const SizedBox(height: 8),
                  Text('No courses found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: courses.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final c = courses[i];
              final isActive = c['is_active'] == true;
              final enrolledCount = _getEnrollmentsForCourse(c).length;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school_rounded, color: _kOrange, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c['title'] ?? '',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isActive ? _kGreen : _kSlate).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isActive ? 'ACTIVE' : 'ARCHIVED',
                                  style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: isActive ? _kGreen : _kSlate),
                                ),
                              ),
                            ],
                          ),
                          if (c['description'] != null && c['description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              c['description'],
                              style: GoogleFonts.inter(fontSize: 12, color: subTextColor, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _infoBadge(Icons.calendar_today_rounded, '${c['start_date'] ?? 'N/A'}', isDark, subTextColor),
                              _infoBadge(Icons.timelapse_rounded, '${c['duration'] ?? 'N/A'}', isDark, subTextColor),
                              _infoBadge(Icons.location_on_outlined, '${c['mode'] ?? 'Hybrid'}', isDark, subTextColor),
                              _infoBadge(Icons.payments_outlined, '${c['fee'] ?? 'Free'}', isDark, _kOrange),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Enrolled button
                        InkWell(
                          onTap: () => _showCourseEnrollmentsDialog(c),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (enrolledCount > 0 ? _kGreen : _kOrange).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: (enrolledCount > 0 ? _kGreen : _kOrange).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_alt_rounded, size: 12, color: enrolledCount > 0 ? _kGreen : _kOrange),
                                const SizedBox(width: 4),
                                Text(
                                  '$enrolledCount Enrolled',
                                  style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold, color: enrolledCount > 0 ? _kGreen : _kOrange),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              color: _kBlue,
                              tooltip: 'Edit Course',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showCourseDialog(c),
                            ),
                            if (isActive)
                              IconButton(
                                icon: const Icon(Icons.archive_outlined, size: 16),
                                color: _kOrange,
                                tooltip: 'Archive',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteCourse(c),
                              )
                            else ...[
                              IconButton(
                                icon: const Icon(Icons.restore_from_trash_rounded, size: 16),
                                color: _kGreen,
                                tooltip: 'Restore',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _restoreCourse(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                                color: _kRed,
                                tooltip: 'Delete Permanently',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteCourse(c, permanent: true),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ── TAB 2: MEMBER ENROLLED ─────────────────────────────────────────────────
  Widget _buildEnrollmentsTab(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final filteredList = _filteredEnrollments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter toolbar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (v) => setState(() => _enrollmentSearchQuery = v.trim()),
                        style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Search enrolled students by name, company, email, ref...',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: subTextColor),
                          prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _coursePill('All Courses (${_enrollments.length})', 'all', isDark, borderColor, textColor),
                    ..._courses.map((c) {
                      final cId = c['id']?.toString() ?? '';
                      final cTitle = c['title'] ?? 'Course';
                      final count = _getEnrollmentsForCourse(c).length;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _coursePill('$cTitle ($count)', cId, isDark, borderColor, textColor),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingEnrollments)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(3, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
            ),
          )
        else if (filteredList.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.people_outline_rounded, size: 36, color: subTextColor),
                  const SizedBox(height: 8),
                  Text('No enrolled members found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredList.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final en = filteredList[i];
              final memberName = en['member_name'] ?? 'Enrolled Member';
              final company = en['company'] ?? 'Licensed Broker';
              final courseTitle = en['course_title'] ?? 'CTI Course';
              final mode = en['mode'] ?? 'Hybrid';
              final amount = en['amount']?.toString() ?? '0.00';
              final paymentRef = en['payment_ref'] ?? 'N/A';
              final phone = en['phone'] ?? 'N/A';
              final email = en['email'] ?? 'N/A';
              final enrolledDate = en['created_at']?.toString().split('T').first ?? '';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _kGreen.withValues(alpha: 0.12),
                      child: Text(
                        memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: _kGreen),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(memberName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5, color: textColor)),
                              if (company.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text('• $company', style: GoogleFonts.inter(fontSize: 11.5, color: _kOrange, fontWeight: FontWeight.w500)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('Course: $courseTitle ($mode)', style: GoogleFonts.inter(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
                          Text('Ref: $paymentRef • GHS $amount • $phone • $email ${enrolledDate.isNotEmpty ? '• Date: $enrolledDate' : ''}', style: GoogleFonts.inter(fontSize: 11, color: subTextColor)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('PAID & ENROLLED', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: _kGreen)),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ── TAB 3: GUEST ENROLLED & PAID ───────────────────────────────────────────
  Widget _buildGuestEnrollmentsTab(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final filtered = _filteredGuestEnrollments;
    final totalGuests = _guestEnrollments.length;
    final paidGuests = _guestEnrollments.where((e) {
      final st = (e['status'] ?? '').toString().toLowerCase();
      return st == 'paid' || st == 'completed' || st == 'success';
    }).length;
    final pendingGuests = totalGuests - paidGuests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls toolbar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (v) => setState(() => _guestSearchQuery = v.trim()),
                        style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Search guest name, phone, email, CTI reference...',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: subTextColor),
                          prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        ),
                      ),
                    ),
                  ),
                  if (filtered.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        final roster = filtered.map((e) {
                          final name = e['guest_name'] ?? 'Guest';
                          final phone = e['phone'] ?? '';
                          final email = e['email'] ?? '';
                          final course = e['course_title'] ?? 'CTI Course';
                          final ref = e['reference_no'] ?? '';
                          final status = e['status'] ?? 'paid';
                          return '$name | $phone | $email | Course: $course | Ref: $ref | Status: $status';
                        }).join('\n');
                        Clipboard.setData(ClipboardData(text: roster));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Guest roster copied to clipboard!'),
                            backgroundColor: _kGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: Text('Copy Roster', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _filterPill('All Status ($totalGuests)', _guestStatusFilter == 'all', () => setState(() => _guestStatusFilter = 'all'), borderColor, textColor),
                  const SizedBox(width: 6),
                  _filterPill('Paid ($paidGuests)', _guestStatusFilter == 'paid', () => setState(() => _guestStatusFilter = 'paid'), borderColor, textColor, activeColor: _kGreen),
                  const SizedBox(width: 6),
                  _filterPill('Pending ($pendingGuests)', _guestStatusFilter == 'pending', () => setState(() => _guestStatusFilter = 'pending'), borderColor, textColor, activeColor: _kOrange),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _coursePill('All Courses', 'all', isDark, borderColor, textColor),
                    ..._courses.map((c) {
                      final cTitle = c['title']?.toString() ?? 'Course';
                      final isSel = _guestCourseFilter.toLowerCase() == cTitle.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () => setState(() => _guestCourseFilter = isSel ? 'all' : cTitle),
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSel ? _kIndigo : (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isSel ? _kIndigo : borderColor),
                            ),
                            child: Text(
                              cTitle,
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingGuestEnrollments)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(3, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
            ),
          )
        else if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.person_search_rounded, size: 36, color: subTextColor),
                  const SizedBox(height: 8),
                  Text('No guest course enrollments found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final g = filtered[i];
              final name = g['guest_name']?.toString() ?? 'Guest Student';
              final phone = g['phone']?.toString() ?? '';
              final email = g['email']?.toString() ?? '';
              final course = g['course_title']?.toString() ?? 'CTI Course';
              final rawRef = g['reference_no']?.toString() ?? '';
              final ctiRef = rawRef.replaceAll('GSR-', 'CTI-');
              final amount = g['amount']?.toString() ?? '1500.00';
              final status = (g['status']?.toString() ?? 'paid').toLowerCase();
              final isPaid = status == 'paid' || status == 'completed' || status == 'success';
              final dateStr = g['created_at']?.toString().split('T').first ?? '';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isPaid ? _kGreen.withValues(alpha: 0.12) : _kOrange.withValues(alpha: 0.12),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'G',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: isPaid ? _kGreen : _kOrange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5, color: textColor)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: _kIndigo.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('GUEST', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: _kIndigo)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('Course: $course • Fee: GHS $amount', style: GoogleFonts.inter(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
                          Text('Ref: $ctiRef • $phone • $email ${dateStr.isNotEmpty ? '• Date: $dateStr' : ''}', style: GoogleFonts.inter(fontSize: 11, color: subTextColor)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isPaid ? _kGreen : _kOrange).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPaid ? 'PAID' : 'PENDING',
                            style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: isPaid ? _kGreen : _kOrange),
                          ),
                        ),
                        if (!isPaid) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _markGuestPaid(rawRef),
                            child: Text(
                              'Mark Paid',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kGreen),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ── HELPER WIDGETS & DIALOGS ───────────────────────────────────────────────
  Widget _infoBadge(IconData icon, String text, bool isDark, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _filterPill(String label, bool isSelected, VoidCallback onTap, Color borderColor, Color textColor, {Color? activeColor}) {
    final col = activeColor ?? _kOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? col : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? col : borderColor),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : textColor,
          ),
        ),
      ),
    );
  }

  Widget _coursePill(String label, String value, bool isDark, Color borderColor, Color textColor) {
    final isSelected = _enrollmentCourseFilter == value;
    return InkWell(
      onTap: () => setState(() => _enrollmentCourseFilter = value),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? _kOrange : (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? _kOrange : borderColor),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  void _showCourseEnrollmentsDialog(dynamic course) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderCol = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final fieldBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);

    final courseTitle = course['title'] ?? 'CTI Course';
    final courseEnrollments = _getEnrollmentsForCourse(course);
    String studentFilter = '';

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final filteredList = courseEnrollments.where((e) {
            if (studentFilter.isEmpty) return true;
            final q = studentFilter.toLowerCase();
            final name = (e['member_name']?.toString() ?? '').toLowerCase();
            final comp = (e['company']?.toString() ?? '').toLowerCase();
            final email = (e['email']?.toString() ?? '').toLowerCase();
            return name.contains(q) || comp.contains(q) || email.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.school_rounded, color: _kOrange, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(courseTitle, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Enrolled Students (${courseEnrollments.length} Total)', style: GoogleFonts.inter(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: textMuted,
                  onPressed: () => Navigator.pop(dlgCtx),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setDlgState(() => studentFilter = v.trim()),
                    style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search students by name, email, or company...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      filled: true,
                      fillColor: fieldBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filteredList.isEmpty
                        ? Center(
                            child: Text(
                              courseEnrollments.isEmpty ? 'No members enrolled yet.' : 'No matching students found.',
                              style: GoogleFonts.outfit(fontSize: 13.5, color: textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredList.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 6),
                            itemBuilder: (ctx, i) {
                              final en = filteredList[i];
                              final memberName = en['member_name'] ?? 'Member';
                              final company = en['company'] ?? 'Broker';
                              final email = en['email'] ?? '';
                              final phone = en['phone'] ?? '';
                              final amount = en['amount']?.toString() ?? '';

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: _kOrange.withValues(alpha: 0.15),
                                      child: Text(memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: _kOrange)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('$memberName • $company', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                                          Text('$email • $phone', style: GoogleFonts.inter(fontSize: 11.5, color: textMuted)),
                                        ],
                                      ),
                                    ),
                                    if (amount.isNotEmpty)
                                      Text('GHS $amount', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kGreen)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text('Close', style: GoogleFonts.outfit(color: textMuted)),
              ),
              if (courseEnrollments.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    final names = courseEnrollments.map((e) => '${e['member_name']} (${e['company'] ?? 'Broker'}) - ${e['phone']} - ${e['email']}').join('\n');
                    Clipboard.setData(ClipboardData(text: names));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Student roster copied to clipboard'),
                        backgroundColor: _kGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text('Copy Roster', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCourseDialog([dynamic existing]) async {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?['title']?.toString() ?? '');
    final dateCtrl = TextEditingController(text: existing?['start_date']?.toString() ?? '25 Aug 2026');
    final durationCtrl = TextEditingController(text: existing?['duration']?.toString() ?? '4 Weeks');
    final feeCtrl = TextEditingController(text: existing?['fee']?.toString() ?? 'GHS 1,980');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    String mode = existing?['mode']?.toString() ?? 'Hybrid';
    bool notifyMembers = true;
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.school_rounded, color: _kOrange, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEdit ? 'Edit CTI Course' : 'Add New CTI Course',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    style: GoogleFonts.outfit(fontSize: 13.5),
                    decoration: const InputDecoration(labelText: 'Course Title *', hintText: 'e.g. Freight Forwarding Fundamentals'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          style: GoogleFonts.outfit(fontSize: 13.5),
                          decoration: const InputDecoration(labelText: 'Start Date *', hintText: 'e.g. 25 Aug 2026'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: durationCtrl,
                          style: GoogleFonts.outfit(fontSize: 13.5),
                          decoration: const InputDecoration(labelText: 'Duration *', hintText: 'e.g. 4 Weeks'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: mode,
                          decoration: const InputDecoration(labelText: 'Delivery Mode'),
                          items: const [
                            DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                            DropdownMenuItem(value: 'In-Person', child: Text('In-Person Classroom')),
                            DropdownMenuItem(value: 'Online', child: Text('Online Virtual')),
                          ],
                          onChanged: (v) => setDlgState(() => mode = v ?? 'Hybrid'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: feeCtrl,
                          style: GoogleFonts.outfit(fontSize: 13.5),
                          decoration: const InputDecoration(labelText: 'Fee (GHS) *', hintText: 'e.g. GHS 1,980'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Description & Scope *'),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '🔔 Broadcast Push Notification to all Members',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kOrange),
                    ),
                    value: notifyMembers,
                    activeColor: _kOrange,
                    onChanged: (v) => setDlgState(() => notifyMembers = v ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      setDlgState(() => submitting = true);

                      final payload = {
                        'title': titleCtrl.text.trim(),
                        'start_date': dateCtrl.text.trim(),
                        'duration': durationCtrl.text.trim(),
                        'mode': mode,
                        'fee': feeCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'notify_members': notifyMembers,
                      };

                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        if (isEdit) {
                          await _api.put('/events/admin/courses/${existing['id']}', data: payload);
                        } else {
                          await _api.post('/events/admin/courses', data: payload);
                        }
                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        _fetchCourses();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(isEdit ? 'Course updated successfully!' : 'Course created and announced!'),
                            backgroundColor: _kGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        setDlgState(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating),
                        );
                      }
                    },
              child: Text(submitting ? 'Saving...' : (isEdit ? 'Save Changes' : 'Publish Course')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreCourse(dynamic course) async {
    try {
      await _api.post('/events/admin/courses/${course['id']}/restore');
      _fetchCourses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course restored to active catalog!'), backgroundColor: _kGreen, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deleteCourse(dynamic course, {bool permanent = false}) async {
    final title = permanent ? 'Permanently Delete Course?' : 'Archive Course?';
    final content = permanent
        ? 'This will permanently remove "${course['title']}". Action cannot be undone.'
        : 'Archive "${course['title']}"? It can be restored anytime from the Archived tab.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(content, style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(permanent ? 'Delete' : 'Archive'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final url = permanent
            ? '/events/admin/courses/${course['id']}?permanent=true'
            : '/events/admin/courses/${course['id']}';
        await _api.delete(url);
        _fetchCourses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(permanent ? 'Course permanently deleted.' : 'Course archived.'),
              backgroundColor: permanent ? _kRed : _kOrange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }
}
