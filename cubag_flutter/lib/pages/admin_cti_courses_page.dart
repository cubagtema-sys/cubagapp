import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kRed = Color(0xFFEF4444);
const _kDarkBrown = Color(0xFF1A0F0A);
const _kCardBrown = Color(0xFF281710);
const _kBorderBrown = Color(0xFF4D2D20);

class AdminCtiCoursesPage extends StatefulWidget {
  const AdminCtiCoursesPage({super.key});

  @override
  State<AdminCtiCoursesPage> createState() => _AdminCtiCoursesPageState();
}

class _AdminCtiCoursesPageState extends State<AdminCtiCoursesPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _adminTabController;

  List<dynamic> _courses = [];
  List<dynamic> _enrollments = [];
  List<dynamic> _guestEnrollments = [];
  bool _loading = true;
  bool _loadingEnrollments = false;
  bool _loadingGuestEnrollments = false;
  String? _error;
  String _searchQuery = '';
  int _filterTab = 0; // 0: All, 1: Active, 2: Archived
  String _enrollmentCourseFilter = 'all'; // 'all' or course ID/title
  String _enrollmentSearchQuery = '';

  // Guest Enrollments tab filters
  String _guestStatusFilter = 'all'; // 'all', 'paid', 'pending'
  String _guestCourseFilter = 'all';
  String _guestSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _adminTabController = TabController(length: 3, vsync: this);
    _adminTabController.addListener(() {
      if (_adminTabController.index == 1 &&
          _enrollments.isEmpty &&
          !_loadingEnrollments) {
        _fetchEnrollments();
      } else if (_adminTabController.index == 2 &&
          _guestEnrollments.isEmpty &&
          !_loadingGuestEnrollments) {
        _fetchGuestEnrollments();
      }
    });
    _fetchCourses();
    _fetchEnrollments();
    _fetchGuestEnrollments();
  }

  @override
  void dispose() {
    _adminTabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCourses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      _fetchEnrollments();
      _fetchGuestEnrollments();
    } catch (e, st) {
      AppLogger.error('admin_cti_courses', e, st);
      if (mounted) {
        setState(() {
          _error = 'Failed to load CTI courses';
          _loading = false;
        });
      }
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
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: _kRed,
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

  void _showCourseEnrollmentsDialog(dynamic course) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? _kCardBrown : Colors.white;
    final borderCol = isDark ? _kBorderBrown : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);
    final fieldBg = isDark ? _kDarkBrown : const Color(0xFFF8FAFC);

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
            final phone = (e['phone']?.toString() ?? '').toLowerCase();
            final ref = (e['payment_ref']?.toString() ?? '').toLowerCase();
            return name.contains(q) ||
                comp.contains(q) ||
                email.contains(q) ||
                phone.contains(q) ||
                ref.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courseTitle,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enrolled Students & Course Roster (${courseEnrollments.length} Total)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _kOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.grey,
                  onPressed: () => Navigator.pop(dlgCtx),
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              height: 520,
              child: Column(
                children: [
                  // Course Summary Header Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderCol),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryCol(
                          'START DATE',
                          course['start_date'] ?? 'N/A',
                          Icons.calendar_today_rounded,
                          _kBlue,
                          textPrimary,
                        ),
                        _summaryCol(
                          'DURATION',
                          course['duration'] ?? 'N/A',
                          Icons.timelapse_rounded,
                          _kIndigo,
                          textPrimary,
                        ),
                        _summaryCol(
                          'MODE',
                          course['mode'] ?? 'Hybrid',
                          Icons.location_on_outlined,
                          _kOrange,
                          textPrimary,
                        ),
                        _summaryCol(
                          'FEE',
                          course['fee'] ?? 'Free',
                          Icons.payments_outlined,
                          _kGreen,
                          textPrimary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search box
                  TextField(
                    onChanged: (v) => setDlgState(() => studentFilter = v.trim()),
                    style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search enrolled students by name, email, or company...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                      filled: true,
                      fillColor: fieldBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Students List
                  Expanded(
                    child: filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline_rounded,
                                  size: 42,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  courseEnrollments.isEmpty
                                      ? 'No members have enrolled in this course yet.'
                                      : 'No matching students found.',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredList.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final en = filteredList[i];
                              final memberName = en['member_name'] ?? 'Enrolled Member';
                              final company = en['company'] ?? 'Licensed Brokerage';
                              final email = en['email'] ?? '';
                              final phone = en['phone'] ?? '';
                              final amount = en['amount']?.toString() ?? '';
                              final ref = en['payment_ref'] ?? '';
                              final enrolledDate = en['created_at']?.toString().split('T').first ?? '';

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: _kOrange.withAlpha(30),
                                      child: Text(
                                        memberName.isNotEmpty ? memberName[0].toUpperCase() : 'M',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: _kOrange,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                memberName,
                                                style: GoogleFonts.outfit(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                  color: textPrimary,
                                                ),
                                              ),
                                              if (company.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '• $company',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    color: textMuted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$email • $phone',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              color: textMuted,
                                            ),
                                          ),
                                          if (ref.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Ref: $ref ${enrolledDate.isNotEmpty ? '• Enrolled on $enrolledDate' : ''}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _kGreen.withAlpha(25),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: _kGreen.withAlpha(60),
                                            ),
                                          ),
                                          child: Text(
                                            'PAID & ENROLLED',
                                            style: GoogleFonts.outfit(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: _kGreen,
                                            ),
                                          ),
                                        ),
                                        if (amount.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'GHS $amount',
                                            style: GoogleFonts.outfit(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: _kOrange,
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
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text(
                  'Close',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              if (courseEnrollments.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    final names = courseEnrollments
                        .map((e) => '${e['member_name']} (${e['company'] ?? 'Broker'}) - ${e['phone']} - ${e['email']}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: names));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enrolled students roster copied to clipboard'),
                        backgroundColor: _kGreen,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: Text(
                    'Copy Student Roster',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCol(
    String label,
    String val,
    IconData icon,
    Color iconColor,
    Color textColor,
  ) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          val,
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.school_rounded, color: _kOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEdit ? 'Edit CTI Course' : 'Add New CTI Course',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add or update CUBAG Training Institute (CTI) courses displayed on the portal and mobile app.',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Course Title *',
                      hintText: 'e.g. Freight Forwarding Fundamentals',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Start Date *',
                            hintText: 'e.g. 25 Aug 2026',
                            prefixIcon: Icon(Icons.calendar_today_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: durationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Duration *',
                            hintText: 'e.g. 4 Weeks',
                            prefixIcon: Icon(Icons.timelapse_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: mode,
                          decoration: const InputDecoration(labelText: 'Delivery Mode'),
                          items: const [
                            DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid (In-Person + Online)')),
                            DropdownMenuItem(value: 'In-Person', child: Text('In-Person Classroom')),
                            DropdownMenuItem(value: 'Online', child: Text('Online Live / Virtual')),
                          ],
                          onChanged: (v) => setDlgState(() => mode = v ?? 'Hybrid'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: feeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Fee (GHS) *',
                            hintText: 'e.g. GHS 1,980',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description & Scope *',
                      hintText: 'Detailed syllabus, target audience, and certification details...',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Notify all members checkbox
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kOrange.withAlpha(50)),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '🔔 Broadcast Announcement & Push Notification to all Members',
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kOrange),
                      ),
                      subtitle: Text(
                        'Automatically sends an in-app alert, announcement post, and push notification.',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600),
                      ),
                      value: notifyMembers,
                      activeColor: _kOrange,
                      onChanged: (v) => setDlgState(() => notifyMembers = v ?? true),
                    ),
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
              style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
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
                            content: Text(
                              isEdit ? 'Course updated successfully!' : 'Course created and announced to all members!',
                            ),
                            backgroundColor: _kGreen,
                          ),
                        );
                      } catch (e) {
                        setDlgState(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: _kRed),
                        );
                      }
                    },
              child: Text(submitting ? 'Saving...' : (isEdit ? 'Save Changes' : 'Publish & Announce Course')),
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
          const SnackBar(
            content: Text('Course restored to active catalog! 🎉'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore course: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  Future<void> _deleteCourse(dynamic course, {bool permanent = false}) async {
    final title = permanent ? 'Permanently Delete CTI Course?' : 'Archive CTI Course?';
    final content = permanent
        ? 'This will permanently remove "${course['title']}" and its course record. This action cannot be undone.'
        : 'Are you sure you want to archive "${course['title']}"? It will be moved to the Archived tab and can be restored anytime.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(content, style: GoogleFonts.inter(fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(permanent ? 'Permanently Delete' : 'Archive Course'),
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
              content: Text(permanent ? 'Course permanently deleted.' : 'Course archived. You can view it in the Archived tab.'),
              backgroundColor: permanent ? _kRed : _kOrange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _kRed),
          );
        }
      }
    }
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
    final cardBg = isDark ? _kCardBrown : Colors.white;
    final borderColor = isDark ? _kBorderBrown : const Color(0xFFE2E8F0);

    final total = _courses.length;
    final active = _courses.where((c) => c['is_active'] == true).length;
    final inactive = total - active;

    return AppLayout(
      title: 'CTI Courses Admin',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'CUBAG Training Institute (CTI) Courses',
            subtitle: 'Manage training course catalog, view enrolled members & guest applicants, schedules, and fee receipts.',
            actions: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _showCourseDialog(),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text('Add New Course', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Metric Stats Cards
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Courses',
                  value: '$total',
                  icon: Icons.school_outlined,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Active Courses',
                  value: '$active',
                  icon: Icons.check_circle_outline_rounded,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Member Enrolled',
                  value: '${_enrollments.length}',
                  icon: Icons.people_alt_outlined,
                  color: _kIndigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Guest Enrolled',
                  value: '${_guestEnrollments.length}',
                  icon: Icons.person_pin_circle_outlined,
                  color: _kOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tabs: Course Catalog vs Enrolled Members vs Guest Enrollments
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: TabBar(
              controller: _adminTabController,
              indicatorColor: _kOrange,
              labelColor: _kOrange,
              unselectedLabelColor: Colors.grey,
              tabs: [
                const Tab(icon: Icon(Icons.school_rounded, size: 16), text: 'Course Catalog & Publishing'),
                Tab(icon: const Icon(Icons.people_alt_rounded, size: 16), text: 'Member Enrolled (${_enrollments.length})'),
                Tab(icon: const Icon(Icons.person_pin_rounded, size: 16), text: 'Guest Enrolled & Paid (${_guestEnrollments.length})'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          AnimatedBuilder(
            animation: _adminTabController,
            builder: (context, _) {
              if (_adminTabController.index == 0) {
                return _buildCoursesTab(total, active, inactive, isDark, cardBg, borderColor);
              } else if (_adminTabController.index == 1) {
                return _buildEnrollmentsTab(isDark, cardBg, borderColor);
              } else {
                return _buildGuestEnrollmentsTab(isDark, cardBg, borderColor);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesTab(
    int total,
    int active,
    int inactive,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Filter controls
        AdminToolbar(
          searchHint: 'Search courses by title, delivery mode, or keywords...',
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          filters: [
            AdminFilterChip(
              label: 'All Courses',
              count: total,
              isSelected: _filterTab == 0,
              onTap: () => setState(() => _filterTab = 0),
            ),
            AdminFilterChip(
              label: 'Active',
              count: active,
              isSelected: _filterTab == 1,
              onTap: () => setState(() => _filterTab = 1),
              selectedColor: kAdminGreen,
            ),
            AdminFilterChip(
              label: 'Archived',
              count: inactive,
              isSelected: _filterTab == 2,
              onTap: () => setState(() => _filterTab = 2),
              selectedColor: Colors.grey.shade700,
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: _kOrange)),
          )
        else if (_error != null)
          Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
        else if (_filteredCourses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.school_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'No CTI courses found.',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredCourses.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (ctx, i) {
              final c = _filteredCourses[i];
              final isActive = c['is_active'] == true;
              final enrolledList = _getEnrollmentsForCourse(c);
              final enrolledCount = enrolledList.length;

              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
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
                            color: _kOrange.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.school_rounded, color: _kOrange, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c['title'] ?? '',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16.5,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (isActive ? _kGreen : Colors.grey).withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: (isActive ? _kGreen : Colors.grey).withAlpha(60),
                                      ),
                                    ),
                                    child: Text(
                                      isActive ? 'ACTIVE' : 'ARCHIVED',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? _kGreen : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                c['description'] ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: textMuted,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  _infoChip(Icons.calendar_today_rounded, 'Start: ${c['start_date']}', isDark),
                                  _infoChip(Icons.timelapse_rounded, 'Duration: ${c['duration']}', isDark),
                                  _infoChip(Icons.location_on_outlined, 'Mode: ${c['mode']}', isDark),
                                  _infoChip(Icons.payments_outlined, 'Fee: ${c['fee']}', isDark, color: _kOrange),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: borderColor, height: 1),
                    const SizedBox(height: 12),

                    // Actions & Enrolled Students button
                    Row(
                      children: [
                        // View Enrolled Button
                        OutlinedButton.icon(
                          onPressed: () => _showCourseEnrollmentsDialog(c),
                          icon: Icon(
                            Icons.people_alt_rounded,
                            size: 16,
                            color: enrolledCount > 0 ? _kGreen : _kOrange,
                          ),
                          label: Text(
                            enrolledCount == 1
                                ? '1 Enrolled Student'
                                : '$enrolledCount Enrolled Students',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: enrolledCount > 0 ? _kGreen : _kOrange,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: (enrolledCount > 0 ? _kGreen : _kOrange).withAlpha(120),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const Spacer(),

                        // Actions
                        if (!isActive) ...[
                          // Restore button for archived courses
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.restore_from_trash_rounded, size: 16),
                            label: Text(
                              'Restore',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            onPressed: () => _restoreCourse(c),
                          ),
                          const SizedBox(width: 6),
                          // Edit
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: _kBlue, size: 20),
                            tooltip: 'Edit Course',
                            onPressed: () => _showCourseDialog(c),
                          ),
                          // Permanent Delete
                          IconButton(
                            icon: const Icon(Icons.delete_forever_rounded, color: _kRed, size: 20),
                            tooltip: 'Permanently Delete',
                            onPressed: () => _deleteCourse(c, permanent: true),
                          ),
                        ] else ...[
                          // Edit
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: _kBlue, size: 20),
                            tooltip: 'Edit Course',
                            onPressed: () => _showCourseDialog(c),
                          ),
                          // Archive
                          IconButton(
                            icon: const Icon(Icons.archive_outlined, color: _kOrange, size: 20),
                            tooltip: 'Archive Course',
                            onPressed: () => _deleteCourse(c),
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

  Widget _buildEnrollmentsTab(bool isDark, Color cardBg, Color borderColor) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);
    final fieldBg = isDark ? _kDarkBrown : const Color(0xFFF8FAFC);

    if (_loadingEnrollments) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    final filteredList = _filteredEnrollments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Course Filter Dropdown & Search Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.filter_list_rounded, color: _kOrange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'FILTER ENROLLMENTS BY COURSE',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _kOrange,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Course Selector Pills / Dropdown
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _courseFilterPill(
                    'All Courses (${_enrollments.length})',
                    'all',
                    isDark,
                  ),
                  ..._courses.map((c) {
                    final cId = c['id']?.toString() ?? '';
                    final cTitle = c['title'] ?? 'Course';
                    final count = _getEnrollmentsForCourse(c).length;
                    return _courseFilterPill(
                      '$cTitle ($count)',
                      cId,
                      isDark,
                    );
                  }),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                onChanged: (v) => setState(() => _enrollmentSearchQuery = v.trim()),
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search enrolled students by name, company, email, or payment ref...',
                  hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (filteredList.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  _enrollmentCourseFilter != 'all'
                      ? 'No members have enrolled in this selected course yet.'
                      : 'No member course enrollments found.',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredList.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final en = filteredList[idx];
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kGreen.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: _kGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                memberName,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '• $company',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enrolled in: $courseTitle ($mode)',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kOrange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ref: $paymentRef • GHS $amount • Phone: $phone • Email: $email ${enrolledDate.isNotEmpty ? '• Date: $enrolledDate' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PAID & ENROLLED',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _courseFilterPill(String label, String value, bool isDark) {
    final isSelected = _enrollmentCourseFilter == value;
    return InkWell(
      onTap: () => setState(() => _enrollmentCourseFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _kOrange
              : (isDark ? _kDarkBrown : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _kOrange
                : (isDark ? _kBorderBrown : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, bool isDark, {Color? color}) {
    final col = color ?? (isDark ? Colors.white70 : const Color(0xFF475569));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? (isDark ? Colors.white : Colors.black)).withAlpha(isDark ? 20 : 10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: col),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: col,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestEnrollmentsTab(
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);
    final fieldBg = isDark ? _kDarkBrown : const Color(0xFFF8FAFC);
    final borderCol = isDark ? _kBorderBrown : const Color(0xFFE2E8F0);

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
        // Controls container (search + filters + copy roster)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _guestSearchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search guest name, phone, email, CTI reference, or course...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: fieldBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Refresh Guest Enrollments',
                    onPressed: _fetchGuestEnrollments,
                    icon: const Icon(Icons.refresh_rounded),
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
                            content: Text('Guest enrollment roster copied to clipboard!'),
                            backgroundColor: _kGreen,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text('Copy Roster', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // Status filters
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _guestStatusFilterChip('All Status ($totalGuests)', 'all', isDark),
                  _guestStatusFilterChip('Paid ($paidGuests)', 'paid', isDark),
                  _guestStatusFilterChip('Pending ($pendingGuests)', 'pending', isDark),
                ],
              ),
              const SizedBox(height: 10),

              // Course filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _guestCourseFilterChip('All Courses', 'all', isDark),
                    ..._courses.map((c) {
                      final cTitle = c['title']?.toString() ?? 'Course';
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _guestCourseFilterChip(cTitle, cTitle, isDark),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List of guest records
        if (_loadingGuestEnrollments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.person_search_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'No guest course enrollments found.',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'When guests register for courses from the landing page, their payments & references will appear here.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final g = filtered[i];
              final name = g['guest_name']?.toString() ?? 'Guest Student';
              final phone = g['phone']?.toString() ?? '';
              final email = g['email']?.toString() ?? '';
              final company = g['company']?.toString() ?? 'Guest Student / Applicant';
              final course = g['course_title']?.toString() ?? 'CTI Professional Course';
              final rawRef = g['reference_no']?.toString() ?? '';
              final ctiRef = rawRef.replaceAll('GSR-', 'CTI-');
              final amount = g['amount']?.toString() ?? '1500.00';
              final network = g['payment_network']?.toString() ?? 'Mobile Money';
              final status = (g['status']?.toString() ?? 'paid').toLowerCase();
              final isPaid = status == 'paid' || status == 'completed' || status == 'success';
              final dateStr = g['created_at']?.toString().split('T').first ?? '';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isPaid ? _kGreen.withAlpha(25) : _kOrange.withAlpha(25),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'G',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isPaid ? _kGreen : _kOrange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _kIndigo.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'GUEST ENROLLMENT',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: _kIndigo,
                                  ),
                                ),
                              ),
                              if (company.isNotEmpty && company != 'Guest Student') ...[
                                const SizedBox(width: 6),
                                Text(
                                  '• $company',
                                  style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '📚 Course: $course',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kOrange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              if (phone.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone_rounded, size: 13, color: textMuted),
                                    const SizedBox(width: 4),
                                    Text(phone, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                  ],
                                ),
                              if (email.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.email_outlined, size: 13, color: textMuted),
                                    const SizedBox(width: 4),
                                    Text(email, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                  ],
                                ),
                              if (network.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.payment_rounded, size: 13, color: textMuted),
                                    const SizedBox(width: 4),
                                    Text(network, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                  ],
                                ),
                              if (dateStr.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 12, color: textMuted),
                                    const SizedBox(width: 4),
                                    Text(dateStr, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'CTI Ref: $ctiRef',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: _kOrange,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: ctiRef));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('$ctiRef copied to clipboard!'),
                                            backgroundColor: _kGreen,
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                      child: const Icon(Icons.copy_rounded, size: 13, color: _kOrange),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Fee: GHS $amount',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPaid ? _kGreen.withAlpha(25) : _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPaid ? _kGreen.withAlpha(60) : _kOrange.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPaid ? Icons.check_circle_rounded : Icons.pending_rounded,
                                size: 13,
                                color: isPaid ? _kGreen : _kOrange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPaid ? 'PAID & ENROLLED' : 'PENDING APPROVAL',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPaid ? _kGreen : _kOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isPaid) ...[
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _markGuestPaid(rawRef),
                            icon: const Icon(Icons.check_rounded, size: 14),
                            label: Text('Mark Paid', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _guestStatusFilterChip(String label, String value, bool isDark) {
    final isSelected = _guestStatusFilter == value;
    return InkWell(
      onTap: () => setState(() => _guestStatusFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _kOrange
              : (isDark ? _kDarkBrown : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _kOrange
                : (isDark ? _kBorderBrown : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _guestCourseFilterChip(String label, String value, bool isDark) {
    final isSelected = _guestCourseFilter == value;
    return InkWell(
      onTap: () => setState(() => _guestCourseFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _kIndigo
              : (isDark ? _kDarkBrown : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _kIndigo
                : (isDark ? _kBorderBrown : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }
}
