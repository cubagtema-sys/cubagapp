import '../components/admin_dialog.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kRed = CubagColors.lapsed;

class AdminPortNewsPage extends StatefulWidget {
  const AdminPortNewsPage({super.key});

  @override
  State<AdminPortNewsPage> createState() => _AdminPortNewsPageState();
}

class _AdminPortNewsPageState extends State<AdminPortNewsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<dynamic> _bulletins = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  int _filterTab = 0; // 0: All, 1: Active, 2: Inactive

  @override
  void initState() {
    super.initState();
    _fetchBulletins();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBulletins() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/news/admin/bulletins');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _bulletins = res.data['items'];
          _loading = false;
        });
      } else if (mounted && res.data is List) {
        setState(() {
          _bulletins = res.data;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_port_bulletins', e, st);
      if (mounted) {
        setState(() {
          _error = 'Failed to load port bulletins';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showBulletinDialog([dynamic existing]) async {
    final isEdit = existing != null;
    final portCtrl = TextEditingController(text: existing?['port_name']?.toString() ?? '');
    final codeCtrl = TextEditingController(text: existing?['code']?.toString() ?? '');
    final noticeCtrl = TextEditingController(text: existing?['notice']?.toString() ?? '');
    String status = existing?['status']?.toString() ?? 'Operational';
    if (!const ['Operational', 'Normal', 'Maintenance', 'Restricted'].contains(status)) status = 'Operational';
    bool submitting = false;
    String? error;

    String colorFor(String s) => switch (s) {
          'Maintenance' => '#E65100',
          'Restricted' => '#C62828',
          _ => '#2E7D32',
        };

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          Future<void> submit() async {
            final port = portCtrl.text.trim();
            final notice = noticeCtrl.text.trim();
            if (port.isEmpty || notice.isEmpty) {
              setDlgState(() => error = 'Add the port and the note.');
              return;
            }
            setDlgState(() {
              submitting = true;
              error = null;
            });
            final data = {
              'port_name': port,
              'code': codeCtrl.text.trim(),
              'status': status,
              'notice': notice,
              'status_color': colorFor(status),
            };
            try {
              if (isEdit) {
                await _api.put('/news/admin/bulletins/${existing['id']}', data: {...data, 'is_active': existing['is_active'] ?? true});
              } else {
                await _api.post('/news/admin/bulletins', data: data);
              }
              if (dlgCtx.mounted) {
                Navigator.pop(dlgCtx);
                _fetchBulletins();
              }
            } catch (e) {
              setDlgState(() {
                submitting = false;
                error = 'Could not save. Try again.';
              });
            }
          }

          return AdminDialog(
            title: isEdit ? 'Edit port update' : 'New port update',
            subtitle: 'A short note on how a port is running. Members see it in the app.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(submitting ? 'Saving…' : (isEdit ? 'Save changes' : 'Post update')),
              ),
            ],
            children: [
              AdminFieldPair(
                AdminField(
                  label: 'Port or terminal',
                  child: TextField(controller: portCtrl, decoration: const InputDecoration(hintText: 'For example: Tema Terminal 3')),
                ),
                AdminField(
                  label: 'Code (optional)',
                  child: TextField(controller: codeCtrl, decoration: const InputDecoration(hintText: 'For example: TMA')),
                ),
              ),
              AdminField(
                label: 'Status',
                child: AdminChoice<String>(
                  options: const [
                    ('Operational', 'Operational'),
                    ('Normal', 'Normal'),
                    ('Maintenance', 'Maintenance'),
                    ('Restricted', 'Restricted'),
                  ],
                  value: status,
                  onChanged: (v) => setDlgState(() => status = v),
                ),
              ),
              AdminField(
                label: 'Note',
                child: TextField(
                  controller: noticeCtrl,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'For example: Gate 2 closed until Friday. Use Gate 1.'),
                ),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
    portCtrl.dispose();
    codeCtrl.dispose();
    noticeCtrl.dispose();
  }

  Future<void> _toggleStatus(dynamic bulletin) async {
    final id = bulletin['id'];
    final newActive = !(bulletin['is_active'] == true);
    try {
      await _api.put('/news/admin/bulletins/$id', data: {'is_active': newActive});
      _fetchBulletins();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  Future<void> _deleteBulletin(dynamic bulletin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Archive this update?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Remove "${bulletin['port_name']}" bulletin from public view?', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.delete('/news/admin/bulletins/${bulletin['id']}');
      _fetchBulletins();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error archiving bulletin: $e')));
      }
    }
  }

  List<dynamic> get _filteredBulletins {
    return _bulletins.where((b) {
      final port = (b['port_name']?.toString() ?? '').toLowerCase();
      final notice = (b['notice']?.toString() ?? '').toLowerCase();
      final code = (b['code']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matches = query.isEmpty || port.contains(query) || notice.contains(query) || code.contains(query);

      final isActive = b['is_active'] == true;
      if (_filterTab == 1 && !isActive) return false;
      if (_filterTab == 2 && isActive) return false;

      return matches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = _bulletins.length;
    final active = _bulletins.where((b) => b['is_active'] == true).length;
    final bulletins = _filteredBulletins;

    return AppLayout(
      title: 'News',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Port news',
                subtitle: 'Short status notes for each port. Shown updates appear in the member app; hide one when it no longer applies.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _fetchBulletins,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showBulletinDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New update'),
                  ),
                ],
              ),
              FilterTabs(
                tabs: [('0', 'All · $total'), ('1', 'Shown · $active'), ('2', 'Hidden · ${total - active}')],
                selected: '$_filterTab',
                onSelected: (k) => setState(() => _filterTab = int.parse(k)),
              ),
              const SizedBox(height: CubagSpace.sm),
              AdminSearchField(
                hint: 'Search port, code or text',
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                EmptyMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load port news',
                  message: _error,
                  action: OutlinedButton(onPressed: _fetchBulletins, child: const Text('Try again')),
                )
              else if (bulletins.isEmpty)
                EmptyMessage(
                  icon: Icons.anchor_rounded,
                  title: total == 0 ? 'No port updates yet' : 'No updates match',
                  message: total == 0
                      ? 'Post a note when a port is closed, slow or back to normal.'
                      : 'Try another filter, or clear the search.',
                )
              else
                AdminRowGroup(children: [for (final b in bulletins) _bulletinItem(b)]),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulletinItem(dynamic b) {
    final isActive = b['is_active'] == true;
    final statusStr = b['status']?.toString() ?? 'Operational';
    final portName = b['port_name']?.toString() ?? '';
    final code = b['code']?.toString() ?? '';
    final notice = b['notice']?.toString() ?? '';
    final s = statusStr.toLowerCase();
    final kind = s == 'operational' || s == 'normal'
        ? StatusKind.good
        : (s == 'restricted' || s == 'closed' ? StatusKind.bad : StatusKind.pending);

    return Padding(
      padding: const EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.md, CubagSpace.xs, CubagSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: CubagSpace.xs,
                  runSpacing: CubagSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(portName, style: CubagType.bodyStrong),
                    if (code.isNotEmpty) Text(code, style: CubagType.caption),
                    StatusChip(statusStr[0].toUpperCase() + statusStr.substring(1), kind: kind),
                    if (!isActive) const StatusChip('Hidden'),
                  ],
                ),
                if (notice.isNotEmpty) ...[
                  const SizedBox(height: CubagSpace.xxs),
                  SelectableText(notice, style: CubagType.body.copyWith(color: isActive ? CubagColors.inkSoft : CubagColors.muted)),
                ],
              ],
            ),
          ),
          Tooltip(
            message: isActive ? 'Shown to members' : 'Hidden from members',
            child: Switch(value: isActive, onChanged: (_) => _toggleStatus(b)),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
            onSelected: (v) {
              if (v == 'edit') _showBulletinDialog(b);
              if (v == 'delete') _deleteBulletin(b);
              if (v == 'copy') {
                Clipboard.setData(ClipboardData(text: notice));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Text copied'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'copy', child: Text('Copy text')),
              PopupMenuItem(value: 'delete', child: Text('Archive', style: TextStyle(color: CubagColors.lapsed))),
            ],
          ),
        ],
      ),
    );
  }
}
