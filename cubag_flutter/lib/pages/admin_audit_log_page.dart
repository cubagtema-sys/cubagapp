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
  bool _filtersVisible = false;

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

        final actor = log['actor_name']?.toString() ?? 'System';
        final role = log['actor_role']?.toString() ?? 'admin';
        final action = log['action']?.toString() ?? 'Action';
        final targetType = log['target_type']?.toString() ?? '—';
        final targetName = log['target_name']?.toString() ?? '—';
        final createdAt = log['created_at']?.toString() ?? '—';
        final ipAddress = log['ip_address']?.toString() ?? '—';

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
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Audit Entry Details',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: textCol,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(
                    'Timestamp',
                    createdAt,
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    'Admin / Actor',
                    '$actor ($role)',
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    'Action Performed',
                    action,
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    'Target Type',
                    targetType.toUpperCase(),
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    'Target Subject / Name',
                    targetName,
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    'Origin IP Address',
                    ipAddress,
                    inputBg,
                    borderCol,
                    textCol,
                    subTextCol,
                  ),
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
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol),
          ),
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.bold,
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
      final actor = (log['actor_name']?.toString() ?? '').toLowerCase();
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
    if (a.contains('delete') || a.contains('archive') || a.contains('suspend')) {
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

    return AppLayout(
      title: 'Audit Log',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Administrative Audit Trail',
            subtitle:
                'Real-time tamper-evident log of all admin operations, approvals, and platform modifications.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminOrange,
                  side: const BorderSide(color: kAdminOrange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () =>
                    setState(() => _filtersVisible = !_filtersVisible),
                icon: Icon(
                  _filtersVisible
                      ? Icons.filter_alt_off_rounded
                      : Icons.filter_alt_rounded,
                  size: 18,
                ),
                label: Text(
                  _filtersVisible ? 'Hide Filters' : 'Filter Log',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
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
                onPressed: () => _fetchLogs(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  'Refresh',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Metric Cards ─────────────────────────────────────────────────────
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
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Current Page Records',
                  value: '${displayLogs.length}',
                  icon: Icons.view_list_rounded,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Active Administrators',
                  value:
                      '${_actorsOptions.isNotEmpty ? _actorsOptions.length : 1}',
                  icon: Icons.admin_panel_settings_rounded,
                  color: kAdminOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Filter & Search Panel ────────────────────────────────────────────
          AdminToolbar(
            searchHint:
                'Search audit trail by actor, action, or target subject...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            trailing: _hasActiveFilters
                ? TextButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(
                      Icons.clear_all_rounded,
                      size: 16,
                      color: _kRed,
                    ),
                    label: Text(
                      'Reset Filters',
                      style: GoogleFonts.outfit(
                        color: _kRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          if (_filtersVisible)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  // Target Type dropdown chip
                  ActionChip(
                    avatar: const Icon(
                      Icons.category_outlined,
                      size: 16,
                      color: _kOrange,
                    ),
                    label: Text(
                      _filterTargetType.isEmpty
                          ? 'All Target Types'
                          : 'Type: $_filterTargetType',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

                  // Action Type dropdown chip
                  ActionChip(
                    avatar: const Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: _kBlue,
                    ),
                    label: Text(
                      _filterActionType.isEmpty
                          ? 'All Actions'
                          : 'Action: $_filterActionType',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      _showOptionDialog(
                        'Action Type',
                        [
                          '',
                          'Created',
                          'Updated',
                          'Archived',
                          'Deleted',
                          'Approved',
                          'Suspended',
                        ],
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

                  // From date chip
                  ActionChip(
                    avatar: const Icon(
                      Icons.calendar_today_rounded,
                      size: 15,
                      color: _kGreen,
                    ),
                    label: Text(
                      _filterDateFrom.isEmpty
                          ? 'From: Any'
                          : 'From: $_filterDateFrom',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _pickDate(true),
                  ),

                  // To date chip
                  ActionChip(
                    avatar: const Icon(
                      Icons.event_available_rounded,
                      size: 15,
                      color: _kGreen,
                    ),
                    label: Text(
                      _filterDateTo.isEmpty ? 'To: Any' : 'To: $_filterDateTo',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _pickDate(false),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // ── Tabular Audit Log Table ──────────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (displayLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 48,
                    color: subTextCol,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No audit logs found.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: textCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try clearing search filters or refreshing the page.',
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
                            DataColumn(label: Text('TIMESTAMP')),
                            DataColumn(label: Text('ACTOR / ADMIN')),
                            DataColumn(label: Text('IP ADDRESS')),
                            DataColumn(label: Text('ACTION PERFORMED')),
                            DataColumn(label: Text('TARGET TYPE')),
                            DataColumn(label: Text('TARGET SUBJECT / DETAILS')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: displayLogs.map((log) {
                            final actor =
                                log['actor_name']?.toString() ?? 'Admin';
                            final role =
                                log['actor_role']?.toString() ?? 'admin';
                            final ipAddress =
                                log['ip_address']?.toString() ?? '127.0.0.1';
                            final action =
                                log['action']?.toString() ?? 'Action';
                            final targetType =
                                log['target_type']?.toString() ?? '—';
                            final targetName =
                                log['target_name']?.toString() ?? '—';
                            final createdAt =
                                log['created_at']?.toString() ?? '';
                            final badgeColor = _actionBadgeColor(action);

                            return DataRow(
                              cells: [
                                // 1. Timestamp
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 14,
                                        color: _kOrange,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        createdAt.isNotEmpty
                                            ? createdAt
                                                  .replaceFirst('T', ' ')
                                                  .split('.')
                                                  .first
                                            : '—',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: textCol,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 2. Actor / Admin
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: _kBlue.withAlpha(40),
                                        child: Text(
                                          actor.isNotEmpty
                                              ? actor[0].toUpperCase()
                                              : 'A',
                                          style: GoogleFonts.outfit(
                                            color: _kBlue,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            actor,
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                              color: textCol,
                                            ),
                                          ),
                                          Text(
                                            role.toUpperCase(),
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: subTextCol,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // 3. IP Address
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(
                                              0xFF1A0F0A,
                                            ).withAlpha(150)
                                          : const Color(0xFFf1f5f9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.lan_outlined,
                                          size: 13,
                                          color: _kBlue,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          ipAddress,
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: textCol,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // 4. Action Performed Badge
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: badgeColor.withAlpha(50),
                                      ),
                                    ),
                                    child: Text(
                                      action,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                ),

                                // 5. Target Type
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      targetType.toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: subTextCol,
                                      ),
                                    ),
                                  ),
                                ),

                                // 6. Target Subject & Details
                                DataCell(
                                  Container(
                                    constraints: BoxConstraints(
                                      minWidth: 180,
                                      maxWidth: constraints.maxWidth > 900
                                          ? constraints.maxWidth * 0.28
                                          : 280,
                                    ),
                                    child: Text(
                                      targetName,
                                      style: GoogleFonts.inter(
                                        fontSize: 17,
                                        color: textCol,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),

                                // 7. Action: Inspect
                                DataCell(
                                  IconButton(
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: _kOrange,
                                    ),
                                    tooltip: 'View Full Audit Record',
                                    onPressed: () => _showLogDetailsModal(
                                      Map<String, dynamic>.from(log),
                                    ),
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

          const SizedBox(height: 16),

          // ── Pagination Bar ───────────────────────────────────────────────────
          if (_total > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_offset + 1}–${(_offset + _limit).clamp(0, _total)} of $_total audit entries',
                  style: GoogleFonts.inter(color: subTextCol, fontSize: 17),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textCol,
                        side: BorderSide(color: borderCol),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _offset > 0 ? _prevPage : null,
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      label: const Text('Previous'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textCol,
                        side: BorderSide(color: borderCol),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _offset + _limit < _total ? _nextPage : null,
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
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
        return AlertDialog(
          title: Text(
            'Select $title',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 320,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final opt = options[i];
                return ListTile(
                  title: Text(
                    opt.isEmpty ? 'All' : opt,
                    style: GoogleFonts.inter(fontSize: 18),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect(opt);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
