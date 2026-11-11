import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kRed = Color(0xFFEF4444);
const _kSlate = Color(0xFF64748B);

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
    String colorHex = existing?['status_color']?.toString() ?? '#2E7D32';
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.anchor_rounded, color: _kOrange, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                isEdit ? 'Edit Port Bulletin' : 'Post Port Bulletin',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Publish operational status updates for cargo terminals displayed on member portals & dashboard.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: portCtrl,
                    style: TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: 'Port / Terminal Name *',
                      hintText: 'e.g. Tema Port Terminal 3',
                      prefixIcon: Icon(Icons.location_city_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: codeCtrl,
                          style: TextStyle(fontSize: 13.5),
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            hintText: 'e.g. TMP',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'Operational', child: Text('Operational (Green)')),
                            DropdownMenuItem(value: 'Normal', child: Text('Normal (Green)')),
                            DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance (Orange)')),
                            DropdownMenuItem(value: 'Restricted', child: Text('Restricted (Red)')),
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: noticeCtrl,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Live Operational Notice *',
                      hintText: 'e.g. MPS Terminal 3 fully operational. Digital gate clearance active.',
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
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
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
                      }
                    },
              child: submitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? 'Save Changes' : 'Post Bulletin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
        title: Text('Archive Port Bulletin?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  Color _badgeColor(String status) {
    switch (status.toLowerCase()) {
      case 'operational':
      case 'normal':
        return _kGreen;
      case 'maintenance':
        return _kOrange;
      case 'restricted':
        return _kRed;
      default:
        return _kBlue;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderCol = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF1F1612);
    final subTextColor = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    final total = _bulletins.length;
    final active = _bulletins.where((b) => b['is_active'] == true).length;
    final inactive = total - active;
    final bulletins = _filteredBulletins;

    return AppLayout(
      title: 'Port Operational News',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 950;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  AdminHeader(
                    title: 'Port Bulletins & Status Updates',
                    subtitle: 'Live operational notices and harbor clearance advisories across Ghana ports.',
                    actions: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                          side: BorderSide(color: borderCol),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _fetchBulletins,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text('Refresh', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () => _showBulletinDialog(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('Post Bulletin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Maintained KPI Cards Row (Interactive)
                  _buildKPIRow(isDark, cardBg, borderCol, textColor, subTextColor, total, active, inactive),
                  const SizedBox(height: 16),

                  // Filter & Search Toolbar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderCol),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(() => _searchQuery = v.trim()),
                              style: TextStyle(fontSize: 13.5, color: textColor),
                              decoration: InputDecoration(
                                hintText: 'Search by port, terminal code, or operational notice...',
                                hintStyle: TextStyle(fontSize: 12.5, color: subTextColor),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFFAF6F0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Close',
                                        icon: const Icon(Icons.close_rounded, size: 14),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _filterPill('All ($total)', _filterTab == 0, () => setState(() => _filterTab = 0), borderCol, textColor),
                              const SizedBox(width: 6),
                              _filterPill('Active ($active)', _filterTab == 1, () => setState(() => _filterTab = 1), borderCol, textColor, activeColor: _kGreen),
                              const SizedBox(width: 6),
                              _filterPill('Archived ($inactive)', _filterTab == 2, () => setState(() => _filterTab = 2), borderCol, textColor, activeColor: _kSlate),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Content List
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: List.generate(3, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
                      ),
                    )
                  else if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  else if (bulletins.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderCol),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.anchor_rounded, size: 36, color: subTextColor),
                            const SizedBox(height: 8),
                            Text('No port bulletins found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                          ],
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: bulletins.map((b) {
                        final cardWidth = isDesktop ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
                        return SizedBox(
                          width: cardWidth,
                          child: _buildBulletinCard(b, isDark, cardBg, borderCol, textColor, subTextColor),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBulletinCard(
    dynamic b,
    bool isDark,
    Color cardBg,
    Color borderCol,
    Color textColor,
    Color subTextColor,
  ) {
    final isActive = b['is_active'] == true;
    final statusStr = b['status']?.toString() ?? 'Operational';
    final badgeColor = _badgeColor(statusStr);
    final portName = b['port_name']?.toString() ?? '';
    final code = b['code']?.toString() ?? '';
    final notice = b['notice']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.anchor_rounded, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: SelectableText(
                            portName,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                          ),
                        ),
                        if (code.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: borderCol),
                            ),
                            child: SelectableText(
                              code,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: subTextColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        statusStr.toUpperCase(),
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: isActive,
                  activeThumbColor: _kGreen,
                  onChanged: (_) => _toggleStatus(b),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFFAF6F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderCol.withValues(alpha: 0.7)),
            ),
            child: SelectableText(
              notice,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: subTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: notice));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notice copied to clipboard'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text('Copy Notice', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    color: _kBlue,
                    tooltip: 'Edit Bulletin',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showBulletinDialog(b),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    color: _kRed,
                    tooltip: 'Archive',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteBulletin(b),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKPIRow(
    bool isDark,
    Color cardBg,
    Color borderCol,
    Color textColor,
    Color subTextColor,
    int total,
    int active,
    int inactive,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        final cards = [
          _kpiCard('Total Bulletins', '$total', Icons.feed_outlined, _kBlue, _filterTab == 0, () => setState(() => _filterTab = 0), isDark, cardBg, borderCol, textColor, subTextColor),
          _kpiCard('Active Live', '$active', Icons.check_circle_outline_rounded, _kGreen, _filterTab == 1, () => setState(() => _filterTab = 1), isDark, cardBg, borderCol, textColor, subTextColor),
          _kpiCard('Archived / Hidden', '$inactive', Icons.pause_circle_outline_rounded, _kSlate, _filterTab == 2, () => setState(() => _filterTab = 2), isDark, cardBg, borderCol, textColor, subTextColor),
        ];

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((c) => Container(width: 170, margin: const EdgeInsets.only(right: 8), child: c)).toList(),
          ),
        );
      },
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
    Color cardBg,
    Color borderCol,
    Color textColor,
    Color subTextColor,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.22 : 0.1) : cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : borderCol,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isSelected ? color : subTextColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(String label, bool isSelected, VoidCallback onTap, Color borderColor, Color textColor, {Color? activeColor}) {
    final col = activeColor ?? _kOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? col : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? col : borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : textColor,
          ),
        ),
      ),
    );
  }
}
