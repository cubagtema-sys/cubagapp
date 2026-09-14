import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kIndigo = Color(0xFF6366F1);

class AdminDocumentRulesPage extends StatefulWidget {
  const AdminDocumentRulesPage({super.key});

  @override
  State<AdminDocumentRulesPage> createState() => _AdminDocumentRulesPageState();
}

class _AdminDocumentRulesPageState extends State<AdminDocumentRulesPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<dynamic> _allRequirements = [];

  String _selectedCategory = 'corporate'; // corporate | licentiate | associate
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
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${req['label']}"? Existing submitted applications will not lose their files.',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(
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
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
    final catName = _selectedCategory == 'licentiate'
        ? 'Licentiate'
        : (_selectedCategory == 'associate' ? 'Associate' : 'Corporate');
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
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: Text(
            enableAll
                ? 'Are you sure you want to enable all document requirements for $catName ($scopeName)? Applicants will be required to upload them.'
                : 'Are you sure you want to disable all document requirements for $catName ($scopeName)? Applicants will not be asked to upload any documents and can proceed directly to payment.',
            style: GoogleFonts.inter(fontSize: 13.5),
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
              child: Text(enableAll ? 'Enable All' : 'Turn Off All', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final currentRules = _currentRules;
    final totalRules = currentRules.length;
    final mandatoryRules = currentRules.where((r) => r['is_required'] == true).length;
    final optionalRules = currentRules.where((r) => r['is_required'] != true).length;
    final activeRules = currentRules.where((r) => r['is_active'] == true).length;

    String catTitle = 'Corporate Brokerage';
    if (_selectedCategory == 'licentiate') {
      catTitle = 'Licentiate Broker';
    } else if (_selectedCategory == 'associate') {
      catTitle = 'Associate Member';
    }

    return AppLayout(
      title: 'Compliance & Document Rules',
      scrollable: false,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: AdminHeader(
                title: 'Compliance & Document Rules',
                subtitle:
                    'Configure mandatory and optional compliance certificates for New Onboarding and Annual Renewals across all membership classes.',
                actions: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor: _kOrange.withAlpha(80),
                    ),
                    onPressed: () => _openAddEditDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Add Rule',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                      side: BorderSide(color: borderColor, width: 1.2),
                      backgroundColor: cardBg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _fetch,
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: _kOrange),
                    label: Text(
                      'Refresh',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Top Category Tabs (Corporate | Licentiate | Associate)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildCategoryTab(
                      'Corporate Brokerage',
                      'corporate',
                      Icons.corporate_fare_rounded,
                      _kIndigo,
                      _countFor('corporate', 'new') + _countFor('corporate', 'renewal'),
                    ),
                    const SizedBox(width: 4),
                    _buildCategoryTab(
                      'Licentiate Broker',
                      'licentiate',
                      Icons.badge_rounded,
                      _kOrange,
                      _countFor('licentiate', 'new') + _countFor('licentiate', 'renewal'),
                    ),
                    const SizedBox(width: 4),
                    _buildCategoryTab(
                      'Associate Member',
                      'associate',
                      Icons.people_alt_rounded,
                      _kGreen,
                      _countFor('associate', 'new') + _countFor('associate', 'renewal'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Scope Sub-Tabs + Search + KPIs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Scope selector
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A0F0A)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildScopePill(
                                'Complete Application',
                                'new',
                                Icons.assignment_rounded,
                                _countFor(_selectedCategory, 'new'),
                              ),
                              const SizedBox(width: 4),
                              _buildScopePill(
                                'Annual Renewal',
                                'renewal',
                                Icons.autorenew_rounded,
                                _countFor(_selectedCategory, 'renewal'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Search box
                        Expanded(
                          child: Container(
                              height: 38,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1A0F0A)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search document title, key, or instructions...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  size: 17,
                                  color: textMuted,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Counter mini-badges & Bulk Toggle Actions
                    Row(
                      children: [
                        _buildCounterBadge(
                          'Total Rules',
                          '$totalRules',
                          Icons.rule_folder_rounded,
                          _kIndigo,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildCounterBadge(
                          'Mandatory',
                          '$mandatoryRules',
                          Icons.lock_rounded,
                          _kRed,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildCounterBadge(
                          'Optional',
                          '$optionalRules',
                          Icons.help_outline_rounded,
                          _kAmber,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildCounterBadge(
                          'Active in Prod',
                          '$activeRules',
                          Icons.check_circle_outline_rounded,
                          _kGreen,
                          isDark,
                        ),
                        const Spacer(),
                        if (totalRules > 0) ...[
                          if (activeRules > 0)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kRed,
                                side: const BorderSide(color: _kRed, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _bulkToggleCategory(false),
                              icon: const Icon(Icons.power_settings_new_rounded, size: 15, color: _kRed),
                              label: Text('Turn Off All ($catTitle)', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            )
                          else
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              onPressed: () => _bulkToggleCategory(true),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                              label: Text('Enable All ($catTitle)', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Table Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF4D2D20)
                      : const Color(0xFFF1F5F9),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 50,
                      child: Text('ORDER', style: _headerColStyle(textMuted)),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'DOCUMENT NAME',
                        style: _headerColStyle(textMuted),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'INSTRUCTIONS & SCOPE',
                        style: _headerColStyle(textMuted),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        'MANDATORY',
                        style: _headerColStyle(textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        'STATUS',
                        style: _headerColStyle(textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        'ACTIONS',
                        style: _headerColStyle(textMuted),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // List of Rules
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    border: Border(
                      left: BorderSide(color: borderColor),
                      right: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
                    ),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _kOrange),
                        )
                      : currentRules.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.rule_folder_outlined,
                                    size: 48,
                                    color: textMuted.withAlpha(120),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No rules configured for $catTitle (${_selectedScope == "new" ? "New Application" : "Annual Renewal"})',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Click "Add Rule" to configure required compliance certificates.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kOrange,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _openAddEditDialog(),
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    label: Text(
                                      'Add First Rule',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: currentRules.length,
                              separatorBuilder: (_, index) => Divider(
                                color: borderColor.withAlpha(80),
                                height: 1,
                              ),
                              itemBuilder: (ctx, i) {
                                final r = currentRules[i];
                                return _buildRuleRow(
                                  r,
                                  i,
                                  isDark,
                                  borderColor,
                                  textPrimary,
                                  textMuted,
                                );
                              },
                            ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTab(
    String label,
    String key,
    IconData icon,
    Color color,
    int totalCount,
  ) {
    final isSel = _selectedCategory == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = key),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isSel
                ? (isDark ? color.withAlpha(40) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSel
                ? Border.all(color: color, width: 1.5)
                : null,
            boxShadow: isSel && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSel
                    ? color
                    : (isDark ? Colors.white60 : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                  color: isSel
                      ? (isDark ? Colors.white : color)
                      : (isDark ? Colors.white70 : const Color(0xFF334155)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSel
                      ? color
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalCount',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSel
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopePill(
    String label,
    String scope,
    IconData icon,
    int count,
  ) {
    final isSel = _selectedScope == scope;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _selectedScope = scope),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel
              ? _kOrange
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? Colors.black.withAlpha(40) : (isDark ? Colors.white12 : Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterBadge(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(isDark ? 50 : 35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow(
    Map<String, dynamic> r,
    int index,
    bool isDark,
    Color borderColor,
    Color textPrimary,
    Color textMuted,
  ) {
    final order = (r['display_order'] as num?)?.toInt() ?? (index + 1);
    final label = (r['label'] as String?) ?? 'Document Rule';
    final desc = (r['description'] as String?) ?? '';
    final isRequired = r['is_required'] == true;
    final isActive = r['is_active'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          // Order Number
          SizedBox(
            width: 50,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  '$order',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
          ),

          // Document Name
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Instructions & Scope
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                desc.isNotEmpty
                    ? desc
                    : 'Statutory credential verification required for compliance.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: textMuted,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Mandatory Pill
          SizedBox(
            width: 110,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isRequired
                      ? _kRed.withAlpha(isDark ? 30 : 15)
                      : _kAmber.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isRequired
                        ? _kRed.withAlpha(60)
                        : _kAmber.withAlpha(60),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRequired ? Icons.lock_rounded : Icons.info_outline_rounded,
                      size: 11,
                      color: isRequired ? _kRed : _kAmber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isRequired ? 'MANDATORY' : 'OPTIONAL',
                      style: GoogleFonts.outfit(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isRequired ? _kRed : _kAmber,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Active Status Pill
          SizedBox(
            width: 90,
            child: Center(
              child: InkWell(
                onTap: () => _toggleActive(r),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _kGreen.withAlpha(isDark ? 30 : 15)
                        : Colors.grey.withAlpha(isDark ? 30 : 15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? _kGreen.withAlpha(60)
                          : Colors.grey.withAlpha(60),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? _kGreen : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'ACTIVE' : 'OFF',
                        style: GoogleFonts.outfit(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isActive ? _kGreen : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Action Buttons
          SizedBox(
            width: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit Rule',
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  color: _kOrange,
                  onPressed: () => _openAddEditDialog(r),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Delete Rule',
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  color: _kRed,
                  onPressed: () => _deleteRule(r),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerColStyle(Color color) {
    return GoogleFonts.outfit(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0.6,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD / EDIT RULE MODAL DIALOG
// ─────────────────────────────────────────────────────────────────────────────
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
    final inputBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
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
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
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
                          'MEMBERSHIP CATEGORY',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
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
                                  child: Text('Corporate Brokerage'),
                                ),
                                DropdownMenuItem(
                                  value: 'licentiate',
                                  child: Text('Licentiate Broker'),
                                ),
                                DropdownMenuItem(
                                  value: 'associate',
                                  child: Text('Associate Member'),
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
                          'APPLICATION SCOPE',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
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
                          'DOCUMENT TITLE / NAME *',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _labelCtrl,
                          style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
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
                          'ORDER',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _orderCtrl,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
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
                'INSTRUCTIONS / GUIDELINES FOR APPLICANT',
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 12.5, color: textColor),
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
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Must be uploaded before submission',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
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
                        'Active in Production',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Visible to applicants on portal',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
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
                      style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
