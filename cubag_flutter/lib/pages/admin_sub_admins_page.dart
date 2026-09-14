import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kBlue = Color(0xFF3b82f6);
const _kRed = Color(0xFFef4444);
const _kAmber = Color(0xFFf59e0b);
const _kPurple = Color(0xFF8b5cf6);
const _kIndigo = Color(0xFF6366f1);
const _kCardBg = Color(0xFF281710);

// All available permission modules — must match backend ALL_PERMISSIONS list.
const _kAllPermissions = [
  'members',
  'payments',
  'tickets',
  'announcements',
  'schedules',
  'events',
  'surveys',
  'intelligence',
  'audit_log',
  'fees',
  'settings',
  'compliance',
  'documents',
  'messaging',
  'notifications',
];

const _kPermissionLabels = {
  'members': 'Member Management',
  'payments': 'Financial Center',
  'tickets': 'Support Tickets',
  'announcements': 'Announcements',
  'schedules': 'Cargo Schedules',
  'events': 'Events & Meetings',
  'surveys': 'Surveys & Elections',
  'intelligence': 'Intelligence Hub',
  'audit_log': 'Audit Log',
  'fees': 'Platform Fees',
  'settings': 'System Settings',
  'compliance': 'Compliance & Licensing',
  'documents': 'Documents Hub',
  'messaging': 'Member Messaging',
  'notifications': 'Broadcasts & Alerts',
};

const _kPermissionDescriptions = {
  'members': 'View, approve, and manage directory members and profiles',
  'payments': 'Process dues, invoices, and review incoming payments',
  'tickets': 'Resolve and reply to member support inquiries',
  'announcements': 'Create and publish portal-wide announcements',
  'schedules': 'Manage vessel arrivals, departure schedules, and ports',
  'events': 'Organize AGMs, conferences, and check-in registrations',
  'surveys': 'Create member polls, election ballots, and view results',
  'intelligence': 'Post trade intelligence updates, news, and advisory reports',
  'audit_log': 'Inspect administrative activity audit records and IP logs',
  'fees': 'Configure membership dues rates and verification fees',
  'settings': 'Adjust association platform settings and compliance rules',
  'compliance': 'Review Member ID renewal applications and scores',
  'documents': 'Inspect, approve, and download verified member documents',
  'messaging': 'Direct messaging with verified customs brokers',
  'notifications': 'Send push broadcasts and emergency alerts',
};

const _kPermissionIcons = {
  'members': Icons.people_outline_rounded,
  'payments': Icons.payments_outlined,
  'tickets': Icons.support_agent_outlined,
  'announcements': Icons.campaign_outlined,
  'schedules': Icons.local_shipping_outlined,
  'events': Icons.event_outlined,
  'surveys': Icons.how_to_vote_outlined,
  'intelligence': Icons.cell_tower_rounded,
  'audit_log': Icons.history_outlined,
  'fees': Icons.request_quote_outlined,
  'settings': Icons.settings_outlined,
  'compliance': Icons.verified_user_outlined,
  'documents': Icons.folder_shared_outlined,
  'messaging': Icons.chat_bubble_outline_rounded,
  'notifications': Icons.notifications_none_rounded,
};

// Preset role templates
class _RoleTemplate {
  final String id, label, description;
  final IconData icon;
  final Color color;
  final List<String> permissions;
  const _RoleTemplate({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.permissions,
  });
}

