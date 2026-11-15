import '../components/admin_dialog.dart';
import '../components/custom_dropdown.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kGreen = CubagColors.valid;
const _kBlue = Color(0xFF3b82f6);
const _kRed = CubagColors.lapsed;
const _kAmber = CubagColors.due;
const _kPurple = Color(0xFF8b5cf6);
const _kCardBg = Color(0xFF22140E);

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
  'members': 'Members',
  'payments': 'Payments',
  'tickets': 'Tickets',
  'announcements': 'Announcements',
  'schedules': 'Schedules',
  'events': 'Events',
  'surveys': 'Polls',
  'intelligence': 'Insights',
  'audit_log': 'Audit',
  'fees': 'Fees',
  'settings': 'Settings',
  'compliance': 'Compliance',
  'documents': 'Applications',
  'messaging': 'Messages',
  'notifications': 'Notifications',
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
  'messaging': 'Direct messaging with verified members',
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
    label: 'Compliance officer',
    description: 'Member ID, renewals & document inspection',
    icon: Icons.verified_user_outlined,
    color: _kGreen,
    permissions: ['compliance', 'documents', 'members', 'audit_log'],
  ),
  _RoleTemplate(
    id: 'membership',
    label: 'Membership officer',
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
    label: 'Finance officer',
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
    label: 'Operations',
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
          style: TextStyle(fontWeight: FontWeight.bold),
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        content: Text(
          'Demote ${sa['name']} back to a regular member?\nAll their administrative permissions will be revoked.',
          style: TextStyle(color: subTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: subTextColor),
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
              style: TextStyle(
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
    showDialog(
      context: context,
      builder: (ctx) => _CreateSubAdminSheet(
        onCreated: () {
          Navigator.pop(ctx);
          _toast('Admin added');
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
          _toast('Access saved');
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
    final cardBg = isDark ? _kCardBg : const Color(0xFFFBF8F3);
    final borderCol = isDark
        ? const Color(0xFF3D261C)
        : CubagColors.line;
    final textCol = isDark ? Colors.white : const Color(0xFF1F1612);
    final subTextCol = isDark
        ? const Color(0xFFB0A298)
        : const Color(0xFF6B5E55);
    final inputBg = isDark
        ? CubagColors.ink
        : const Color(0xFFFAF6F0);

    // Only full admins and super admins may access this page
    if (auth.userRole != 'admin' && auth.userRole != 'super_admin') {
      return AppLayout(
        title: 'Admins',
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
                style: TextStyle(color: subTextCol, fontSize: 18),
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
      title: 'Admins',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Admins',
                subtitle: 'Staff who help run CUBAG, and which sections each one can open. Open an admin to change their access.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => _showCreateSheet(isDark, cardBg, borderCol, textCol, subTextCol, inputBg),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Add admin'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                AdminFigure('All', '$totalSubAdmins', selected: _filterRole == 'all', onTap: () => setState(() => _filterRole = 'all')),
                AdminFigure('Full access', '$fullAccessCount', selected: _filterRole == 'full', onTap: () => setState(() => _filterRole = 'full')),
                AdminFigure('Limited access', '$scopedCount'),
              ]),
              const SizedBox(height: CubagSpace.md),
              LayoutBuilder(
                builder: (context, c) {
                  final search = AdminSearchField(
                    hint: 'Search name, email or section',
                    onChanged: (v) => setState(() => _searchQuery = v),
                  );
                  final role = SizedBox(
                    width: c.maxWidth < 560 ? double.infinity : 210,
                    child: CustomDropdown<String>(
                      value: _filterRole,
                      items: const [
                        DropdownItem(value: 'all', label: 'All roles'),
                        DropdownItem(value: 'compliance', label: 'Compliance'),
                        DropdownItem(value: 'finance', label: 'Finance'),
                        DropdownItem(value: 'membership', label: 'Membership'),
                        DropdownItem(value: 'operations', label: 'Operations'),
                        DropdownItem(value: 'communications', label: 'Communications'),
                        DropdownItem(value: 'full', label: 'Full access'),
                        DropdownItem(value: 'custom', label: 'Custom'),
                      ],
                      onChanged: (v) => setState(() => _filterRole = v),
                    ),
                  );
                  if (c.maxWidth < 560) {
                    return Column(children: [search, const SizedBox(height: CubagSpace.xs), role]);
                  }
                  return Row(children: [Expanded(child: search), const SizedBox(width: CubagSpace.sm), role]);
                },
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (displaySubAdmins.isEmpty)
                EmptyMessage(
                  icon: Icons.admin_panel_settings_outlined,
                  title: _subAdmins.isEmpty ? 'No other admins yet' : 'No admins match',
                  message: _subAdmins.isEmpty
                      ? 'Use Add admin to give a staff member access to some or all sections.'
                      : 'Try another role, or clear the search.',
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [
                    for (final sa in displaySubAdmins)
                      () {
                        final map = Map<String, dynamic>.from(sa as Map);
                        final name = map['name']?.toString() ?? 'Admin';
                        final email = map['email']?.toString() ?? '';
                        final perms = List<String>.from(map['permissions'] ?? []);
                        final template = _getMatchingTemplate(perms);
                        final access = perms.isEmpty
                            ? 'No access'
                            : (perms.length >= _kAllPermissions.length
                                ? 'Full access'
                                : (template?.label ?? 'Custom: ${perms.length} sections'));
                        final sections = perms.map((p) => _kPermissionLabels[p] ?? p).join(', ');
                        return AdminListRow(
                          leading: AdminRowMark(initials: adminInitials(name)),
                          title: name,
                          subtitle: email,
                          meta: sections.isEmpty ? null : sections,
                          status: StatusChip(
                            access,
                            kind: perms.isEmpty ? StatusKind.bad : (perms.length >= _kAllPermissions.length ? StatusKind.good : StatusKind.neutral),
                          ),
                          onTap: () => _showEditModal(map),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
                            onSelected: (v) {
                              if (v == 'edit') _showEditModal(map);
                              if (v == 'remove') _remove(map, cardBg, borderCol, textCol, subTextCol);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Change access')),
                              PopupMenuItem(value: 'remove', child: Text('Remove admin', style: TextStyle(color: CubagColors.lapsed))),
                            ],
                          ),
                        );
                      }(),
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

/// Role presets plus one switch per section; shared by the add and edit pop-ups.
class _SectionPicker extends StatelessWidget {
  final Set<String> selected;
  final String? template;
  final void Function(Set<String> perms, String? template) onChanged;
  const _SectionPicker({required this.selected, required this.template, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final all = selected.length == _kAllPermissions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminField(
          label: 'Start from a role',
          help: 'Fills in the sections below. You can still change them.',
          child: AdminChoice<String>(
            options: [for (final t in _kRoleTemplates) (t.id, t.label), ('full', 'Full access')],
            value: template ?? '',
            onChanged: (id) {
              if (id == 'full') {
                onChanged(Set<String>.from(_kAllPermissions), 'full');
              } else {
                final t = _kRoleTemplates.firstWhere((t) => t.id == id);
                onChanged(Set<String>.from(t.permissions), id);
              }
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Sections they can open · ${selected.length} of ${_kAllPermissions.length}',
                style: CubagType.label,
              ),
            ),
            TextButton(
              onPressed: () => onChanged(all ? <String>{} : Set<String>.from(_kAllPermissions), all ? null : 'full'),
              child: Text(all ? 'Clear all' : 'Select all'),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.xs),
        AdminRowGroup(
          children: [
            for (final perm in _kAllPermissions)
              SwitchListTile(
                value: selected.contains(perm),
                onChanged: (v) {
                  final next = Set<String>.from(selected);
                  v ? next.add(perm) : next.remove(perm);
                  onChanged(next, null);
                },
                secondary: Icon(_kPermissionIcons[perm] ?? Icons.check_rounded, color: CubagColors.cocoa, size: 20),
                title: Text(_kPermissionLabels[perm] ?? perm, style: CubagType.bodyStrong),
                subtitle: Text(_kPermissionDescriptions[perm] ?? '', style: CubagType.caption),
                dense: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _CreateSubAdminSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateSubAdminSheet({required this.onCreated});
  @override
  State<_CreateSubAdminSheet> createState() => _CreateSubAdminSheetState();
}

class _CreateSubAdminSheetState extends State<_CreateSubAdminSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  Set<String> _perms = {};
  String? _template;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_perms.isEmpty) {
      setState(() => _error = 'Choose at least one section.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().post('/sub-admins/', data: {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'password': _passCtrl.text.trim(),
        'permissions': _perms.toList(),
      });
      if (!mounted) return;
      if (res.statusCode == 201) {
        widget.onCreated();
        return;
      }
      setState(() => _error = (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not add the admin.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add the admin. Check the connection and try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AdminDialog(
        title: 'Add admin',
        subtitle: 'They sign in to this portal with this email and the temporary password.',
        maxWidth: 640,
        actions: [
          TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Adding…' : 'Add admin')),
        ],
        children: [
          AdminFieldPair(
            AdminField(
              label: 'Full name',
              child: TextFormField(
                controller: _nameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Add their name' : null,
              ),
            ),
            AdminField(
              label: 'Email',
              child: TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@')) ? 'Add a valid email' : null,
              ),
            ),
          ),
          AdminField(
            label: 'Temporary password',
            help: 'At least 6 characters. Share it privately; they should change it after signing in.',
            child: TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ),
          _SectionPicker(
            selected: _perms,
            template: _template,
            onChanged: (p, t) => setState(() {
              _perms = p;
              _template = t;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: CubagSpace.md),
            Text(_error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
          ],
        ],
      ),
    );
  }
}

class _EditPermissionsDialog extends StatefulWidget {
  final Map<String, dynamic> subAdmin;
  final VoidCallback onSaved;
  const _EditPermissionsDialog({required this.subAdmin, required this.onSaved});

  @override
  State<_EditPermissionsDialog> createState() => _EditPermissionsDialogState();
}

class _EditPermissionsDialogState extends State<_EditPermissionsDialog> {
  late Set<String> _selected;
  String? _template;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.subAdmin['permissions'] ?? []);
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().put(
        '/sub-admins/${widget.subAdmin['id']}/permissions',
        data: {'permissions': _selected.toList()},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        widget.onSaved();
        return;
      }
      setState(() => _error = (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not save.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Check the connection and try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.subAdmin['name']?.toString() ?? 'Admin';
    final email = widget.subAdmin['email']?.toString() ?? '';
    return AdminDialog(
      title: 'Access for $name',
      subtitle: email.isEmpty ? null : '$email · changes apply the next time they open a page.',
      maxWidth: 640,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _loading ? null : _save, child: Text(_loading ? 'Saving…' : 'Save access')),
      ],
      children: [
        _SectionPicker(
          selected: _selected,
          template: _template,
          onChanged: (p, t) => setState(() {
            _selected = p;
            _template = t;
          }),
        ),
        if (_selected.isEmpty) ...[
          const SizedBox(height: CubagSpace.sm),
          Text('With no sections they can sign in but cannot open anything.', style: CubagType.small.copyWith(color: CubagColors.due)),
        ],
        if (_error != null) ...[
          const SizedBox(height: CubagSpace.sm),
          Text(_error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
        ],
      ],
    );
  }
}
