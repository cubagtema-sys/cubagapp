import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);

class AdminTasksPage extends StatefulWidget {
  const AdminTasksPage({super.key});
  @override
  State<AdminTasksPage> createState() => _State();
}

class _State extends State<AdminTasksPage> {
  final _api = ApiService();
  List<dynamic> _tasks = [];
  List<dynamic> _members = [];
  bool _loading = true;
  bool _hasError = false;
  bool _loadingMore = false;
  String _tab = 'submissions';
  String _message = '';

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  // Create form
  String _memberId = '';
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _dueDate = '';

  // Verify state
  int? _verifyingId;
  final Map<int, String> _verifyNotes = {};
  final Map<int, TextEditingController> _verifyCtrl = {};

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _fetchTasks();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && _hasMore && _tab != 'create') {
        _fetchMore();
      }
    }
  }

  Future<void> _fetchMembers() async {
    try {
      final res = await _api.fetchData('members');
      if (mounted && res is List) setState(() => _members = res);
    } catch (e, st) {
      AppLogger.error('admin_tasks_page', e, st);
    }
  }

  Future<void> _fetchTasks({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _loading = true;
        _tasks = [];
      });
    } else {
      if (!_loading) setState(() => _loading = true);
    }

    final fetchTab = _tab;
    await _api.fetchDataWithCache(
      '/tasks/admin/all?page=$_page&per_page=20&status=$fetchTab',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (_tab != fetchTab) return;
        if (hasError && _tasks.isEmpty) {
          setState(() {
            _loading = false;
            _hasError = true;
          });
          return;
        }
        if (data == null) {
          setState(() => _loading = false);
          return;
        }
        final d = data as Map<String, dynamic>;
        setState(() {
          _loading = false;
          _hasError = false;
          _tasks = ApiService.ensureList(d);
          if (d.containsKey('total')) {
            _total = d['total'];
            _hasMore = _tasks.length < _total;
          } else {
            _hasMore = false;
          }
        });
      },
    );
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final res = await _api.get(
        '/tasks/admin/all?page=$_page&per_page=20&status=$_tab',
      );
      if (res.statusCode == 200) {
        final d = res.data as Map<String, dynamic>;
        final newItems = ApiService.ensureList(d);
        setState(() {
          _tasks.addAll(newItems);
          if (d.containsKey('total')) {
            _hasMore = _tasks.length < d['total'];
          } else {
            _hasMore = newItems.isNotEmpty;
          }
        });
      }
    } catch (_) {
      _page--;
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _onTabChanged(String newTab) {
    if (_tab == newTab) return;
    setState(() => _tab = newTab);
    if (newTab != 'create') {
      _fetchTasks(refresh: true);
    }
  }

  Future<void> _assignTask() async {
    if (_titleCtrl.text.isEmpty || _dueDate.isEmpty) return;
    setState(() => _loading = true);
    await _api.postData('tasks/admin/create', {
      'title': _titleCtrl.text,
      'description': _descCtrl.text,
      'due_date': _dueDate,
      'member_id': _memberId,
    });
    _titleCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _dueDate = '';
      _memberId = '';
      _loading = false;
      _message = 'Task successfully assigned.';
    });
    if (_tab != 'create') {
      await _fetchTasks(refresh: true);
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _message = '');
    });
  }

  Future<void> _verify(int submissionId) async {
    await _api.patchData('tasks/admin/$submissionId/verify', {
      'admin_notes': _verifyNotes[submissionId] ?? '',
    });
    setState(() => _verifyingId = null);
    await _fetchTasks(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      {'id': 'submissions', 'label': 'Submissions'},
      {'id': 'pending', 'label': 'Pending'},
      {'id': 'verified', 'label': 'Verified'},
      {'id': 'create', 'label': 'Assign New Task'},
    ];
    return AppLayout(
      title: 'Compliance Control',
      scrollable: false,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeader(
              title: 'Compliance Directives & Member Tasks',
              subtitle:
                  'Assign mandatory filings, review member evidence submissions, and verify regulatory compliance.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (_tab == 'create') {
                      _onTabChanged('submissions');
                    } else {
                      _onTabChanged('create');
                    }
                  },
                  icon: Icon(
                    _tab == 'create'
                        ? Icons.list_alt_rounded
                        : Icons.add_task_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _tab == 'create' ? 'View Submissions' : 'Assign New Task',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Tab bar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF281710)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: tabs.map((t) {
                  final active = _tab == t['id'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onTabChanged(t['id']!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? kAdminOrange : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t['label']!,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            if (_message.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _message,
                  style: const TextStyle(
                    color: _kGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            if (_tab == 'create') _buildCreate(),
            if (_tab != 'create') _buildTaskList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreate() => Container(
    constraints: const BoxConstraints(maxWidth: 600),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'New Assignment',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 16),
        const Text(
          'Assign To',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        CustomDropdown<String>(
          value: _memberId,
          hint: 'Select a member...',
          items: [
            const DropdownItem(value: 'all', label: 'All Active Members'),
            ..._members.map(
              (m) => DropdownItem<String>(
                value: m['id'].toString(),
                label: m['name'] ?? '',
              ),
            ),
          ],
          onChanged: (v) => setState(() => _memberId = v),
        ),
        const SizedBox(height: 14),
        const Text(
          'Task Title',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _titleCtrl,
          decoration: _deco(hint: 'Title...'),
        ),
        const SizedBox(height: 14),
        const Text(
          'Due Date',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime(2099),
            );
            if (picked != null) {
              setState(
                () => _dueDate =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _dueDate.isEmpty ? 'Pick date' : _dueDate,
                  style: TextStyle(
                    color: _dueDate.isEmpty
                        ? Colors.grey.shade600
                        : Colors.black,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Instructions',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 4,
          decoration: _deco(hint: 'Task details...'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _assignTask,
            icon: const Icon(Icons.send),
            label: const Text(
              'Assign Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildTaskList() {
    if (_loading) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (ctx, i) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => const ShimmerListTile(),
      );
    }
    if (_hasError && _tasks.isEmpty) {
      return FetchErrorView(onRetry: () => _fetchTasks(refresh: true));
    }
    if (_tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No tasks found.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: [
        ..._tasks.map((task) {
          final sid = task['submission_id'] as int?;
          if (sid != null) {
            _verifyCtrl.putIfAbsent(sid, () => TextEditingController());
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  color: task['admin_verified'] == true
                      ? _kGreen.withAlpha(12)
                      : (sid != null
                            ? _kOrange.withAlpha(8)
                            : Colors.grey.shade50),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task['title'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: _kOrange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  task['member_name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    color: _kOrange,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Due: ${task['due_date'] ?? ''}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (task['admin_verified'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _kGreen.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Verified',
                            style: TextStyle(
                              color: _kGreen,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else if (sid != null)
                        ElevatedButton(
                          onPressed: () => setState(
                            () =>
                                _verifyingId = _verifyingId == sid ? null : sid,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Verify',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (task['completion_note'] != null &&
                    task['completion_note'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MEMBER NOTE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          task['completion_note'],
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                if (_verifyingId == sid && sid != null)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Admin Notes (optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        TextField(
                          controller: _verifyCtrl[sid],
                          maxLines: 2,
                          onChanged: (v) => _verifyNotes[sid] = v,
                          decoration: _deco(
                            hint: 'Any notes for the member...',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: () => _verify(sid),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(140, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Confirm Verified',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _verifyingId = null),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),
        if (_loadingMore)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!_loading && _total > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '${_tasks.length} tasks shown${_total > 0 ? " of $_total" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _deco({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748b)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kOrange, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red, width: 2),
    ),
  );
}
