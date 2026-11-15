import '../components/custom_dropdown.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

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
    final total = _courses.length;
    final active = _courses.where((c) => c['is_active'] == true).length;
    final tab = _tabController.index;

    return AppLayout(
      title: 'Courses',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Courses',
                subtitle: 'Courses from the CUBAG Training Institute, and the members and guests who enrolled.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _fetchAll,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showCourseDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New course'),
                  ),
                ],
              ),
              FilterTabs(
                tabs: [
                  ('0', 'Courses · $total'),
                  ('1', 'Members · ${_enrollments.length}'),
                  ('2', 'Guests · ${_guestEnrollments.length}'),
                ],
                selected: '$tab',
                onSelected: (k) => setState(() => _tabController.index = int.parse(k)),
              ),
              const SizedBox(height: CubagSpace.md),
              if (tab == 0) ..._coursesView(total, active),
              if (tab == 1) ..._membersView(),
              if (tab == 2) ..._guestsView(),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingList() => Column(
        children: List.generate(
          3,
          (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
        ),
      );

  List<Widget> _coursesView(int total, int active) {
    final courses = _filteredCourses;
    return [
      AdminFigureStrip(figures: [
        AdminFigure('All', '$total', selected: _filterTab == 0, onTap: () => setState(() => _filterTab = 0)),
        AdminFigure('Open for enrolment', '$active', selected: _filterTab == 1, onTap: () => setState(() => _filterTab = 1)),
        AdminFigure('Archived', '${total - active}', selected: _filterTab == 2, onTap: () => setState(() => _filterTab = 2)),
      ]),
      const SizedBox(height: CubagSpace.md),
      AdminSearchField(hint: 'Search courses', onChanged: (v) => setState(() => _searchQuery = v)),
      const SizedBox(height: CubagSpace.md),
      if (_loading)
        _loadingList()
      else if (courses.isEmpty)
        EmptyMessage(
          icon: Icons.school_outlined,
          title: total == 0 ? 'No courses yet' : 'No courses match',
          message: total == 0
              ? 'Add a course and members can enrol and pay from the app.'
              : 'Try another filter, or clear the search.',
        )
      else
        AdminRowGroup(dividerIndent: 68, children: [for (final c in courses) _courseRow(c)]),
    ];
  }

  Widget _courseRow(dynamic c) {
    final isActive = c['is_active'] == true;
    final enrolled = _getEnrollmentsForCourse(c).length;
    final fee = '${c['fee'] ?? ''}'.trim();
    return AdminListRow(
      leading: AdminRowMark(icon: Icons.school_outlined, color: isActive ? CubagColors.cocoa : CubagColors.muted),
      title: c['title']?.toString() ?? '',
      subtitle: [
        if ((c['start_date'] ?? '').toString().isNotEmpty) 'Starts ${c['start_date']}',
        if ((c['duration'] ?? '').toString().isNotEmpty) '${c['duration']}',
        if ((c['mode'] ?? '').toString().isNotEmpty) '${c['mode']}',
      ].join(' · '),
      meta: [
        fee.isEmpty || fee == '0' ? 'Free' : (fee.contains('GH') ? fee : 'GH₵ $fee'),
        enrolled == 1 ? '1 member enrolled' : '$enrolled members enrolled',
      ].join(' · '),
      status: isActive ? const StatusChip('Open', kind: StatusKind.good) : const StatusChip('Archived'),
      onTap: () => _showCourseEnrollmentsDialog(c),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
        onSelected: (v) {
          switch (v) {
            case 'enrolled':
              _showCourseEnrollmentsDialog(c);
            case 'edit':
              _showCourseDialog(c);
            case 'archive':
              _deleteCourse(c);
            case 'restore':
              _restoreCourse(c);
            case 'delete':
              _deleteCourse(c, permanent: true);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'enrolled', child: Text('Who enrolled')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (isActive)
            const PopupMenuItem(value: 'archive', child: Text('Archive'))
          else ...[
            const PopupMenuItem(value: 'restore', child: Text('Restore')),
            PopupMenuItem(value: 'delete', child: Text('Delete for good', style: TextStyle(color: CubagColors.lapsed))),
          ],
        ],
      ),
    );
  }

  Widget _courseFilter(String selected, ValueChanged<String> onChanged) => SizedBox(
        width: 240,
        child: CustomDropdown<String>(
          value: selected,
          items: [
            const DropdownItem(value: 'all', label: 'All courses'),
            for (final c in _courses)
              DropdownItem(value: (c['title'] ?? '').toString(), label: (c['title'] ?? 'Course').toString()),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _searchAndCourse(String hint, ValueChanged<String> onSearch, Widget course) => LayoutBuilder(
        builder: (context, c) {
          final search = AdminSearchField(hint: hint, onChanged: onSearch);
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: CubagSpace.xs), course],
            );
          }
          return Row(children: [Expanded(child: search), const SizedBox(width: CubagSpace.sm), course]);
        },
      );

  List<Widget> _membersView() {
    final list = _filteredEnrollments;
    final courseKey = _enrollmentCourseFilter == 'all'
        ? 'all'
        : (_courses.firstWhere(
              (c) => c['id']?.toString() == _enrollmentCourseFilter,
              orElse: () => {'title': 'all'},
            )['title'] ??
            'all').toString();
    return [
      _searchAndCourse(
        'Search name, company or reference',
        (v) => setState(() => _enrollmentSearchQuery = v),
        _courseFilter(courseKey, (title) {
          setState(() {
            _enrollmentCourseFilter = title == 'all'
                ? 'all'
                : (_courses.firstWhere((c) => (c['title'] ?? '').toString() == title, orElse: () => {'id': 'all'})['id'] ?? 'all')
                    .toString();
          });
        }),
      ),
      const SizedBox(height: CubagSpace.md),
      if (_loadingEnrollments)
        _loadingList()
      else if (list.isEmpty)
        const EmptyMessage(
          icon: Icons.people_outline_rounded,
          title: 'No members enrolled',
          message: 'Members who enrol and pay in the app appear here.',
        )
      else
        AdminRowGroup(
          dividerIndent: 68,
          children: [
            for (final en in list)
              AdminListRow(
                leading: AdminRowMark(initials: adminInitials((en['member_name'] ?? '').toString())),
                title: (en['member_name'] ?? 'Member').toString(),
                subtitle: [
                  (en['course_title'] ?? 'Course').toString(),
                  if ((en['company'] ?? '').toString().isNotEmpty) en['company'].toString(),
                ].join(' · '),
                meta: [
                  'GH₵ ${en['amount'] ?? '0.00'}',
                  if ((en['payment_ref'] ?? '').toString().isNotEmpty) 'Ref ${en['payment_ref']}',
                  if ((en['created_at'] ?? '').toString().isNotEmpty) en['created_at'].toString().split('T').first,
                ].join(' · '),
                status: const StatusChip('Paid', kind: StatusKind.good),
              ),
          ],
        ),
    ];
  }

  List<Widget> _guestsView() {
    final filtered = _filteredGuestEnrollments;
    bool paid(dynamic e) => const {'paid', 'completed', 'success'}.contains((e['status'] ?? '').toString().toLowerCase());
    final totalGuests = _guestEnrollments.length;
    final paidGuests = _guestEnrollments.where(paid).length;

    return [
      AdminFigureStrip(figures: [
        AdminFigure('All guests', '$totalGuests', selected: _guestStatusFilter == 'all', onTap: () => setState(() => _guestStatusFilter = 'all')),
        AdminFigure('Paid', '$paidGuests', color: CubagColors.valid, selected: _guestStatusFilter == 'paid', onTap: () => setState(() => _guestStatusFilter = 'paid')),
        AdminFigure(
          'Not paid yet',
          '${totalGuests - paidGuests}',
          color: totalGuests - paidGuests > 0 ? CubagColors.due : null,
          selected: _guestStatusFilter == 'pending',
          onTap: () => setState(() => _guestStatusFilter = 'pending'),
        ),
      ]),
      const SizedBox(height: CubagSpace.md),
      _searchAndCourse(
        'Search name, phone or reference',
        (v) => setState(() => _guestSearchQuery = v),
        _courseFilter(_guestCourseFilter, (t) => setState(() => _guestCourseFilter = t)),
      ),
      const SizedBox(height: CubagSpace.md),
      if (_loadingGuestEnrollments)
        _loadingList()
      else if (filtered.isEmpty)
        const EmptyMessage(
          icon: Icons.person_outline_rounded,
          title: 'No guest enrolments',
          message: 'People who are not members can enrol from the public course page. They appear here.',
        )
      else ...[
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              final roster = filtered.map((e) {
                return '${e['guest_name'] ?? 'Guest'} | ${e['phone'] ?? ''} | ${e['email'] ?? ''} | '
                    'Course: ${e['course_title'] ?? ''} | Ref: ${e['reference_no'] ?? ''} | Status: ${e['status'] ?? ''}';
              }).join('\n');
              Clipboard.setData(ClipboardData(text: roster));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Guest list copied'), behavior: SnackBarBehavior.floating),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy this list'),
          ),
        ),
        AdminRowGroup(
          dividerIndent: 68,
          children: [
            for (final g in filtered)
              () {
                final rawRef = g['reference_no']?.toString() ?? '';
                final isPaid = paid(g);
                return AdminListRow(
                  leading: AdminRowMark(initials: adminInitials((g['guest_name'] ?? '').toString())),
                  title: (g['guest_name'] ?? 'Guest').toString(),
                  subtitle: [
                    (g['course_title'] ?? 'Course').toString(),
                    'GH₵ ${g['amount'] ?? '—'}',
                  ].join(' · '),
                  meta: [
                    if (rawRef.isNotEmpty) rawRef.replaceAll('GSR-', 'CTI-'),
                    if ((g['phone'] ?? '').toString().isNotEmpty) g['phone'].toString(),
                    if ((g['created_at'] ?? '').toString().isNotEmpty) g['created_at'].toString().split('T').first,
                  ].join(' · '),
                  status: isPaid
                      ? const StatusChip('Paid', kind: StatusKind.good)
                      : const StatusChip('Not paid', kind: StatusKind.pending),
                  trailing: isPaid
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(left: CubagSpace.xs),
                          child: OutlinedButton(
                            onPressed: rawRef.isEmpty ? null : () => _markGuestPaid(rawRef),
                            child: const Text('Mark paid'),
                          ),
                        ),
                );
              }(),
          ],
        ),
      ],
    ];
  }

  void _showCourseEnrollmentsDialog(dynamic course) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderCol = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F1612);
    final textMuted = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);
    final fieldBg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);

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
                      Text(courseTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Enrolled Students (${courseEnrollments.length} Total)', style: TextStyle(fontSize: 12, color: AppColors.accentOrangeText, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
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
                    style: TextStyle(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search students',
                      hintStyle: TextStyle(fontSize: 12.5, color: textMuted),
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
                              style: TextStyle(fontSize: 13.5, color: textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredList.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 6),
                            itemBuilder: (ctx, i) {
                              final en = filteredList[i];
                              final memberName = en['member_name'] ?? 'Member';
                              final company = en['company'] ?? 'Member';
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
                                      child: Text(memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.accentOrangeText)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('$memberName • $company', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                                          Text('$email • $phone', style: TextStyle(fontSize: 11.5, color: textMuted)),
                                        ],
                                      ),
                                    ),
                                    if (amount.isNotEmpty)
                                      Text('GHS $amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kGreen)),
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
                child: Text('Close', style: TextStyle(color: textMuted)),
              ),
              if (courseEnrollments.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    final names = courseEnrollments.map((e) => '${e['member_name']} (${e['company'] ?? 'Member'}) - ${e['phone']} - ${e['email']}').join('\n');
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
                  label: Text('Copy Roster', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                    style: TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(labelText: 'Course Title *', hintText: 'e.g. Freight Forwarding Fundamentals'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          style: TextStyle(fontSize: 13.5),
                          decoration: const InputDecoration(labelText: 'Start Date *', hintText: 'e.g. 25 Aug 2026'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: durationCtrl,
                          style: TextStyle(fontSize: 13.5),
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
                          style: TextStyle(fontSize: 13.5),
                          decoration: const InputDecoration(labelText: 'Fee (GHS) *', hintText: 'e.g. GHS 1,980'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Description & Scope *'),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '🔔 Broadcast Push Notification to all Members',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentOrangeText),
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
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(content, style: TextStyle(fontSize: 13)),
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