const _kRoleTemplates = [
  _RoleTemplate(
    id: 'compliance',
    label: 'Compliance Officer',
    description: 'Member ID, renewals & document inspection',
    icon: Icons.verified_user_outlined,
    color: _kGreen,
    permissions: ['compliance', 'documents', 'members', 'audit_log'],
  ),
  _RoleTemplate(
    id: 'membership',
    label: 'Membership Officer',
    description: 'Member onboarding, status & support',
    icon: Icons.badge_outlined,
    color: _kBlue,
    permissions: [
      'members',
      'payments',
      'tickets',
      'announcements',
      'documents',
    ],
  ),
  _RoleTemplate(
    id: 'finance',
    label: 'Finance Officer',
    description: 'Payments, dues & fee configuration',
    icon: Icons.account_balance_outlined,
    color: _kGreen,
    permissions: ['payments', 'fees', 'members', 'documents'],
  ),
  _RoleTemplate(
    id: 'communications',
    label: 'Communications',
    description: 'Announcements, events, messaging & broadcasts',
    icon: Icons.campaign_outlined,
    color: _kAmber,
    permissions: [
      'announcements',
      'events',
      'intelligence',
      'messaging',
      'notifications',
    ],
  ),
  _RoleTemplate(
    id: 'operations',
    label: 'Operations Support',
    description: 'Tickets, schedules & member queries',
    icon: Icons.support_agent_outlined,
    color: _kPurple,
    permissions: [
      'tickets',
      'schedules',
      'members',
      'announcements',
      'messaging',
    ],
  ),
];

class AdminSubAdminsPage extends StatefulWidget {
  const AdminSubAdminsPage({super.key});
  @override
  State<AdminSubAdminsPage> createState() => _AdminSubAdminsPageState();
}

class _AdminSubAdminsPageState extends State<AdminSubAdminsPage> {
  bool _loading = true;
  List<dynamic> _subAdmins = [];
  String _searchQuery = '';
  String _filterRole = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/sub-admins/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _subAdmins = res.data['sub_admins'] ?? [];
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_sub_admins_page', e, st);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: error ? _kRed : _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _remove(
    Map<String, dynamic> sa,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        title: Text(
          'Remove Sub-Admin',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        content: Text(
          'Demote ${sa['name']} back to a regular member?\nAll their administrative permissions will be revoked.',
          style: GoogleFonts.outfit(color: subTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: subTextColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await ApiService().delete('/sub-admins/${sa['id']}');
      if (res.statusCode == 200) {
        _toast('Sub-admin removed successfully');
        _fetch();
      } else {
        _toast(
          res.data['message'] ?? 'Failed to remove sub-admin',
          error: true,
        );
      }
    } catch (e) {
      _toast('Network error: $e', error: true);
    }
  }

  void _showCreateSheet(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
    Color inputBg,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateSubAdminSheet(
        isDark: isDark,
        cardBg: cardBg,
        borderColor: borderColor,
        textColor: textColor,
        subTextColor: subTextColor,
        inputBg: inputBg,
        onCreated: () {
          Navigator.pop(ctx);
          _toast('Sub-admin created successfully');
          _fetch();
        },
      ),
    );
  }

