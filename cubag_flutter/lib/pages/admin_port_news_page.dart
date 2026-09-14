import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kCardBg = Color(0xFF281710);

class AdminPortNewsPage extends StatefulWidget {
  const AdminPortNewsPage({super.key});

  @override
  State<AdminPortNewsPage> createState() => _AdminPortNewsPageState();
}

class _AdminPortNewsPageState extends State<AdminPortNewsPage> {
  final ApiService _api = ApiService();
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
    final portCtrl = TextEditingController(
      text: existing?['port_name']?.toString() ?? '',
    );
    final codeCtrl = TextEditingController(
      text: existing?['code']?.toString() ?? '',
    );
    final noticeCtrl = TextEditingController(
      text: existing?['notice']?.toString() ?? '',
    );
    String status = existing?['status']?.toString() ?? 'Operational';
    String colorHex = existing?['status_color']?.toString() ?? '#2E7D32';
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
                isEdit ? 'Edit Port Bulletin' : 'Post Port Bulletin',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publish operational status updates for Ghana ports & cargo terminals to the homepage.',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: portCtrl,
                  decoration: InputDecoration(
                    labelText: 'Port / Terminal Name *',
                    hintText: 'e.g. Tema Port Terminal',
                    prefixIcon: const Icon(
                      Icons.location_city_rounded,
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: codeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Code',
                          hintText: 'e.g. TMP',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Operational',
                            child: Text('Operational (Green)'),
                          ),
                          DropdownMenuItem(
                            value: 'Normal',
                            child: Text('Normal (Green)'),
                          ),
                          DropdownMenuItem(
                            value: 'Maintenance',
                            child: Text('Maintenance (Orange)'),
                          ),
                          DropdownMenuItem(
                            value: 'Restricted',
                            child: Text('Restricted (Red)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setDlgState(() {
                            status = val;
                            if (val == 'Maintenance') {
                              colorHex = '#E65100';
                            } else if (val == 'Restricted') {
                              colorHex = '#C62828';
                            } else {
                              colorHex = '#2E7D32';
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noticeCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Live Operational Notice *',
                    hintText:
                        'e.g. Berth 3 & MPS Terminal 3 fully operational. Digital gate clearance active.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
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
                      final port = portCtrl.text.trim();
                      final notice = noticeCtrl.text.trim();
                      if (port.isEmpty || notice.isEmpty) return;
                      setDlgState(() => submitting = true);
                      try {
                        if (isEdit) {
                          await _api.put(
                            '/news/admin/bulletins/${existing['id']}',
                            data: {
                              'port_name': port,
                              'code': codeCtrl.text.trim(),
                              'status': status,
                              'notice': notice,
                              'status_color': colorHex,
                              'is_active': existing['is_active'] ?? true,
                            },
                          );
                        } else {
                          await _api.post(
                            '/news/admin/bulletins',
                            data: {
                              'port_name': port,
                              'code': codeCtrl.text.trim(),
                              'status': status,
                              'notice': notice,
                              'status_color': colorHex,
                            },
                          );
                        }
                        if (dlgCtx.mounted) {
                          Navigator.pop(dlgCtx);
                          _fetchBulletins();
                        }
                      } catch (e) {
                        setDlgState(() => submitting = false);
                        if (dlgCtx.mounted) {
                          ScaffoldMessenger.of(dlgCtx).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save bulletin: $e'),
                            ),
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
                      isEdit ? 'Save Changes' : 'Post Bulletin',
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

    portCtrl.dispose();
    codeCtrl.dispose();
    noticeCtrl.dispose();
  }

  Future<void> _toggleStatus(dynamic bulletin) async {
    final id = bulletin['id'];
    final newActive = !(bulletin['is_active'] == true);
    try {
      await _api.put(
        '/news/admin/bulletins/$id',
        data: {'is_active': newActive},
      );
      _fetchBulletins();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  Future<void> _deleteBulletin(dynamic bulletin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Archive Port Bulletin?'),
        content: Text(
          'Are you sure you want to remove "${bulletin['port_name']}" bulletin from public view?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive', style: TextStyle(color: Colors.white)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error archiving bulletin: $e')));
      }
    }
  }

  List<dynamic> get _filteredBulletins {
    return _bulletins.where((b) {
      final port = (b['port_name']?.toString() ?? '').toLowerCase();
      final notice = (b['notice']?.toString() ?? '').toLowerCase();
      final code = (b['code']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matches =
          query.isEmpty ||
          port.contains(query) ||
          notice.contains(query) ||
          code.contains(query);

      final isActive = b['is_active'] == true;
      if (_filterTab == 1 && !isActive) return false;
      if (_filterTab == 2 && isActive) return false;

      return matches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);

    final total = _bulletins.length;
    final active = _bulletins.where((b) => b['is_active'] == true).length;
    final inactive = total - active;

    return AppLayout(
      title: 'Port Operational News',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Port Bulletins & Status Updates',
            subtitle:
                'Live operational updates displayed under Port Operational News tab on the homepage.',
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
                onPressed: () => _showBulletinDialog(),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(
                  'Post Port Bulletin',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Metric Stats Cards
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Bulletins',
                  value: '$total',
                  icon: Icons.feed_outlined,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Active Live',
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
            ],
          ),
          const SizedBox(height: 16),

          // Search & Filter controls
          AdminToolbar(
            searchHint: 'Search bulletins by port or notice content...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            filters: [
              AdminFilterChip(
                label: 'All Bulletins',
                count: total,
                isSelected: _filterTab == 0,
                onTap: () => setState(() => _filterTab = 0),
              ),
              AdminFilterChip(
                label: 'Active Live',
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

          // Content List
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_filteredBulletins.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.feed_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No port bulletins found.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredBulletins.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final b = _filteredBulletins[i];
                final isActive = b['is_active'] == true;
                final statusStr = b['status']?.toString() ?? 'Operational';

                return Card(
                  color: cardBg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: borderCol),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.anchor_rounded,
                            color: _kOrange,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    b['port_name']?.toString() ?? '',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (b['code'] != null &&
                                      b['code'].toString().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        b['code'].toString(),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _kGreen.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusStr,
                                      style: GoogleFonts.inter(
                                        color: _kGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b['notice']?.toString() ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  height: 1.4,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit Bulletin',
                              onPressed: () => _showBulletinDialog(b),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.red,
                              ),
                              tooltip: 'Archive Bulletin',
                              onPressed: () => _deleteBulletin(b),
                            ),
                            Switch(
                              value: isActive,
                              activeThumbColor: _kGreen,
                              onChanged: (_) => _toggleStatus(b),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
