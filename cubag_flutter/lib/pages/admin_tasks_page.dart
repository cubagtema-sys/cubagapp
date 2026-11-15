import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';


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
  String _tab = 'submitted';
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
    final creating = _tab == 'create';
    return AppLayout(
      title: 'Tasks',
      scrollable: false,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminHeader(
                  title: 'Tasks',
                  subtitle: 'Tasks you set for members, and the proof they send back. Check each submission, then mark it verified.',
                  actions: [
                    if (!creating)
                      FilledButton.icon(
                        onPressed: () => _onTabChanged('create'),
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text('Assign a task'),
                      ),
                  ],
                ),
                if (_message.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: CubagSpace.md),
                    padding: const EdgeInsets.all(CubagSpace.md),
                    decoration: BoxDecoration(
                      color: CubagColors.validTint,
                      borderRadius: BorderRadius.circular(CubagRadius.card),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: CubagColors.valid, size: 20),
                        const SizedBox(width: CubagSpace.sm),
                        Expanded(child: Text(_message, style: CubagType.label.copyWith(color: CubagColors.valid))),
                      ],
                    ),
                  ),
                if (creating) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _onTabChanged('submitted'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('All tasks'),
                    ),
                  ),
                  const SizedBox(height: CubagSpace.xs),
                  _buildCreate(),
                ] else ...[
                  FilterTabs(
                    tabs: const [
                      ('submitted', 'To check'),
                      ('pending', 'Waiting for member'),
                      ('verified', 'Verified'),
                      ('all', 'All'),
                    ],
                    selected: _tab,
                    onSelected: _onTabChanged,
                  ),
                  const SizedBox(height: CubagSpace.md),
                  _buildTaskList(),
                ],
                const SizedBox(height: CubagSpace.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: CubagSpace.xs, top: CubagSpace.md),
        child: Text(text, style: CubagType.label),
      );

  Widget _buildCreate() => Align(
        alignment: Alignment.topLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(CubagSpace.xl),
          decoration: BoxDecoration(
            color: CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Assign a task', style: CubagType.title),
              const SizedBox(height: CubagSpace.xxs),
              Text('The member sees it on their Tasks screen and is notified.', style: CubagType.small),
              _fieldLabel('Who it is for'),
              CustomDropdown<String>(
                value: _memberId,
                hint: 'Choose a member',
                items: [
                  const DropdownItem(value: 'all', label: 'All active members'),
                  ..._members.map(
                    (m) => DropdownItem<String>(value: m['id'].toString(), label: m['name'] ?? ''),
                  ),
                ],
                onChanged: (v) => setState(() => _memberId = v),
              ),
              _fieldLabel('Title'),
              TextField(
                controller: _titleCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'For example: Upload your 2027 tax clearance'),
              ),
              _fieldLabel('Due date'),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () async {
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
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(_dueDate.isEmpty ? 'Pick a date' : _dueDate),
              ),
              _fieldLabel('Instructions'),
              TextField(
                controller: _descCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'What the member must do, and what proof to send'),
              ),
              const SizedBox(height: CubagSpace.xl),
              FilledButton.icon(
                onPressed: _loading || _titleCtrl.text.trim().isEmpty || _dueDate.isEmpty || _memberId.isEmpty
                    ? null
                    : _assignTask,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Assign task'),
              ),
              if (_memberId.isEmpty || _titleCtrl.text.trim().isEmpty || _dueDate.isEmpty) ...[
                const SizedBox(height: CubagSpace.xs),
                Text('Choose a member, a title and a due date first.', style: CubagType.caption, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );

  Widget _buildTaskList() {
    if (_loading) {
      return Column(
        children: List.generate(
          6,
          (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
        ),
      );
    }
    if (_hasError && _tasks.isEmpty) {
      return FetchErrorView(onRetry: () => _fetchTasks(refresh: true));
    }
    if (_tasks.isEmpty) {
      return EmptyMessage(
        icon: Icons.task_alt_rounded,
        title: switch (_tab) {
          'submitted' => 'Nothing to check',
          'all' => 'No tasks yet',
          'verified' => 'No verified tasks yet',
          _ => 'No tasks waiting',
        },
        message: switch (_tab) {
          'submitted' => 'When a member sends proof for a task, it appears here.',
          'all' => 'Use Assign a task to set one for a member or for everyone.',
          'verified' => 'Tasks you verify are kept here.',
          _ => 'Tasks members have not done yet appear here.',
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminRowGroup(children: [for (final task in _tasks) _taskItem(task)]),
        if (_loadingMore)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        if (_total > 0)
          Padding(
            padding: const EdgeInsets.only(top: CubagSpace.sm),
            child: Text('${_tasks.length} of $_total shown', style: CubagType.caption, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _taskItem(dynamic task) {
    final sid = task['submission_id'] as int?;
    if (sid != null) _verifyCtrl.putIfAbsent(sid, () => TextEditingController());
    final verified = task['admin_verified'] == true;
    final member = (task['member_name'] ?? 'Unknown member').toString();
    final note = task['completion_note']?.toString() ?? '';
    final open = _verifyingId == sid && sid != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminListRow(
          leading: AdminRowMark(initials: adminInitials(member)),
          title: (task['title'] ?? '').toString(),
          subtitle: member,
          meta: 'Due ${task['due_date'] ?? '—'}',
          status: verified
              ? const StatusChip('Verified', kind: StatusKind.good)
              : (sid != null
                  ? const StatusChip('Sent proof', kind: StatusKind.pending)
                  : const StatusChip('Not done yet')),
          trailing: const SizedBox(width: CubagSpace.xs),
        ),
        if (note.isNotEmpty || (sid != null && !verified))
          Padding(
            padding: const EdgeInsets.fromLTRB(68, 0, CubagSpace.md, CubagSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (note.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(CubagSpace.sm),
                    decoration: BoxDecoration(
                      color: CubagColors.sand,
                      borderRadius: BorderRadius.circular(CubagRadius.control),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Member\'s note', style: CubagType.caption),
                        const SizedBox(height: 2),
                        Text(note, style: CubagType.body.copyWith(color: CubagColors.ink)),
                      ],
                    ),
                  ),
                if (sid != null && !verified && !open) ...[
                  const SizedBox(height: CubagSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: () => setState(() => _verifyingId = sid),
                      child: const Text('Verify'),
                    ),
                  ),
                ],
                if (open) ...[
                  const SizedBox(height: CubagSpace.sm),
                  TextField(
                    controller: _verifyCtrl[sid],
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (v) => _verifyNotes[sid] = v,
                    decoration: const InputDecoration(
                      labelText: 'Note to the member (optional)',
                    ),
                  ),
                  const SizedBox(height: CubagSpace.sm),
                  Wrap(
                    spacing: CubagSpace.xs,
                    children: [
                      FilledButton(onPressed: () => _verify(sid), child: const Text('Mark verified')),
                      TextButton(onPressed: () => setState(() => _verifyingId = null), child: const Text('Cancel')),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
