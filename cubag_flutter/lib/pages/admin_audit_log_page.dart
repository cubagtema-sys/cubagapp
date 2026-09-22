import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kBlue = Color(0xFF3b82f6);
const _kRed = Color(0xFFef4444);
const _kPurple = Color(0xFF8b5cf6);
const _kCardBg = Color(0xFF281710);

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
  bool _filtersVisible = true;

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

  void _showActorDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? _kCardBg : Colors.white,
          title: Text(
            'Filter by Admin / Sub-Admin',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      'All Admins & Sub-Admins',
                      style: GoogleFonts.outfit(
                        fontWeight: _filterActorId.isEmpty
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _filterActorId.isEmpty ? _kOrange : null,
                      ),
                    ),
                    trailing: _filterActorId.isEmpty
                        ? const Icon(Icons.check, color: _kOrange, size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _filterActorId = '';
                        _offset = 0;
                      });
                      _fetchLogs();
                    },
                  ),
                  const Divider(height: 1),
                  ..._actorsOptions.map((actor) {
                    final aId = actor['id']?.toString() ?? '';
                    final aName = actor['name']?.toString() ?? 'User #$aId';
                    final aRole = (actor['role']?.toString() ?? 'sub_admin').toUpperCase();
                    final isSelected = _filterActorId == aId;
                    return ListTile(
                      title: Text(
                        aName,
                        style: GoogleFonts.outfit(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? _kOrange : null,
                        ),
                      ),
                      subtitle: Text(
                        aRole.replaceAll('_', ' '),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: aRole.contains('SUPER')
                              ? _kOrange
                              : (aRole.contains('SUB') ? _kPurple : _kBlue),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: _kOrange, size: 18)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _filterActorId = aId;
                          _offset = 0;
                        });
                        _fetchLogs();
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOptionDialog(
    String title,
    List<String> options,
    Function(String) onSelect,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? _kCardBg : Colors.white,
          title: Text(
            'Select $title',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.map((opt) {
                  final label = opt.isEmpty ? 'All ${title}s' : opt;
                  return ListTile(
                    title: Text(label, style: GoogleFonts.outfit(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelect(opt);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogDetailsModal(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? _kCardBg : Colors.white;
        final borderCol = isDark
            ? const Color(0xFF4D2D20)
            : const Color(0xFFe2e8f0);
        final textCol = isDark
            ? const Color(0xFFf8fafc)
            : const Color(0xFF1A0F0A);
        final subTextCol = isDark
            ? const Color(0xFF94a3b8)
            : const Color(0xFF64748b);
        final inputBg = isDark
            ? const Color(0xFF1A0F0A).withAlpha(120)
            : const Color(0xFFf8fafc);

        final actor = log['admin_name'] ?? log['actor_name'] ?? 'Admin';
        final role = (log['admin_role'] ?? log['actor_role'] ?? 'admin').toString();
        final action = log['action']?.toString() ?? 'Action';
        final targetType = log['target_type']?.toString() ?? '—';
        final targetName = log['target_name']?.toString() ?? '—';
        final details = log['details']?.toString() ?? '—';
        final createdAt = log['created_at']?.toString() ?? '—';
        final ipAddress = log['ip_address']?.toString() ?? '127.0.0.1';

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: cardBg,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_edu_rounded,
                  color: _kOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Audit Entry Details',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: textCol,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Timestamp', createdAt, inputBg, borderCol, textCol, subTextCol),
                  const SizedBox(height: 8),
                  _detailRow('Actor / Role', '$actor (${role.toUpperCase()})', inputBg, borderCol, textCol, subTextCol),
                  const SizedBox(height: 8),
                  _detailRow('Action Performed', action, inputBg, borderCol, textCol, subTextCol),
                  const SizedBox(height: 8),
                  _detailRow('Target Type', targetType.toUpperCase(), inputBg, borderCol, textCol, subTextCol),
                  if (targetName != '—') ...[
                    const SizedBox(height: 8),
                    _detailRow('Target Subject / Name', targetName, inputBg, borderCol, textCol, subTextCol),
                  ],
                  if (details != '—') ...[
                    const SizedBox(height: 8),
                    _detailRow('Details / Payload', details, inputBg, borderCol, textCol, subTextCol),
                  ],
                  const SizedBox(height: 8),
                  _detailRow('Origin IP Address', ipAddress, inputBg, borderCol, textCol, subTextCol),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(
    String label,
    String value,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol),
          ),
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textCol,
            ),
          ),
        ),
      ],
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

  Color _actionBadgeColor(String action) {
    final a = action.toLowerCase();
    if (a.contains('create') || a.contains('add') || a.contains('publish')) {
      return _kGreen;
    }
    if (a.contains('update') || a.contains('edit') || a.contains('save')) {
      return _kBlue;
    }
    if (a.contains('delete') || a.contains('archive') || a.contains('reject') || a.contains('suspend')) {
      return _kRed;
    }
    if (a.contains('approve') || a.contains('verified')) return _kPurple;
    return _kOrange;
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

    final displayLogs = _filteredLogs;

    // Determine current actor filter label
    String currentActorLabel = 'All Admins & Sub-Admins';
    if (_filterActorId.isNotEmpty) {
      final match = _actorsOptions.firstWhere(
        (a) => a['id']?.toString() == _filterActorId,
        orElse: () => {'name': 'Actor #$_filterActorId'},
      );
      currentActorLabel = match['name']?.toString() ?? 'Selected Actor';
    }

    return AppLayout(
      title: 'Audit Log',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Administrative Audit Trail',
            subtitle:
                'Real-time tamper-evident log of all operations performed by Super Admins and Sub-Admins.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminOrange,
                  side: const BorderSide(color: kAdminOrange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () =>
                    setState(() => _filtersVisible = !_filtersVisible),
                icon: Icon(
                  _filtersVisible
                      ? Icons.filter_alt_off_rounded
                      : Icons.filter_alt_rounded,
                  size: 16,
                ),
                label: Text(
                  _filtersVisible ? 'Hide Filters' : 'Filter Log',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _fetchLogs(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Refresh',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Metric Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide
                  ? Row(
                      children: [
                        Expanded(
                          child: AdminStatCard(
                            label: 'Total Logged Events',
                            value: '$_total',
                            icon: Icons.history_rounded,
                            color: kAdminBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AdminStatCard(
                            label: 'Active Admins & Staff',
                            value: '${_actorsOptions.isNotEmpty ? _actorsOptions.length : 1}',
                            icon: Icons.admin_panel_settings_rounded,
                            color: kAdminPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AdminStatCard(
                            label: 'Audit Integrity',
                            value: '100% Tamper-Evident',
                            icon: Icons.verified_user_rounded,
                            color: kAdminGreen,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AdminStatCard(
                                label: 'Total Logged Events',
                                value: '$_total',
                                icon: Icons.history_rounded,
                                color: kAdminBlue,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdminStatCard(
                                label: 'Admins & Staff',
                                value: '${_actorsOptions.isNotEmpty ? _actorsOptions.length : 1}',
                                icon: Icons.admin_panel_settings_rounded,
                                color: kAdminPurple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AdminStatCard(
                          label: 'Audit Integrity',
                          value: '100% Tamper-Evident',
                          icon: Icons.verified_user_rounded,
                          color: kAdminGreen,
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: 14),

          // Filters Toolbar
          if (_filtersVisible)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search text input
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: GoogleFonts.inter(fontSize: 14, color: textCol),
                    decoration: InputDecoration(
                      hintText: 'Search logs by admin name, action, target subject...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: subTextCol),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _kOrange),
                      filled: true,
                      fillColor: headerBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kOrange, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Filter Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Actor Filter (Super Admin / Sub-Admin)
                      ActionChip(
                        avatar: const Icon(Icons.person_pin_rounded, size: 15, color: _kPurple),
                        label: Text(
                          _filterActorId.isEmpty ? 'All Admins & Sub-Admins' : 'Admin: $currentActorLabel',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _showActorDialog,
                      ),

                      // Target Type chip
                      ActionChip(
                        avatar: const Icon(Icons.category_outlined, size: 15, color: _kOrange),
                        label: Text(
                          _filterTargetType.isEmpty ? 'All Target Types' : 'Type: $_filterTargetType',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          _showOptionDialog(
                            'Target Type',
                            ['', ..._targetTypeOptions],
                            (v) {
                              setState(() {
                                _filterTargetType = v;
                                _offset = 0;
                              });
                              _fetchLogs();
                            },
                          );
                        },
                      ),

                      // Action Type chip
                      ActionChip(
                        avatar: const Icon(Icons.touch_app_outlined, size: 15, color: _kBlue),
                        label: Text(
                          _filterActionType.isEmpty ? 'All Actions' : 'Action: $_filterActionType',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          _showOptionDialog(
                            'Action Type',
                            ['', 'Created', 'Updated', 'Approved', 'Rejected', 'Deleted', 'Archived'],
                            (v) {
                              setState(() {
                                _filterActionType = v;
                                _offset = 0;
                              });
                              _fetchLogs();
                            },
                          );
                        },
                      ),

                      // From Date
                      ActionChip(
                        avatar: const Icon(Icons.calendar_today_rounded, size: 14, color: _kGreen),
                        label: Text(
                          _filterDateFrom.isEmpty ? 'From: Any' : 'From: $_filterDateFrom',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _pickDate(true),
                      ),

                      // To Date
                      ActionChip(
                        avatar: const Icon(Icons.event_available_rounded, size: 14, color: _kGreen),
                        label: Text(
                          _filterDateTo.isEmpty ? 'To: Any' : 'To: $_filterDateTo',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _pickDate(false),
                      ),

                      if (_hasActiveFilters)
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.clear_all_rounded, size: 16, color: _kRed),
                          label: Text(
                            'Reset',
                            style: GoogleFonts.outfit(color: _kRed, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

          // Audit Log Table
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (displayLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 40, color: subTextCol),
                  const SizedBox(height: 10),
                  Text(
                    'No audit logs found.',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: textCol),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try resetting filters or checking sub-admin activities.',
                    style: GoogleFonts.inter(fontSize: 13, color: subTextCol),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderCol),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(headerBg),
                          headingTextStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: subTextCol,
                            letterSpacing: 0.5,
                          ),
                          dataTextStyle: GoogleFonts.outfit(fontSize: 13, color: textCol),
                          columnSpacing: 20,
                          horizontalMargin: 18,
                          dataRowMinHeight: 56,
                          dataRowMaxHeight: 64,
                          columns: const [
                            DataColumn(label: Text('TIMESTAMP')),
                            DataColumn(label: Text('ACTOR / ADMIN')),
                            DataColumn(label: Text('ACTION')),
                            DataColumn(label: Text('TARGET TYPE')),
                            DataColumn(label: Text('SUBJECT / DETAILS')),
                            DataColumn(label: Text('IP ADDRESS')),
                            DataColumn(label: Text('DETAILS')),
                          ],
                          rows: displayLogs.map((log) {
                            final actor = (log['admin_name'] ?? log['actor_name'] ?? 'Admin').toString();
                            final role = (log['admin_role'] ?? log['actor_role'] ?? 'sub_admin').toString().toUpperCase();
                            final ipAddress = log['ip_address']?.toString() ?? '127.0.0.1';
                            final action = log['action']?.toString() ?? 'Action';
                            final targetType = log['target_type']?.toString() ?? '—';
                            final targetName = log['target_name']?.toString() ?? '—';
                            final createdAt = log['created_at']?.toString() ?? '';
                            final badgeColor = _actionBadgeColor(action);

                            final isSuperAdmin = role.contains('SUPER');
                            final isSubAdmin = role.contains('SUB');

                            return DataRow(
                              cells: [
                                // 1. Timestamp
                                DataCell(
                                  Text(
                                    createdAt.isNotEmpty
                                        ? createdAt.replaceFirst('T', ' ').split('.').first
                                        : '—',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: subTextCol,
                                    ),
                                  ),
                                ),

                                // 2. Actor / Admin
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: (isSuperAdmin ? _kOrange : (isSubAdmin ? _kPurple : _kBlue)).withAlpha(35),
                                        child: Text(
                                          actor.isNotEmpty ? actor[0].toUpperCase() : 'A',
                                          style: GoogleFonts.outfit(
                                            color: isSuperAdmin ? _kOrange : (isSubAdmin ? _kPurple : _kBlue),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            actor,
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: textCol,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: (isSuperAdmin ? _kOrange : (isSubAdmin ? _kPurple : _kBlue)).withAlpha(20),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              role.replaceAll('_', ' '),
                                              style: GoogleFonts.inter(
                                                fontSize: 9,
                                                color: isSuperAdmin ? _kOrange : (isSubAdmin ? _kPurple : _kBlue),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // 3. Action
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: badgeColor.withAlpha(60)),
                                    ),
                                    child: Text(
                                      action,
                                      style: GoogleFonts.outfit(
                                        color: badgeColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),

                                // 4. Target Type
                                DataCell(
                                  Text(
                                    targetType.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: subTextCol,
                                    ),
                                  ),
                                ),

                                // 5. Subject
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      targetName,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: textCol,
                                      ),
                                    ),
                                  ),
                                ),

                                // 6. IP Address
                                DataCell(
                                  Text(
                                    ipAddress,
                                    style: GoogleFonts.inter(fontSize: 11, color: subTextCol),
                                  ),
                                ),

                                // 7. Action Button
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new_rounded, size: 16, color: _kOrange),
                                    tooltip: 'View Full Audit Record',
                                    onPressed: () => _showLogDetailsModal(Map<String, dynamic>.from(log)),
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
          const SizedBox(height: 14),

          // Pagination bar
          if (_total > _limit)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_offset + 1} - ${(_offset + _limit).clamp(0, _total)} of $_total entries',
                  style: GoogleFonts.inter(fontSize: 13, color: subTextCol),
                ),
                Row(
                  children: [
                    IconButton.outlined(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      onPressed: _offset > 0 ? _prevPage : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      onPressed: _offset + _limit < _total ? _nextPage : null,
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
