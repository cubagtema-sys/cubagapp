import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kCardBg = Color(0xFF281710);

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
                style: GoogleFonts.outfit(
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
                style: GoogleFonts.inter(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final headerBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(150)
        : const Color(0xFFf8fafc);
    final textCol = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextCol = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);

    final totalPorts = _ports.length;
    final activePorts = _ports.where((p) => p['is_active'] == true).length;
    final inactivePorts = totalPorts - activePorts;
    final displayPorts = _filteredPorts;

    return AppLayout(
      title: 'Ports of Operation',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Ports & Border Terminals',
            subtitle:
                'Manage operational entry points, customs terminals, and border stations across Ghana.',
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
                onPressed: () => _showPortDialog(),
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: Text(
                  'Add New Port',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Metric Stats Cards ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Ports',
                  value: '$totalPorts',
                  icon: Icons.anchor_rounded,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Active Locations',
                  value: '$activePorts',
                  icon: Icons.check_circle_outline_rounded,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Inactive / Disabled',
                  value: '$inactivePorts',
                  icon: Icons.pause_circle_outline_rounded,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search & Filter Controls ─────────────────────────────────────────
          AdminToolbar(
            searchHint: 'Search by port name or code...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            filters: [
              AdminFilterChip(
                label: 'All Ports',
                count: totalPorts,
                isSelected: _filterTab == 0,
                onTap: () => setState(() => _filterTab = 0),
              ),
              AdminFilterChip(
                label: 'Active',
                count: activePorts,
                isSelected: _filterTab == 1,
                onTap: () => setState(() => _filterTab = 1),
                selectedColor: kAdminGreen,
              ),
              AdminFilterChip(
                label: 'Inactive',
                count: inactivePorts,
                isSelected: _filterTab == 2,
                onTap: () => setState(() => _filterTab = 2),
                selectedColor: Colors.grey.shade700,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Tabular Ports DataTable ──────────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (displayPorts.isEmpty)
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
                    Icons.location_off_outlined,
                    size: 48,
                    color: subTextCol,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No ports match your filter.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: textCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try clearing the search filter or adding a new port location.',
                    style: GoogleFonts.inter(fontSize: 17, color: subTextCol),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(headerBg),
                          headingTextStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: subTextCol,
                            letterSpacing: 0.5,
                          ),
                          dataTextStyle: GoogleFonts.outfit(
                            fontSize: 17,
                            color: textCol,
                          ),
                          columnSpacing: 24,
                          horizontalMargin: 24,
                          dataRowMinHeight: 62,
                          dataRowMaxHeight: 74,
                          columns: const [
                            DataColumn(label: Text('PORT / TERMINAL NAME')),
                            DataColumn(label: Text('PORT CODE')),
                            DataColumn(label: Text('OPERATIONAL STATUS')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: displayPorts.map((p) {
                            final name =
                                p['name']?.toString() ?? 'Unnamed Port';
                            final code = p['code']?.toString() ?? '—';
                            final isActive = p['is_active'] == true;

                            return DataRow(
                              cells: [
                                // 1. Port Name
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? _kGreen.withAlpha(25)
                                              : Colors.grey.withAlpha(25),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.anchor_rounded,
                                          size: 18,
                                          color: isActive
                                              ? _kGreen
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        name,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: textCol,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 2. Port Code
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(
                                              0xFF1A0F0A,
                                            ).withAlpha(150)
                                          : const Color(0xFFf1f5f9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Text(
                                      code.isNotEmpty ? code : '—',
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _kOrange,
                                      ),
                                    ),
                                  ),
                                ),

                                // 3. Status Switch & Badge
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? _kGreen.withAlpha(25)
                                              : Colors.grey.withAlpha(25),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          isActive
                                              ? 'Operational / Active'
                                              : 'Inactive',
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isActive
                                                ? _kGreen
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Switch(
                                        value: isActive,
                                        activeThumbColor: _kGreen,
                                        onChanged: (_) => _togglePortStatus(p),
                                      ),
                                    ],
                                  ),
                                ),

                                // 4. Actions
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: _kOrange,
                                        ),
                                        tooltip: 'Edit Port Details',
                                        onPressed: () => _showPortDialog(p),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