  void _showEditModal(Map<String, dynamic> sa) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _EditPermissionsDialog(
        subAdmin: sa,
        onSaved: () {
          Navigator.pop(ctx);
          _toast('Permissions updated successfully');
          _fetch();
        },
      ),
    );
  }

  _RoleTemplate? _getMatchingTemplate(List<String> perms) {
    final permsSet = Set<String>.from(perms);
    return _kRoleTemplates.cast<_RoleTemplate?>().firstWhere(
      (t) =>
          t != null &&
          Set<String>.from(t.permissions).difference(permsSet).isEmpty &&
          permsSet.difference(Set<String>.from(t.permissions)).isEmpty,
      orElse: () => null,
    );
  }

  List<dynamic> get _filteredSubAdmins {
    return _subAdmins.where((sa) {
      final name = (sa['name']?.toString() ?? '').toLowerCase();
      final email = (sa['email']?.toString() ?? '').toLowerCase();
      final perms = List<String>.from(sa['permissions'] ?? []);
      final permLabels = perms
          .map((p) => (_kPermissionLabels[p] ?? p).toLowerCase())
          .join(' ');
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          permLabels.contains(q);

      if (!matchesSearch) return false;

      if (_filterRole == 'all') return true;

      if (_filterRole == 'compliance') {
        return perms.contains('compliance') || perms.contains('documents');
      }
      if (_filterRole == 'finance') {
        return perms.contains('payments') || perms.contains('fees');
      }
      if (_filterRole == 'membership') {
        return perms.contains('members');
      }
      if (_filterRole == 'communications') {
        return perms.contains('announcements') ||
            perms.contains('events') ||
            perms.contains('messaging') ||
            perms.contains('notifications');
      }
      if (_filterRole == 'operations') {
        return perms.contains('tickets') || perms.contains('schedules');
      }
      if (_filterRole == 'full') {
        return perms.length >= _kAllPermissions.length;
      }
      if (_filterRole == 'custom') {
        final match = _getMatchingTemplate(perms);
        return match == null &&
            perms.isNotEmpty &&
            perms.length < _kAllPermissions.length;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

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
    final inputBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(120)
        : const Color(0xFFf8fafc);

    // Only full admins and super admins may access this page
    if (auth.userRole != 'admin' && auth.userRole != 'super_admin') {
      return AppLayout(
        title: 'Sub-Admins',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 48,
                color: subTextCol.withAlpha(120),
              ),
              const SizedBox(height: 12),
              Text(
                'Full admin access required',
                style: GoogleFonts.outfit(color: subTextCol, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final totalSubAdmins = _subAdmins.length;
    final fullAccessCount = _subAdmins.where((sa) {
      final perms = List<String>.from(sa['permissions'] ?? []);
      return perms.length >= _kAllPermissions.length;
    }).length;
    final scopedCount = totalSubAdmins - fullAccessCount;
    final displaySubAdmins = _filteredSubAdmins;

    return AppLayout(
      title: 'Sub-Admins & Permissions',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Sub-Administrators & RBAC Access',
            subtitle:
                'Manage delegated administrative accounts, assign operational module scopes, and configure RBAC permissions.',
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
                onPressed: () => _showCreateSheet(
                  isDark,
                  cardBg,
                  borderCol,
                  textCol,
                  subTextCol,
                  inputBg,
                ),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: Text(
                  'Add Sub-Admin',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Metric Summary Cards ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Sub-Admins',
                  value: totalSubAdmins.toString(),
                  icon: Icons.admin_panel_settings_rounded,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Full Access Admins',
                  value: fullAccessCount.toString(),
                  icon: Icons.verified_user_rounded,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Scoped Officers',
                  value: scopedCount.toString(),
                  icon: Icons.tune_rounded,
                  color: kAdminPurple,
                ),
              ),
            ],
          ),
          // ── Search & Filter Controls ─────────────────────────────────────────
          AdminToolbar(
            searchHint: 'Search sub-admin by name, email, or module...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A0F0A).withAlpha(150)
                    : const Color(0xFFf8fafc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderCol),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterRole,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: kAdminOrange,
                  ),
                  dropdownColor: cardBg,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textCol,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(
                      value: 'compliance',
                      child: Text('Compliance'),
                    ),
                    DropdownMenuItem(value: 'finance', child: Text('Finance')),
                    DropdownMenuItem(
                      value: 'membership',
                      child: Text('Membership'),
                    ),
                    DropdownMenuItem(
                      value: 'operations',
                      child: Text('Operations'),
                    ),
                    DropdownMenuItem(
                      value: 'communications',
                      child: Text('Communications'),
                    ),
                    DropdownMenuItem(value: 'full', child: Text('Full Access')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _filterRole = v);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Tabular Sub-Admins DataTable ─────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (displaySubAdmins.isEmpty)
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
                    Icons.admin_panel_settings_outlined,
                    size: 48,
                    color: subTextCol,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No sub-admin accounts match your filter.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: textCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Click "Add Sub-Admin" to delegate platform module responsibilities.',
                    style: GoogleFonts.inter(fontSize: 15, color: subTextCol),
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
                            fontSize: 14,
                            color: subTextCol,
                            letterSpacing: 0.5,
                          ),
                          dataTextStyle: GoogleFonts.outfit(
                            fontSize: 15,
                            color: textCol,
                          ),
                          columnSpacing: 24,
                          horizontalMargin: 24,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('SUB-ADMIN OFFICER')),
                            DataColumn(label: Text('ROLE TEMPLATE')),
                            DataColumn(
                              label: Text('MODULE SCOPE / PERMISSIONS'),
                            ),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: displaySubAdmins.map((sa) {
                            final name = sa['name']?.toString() ?? 'Sub-Admin';
                            final email = sa['email']?.toString() ?? '—';
                            final perms = List<String>.from(
                              sa['permissions'] ?? [],
                            );
                            final match = _getMatchingTemplate(perms);
                            final roleLabel =
                                match?.label ??
                                (perms.isEmpty
                                    ? 'No Access'
                                    : (perms.length >= _kAllPermissions.length
                                          ? 'Full Access Admin'
                                          : 'Custom Scope (${perms.length})'));
                            final roleColor =
                                match?.color ??
                                (perms.isEmpty
                                    ? _kRed
                                    : (perms.length >= _kAllPermissions.length
                                          ? _kGreen
                                          : _kIndigo));

                            return DataRow(
                              cells: [
                                // 1. Sub-Admin Officer (Avatar + Name + Email)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: roleColor.withAlpha(
                                          35,
                                        ),
                                        child: Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : 'A',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            color: roleColor,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: textCol,
                                            ),
                                          ),
                                          Text(
                                            email,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: subTextCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // 2. Role Template Badge
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roleColor.withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: roleColor.withAlpha(60),
                                      ),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: roleColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),

                                // 3. Module Scope / Permissions Preview
                                DataCell(
                                  Container(
                                    constraints: BoxConstraints(
                                      minWidth: 180,
                                      maxWidth: constraints.maxWidth > 900
                                          ? constraints.maxWidth * 0.30
                                          : 280,
                                    ),
                                    child: perms.isEmpty
                                        ? Text(
                                            'No modules granted',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: _kRed,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        : Text(
                                            perms
                                                .map(
                                                  (p) =>
                                                      _kPermissionLabels[p] ??
                                                      p,
                                                )
                                                .join(', '),
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: subTextCol,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                ),

                                // 4. Status
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _kGreen.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: _kGreen,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Active',
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _kGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // 5. Action Buttons
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: _kOrange.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: _kOrange.withAlpha(50),
                                          ),
                                        ),
                                        child: IconButton(
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          icon: const Icon(
                                            Icons.admin_panel_settings_outlined,
                                            size: 18,
                                            color: _kOrange,
                                          ),
                                          tooltip:
                                              'Configure Module Privileges',
                                          onPressed: () => _showEditModal(
                                            Map<String, dynamic>.from(sa),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: _kRed.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: _kRed.withAlpha(50),
                                          ),
                                        ),
                                        child: IconButton(
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: _kRed,
                                          ),
                                          tooltip: 'Revoke Access & Remove',
                                          onPressed: () => _remove(
                                            Map<String, dynamic>.from(sa),
                                            cardBg,
                                            borderCol,
                                            textCol,
                                            subTextCol,
                                          ),
                                        ),
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

// ── Create Sub-Admin bottom sheet ──────────────────────────────────────────────
class _CreateSubAdminSheet extends StatefulWidget {
  final VoidCallback onCreated;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color textColor;
  final Color subTextColor;
  final Color inputBg;

  const _CreateSubAdminSheet({
    required this.onCreated,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.textColor,
    required this.subTextColor,
    required this.inputBg,
  });
  @override
  State<_CreateSubAdminSheet> createState() => _CreateSubAdminSheetState();
}

class _CreateSubAdminSheetState extends State<_CreateSubAdminSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final Set<String> _selectedPerms = {};
  String? _selectedTemplate;
  bool _loading = false;
  bool _obscure = true;

  void _applyTemplate(String templateId) {
    final tpl = _kRoleTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => _kRoleTemplates.first,
    );
    setState(() {
      _selectedTemplate = templateId;
      _selectedPerms.clear();
      _selectedPerms.addAll(tpl.permissions);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().post(
        '/sub-admins/',
        data: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim().toLowerCase(),
          'password': _passCtrl.text.trim(),
          'permissions': _selectedPerms.toList(),
        },
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        widget.onCreated();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data['message'] ?? 'Failed to create sub-admin',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error', style: GoogleFonts.outfit())),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.borderColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'New Sub-Admin Account',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: widget.textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Provision a new officer with scoped operational modules.',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: widget.subTextColor,
                ),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameCtrl,
                style: GoogleFonts.outfit(
                  color: widget.textColor,
                  fontSize: 16,
                ),
                decoration: _inputDeco(
                  label: 'Full Name',
                  icon: Icons.person_outline_rounded,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.outfit(
                  color: widget.textColor,
                  fontSize: 16,
                ),
                decoration: _inputDeco(
                  label: 'Email Address',
                  icon: Icons.email_outlined,
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Valid email required'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: GoogleFonts.outfit(
                  color: widget.textColor,
                  fontSize: 16,
                ),
                decoration: _inputDeco(
                  label: 'Temporary Password',
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: widget.subTextColor,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),

              const SizedBox(height: 24),
              Text(
                'Role Preset Template',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: widget.textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a role to auto-configure module permissions.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: widget.subTextColor,
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kRoleTemplates.map((tpl) {
                  final isSelected = _selectedTemplate == tpl.id;
                  return ChoiceChip(
                    avatar: Icon(
                      tpl.icon,
                      size: 16,
                      color: isSelected ? Colors.white : tpl.color,
                    ),
                    label: Text(
                      tpl.label,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: tpl.color,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : widget.textColor,
                    ),
                    onSelected: (_) => _applyTemplate(tpl.id),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    Text(
                      'Granted Modules (${_selectedPerms.length} of ${_kAllPermissions.length})',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: widget.textColor,
                      ),
                    ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedPerms.length == _kAllPermissions.length) {
                          _selectedPerms.clear();
                        } else {
                          _selectedPerms.addAll(_kAllPermissions);
                        }
                      });
                    },
                    child: Text(
                      _selectedPerms.length == _kAllPermissions.length
                          ? 'Clear all'
                          : 'Select all',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ..._kAllPermissions.map((perm) {
                final isGranted = _selectedPerms.contains(perm);
                return CheckboxListTile(
                  dense: true,
                  title: Text(
                    _kPermissionLabels[perm] ?? perm,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: widget.textColor,
                    ),
                  ),
                  subtitle: Text(
                    _kPermissionDescriptions[perm] ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: widget.subTextColor,
                    ),
                  ),
                  secondary: Icon(
                    _kPermissionIcons[perm] ?? Icons.check_rounded,
                    size: 18,
                    color: isGranted ? _kOrange : widget.subTextColor,
                  ),
                  value: isGranted,
                  activeColor: _kOrange,
                  side: BorderSide(color: widget.subTextColor.withAlpha(120)),
                  onChanged: (v) => setState(() {
                    v == true
                        ? _selectedPerms.add(perm)
                        : _selectedPerms.remove(perm);
                    _selectedTemplate = null;
                  }),
                );
              }),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Create Sub-Admin',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: widget.subTextColor),
      suffixIcon: suffix,
      filled: true,
      fillColor: widget.inputBg,
      labelStyle: GoogleFonts.outfit(fontSize: 16, color: widget.subTextColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.borderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}

// ── Redesigned Edit permissions modal dialog ──────────────────────────────────
class _EditPermissionsDialog extends StatefulWidget {
  final Map<String, dynamic> subAdmin;
  final VoidCallback onSaved;

  const _EditPermissionsDialog({required this.subAdmin, required this.onSaved});

  @override
  State<_EditPermissionsDialog> createState() => _EditPermissionsDialogState();
}

class _EditPermissionsDialogState extends State<_EditPermissionsDialog> {
  late Set<String> _selected;
  String? _activeTemplate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.subAdmin['permissions'] ?? []);
  }

  void _applyTemplate(String templateId) {
    final tpl = _kRoleTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => _kRoleTemplates.first,
    );
    setState(() {
      _activeTemplate = templateId;
      _selected.clear();
      _selected.addAll(tpl.permissions);
    });
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().put(
        '/sub-admins/${widget.subAdmin['id']}/permissions',
        data: {'permissions': _selected.toList()},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        widget.onSaved();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data['message'] ?? 'Failed to update permissions',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error', style: GoogleFonts.outfit())),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textCol = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextCol = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final name = widget.subAdmin['name']?.toString() ?? 'Sub-Admin';
    final email = widget.subAdmin['email']?.toString() ?? '';

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 720,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // ── Dialog Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderCol)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: _kOrange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Module Privileges: $name',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: textCol,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$email • ${_selected.length} of ${_kAllPermissions.length} modules granted',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: subTextCol,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── Dialog Body ────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role Presets Bar
                    Text(
                      'Role Preset Templates',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textCol,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quickly apply standard operational privilege templates:',
                      style: GoogleFonts.inter(fontSize: 14, color: subTextCol),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._kRoleTemplates.map((tpl) {
                          final isSelected = _activeTemplate == tpl.id;
                          return ActionChip(
                            avatar: Icon(
                              tpl.icon,
                              size: 15,
                              color: isSelected ? Colors.white : tpl.color,
                            ),
                            label: Text(
                              tpl.label,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: isSelected
                                ? tpl.color
                                : tpl.color.withAlpha(20),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : tpl.color,
                            ),
                            onPressed: () => _applyTemplate(tpl.id),
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(
                            Icons.select_all_rounded,
                            size: 15,
                            color: _kGreen,
                          ),
                          label: const Text(
                            'Full Access (All)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          backgroundColor: _kGreen.withAlpha(20),
                          labelStyle: const TextStyle(color: _kGreen),
                          onPressed: () {
                            setState(() {
                              _activeTemplate = 'full';
                              _selected.addAll(_kAllPermissions);
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.clear_rounded,
                            size: 15,
                            color: _kRed,
                          ),
                          label: const Text(
                            'Revoke All',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          backgroundColor: _kRed.withAlpha(20),
                          labelStyle: const TextStyle(color: _kRed),
                          onPressed: () {
                            setState(() {
                              _activeTemplate = 'none';
                              _selected.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Grid of Permission Modules
                    Text(
                      'Granular Module Access Controls',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textCol,
                      ),
                    ),
                    const SizedBox(height: 14),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 2.8,
                          ),
                      itemCount: _kAllPermissions.length,
                      itemBuilder: (ctx, i) {
                        final perm = _kAllPermissions[i];
                        final isGranted = _selected.contains(perm);
                        final label = _kPermissionLabels[perm] ?? perm;
                        final desc = _kPermissionDescriptions[perm] ?? '';
                        final icon =
                            _kPermissionIcons[perm] ?? Icons.check_rounded;

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              isGranted
                                  ? _selected.remove(perm)
                                  : _selected.add(perm);
                              _activeTemplate = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isGranted
                                  ? _kOrange.withAlpha(20)
                                  : (isDark
                                        ? const Color(0xFF1A0F0A).withAlpha(120)
                                        : const Color(0xFFf8fafc)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isGranted
                                    ? _kOrange.withAlpha(120)
                                    : borderCol,
                                width: isGranted ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isGranted
                                        ? _kOrange
                                        : Colors.grey.withAlpha(30),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 16,
                                    color: isGranted
                                        ? Colors.white
                                        : subTextCol,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        label,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isGranted
                                              ? (isDark
                                                    ? Colors.white
                                                    : const Color(0xFF1A0F0A))
                                              : subTextCol,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        desc,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: subTextCol,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: isGranted,
                                  activeColor: _kOrange,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (v) {
                                    setState(() {
                                      v == true
                                          ? _selected.add(perm)
                                          : _selected.remove(perm);
                                      _activeTemplate = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Dialog Footer ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderCol)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selected.length} modules selected',
                    style: GoogleFonts.inter(
                      color: subTextCol,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _loading ? null : _save,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          'Save Permissions',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
