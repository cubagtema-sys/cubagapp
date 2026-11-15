import '../components/admin_dialog.dart';
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
    final courseTitle = (course['title'] ?? 'Course').toString();
    final enrolments = _getEnrollmentsForCourse(course);
    String query = '';

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final q = query.toLowerCase();
          final list = enrolments.where((e) {
            if (q.isEmpty) return true;
            return [e['member_name'], e['company'], e['email']].any((v) => (v ?? '').toString().toLowerCase().contains(q));
          }).toList();

          return AdminDialog(
            title: courseTitle,
            subtitle: enrolments.length == 1 ? '1 member enrolled' : '${enrolments.length} members enrolled',
            maxWidth: 640,
            actions: [
              if (enrolments.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    final text = enrolments
                        .map((e) => '${e['member_name']} (${e['company'] ?? 'Member'}) - ${e['phone'] ?? ''} - ${e['email'] ?? ''}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('List copied'), behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy list'),
                ),
              FilledButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Done')),
            ],
            children: [
              if (enrolments.isNotEmpty) ...[
                AdminSearchField(hint: 'Search name, company or email', onChanged: (v) => setDlgState(() => query = v.trim())),
                const SizedBox(height: CubagSpace.md),
              ],
              if (list.isEmpty)
                EmptyMessage(
                  icon: Icons.people_outline_rounded,
                  title: enrolments.isEmpty ? 'No one enrolled yet' : 'No one matches',
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
                          if ((en['company'] ?? '').toString().isNotEmpty) en['company'].toString(),
                          if ((en['email'] ?? '').toString().isNotEmpty) en['email'].toString(),
                        ].join(' · '),
                        meta: (en['phone'] ?? '').toString(),
                        status: (en['amount'] ?? '').toString().isEmpty
                            ? null
                            : Text('GH₵ ${en['amount']}', style: CubagType.small.copyWith(color: CubagColors.ink)),
                      ),
                  ],
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
    final dateCtrl = TextEditingController(text: existing?['start_date']?.toString() ?? '');
    final durationCtrl = TextEditingController(text: existing?['duration']?.toString() ?? '');
    final feeCtrl = TextEditingController(text: existing?['fee']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    String mode = existing?['mode']?.toString() ?? 'Hybrid';
    if (!const ['Hybrid', 'In-Person', 'Online'].contains(mode)) mode = 'Hybrid';
    bool notifyMembers = !isEdit;
    bool submitting = false;
    String? error;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          Future<void> submit() async {
            if (titleCtrl.text.trim().isEmpty) {
              setDlgState(() => error = 'Add the course name.');
              return;
            }
            setDlgState(() {
              submitting = true;
              error = null;
            });
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
              messenger.showSnackBar(SnackBar(
                content: Text(isEdit ? 'Course updated.' : 'Course published.'),
                behavior: SnackBarBehavior.floating,
              ));
            } catch (e) {
              setDlgState(() {
                submitting = false;
                error = 'Could not save the course. Try again.';
              });
            }
          }

          return AdminDialog(
            title: isEdit ? 'Edit course' : 'New course',
            subtitle: 'Members can read about it, enrol and pay in the app.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(submitting ? 'Saving…' : (isEdit ? 'Save changes' : 'Publish course')),
              ),
            ],
            children: [
              AdminField(
                label: 'Course name',
                child: TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: 'For example: Customs declarations and ICUMS'),
                ),
              ),
              AdminFieldPair(
                AdminField(
                  label: 'Starts',
                  child: TextField(controller: dateCtrl, decoration: const InputDecoration(hintText: 'For example: 25 Aug 2026')),
                ),
                AdminField(
                  label: 'Length',
                  child: TextField(controller: durationCtrl, decoration: const InputDecoration(hintText: 'For example: 4 weeks')),
                ),
              ),
              AdminField(
                label: 'How it is taught',
                child: AdminChoice<String>(
                  options: const [('Hybrid', 'Hybrid'), ('In-Person', 'In person'), ('Online', 'Online')],
                  value: mode,
                  onChanged: (v) => setDlgState(() => mode = v),
                ),
              ),
              AdminField(
                label: 'Fee',
                help: 'Shown to members as written.',
                child: TextField(controller: feeCtrl, decoration: const InputDecoration(hintText: 'For example: GHS 1,980')),
              ),
              AdminField(
                label: 'About the course (optional)',
                child: TextField(
                  controller: descCtrl,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'What it covers and who it is for'),
                ),
              ),
              AdminSwitchRow(
                title: 'Tell all members',
                subtitle: 'Sends a notification when you save.',
                value: notifyMembers,
                onChanged: (v) => setDlgState(() => notifyMembers = v),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
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
    final confirm = await showAdminConfirm(context, title: permanent ? 'Delete this course for good?' : 'Archive this course?', message: permanent ? '"${course['title']}" is removed and cannot be brought back.' : '"${course['title']}" is hidden from members. You can restore it from Archived.', confirmLabel: permanent ? 'Delete for good' : 'Archive', destructive: true);

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
