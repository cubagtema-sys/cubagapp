import '../components/shimmer_loader.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

class AdminDocumentRulesPage extends StatefulWidget {
  const AdminDocumentRulesPage({super.key});

  @override
  State<AdminDocumentRulesPage> createState() => _AdminDocumentRulesPageState();
}

class _AdminDocumentRulesPageState extends State<AdminDocumentRulesPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<dynamic> _allRequirements = [];

  final String _selectedCategory = 'corporate';
  String _selectedScope = 'new'; // new | renewal
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/documents/admin/requirements');
      if (mounted && res.statusCode == 200) {
        final data = res.data;
        if (data is Map && data['requirements'] is List) {
          setState(() {
            _allRequirements = data['requirements'];
            _loading = false;
          });
          return;
        }
      }
    } catch (e, st) {
      AppLogger.error('admin_document_rules_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _currentRules {
    var list = _allRequirements
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((r) {
          final mType = (r['member_type'] as String? ?? 'corporate').toLowerCase();
          final aType = (r['application_type'] as String? ?? 'new').toLowerCase();
          return mType == _selectedCategory && aType == _selectedScope;
        })
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        final label = (r['label'] as String? ?? '').toLowerCase();
        final key = (r['key'] as String? ?? '').toLowerCase();
        final desc = (r['description'] as String? ?? '').toLowerCase();
        return label.contains(q) || key.contains(q) || desc.contains(q);
      }).toList();
    }

    list.sort((a, b) {
      final ordA = (a['display_order'] as num?)?.toInt() ?? 0;
      final ordB = (b['display_order'] as num?)?.toInt() ?? 0;
      if (ordA != ordB) return ordA.compareTo(ordB);
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      return idA.compareTo(idB);
    });

    return list;
  }

  int _countFor(String cat, String scope) {
    return _allRequirements.where((r) {
      final mType = (r['member_type'] as String? ?? 'corporate').toLowerCase();
      final aType = (r['application_type'] as String? ?? 'new').toLowerCase();
      return mType == cat && aType == scope;
    }).length;
  }

  void _openAddEditDialog([Map<String, dynamic>? existing]) {
    showDialog(
      context: context,
      builder: (ctx) => _AddEditRuleDialog(
        existing: existing,
        defaultCategory: _selectedCategory,
        defaultScope: _selectedScope,
        onSaved: _fetch,
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> req) async {
    final reqId = req['id'];
    final current = req['is_active'] == true;
    try {
      final res = await ApiService().put(
        '/documents/admin/requirements/$reqId',
        data: {'is_active': !current},
      );
      if (mounted && (res.statusCode == 200 || res.statusCode == 204)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !current ? 'Rule activated successfully' : 'Rule deactivated',
            ),
            backgroundColor: !current ? _kGreen : const Color(0xFF4D2D20),
            duration: const Duration(seconds: 2),
          ),
        );
        _fetch();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF281710) : Colors.white,
          title: Text(
            'Delete Document Rule',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : CubagColors.ink,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${req['label']}"? Existing submitted applications will not lose their files.',
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : CubagColors.inkSoft,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final reqId = req['id'];
      try {
        final res = await ApiService().delete(
          '/documents/admin/requirements/$reqId',
        );
        if (mounted && (res.statusCode == 200 || res.statusCode == 204)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rule deleted successfully'),
              backgroundColor: _kRed,
            ),
          );
          _fetch();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete rule'),
              backgroundColor: _kRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _bulkToggleCategory(bool enableAll) async {
    const catName = 'Corporate';
    final scopeName = _selectedScope == 'new' ? 'New Onboarding' : 'Annual Renewal';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF281710) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            enableAll
                ? 'Enable All Documents for $catName'
                : 'Turn Off All Documents for $catName',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            enableAll
                ? 'Are you sure you want to enable all document requirements for $catName ($scopeName)? Applicants will be required to upload them.'
                : 'Are you sure you want to disable all document requirements for $catName ($scopeName)? Applicants will not be asked to upload any documents and can proceed directly to payment.',
            style: TextStyle(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: enableAll ? _kGreen : _kRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(enableAll ? 'Enable All' : 'Turn Off All', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final res = await ApiService().post(
        '/documents/admin/requirements/bulk-toggle',
        data: {
          'member_type': _selectedCategory,
          'application_type': _selectedScope,
          'is_active': enableAll,
        },
      );
      if (mounted && res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enableAll
                  ? 'All $catName documents enabled successfully'
                  : 'All $catName documents turned off successfully',
            ),
            backgroundColor: enableAll ? _kGreen : _kOrange,
            duration: const Duration(seconds: 3),
          ),
        );
        _fetch();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update category document status'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _currentRules;
    final required = rules.where((r) => r['is_required'] == true).length;
    final active = rules.where((r) => r['is_active'] == true).length;

    return AppLayout(
      title: 'Requirements',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Requirements',
                subtitle: 'The documents members must upload when they apply and when they renew. '
                    'Switch one off to stop asking for it; members already approved are not affected.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _fetch,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openAddEditDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add document'),
                  ),
                ],
              ),
              FilterTabs(
                tabs: [
                  ('new', 'New members · ${_countFor(_selectedCategory, 'new')}'),
                  ('renewal', 'Renewals · ${_countFor(_selectedCategory, 'renewal')}'),
                ],
                selected: _selectedScope,
                onSelected: (s) => setState(() => _selectedScope = s),
              ),
              const SizedBox(height: CubagSpace.sm),
              AdminSearchField(hint: 'Search documents', onChanged: (v) => setState(() => _searchQuery = v)),
              const SizedBox(height: CubagSpace.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rules.length} documents · $required required · $active switched on',
                      style: CubagType.small.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (rules.isNotEmpty)
                    PopupMenuButton<bool>(
                      tooltip: 'Switch all',
                      onSelected: _bulkToggleCategory,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: true, child: Text('Switch all on')),
                        PopupMenuItem(value: false, child: Text('Switch all off')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Switch all'),
                            Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: CubagSpace.xs),
              if (_loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (rules.isEmpty)
                EmptyMessage(
                  icon: Icons.rule_folder_outlined,
                  title: _searchQuery.isNotEmpty ? 'No documents match' : 'No documents set',
                  message: _searchQuery.isNotEmpty
                      ? 'Try other words, or clear the search.'
                      : (_selectedScope == 'new'
                          ? 'Add the documents new members must upload.'
                          : 'Add the documents members must upload to renew.'),
                  action: _searchQuery.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _openAddEditDialog(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add document'),
                        )
                      : null,
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [for (var i = 0; i < rules.length; i++) _ruleRow(rules[i], i)],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ruleRow(Map<String, dynamic> r, int index) {
    final order = (r['display_order'] as num?)?.toInt() ?? (index + 1);
    final label = (r['label'] as String?) ?? 'Document';
    final desc = (r['description'] as String?) ?? '';
    final isRequired = r['is_required'] == true;
    final isActive = r['is_active'] == true;

    return AdminListRow(
      leading: AdminRowMark(
        initials: '$order',
        color: isActive ? CubagColors.cocoa : CubagColors.muted,
      ),
      title: label,
      subtitle: desc.isEmpty ? null : desc,
      subtitleLines: 2,
      meta: isActive ? null : 'Switched off · members are not asked for it',
      status: isRequired ? const StatusChip('Required', kind: StatusKind.pending) : const StatusChip('Optional'),
      onTap: () => _openAddEditDialog(r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isActive ? 'Members are asked for it' : 'Switched off',
            child: Switch(value: isActive, onChanged: (_) => _toggleActive(r)),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
            onSelected: (v) {
              if (v == 'edit') _openAddEditDialog(r);
              if (v == 'delete') _deleteRule(r);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: CubagColors.lapsed))),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddEditRuleDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String defaultCategory;
  final String defaultScope;
  final VoidCallback onSaved;

  const _AddEditRuleDialog({
    this.existing,
    required this.defaultCategory,
    required this.defaultScope,
    required this.onSaved,
  });

  @override
  State<_AddEditRuleDialog> createState() => _AddEditRuleDialogState();
}

class _AddEditRuleDialogState extends State<_AddEditRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labelCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _orderCtrl;

  late String _category;
  late String _scope;
  late bool _isRequired;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _labelCtrl = TextEditingController(text: ex?['label'] ?? '');
    _keyCtrl = TextEditingController(text: ex?['key'] ?? '');
    _descCtrl = TextEditingController(text: ex?['description'] ?? '');
    _orderCtrl = TextEditingController(
      text: ex?['display_order']?.toString() ?? '1',
    );

    _category = ex?['member_type'] ?? widget.defaultCategory;
    _scope = ex?['application_type'] ?? widget.defaultScope;
    _isRequired = ex?['is_required'] ?? true;
    _isActive = ex?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _keyCtrl.dispose();
    _descCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final generatedKey = (widget.existing?['key'] as String?)?.isNotEmpty == true
        ? widget.existing!['key']
        : _labelCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

    final payload = {
      'label': _labelCtrl.text.trim(),
      'key': generatedKey,
      'description': _descCtrl.text.trim(),
      'member_type': _category,
      'application_type': _scope,
      'display_order': int.tryParse(_orderCtrl.text.trim()) ?? 1,
      'is_required': _isRequired,
      'is_active': _isActive,
    };

    try {
      if (widget.existing != null) {
        final id = widget.existing!['id'];
        await ApiService().put('/documents/admin/requirements/$id', data: payload);
      } else {
        await ApiService().post('/documents/admin/requirements', data: payload);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing != null
                  ? 'Document rule updated successfully'
                  : 'Document rule created successfully',
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save rule: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF281710) : Colors.white;
    final inputBg = isDark ? CubagColors.ink : CubagColors.sand;
    final borderColor = isDark ? const Color(0xFF4D2D20) : CubagColors.line;
    final textColor = isDark ? Colors.white : CubagColors.ink;
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kOrange.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEdit ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                          color: _kOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isEdit ? 'Edit Document Rule' : 'Add Compliance Document Rule',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.grey,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Membership Category & Application Scope
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Membership category',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentOrangeText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _category,
                              isExpanded: true,
                              dropdownColor: bg,
                              items: const [
                                DropdownMenuItem(
                                  value: 'corporate',
                                  child: Text('Corporate Members'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _category = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Application scope',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentOrangeText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _scope,
                              isExpanded: true,
                              dropdownColor: bg,
                              items: const [
                                DropdownMenuItem(
                                  value: 'new',
                                  child: Text('Complete Application'),
                                ),
                                DropdownMenuItem(
                                  value: 'renewal',
                                  child: Text('Annual Renewal'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _scope = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Title / Label & Display Order
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Document title / name *',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _labelCtrl,
                          style: TextStyle(fontSize: 13.5, color: textColor),
                          validator: (v) => v?.trim().isEmpty == true ? 'Document title required' : null,
                          decoration: InputDecoration(
                            hintText: 'e.g. Tax Clearance Certificate',
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _orderCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13.5, color: textColor),
                          decoration: InputDecoration(
                            hintText: '1',
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Description
              Text(
                'Instructions / guidelines for applicant',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                style: TextStyle(fontSize: 12.5, color: textColor),
                decoration: InputDecoration(
                  hintText: 'e.g. Upload a valid GRA clearance certificate valid for the current fiscal year.',
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),

              const SizedBox(height: 14),

              // Switches: Mandatory & Active
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Mandatory Requirement',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Must be uploaded before submission',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      value: _isRequired,
                      activeThumbColor: _kOrange,
                      onChanged: (v) => setState(() => _isRequired = v),
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Visible to applicants on portal',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      value: _isActive,
                      activeThumbColor: _kGreen,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(
                      isEdit ? 'Save Changes' : 'Create Rule',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
