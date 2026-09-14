import os

FILE_PATH = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_cti_courses_page.dart"

CODE = '''import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = Color(0xFFEF4444);

class AdminCtiCoursesPage extends StatefulWidget {
  const AdminCtiCoursesPage({super.key});

  @override
  State<AdminCtiCoursesPage> createState() => _AdminCtiCoursesPageState();
}

class _AdminCtiCoursesPageState extends State<AdminCtiCoursesPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _adminTabController;

  List<dynamic> _courses = [];
  List<dynamic> _enrollments = [];
  bool _loading = true;
  bool _loadingEnrollments = false;
  String? _error;
  String _searchQuery = '';
  int _filterTab = 0; // 0: All, 1: Active, 2: Archived

  @override
  void initState() {
    super.initState();
    _adminTabController = TabController(length: 2, vsync: this);
    _adminTabController.addListener(() {
      if (_adminTabController.index == 1 && _enrollments.isEmpty && !_loadingEnrollments) {
        _fetchEnrollments();
      }
    });
    _fetchCourses();
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
                          value: mode,
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
              onPressed: submitting ? null : () => Navigator.pop(dlgCtx),
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

                      try {
                        if (isEdit) {
                          await _api.put('/events/admin/courses/${existing['id']}', data: payload);
                        } else {
                          await _api.post('/events/admin/courses', data: payload);
                        }
                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        _fetchCourses();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isEdit ? 'Course updated successfully!' : 'Course created and announced to all members!',
                              ),
                              backgroundColor: _kGreen,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: _kRed),
                          );
                        }
                      }
                    },
              child: Text(submitting ? 'Saving...' : (isEdit ? 'Save Changes' : 'Publish & Announce Course')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCourseStatus(dynamic course) async {
    final newStatus = !(course['is_active'] == true);
    try {
      await _api.put('/events/admin/courses/${course['id']}', data: {'is_active': newStatus});
      _fetchCourses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  Future<void> _deleteCourse(dynamic course) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Archive CTI Course?'),
        content: Text('Are you sure you want to remove "${course['title']}" from the course catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive Course'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.delete('/events/admin/courses/${course['id']}');
        _fetchCourses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Course archived successfully.'), backgroundColor: _kOrange),
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

  @override
  Widget build(BuildContext context) {
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
            subtitle: 'Manage training course catalog, member enrollments, schedules, and automatic announcements.',
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
                  label: 'Archived / Hidden',
                  value: '$inactive',
                  icon: Icons.pause_circle_outline_rounded,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Total Enrolled',
                  value: '${_enrollments.length}',
                  icon: Icons.people_alt_outlined,
                  color: _kIndigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tabs: Course Catalog vs Enrolled Members
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withAlpha(40)),
            ),
            child: TabBar(
              controller: _adminTabController,
              indicatorColor: _kOrange,
              labelColor: _kOrange,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(icon: Icon(Icons.school_rounded, size: 16), text: 'Course Catalog & Publishing'),
                Tab(icon: Icon(Icons.people_alt_rounded, size: 16), text: 'Enrolled Members & Revenue'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          AnimatedBuilder(
            animation: _adminTabController,
            builder: (context, _) {
              if (_adminTabController.index == 0) {
                return _buildCoursesTab(total, active, inactive);
              } else {
                return _buildEnrollmentsTab();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesTab(int total, int active, int inactive) {
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
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withAlpha(40)),
            ),
            child: Column(
              children: [
                Icon(Icons.school_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('No CTI courses found.', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredCourses.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final c = _filteredCourses[i];
              final isActive = c['is_active'] == true;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.withAlpha(40)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _kOrange.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.school_rounded, color: _kOrange, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(c['title'] ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isActive ? _kGreen : Colors.grey).withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isActive ? 'ACTIVE' : 'ARCHIVED',
                                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? _kGreen : Colors.grey),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(c['description'] ?? '', style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade600)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _infoChip(Icons.calendar_today_rounded, 'Start: ${c['start_date']}'),
                              _infoChip(Icons.timelapse_rounded, 'Duration: ${c['duration']}'),
                              _infoChip(Icons.location_on_outlined, 'Mode: ${c['mode']}'),
                              _infoChip(Icons.payments_outlined, 'Fee: ${c['fee']}', color: _kOrange),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, color: isActive ? Colors.grey : _kGreen),
                          tooltip: isActive ? 'Archive Course' : 'Activate Course',
                          onPressed: () => _toggleCourseStatus(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: _kBlue),
                          tooltip: 'Edit Course',
                          onPressed: () => _showCourseDialog(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: _kRed),
                          tooltip: 'Delete Course',
                          onPressed: () => _deleteCourse(c),
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

  Widget _buildEnrollmentsTab() {
    if (_loadingEnrollments) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _kOrange)));
    }

    if (_enrollments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withAlpha(40)),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('No member course enrollments yet.', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _enrollments.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final en = _enrollments[idx];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withAlpha(40)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _kGreen.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.verified_user_rounded, color: _kGreen, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(en['member_name'] ?? 'Member', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        Text('• ${en['company'] ?? 'Licensed Broker'}', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enrolled in: ${en['course_title']} (${en['mode']})',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: _kOrange),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Payment Ref: ${en['payment_ref']} • Amount: GHS ${en['amount']} • Phone: ${en['phone'] ?? 'N/A'}',
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(6)),
                child: Text('PAID & ENROLLED', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color}) {
    final col = color ?? Colors.grey.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: col),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.inter(fontSize: 12, color: col, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
'''

with open(FILE_PATH, "w", encoding="utf-8") as f:
    f.write(CODE)

print("Updated admin_cti_courses_page.dart successfully")
