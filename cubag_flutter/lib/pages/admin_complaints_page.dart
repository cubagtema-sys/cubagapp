import '../components/admin_dialog.dart';
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


class AdminComplaintsPage extends StatefulWidget {
  const AdminComplaintsPage({super.key});

  @override
  State<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends State<AdminComplaintsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _complaints = [];
  bool _loading = true;
  bool _hasError = false;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _fetchComplaints();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchComplaints() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final res = await _api.get('/complaints');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = res.data;
        List<Map<String, dynamic>> items = [];
        if (data is Map && data['data'] is List) {
          items = (data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else if (data is List) {
          items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        setState(() {
          _complaints = items;
          _loading = false;
          _hasError = false;
        });
      } else {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_complaints_fetch', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  String _normalizeStatus(String raw) {
    return raw.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _complaints.length;
    final target = _normalizeStatus(status);
    return _complaints.where((c) {
      final current = _normalizeStatus(c['status']?.toString() ?? '');
      return current == target;
    }).length;
  }

  List<Map<String, dynamic>> get _displayedComplaints {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _complaints.where((c) {
      if (_selectedStatus != 'all') {
        final current = _normalizeStatus(c['status']?.toString() ?? '');
        final target = _normalizeStatus(_selectedStatus);
        if (target == 'resolved') {
          if (current != 'resolved' && current != 'closed') return false;
        } else if (current != target) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final id = (c['complaint_id']?.toString() ?? '').toLowerCase();
        final name = (c['name']?.toString() ?? '').toLowerCase();
        final subject = (c['subject']?.toString() ?? '').toLowerCase();
        final phone = (c['phone']?.toString() ?? '').toLowerCase();
        final port = (c['port']?.toString() ?? '').toLowerCase();
        final desc = (c['description']?.toString() ?? '').toLowerCase();
        final entity = (c['target_entity']?.toString() ?? '').toLowerCase();
        if (!id.contains(query) &&
            !name.contains(query) &&
            !subject.contains(query) &&
            !phone.contains(query) &&
            !port.contains(query) &&
            !desc.contains(query) &&
            !entity.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _openUpdateDialog(Map<String, dynamic> item) {
    const statuses = ['Received', 'Under Review', 'Investigating', 'Resolved', 'Closed'];
    const priorities = ['Normal', 'High', 'Urgent'];
    String status = item['status']?.toString() ?? 'Received';
    if (!statuses.contains(status)) status = 'Received';
    String priority = item['priority']?.toString() ?? 'Normal';
    if (!priorities.contains(priority)) priority = 'Normal';
    final notesCtrl = TextEditingController(text: item['resolution_notes']?.toString() ?? '');
    final assignedCtrl = TextEditingController(text: item['assigned_to']?.toString() ?? '');
    bool saving = false;
    String? error;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          Future<void> save() async {
            setModalState(() {
              saving = true;
              error = null;
            });
            try {
              final res = await _api.put('/complaints/${item['complaint_id']}/status', data: {
                'status': status,
                'priority': priority,
                'assigned_to': assignedCtrl.text.trim(),
                'resolution_notes': notesCtrl.text.trim(),
              });
              if (!mounted) return;
              if (res.statusCode == 200) {
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                _fetchComplaints();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Complaint updated.'), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              setModalState(() => error = 'Could not save. Try again.');
            } catch (e, st) {
              AppLogger.error('admin_complaints_update', e, st);
              setModalState(() => error = 'Could not save. Check the connection and try again.');
            }
            setModalState(() => saving = false);
          }

          return AdminDialog(
            title: 'Update complaint',
            subtitle: '${item['complaint_id'] ?? ''} · ${item['subject'] ?? ''}',
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Saving…' : 'Save')),
            ],
            children: [
              AdminField(
                label: 'Status',
                child: AdminChoice<String>(
                  options: const [
                    ('Received', 'New'),
                    ('Under Review', 'Under review'),
                    ('Investigating', 'Investigating'),
                    ('Resolved', 'Resolved'),
                    ('Closed', 'Closed'),
                  ],
                  value: status,
                  onChanged: (v) => setModalState(() => status = v),
                ),
              ),
              AdminField(
                label: 'Priority',
                child: AdminChoice<String>(
                  options: const [('Normal', 'Normal'), ('High', 'High'), ('Urgent', 'Urgent')],
                  value: priority,
                  onChanged: (v) => setModalState(() => priority = v),
                ),
              ),
              AdminField(
                label: 'Handled by',
                child: TextField(
                  controller: assignedCtrl,
                  decoration: const InputDecoration(hintText: 'For example: Grievance committee'),
                ),
              ),
              AdminField(
                label: 'Notes',
                child: TextField(
                  controller: notesCtrl,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(hintText: 'Findings, hearing dates or next steps'),
                ),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
  }

  void _openViewDetailsDialog(Map<String, dynamic> item) {
    String v(String k) => item[k]?.toString() ?? '';
    final complaintId = v('complaint_id');
    final status = v('status').isEmpty ? 'Received' : v('status');
    final norm = _normalizeStatus(status);
    final description = v('description').isNotEmpty ? v('description') : v('details');
    final company = v('company').isNotEmpty ? v('company') : v('member_company');

    showDialog(
      context: context,
      builder: (dialogCtx) => AdminDialog(
        title: v('subject').isEmpty ? 'Complaint' : v('subject'),
        subtitle: [complaintId, v('created_at').split('T').first].where((s) => s.isNotEmpty).join(' · '),
        maxWidth: 620,
        actions: [
          if (complaintId.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: complaintId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Tracking ID $complaintId copied'), behavior: SnackBarBehavior.floating),
                );
              },
              child: const Text('Copy tracking ID'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _openUpdateDialog(item);
            },
            child: const Text('Update status'),
          ),
        ],
        children: [
          Wrap(
            spacing: CubagSpace.xs,
            children: [
              StatusChip(
                norm == 'received' ? 'New' : status[0].toUpperCase() + status.substring(1).toLowerCase(),
                kind: norm == 'resolved' || norm == 'closed' ? StatusKind.good : StatusKind.pending,
              ),
              if (v('priority').isNotEmpty && v('priority').toLowerCase() != 'normal')
                StatusChip('${v('priority')} priority', kind: StatusKind.bad),
            ],
          ),
          const SizedBox(height: CubagSpace.md),
          Text('What happened', style: CubagType.label),
          const SizedBox(height: CubagSpace.xxs),
          SelectableText(description.isEmpty ? 'No description given.' : description, style: CubagType.body.copyWith(color: CubagColors.ink)),
          const SizedBox(height: CubagSpace.lg),
          Text('From', style: CubagType.label),
          AdminDetailRow('Name', v('name')),
          AdminDetailRow('Phone', v('phone')),
          AdminDetailRow('Email', v('email')),
          if (company.isNotEmpty) AdminDetailRow('Company', company),
          const SizedBox(height: CubagSpace.md),
          Text('About', style: CubagType.label),
          AdminDetailRow('Category', v('category')),
          AdminDetailRow('Port', v('port')),
          if (v('target_entity').isNotEmpty) AdminDetailRow('Against', v('target_entity')),
          if (v('assigned_to').isNotEmpty || v('resolution_notes').isNotEmpty) ...[
            const SizedBox(height: CubagSpace.md),
            Text('Handling', style: CubagType.label),
            if (v('assigned_to').isNotEmpty) AdminDetailRow('Handled by', v('assigned_to')),
            if (v('resolution_notes').isNotEmpty) AdminDetailRow('Notes', v('resolution_notes')),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaints = _displayedComplaints;
    final resolved = _countForStatus('Resolved') + _countForStatus('Closed');
    AdminFigure fig(String label, String key, int n, {Color? color}) => AdminFigure(
          label,
          '$n',
          color: n > 0 ? color : null,
          selected: _selectedStatus.toLowerCase() == key.toLowerCase(),
          onTap: () => setState(() => _selectedStatus = key),
        );

    return AppLayout(
      title: 'Complaints',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Complaints',
                subtitle: 'Complaints from members and the public. Open one to read it, then update its status as you work on it.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _fetchComplaints,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                fig('All', 'all', _complaints.length),
                fig('New', 'Received', _countForStatus('Received'), color: CubagColors.due),
                fig('Under review', 'Under Review', _countForStatus('Under Review'), color: CubagColors.due),
                fig('Investigating', 'Investigating', _countForStatus('Investigating'), color: CubagColors.due),
                fig('Resolved', 'Resolved', resolved, color: CubagColors.valid),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search name, subject, phone or tracking ID',
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (_hasError)
                EmptyMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load complaints',
                  message: 'Check the connection and try again.',
                  action: OutlinedButton(onPressed: _fetchComplaints, child: const Text('Try again')),
                )
              else if (complaints.isEmpty)
                EmptyMessage(
                  icon: Icons.gavel_rounded,
                  title: _complaints.isEmpty ? 'No complaints yet' : 'No complaints match',
                  message: _complaints.isEmpty
                      ? 'Complaints sent from the app or the public form appear here.'
                      : 'Try another filter, or clear the search.',
                )
              else ...[
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [for (final item in complaints) _complaintRow(item)],
                ),
                const SizedBox(height: CubagSpace.sm),
                Text(
                  'Showing ${complaints.length} of ${_complaints.length}',
                  style: CubagType.caption,
                ),
              ],
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _complaintRow(Map<String, dynamic> item) {
    final id = item['complaint_id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Complainant';
    final subject = item['subject']?.toString() ?? 'No subject';
    final port = item['port']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'Received';
    final priority = item['priority']?.toString() ?? 'Normal';
    final norm = _normalizeStatus(status);
    final kind = switch (norm) {
      'resolved' || 'closed' => StatusKind.good,
      'rejected' || 'dismissed' => StatusKind.bad,
      _ => StatusKind.pending,
    };
    final label = norm == 'received' ? 'New' : (status.isEmpty ? 'New' : status[0].toUpperCase() + status.substring(1).toLowerCase());
    final urgent = const {'high', 'urgent', 'critical'}.contains(priority.toLowerCase());

    return AdminListRow(
      leading: AdminRowMark(
        icon: Icons.gavel_rounded,
        color: urgent ? CubagColors.lapsed : CubagColors.cocoa,
        background: urgent ? CubagColors.lapsedTint : CubagColors.sand,
      ),
      title: subject,
      subtitle: [name, if (port.isNotEmpty) port, if (category.isNotEmpty) category].join(' · '),
      meta: [if (id.isNotEmpty) id, if (urgent) '${priority[0].toUpperCase()}${priority.substring(1).toLowerCase()} priority'].join(' · '),
      status: StatusChip(label, kind: kind),
      onTap: () => _openViewDetailsDialog(item),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
        onSelected: (v) {
          if (v == 'update') _openUpdateDialog(item);
          if (v == 'open') _openViewDetailsDialog(item);
          if (v == 'copy') {
            Clipboard.setData(ClipboardData(text: id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Tracking ID $id copied'), behavior: SnackBarBehavior.floating),
            );
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'open', child: Text('Open')),
          const PopupMenuItem(value: 'update', child: Text('Update status')),
          if (id.isNotEmpty) const PopupMenuItem(value: 'copy', child: Text('Copy tracking ID')),
        ],
      ),
    );
  }
}
