import '../components/filter_tabs.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;

class AdminPortsPage extends StatefulWidget {
  const AdminPortsPage({super.key});

  @override
  State<AdminPortsPage> createState() => _AdminPortsPageState();
}

class _AdminPortsPageState extends State<AdminPortsPage> {
  final ApiService _api = ApiService();
  List<dynamic> _ports = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  int _filterTab = 0; // 0: All, 1: Active, 2: Inactive

  @override
  void initState() {
    super.initState();
    _fetchPorts();
  }

  Future<void> _fetchPorts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/admin/ports');
      if (mounted && res.data is List) {
        setState(() {
          _ports = res.data;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_ports', e, st);
      if (mounted) {
        setState(() {
          _error = 'Failed to load ports of operation';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showPortDialog([dynamic existingPort]) async {
    final isEdit = existingPort != null;
    final nameCtrl = TextEditingController(
      text: existingPort?['name']?.toString() ?? '',
    );
    final codeCtrl = TextEditingController(
      text: existingPort?['code']?.toString() ?? '',
    );
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.anchor_rounded,
                  color: _kOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isEdit ? 'Edit Port of Operation' : 'Add Port of Operation',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the official terminal or border post name for member assignments and public guest requests.',
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Port / Terminal Name *',
                  hintText: 'e.g. Buipe Inland Port',
                  prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: 'Port Code (Optional)',
                  hintText: 'e.g. BUP',
                  prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      setDlgState(() => submitting = true);
                      try {
                        if (isEdit) {
                          await _api.put(
                            '/admin/ports/${existingPort['id']}',
                            data: {
                              'name': name,
                              'code': codeCtrl.text.trim(),
                              'is_active': existingPort['is_active'] ?? true,
                            },
                          );
                        } else {
                          await _api.post(
                            '/admin/ports',
                            data: {'name': name, 'code': codeCtrl.text.trim()},
                          );
                        }
                        if (dlgCtx.mounted) {
                          Navigator.pop(dlgCtx);
                          _fetchPorts();
                        }
                      } catch (e) {
                        setDlgState(() => submitting = false);
                        if (dlgCtx.mounted) {
                          ScaffoldMessenger.of(dlgCtx).showSnackBar(
                            SnackBar(content: Text('Failed to save port: $e')),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      isEdit ? 'Save Changes' : 'Add Port',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _togglePortStatus(dynamic port) async {
    final portId = port['id'];
    final newActive = !(port['is_active'] == true);
    try {
      await _api.put('/admin/ports/$portId', data: {'is_active': newActive});
      _fetchPorts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  List<dynamic> get _filteredPorts {
    return _ports.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final code = (p['code']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          query.isEmpty || name.contains(query) || code.contains(query);

      final isActive = p['is_active'] == true;
      if (_filterTab == 1 && !isActive) return false;
      if (_filterTab == 2 && isActive) return false;

      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = _ports.length;
    final activePorts = _ports.where((p) => p['is_active'] == true).length;
    final ports = _filteredPorts;

    return AppLayout(
      title: 'Ports',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Ports',
                subtitle: 'Ports, terminals and border posts members can pick as their district. Switch one off to hide it from new choices.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => _showPortDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add port'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                AdminFigure('All', '$total', selected: _filterTab == 0, onTap: () => setState(() => _filterTab = 0)),
                AdminFigure('In use', '$activePorts', selected: _filterTab == 1, onTap: () => setState(() => _filterTab = 1)),
                AdminFigure('Switched off', '${total - activePorts}', selected: _filterTab == 2, onTap: () => setState(() => _filterTab = 2)),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(hint: 'Search name or code', onChanged: (v) => setState(() => _searchQuery = v)),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                EmptyMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load ports',
                  message: _error,
                  action: OutlinedButton(onPressed: _fetchPorts, child: const Text('Try again')),
                )
              else if (ports.isEmpty)
                EmptyMessage(
                  icon: Icons.anchor_rounded,
                  title: total == 0 ? 'No ports yet' : 'No ports match',
                  message: total == 0 ? 'Add the ports and border posts members work at.' : 'Try another filter, or clear the search.',
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [
                    for (final p in ports)
                      AdminListRow(
                        leading: AdminRowMark(
                          icon: Icons.anchor_rounded,
                          color: p['is_active'] == true ? CubagColors.cocoa : CubagColors.muted,
                        ),
                        title: p['name']?.toString() ?? 'Unnamed port',
                        subtitle: (p['code']?.toString() ?? '').isEmpty ? null : 'Code ${p['code']}',
                        onTap: () => _showPortDialog(p),
                        trailing: Tooltip(
                          message: p['is_active'] == true ? 'In use' : 'Switched off',
                          child: Switch(value: p['is_active'] == true, onChanged: (_) => _togglePortStatus(p)),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
