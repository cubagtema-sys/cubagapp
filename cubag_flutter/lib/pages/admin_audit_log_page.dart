import '../components/admin_dialog.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';


class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<dynamic> _logs = [];
  int _total = 0;
  int _offset = 0;
  final int _limit = 25;

  String _searchQuery = '';
  String _filterTargetType = '';
  String _filterActionType = '';
  String _filterDateFrom = '';
  String _filterDateTo = '';
  String _filterActorId = '';

  List<String> _targetTypeOptions = [];
  List<Map<String, dynamic>> _actorsOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  String _buildQueryParams() {
    final params = <String>['limit=$_limit', 'offset=$_offset'];
    if (_filterTargetType.isNotEmpty) {
      params.add('target_type=$_filterTargetType');
    }
    if (_filterActionType.isNotEmpty) {
      params.add('action_type=$_filterActionType');
    }
    if (_filterDateFrom.isNotEmpty) params.add('date_from=$_filterDateFrom');
    if (_filterDateTo.isNotEmpty) params.add('date_to=$_filterDateTo');
    if (_filterActorId.isNotEmpty) params.add('actor_id=$_filterActorId');
    if (_showAuto) params.add('include_auto=1');
    return params.join('&');
  }

  Future<void> _fetchLogs() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _api.get('/admin/audit-log?${_buildQueryParams()}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        setState(() {
          _logs = data['logs'] ?? [];
          _total = data['total'] ?? 0;
          final opts = data['filter_options'] as Map<String, dynamic>?;
          if (opts != null) {
            _targetTypeOptions = List<String>.from(opts['target_types'] ?? []);
            _actorsOptions = List<Map<String, dynamic>>.from(
              (opts['actors'] ?? []).map((a) => Map<String, dynamic>.from(a)),
            );
          }
          _loading = false;
        });
        return;
      }
    } catch (e, st) {
      AppLogger.error('admin_audit_log_page', e, st);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _nextPage() {
    if (_offset + _limit < _total) {
      setState(() => _offset += _limit);
      _fetchLogs();
    }
  }

  void _prevPage() {
    if (_offset > 0) {
      setState(() => _offset = (_offset - _limit).clamp(0, _total));
      _fetchLogs();
    }
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _filterTargetType = '';
      _filterActionType = '';
      _filterDateFrom = '';
      _filterDateTo = '';
      _filterActorId = '';
      _offset = 0;
    });
    _fetchLogs();
  }

  /// Automatic records of every change and every view of sensitive data.
  /// Kept for security; hidden unless an admin asks to see them.
  bool _showAuto = false;

  bool get _hasActiveFilters =>
      _filterTargetType.isNotEmpty ||
      _filterActionType.isNotEmpty ||
      _filterDateFrom.isNotEmpty ||
      _filterDateTo.isNotEmpty ||
      _filterActorId.isNotEmpty ||
      _searchQuery.isNotEmpty;

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      final str =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        if (isFrom) {
          _filterDateFrom = str;
        } else {
          _filterDateTo = str;
        }
        _offset = 0;
      });
      _fetchLogs();
    }
  }

  /// A list of choices in the shared pop-up; the current one is ticked.
  void _pickFrom(String title, List<(String, String, String?)> options, String current, ValueChanged<String> onPick) {
    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: title,
        maxWidth: 420,
        children: [
          AdminRowGroup(
            children: [
              for (final o in options)
                ListTile(
                  title: Text(o.$2, style: CubagType.bodyStrong),
                  subtitle: o.$3 == null ? null : Text(o.$3!, style: CubagType.caption),
                  trailing: o.$1 == current ? const Icon(Icons.check_rounded, color: CubagColors.cocoa) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onPick(o.$1);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showActorDialog() {
    String roleLabel(String r) => r.contains('super') ? 'Super admin' : (r.contains('sub') ? 'Sub-admin' : 'Admin');
    _pickFrom(
      'Show entries by',
      [
        ('', 'All admins', null),
        for (final a in _actorsOptions)
          (
            a['id']?.toString() ?? '',
            a['name']?.toString() ?? 'Admin #${a['id']}',
            roleLabel((a['role']?.toString() ?? '').toLowerCase()),
          ),
      ],
      _filterActorId,
      (id) {
        setState(() {
          _filterActorId = id;
          _offset = 0;
        });
        _fetchLogs();
      },
    );
  }

  void _showOptionDialog(String title, List<String> options, Function(String) onSelect) {
    final current = title == 'action' ? _filterActionType : _filterTargetType;
    _pickFrom(
      'Show which ${title}s',
      [for (final o in options) (o, o.isEmpty ? 'All ${title}s' : o[0].toUpperCase() + o.substring(1).replaceAll('_', ' '), null)],
      current,
      (v) => onSelect(v),
    );
  }

  void _showLogDetailsModal(Map<String, dynamic> log) {
    String v(String k) => log[k]?.toString() ?? '';
    final actor = v('admin_name').isNotEmpty ? v('admin_name') : (v('actor_name').isNotEmpty ? v('actor_name') : 'Admin');
    final role = (v('admin_role').isNotEmpty ? v('admin_role') : v('actor_role')).toLowerCase();
    final roleLabel = role.contains('super') ? 'Super admin' : (role.contains('sub') ? 'Sub-admin' : 'Admin');
    final d = DateTime.tryParse(v('created_at'))?.toLocal();
    final when = d == null
        ? v('created_at')
        : '${d.day} ${_months[d.month - 1]} ${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final type = v('target_type');

    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: v('action').isEmpty ? 'Audit entry' : _readableAction(v('action')),
        subtitle: 'by $actor · $when',
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        children: [
          AdminDetailRow('Admin', '$actor ($roleLabel)'),
          AdminDetailRow('When', when),
          AdminDetailRow('Action', _readableAction(v('action'))),
          if (type.isNotEmpty) AdminDetailRow('Record type', type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ')),
          if (v('target_name').isNotEmpty) AdminDetailRow('Record', v('target_name')),
          if (v('details').isNotEmpty) ...[
            const SizedBox(height: CubagSpace.sm),
            Text('Details', style: CubagType.label),
            const SizedBox(height: CubagSpace.xxs),
            Container(
              padding: const EdgeInsets.all(CubagSpace.sm),
              decoration: BoxDecoration(color: CubagColors.sand, borderRadius: BorderRadius.circular(CubagRadius.control)),
              child: SelectableText(v('details'), style: CubagType.small.copyWith(color: CubagColors.ink, fontFamily: 'monospace')),
            ),
            const SizedBox(height: CubagSpace.sm),
          ],
          AdminDetailRow('From IP address', v('ip_address')),
        ],
      ),
    );
  }

  List<dynamic> get _filteredLogs {
    if (_searchQuery.isEmpty) return _logs;
    final q = _searchQuery.toLowerCase();
    return _logs.where((log) {
      final actor = ((log['admin_name'] ?? log['actor_name'])?.toString() ?? '').toLowerCase();
      final action = (log['action']?.toString() ?? '').toLowerCase();
      final target = (log['target_name']?.toString() ?? '').toLowerCase();
      final type = (log['target_type']?.toString() ?? '').toLowerCase();
      return actor.contains(q) ||
          action.contains(q) ||
          target.contains(q) ||
          type.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayLogs = _filteredLogs;

    String currentActorLabel = 'All admins';
    if (_filterActorId.isNotEmpty) {
      final match = _actorsOptions.firstWhere(
        (a) => a['id']?.toString() == _filterActorId,
        orElse: () => {'name': 'Admin #$_filterActorId'},
      );
      currentActorLabel = match['name']?.toString() ?? 'Selected admin';
    }

    Widget filter(String label, bool active, VoidCallback onTap, IconData icon) => FilterChip(
          avatar: Icon(icon, size: 16, color: active ? CubagColors.onCocoa : CubagColors.muted),
          label: Text(label),
          selected: active,
          showCheckmark: false,
          labelStyle: CubagType.label.copyWith(color: active ? CubagColors.onCocoa : CubagColors.inkSoft),
          selectedColor: CubagColors.cocoa,
          backgroundColor: CubagColors.paper,
          side: BorderSide(color: active ? CubagColors.cocoa : CubagColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          onSelected: (_) => onTap(),
        );

    // Group entries by day, newest first (the server already orders them).
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final raw in displayLogs) {
      final log = Map<String, dynamic>.from(raw as Map);
      groups.putIfAbsent(_dayLabel(log['created_at']?.toString()), () => []).add(log);
    }

    return AppLayout(
      title: 'Audit',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Audit',
                subtitle: 'What each admin did, and when. Entries cannot be edited from here.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _fetchLogs(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              AdminSearchField(
                hint: 'Search admin, action or record',
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: CubagSpace.sm),
              Wrap(
                spacing: CubagSpace.xs,
                runSpacing: CubagSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  filter(currentActorLabel, _filterActorId.isNotEmpty, _showActorDialog, Icons.person_outline_rounded),
                  filter(
                    _filterTargetType.isEmpty ? 'All records' : _filterTargetType,
                    _filterTargetType.isNotEmpty,
                    () => _showOptionDialog('record type', ['', ..._targetTypeOptions], (v) {
                      setState(() {
                        _filterTargetType = v;
                        _offset = 0;
                      });
                      _fetchLogs();
                    }),
                    Icons.category_outlined,
                  ),
                  filter(
                    _filterActionType.isEmpty ? 'All actions' : _filterActionType,
                    _filterActionType.isNotEmpty,
                    () => _showOptionDialog(
                      'action',
                      ['', 'Created', 'Updated', 'Approved', 'Rejected', 'Deleted', 'Archived'],
                      (v) {
                        setState(() {
                          _filterActionType = v;
                          _offset = 0;
                        });
                        _fetchLogs();
                      },
                    ),
                    Icons.touch_app_outlined,
                  ),
                  filter(
                    _filterDateFrom.isEmpty ? 'From any date' : 'From $_filterDateFrom',
                    _filterDateFrom.isNotEmpty,
                    () => _pickDate(true),
                    Icons.calendar_today_rounded,
                  ),
                  filter(
                    _filterDateTo.isEmpty ? 'To any date' : 'To $_filterDateTo',
                    _filterDateTo.isNotEmpty,
                    () => _pickDate(false),
                    Icons.event_available_rounded,
                  ),
                  filter(
                    'Show page views and raw requests',
                    _showAuto,
                    () {
                      setState(() {
                        _showAuto = !_showAuto;
                        _offset = 0;
                      });
                      _fetchLogs();
                    },
                    Icons.visibility_outlined,
                  ),
                  if (_hasActiveFilters)
                    TextButton(onPressed: _resetFilters, child: const Text('Clear filters')),
                ],
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (displayLogs.isEmpty)
                EmptyMessage(
                  icon: Icons.history_toggle_off_rounded,
                  title: _hasActiveFilters ? 'No entries match' : 'No activity yet',
                  message: _hasActiveFilters
                      ? 'Try other filters, or clear them.'
                      : 'Approvals, edits and deletions by admins are recorded here.',
                )
              else ...[
                Text(
                  _total == 1 ? '1 entry' : '$_total entries',
                  style: CubagType.small.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                for (final day in groups.entries) ...[
                  AdminGroupLabel(day.key),
                  AdminRowGroup(
                    dividerIndent: 68,
                    children: [for (final log in day.value) _logRow(log)],
                  ),
                  const SizedBox(height: CubagSpace.md),
                ],
                if (_total > _limit)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_offset + 1}–${(_offset + _limit).clamp(0, _total)} of $_total',
                          style: CubagType.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Newer entries',
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: _offset > 0 ? _prevPage : null,
                      ),
                      IconButton(
                        tooltip: 'Older entries',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: _offset + _limit < _total ? _nextPage : null,
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _dayLabel(String? raw) {
    final d = DateTime.tryParse(raw ?? '')?.toLocal();
    if (d == null) return 'Undated';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// Older entries were saved with names like 'update_fees': show them as words.
  String _readableAction(String raw) {
    final t = raw.replaceAll('_', ' ').trim();
    return t.isEmpty ? 'Action' : t[0].toUpperCase() + t.substring(1);
  }

  Widget _logRow(Map<String, dynamic> log) {
    final actor = (log['admin_name'] ?? log['actor_name'] ?? 'Admin').toString();
    final role = (log['admin_role'] ?? log['actor_role'] ?? '').toString().toLowerCase();
    final action = _readableAction(log['action']?.toString() ?? 'Action');
    final targetType = log['target_type']?.toString() ?? '';
    final targetName = log['target_name']?.toString() ?? '';
    final ip = log['ip_address']?.toString() ?? '';
    final d = DateTime.tryParse(log['created_at']?.toString() ?? '')?.toLocal();
    final time = d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final a = action.toLowerCase();
    final kind = a.contains('delet') || a.contains('reject') || a.contains('suspend')
        ? StatusKind.bad
        : (a.contains('approv') || a.contains('verif') ? StatusKind.good : StatusKind.neutral);
    final roleLabel = role.contains('super') ? 'Super admin' : (role.contains('sub') ? 'Sub-admin' : '');

    return AdminListRow(
      leading: AdminRowMark(initials: adminInitials(actor)),
      title: actor,
      subtitle: [
        if (targetType.isNotEmpty) targetType[0].toUpperCase() + targetType.substring(1).replaceAll('_', ' '),
        if (targetName.isNotEmpty && targetName != '—') targetName,
      ].join(': '),
      meta: [if (time.isNotEmpty) time, if (roleLabel.isNotEmpty) roleLabel, if (ip.isNotEmpty) ip].join(' · '),
      status: StatusChip(action, kind: kind),
      onTap: () => _showLogDetailsModal(log),
    );
  }
}
