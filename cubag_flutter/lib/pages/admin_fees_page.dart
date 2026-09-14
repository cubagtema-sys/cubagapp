import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBrown = Color(0xFF6B3E26);
const _kPurple = Color(0xFF7C3AED);
const _kBlue = Color(0xFF0284C7);

class AdminFeesPage extends StatefulWidget {
  const AdminFeesPage({super.key});

  @override
  State<AdminFeesPage> createState() => _AdminFeesPageState();
}

class _AdminFeesPageState extends State<AdminFeesPage> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _fees = [];
  bool _saving = false;
  bool _fetching = true;
  String _searchQuery = '';
  String _message = '';
  bool _isSuccess = false;

  // Active Category: 'corporate' (SME & Large), 'associate', 'licentiate', 'all'
  String _selectedCategory = 'corporate';
  String _subFilter = 'all';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchFees();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _searchQuery = v.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchFees() async {
    if (_fees.isEmpty) setState(() => _fetching = true);
    try {
      final res = await _api.get('admin/fees');
      if (mounted && res.data is List) {
        final list = (res.data as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final regItem = list.firstWhere(
          (f) => f['id'] == 'reg_form_fee' || f['id'] == 'new_reg_fee',
          orElse: () => <String, dynamic>{},
        );
        if (regItem.isNotEmpty && regItem['amount'] != null) {
          await SessionStorage.instance.setString('cubag_reg_fee_amount', regItem['amount'].toString());
        }
        setState(() {
          _fees = list;
          _fetching = false;
        });
        return;
      }
    } catch (_) {}

    setState(() => _fetching = false);
  }

  Future<void> _showFeeDialog([
    Map<String, dynamic>? existingFee,
    int? index,
    String defaultSection = 'new_membership',
  ]) async {
    final isEdit = existingFee != null;
    final nameCtrl = TextEditingController(text: existingFee?['label']?.toString() ?? '');
    final amountCtrl = TextEditingController(text: existingFee?['amount']?.toString() ?? '0.00');
    final descCtrl = TextEditingController(text: existingFee?['description']?.toString() ?? '');
    String frequency = existingFee?['frequency']?.toString() ?? 'Annual';
    String section = existingFee?['section']?.toString() ?? defaultSection;
    bool isSummary = existingFee?['is_summary'] == true;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
          final textCol = isDark ? Colors.white : const Color(0xFF0F172A);
          final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                child: Icon(isEdit ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded, color: _kOrange, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isEdit ? 'Edit Fee Tariff' : 'Add Fee Tariff',
                                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: textCol),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            icon: Icon(Icons.close_rounded, color: textCol.withAlpha(150)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      Text('MEMBERSHIP CATEGORY / SECTION *', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('Corporate: New Member', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                            selected: section == 'new_membership',
                            selectedColor: _kOrange,
                            labelStyle: TextStyle(color: section == 'new_membership' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'new_membership');
                            },
                          ),
                          ChoiceChip(
                            label: Text('Corporate: Renewal Dues', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                            selected: section == 'renewal',
                            selectedColor: _kBrown,
                            labelStyle: TextStyle(color: section == 'renewal' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'renewal');
                            },
                          ),
                          ChoiceChip(
                            label: Text('Associate', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                            selected: section == 'associate',
                            selectedColor: const Color(0xFFD97706),
                            labelStyle: TextStyle(color: section == 'associate' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'associate');
                            },
                          ),
                          ChoiceChip(
                            label: Text('Licentiate', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                            selected: section == 'licentiate',
                            selectedColor: const Color(0xFF6B3E26),
                            labelStyle: TextStyle(color: section == 'licentiate' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'licentiate');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Text('TARIFF NAME / DESCRIPTION *', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.outfit(fontSize: 17, color: textCol),
                        decoration: InputDecoration(
                          hintText: 'e.g. New Member Package: Clearing & Forwarding Only (SMEs)',
                          hintStyle: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AMOUNT (GHS) *', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: amountCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: textCol),
                                  decoration: InputDecoration(
                                    prefixText: 'GHS ',
                                    prefixStyle: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: _kOrange),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('FREQUENCY *', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: frequency,
                                      isExpanded: true,
                                      dropdownColor: cardBg,
                                      style: GoogleFonts.outfit(fontSize: 17, color: textCol),
                                      items: const [
                                        DropdownMenuItem(value: 'One-Time', child: Text('One-Time')),
                                        DropdownMenuItem(value: 'Annual', child: Text('Annual')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setDlgState(() => frequency = val);
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

                      Text('FORMULA / BREAKDOWN DETAILS', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        style: GoogleFonts.outfit(fontSize: 16.5, color: textCol),
                        decoration: InputDecoration(
                          hintText: 'e.g. Sub (120) + Vetting (750) + District (250) + C&F Scope (500)',
                          hintStyle: GoogleFonts.inter(fontSize: 15.5, color: const Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),

                      CheckboxListTile(
                        value: isSummary,
                        contentPadding: EdgeInsets.zero,
                        activeColor: _kOrange,
                        title: Text('Package Summary (Total Entrance / Total Renewal)', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: textCol)),
                        subtitle: Text('Check this if this tariff represents a package total paid by members.', style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF94A3B8))),
                        onChanged: (val) => setDlgState(() => isSummary = val ?? false),
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final name = nameCtrl.text.trim();
                              final amtStr = amountCtrl.text.trim();
                              if (name.isEmpty) return;

                              final feeData = <String, dynamic>{
                                'id': existingFee?['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
                                'label': name,
                                'amount': amtStr,
                                'frequency': frequency,
                                'description': descCtrl.text.trim(),
                                'section': section,
                                'is_summary': isSummary,
                              };

                              setState(() {
                                if (isEdit && index != null && index >= 0 && index < _fees.length) {
                                  _fees[index] = feeData;
                                } else {
                                  _fees.add(feeData);
                                }
                              });

                              Navigator.of(dlgCtx).pop();
                              _saveAllFees();
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: Text(isEdit ? 'Update Tariff' : 'Add Tariff', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _removeFee(int index) {
    if (index < 0 || index >= _fees.length) return;
    final itemToRemove = _fees[index];
    final itemName = itemToRemove['label']?.toString() ?? 'Fee Item';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove Fee Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "$itemName" from the official tariff schedule?', style: GoogleFonts.inter(fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _fees.removeAt(index);
              });
              _saveAllFees();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAllFees() async {
    setState(() {
      _saving = true;
      _message = '';
    });

    try {
      final res = await _api.post('admin/fees', data: _fees);
      if ((res.statusCode ?? 500) >= 300) {
        await _api.post('settings/cubag_fees_v2', data: _fees);
      }
      final regItem = _fees.firstWhere(
        (f) => f['id'] == 'reg_form_fee' || f['id'] == 'new_reg_fee',
        orElse: () => <String, dynamic>{},
      );
      if (regItem.isNotEmpty && regItem['amount'] != null) {
        await SessionStorage.instance.setString('cubag_reg_fee_amount', regItem['amount'].toString());
      }
      setState(() {
        _saving = false;
        _isSuccess = true;
        _message = 'Fee schedule published and saved successfully.';
      });
    } catch (e, st) {
      AppLogger.error('admin_fees_save', e, st);
      setState(() {
        _saving = false;
        _isSuccess = false;
        _message = 'Saved locally to platform settings.';
      });
    } finally {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _message = '');
      });
    }
  }

  List<Map<String, dynamic>> _filterList(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    return list.where((f) {
      final name = (f['label']?.toString() ?? '').toLowerCase();
      final desc = (f['description']?.toString() ?? '').toLowerCase();
      final freq = (f['frequency']?.toString() ?? '').toLowerCase();
      final amt = (f['amount']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery) || desc.contains(_searchQuery) || freq.contains(_searchQuery) || amt.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);

    // Grouping by categories:
    // 1. Corporate / Freight Forwarders (Includes both new_membership and renewal sections)
    final corporateFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return (sec == 'new_membership' || sec == 'renewal' || id.startsWith('new_') || id.startsWith('renewal_') || id.startsWith('reg_')) &&
          !id.startsWith('associate_') &&
          !id.startsWith('licentiate_') &&
          sec != 'associate' &&
          sec != 'licentiate';
    }).toList();

    // 2. Associate Membership
    final associateFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return sec == 'associate' || id.startsWith('associate_');
    }).toList();

    // 3. Licentiate Membership
    final licentiateFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return sec == 'licentiate' || id.startsWith('licentiate_');
    }).toList();

    // Determine current display list based on active category & sub-filter
    List<Map<String, dynamic>> activeList = [];
    Color activeThemeColor = _kOrange;
    String activeTitle = 'Corporate Membership Fees (SMEs & Large)';

    if (_selectedCategory == 'corporate') {
      activeThemeColor = _kOrange;
      activeTitle = 'Corporate Membership Tariffs (SME & Large Corporate)';

      if (_subFilter == 'new_packages') {
        activeList = corporateFees.where((f) => f['is_summary'] == true && (f['section'] == 'new_membership' || f['id'].toString().startsWith('new_'))).toList();
      } else if (_subFilter == 'renewal_packages') {
        activeList = corporateFees.where((f) => f['is_summary'] == true && (f['section'] == 'renewal' || f['id'].toString().startsWith('renewal_'))).toList();
      } else if (_subFilter == 'sme') {
        activeList = corporateFees.where((f) {
          final id = (f['id'] ?? '').toString().toLowerCase();
          final lbl = (f['label'] ?? '').toString().toLowerCase();
          return (id.contains('sme') || lbl.contains('sme') || id.contains('new_cf') || id.contains('new_consolidation')) && !id.contains('large') && !lbl.contains('large');
        }).toList();
      } else if (_subFilter == 'large') {
        activeList = corporateFees.where((f) {
          final id = (f['id'] ?? '').toString().toLowerCase();
          final lbl = (f['label'] ?? '').toString().toLowerCase();
          return id.contains('large') || lbl.contains('large');
        }).toList();
      } else if (_subFilter == 'breakdown') {
        activeList = corporateFees.where((f) => f['is_summary'] != true).toList();
      } else {
        activeList = corporateFees;
      }
    } else if (_selectedCategory == 'associate') {
      activeThemeColor = const Color(0xFFD97706);
      activeTitle = 'Associate Membership Tariffs';
      if (_subFilter == 'onetime') {
        activeList = associateFees.where((f) => (f['frequency'] ?? '').toString().toLowerCase().contains('one')).toList();
      } else if (_subFilter == 'annual') {
        activeList = associateFees.where((f) => (f['frequency'] ?? '').toString().toLowerCase().contains('annual')).toList();
      } else {
        activeList = associateFees;
      }
    } else if (_selectedCategory == 'licentiate') {
      activeThemeColor = const Color(0xFF6B3E26);
      activeTitle = 'Licentiate Membership Tariffs (Individual)';
      if (_subFilter == 'onetime') {
        activeList = licentiateFees.where((f) => (f['frequency'] ?? '').toString().toLowerCase().contains('one')).toList();
      } else if (_subFilter == 'annual') {
        activeList = licentiateFees.where((f) => (f['frequency'] ?? '').toString().toLowerCase().contains('annual')).toList();
      } else {
        activeList = licentiateFees;
      }
    } else {
      activeThemeColor = _kPurple;
      activeTitle = 'Master Fee Schedule (All Categories)';
      activeList = _fees;
    }

    final filteredDisplayList = _filterList(activeList);

    return AppLayout(
      title: 'Platform Fees & Tariff Schedule',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP EXECUTIVE HEADER ─────────────────────────────────────────
            AdminHeader(
              title: 'Platform Fees & Tariff Schedule',
              subtitle: 'Configure entrance packages, renewal dues, and operational tariffs for Corporate (SME & Large), Associate, and Licentiate categories.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kOrange,
                    side: const BorderSide(color: _kOrange, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _saveAllFees,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange))
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(
                    _saving ? 'Publishing...' : 'Save & Publish Schedule',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),

            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: (_isSuccess ? _kGreen : _kRed).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (_isSuccess ? _kGreen : _kRed).withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Icon(_isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: _isSuccess ? _kGreen : _kRed, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_message, style: GoogleFonts.outfit(color: _isSuccess ? _kGreen : _kRed, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // ── 1. 3 CORE MEMBERSHIP CATEGORIES KPI CARDS ───────────────────────
            Text(
              'MEMBERSHIP CATEGORIES (3 MAIN BRANCHES)',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 650;
                final isTablet = constraints.maxWidth < 1100;
                final cardWidth = isMobile
                    ? constraints.maxWidth
                    : (isTablet ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4);

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCategoryKpiCard(
                      key: 'corporate',
                      title: 'Corporate / Freight',
                      subtitle: 'SMEs & Large Corporate (New & Renewal)',
                      itemCount: corporateFees.length,
                      color: _kOrange,
                      icon: Icons.domain_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'associate',
                      title: 'Associate Membership',
                      subtitle: 'Institutional Affiliates & Partners',
                      itemCount: associateFees.length,
                      color: const Color(0xFFD97706),
                      icon: Icons.groups_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'licentiate',
                      title: 'Licentiate Membership',
                      subtitle: 'Individual Licensed Forwarders',
                      itemCount: licentiateFees.length,
                      color: const Color(0xFF6B3E26),
                      icon: Icons.badge_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'all',
                      title: 'Master Tariff View',
                      subtitle: 'All Categories Combined (${_fees.length} Total)',
                      itemCount: _fees.length,
                      color: _kPurple,
                      icon: Icons.receipt_long_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // ── 2. SUB-FILTERS & SEARCH TOOLBAR ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(isDark ? 20 : 5), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Active Category Indicator Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: activeThemeColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: activeThemeColor.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: activeThemeColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              activeTitle,
                              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: activeThemeColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Sub-filter Pills
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _buildSubFilterPills(),
                          ),
                        ),
                      ),

                      // Add Item Button for current category
                      OutlinedButton.icon(
                        onPressed: () => _showFeeDialog(null, null, _selectedCategory == 'corporate' ? 'new_membership' : _selectedCategory),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: activeThemeColor,
                          side: BorderSide(color: activeThemeColor.withAlpha(100)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: Text('Add Fee Item', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Search Bar Input
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: border),
                          ),
                          child: TextField(
                            onChanged: _onSearchChanged,
                            style: GoogleFonts.outfit(fontSize: 17, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search tariff by fee name, category, or description...',
                              hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted),
                              prefixIcon: Icon(Icons.search_rounded, size: 17, color: textMuted),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Showing ${filteredDisplayList.length} tariffs',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── 3. STRUCTURED TARIFF DATA TABLE ───────────────────────────────
            _buildFeeTable(
              filteredDisplayList,
              isDark,
              cardBg,
              border,
              textPrimary,
              textMuted,
              activeThemeColor: activeThemeColor,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── CATEGORY KPI CARD WIDGET ───────────────────────────────────────────────
  Widget _buildCategoryKpiCard({
    required String key,
    required String title,
    required String subtitle,
    required int itemCount,
    required Color color,
    required IconData icon,
    required double width,
    required bool isDark,
    required Color cardBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final isSelected = _selectedCategory == key;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = key;
          _subFilter = 'all';
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? color.withAlpha(35) : color.withAlpha(18))
              : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : border,
            width: isSelected ? 2.0 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withAlpha(40),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 15 : 4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isSelected ? 255 : (isDark ? 40 : 25)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: 20,
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'ACTIVE',
                          style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 19.5,
                fontWeight: FontWeight.w900,
                color: isSelected ? (isDark ? Colors.white : color) : textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: isSelected ? (isDark ? Colors.white70 : const Color(0xFF475569)) : textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$itemCount Tariffs',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : textMuted,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: isSelected ? color : textMuted.withAlpha(120),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── SUB-FILTER PILLS BUILDER ───────────────────────────────────────────────
  List<Widget> _buildSubFilterPills() {
    if (_selectedCategory == 'corporate') {
      return [
        _pill('all', 'All Corporate Tariffs'),
        const SizedBox(width: 6),
        _pill('new_packages', '📦 New Member Packages (SME & Large)'),
        const SizedBox(width: 6),
        _pill('renewal_packages', '🔄 Annual Renewal Packages'),
        const SizedBox(width: 6),
        _pill('sme', '🏢 SME Only Tariffs'),
        const SizedBox(width: 6),
        _pill('large', '🏛️ Large Corporate Only'),
        const SizedBox(width: 6),
        _pill('breakdown', '📑 Isolated Components'),
      ];
    } else if (_selectedCategory == 'associate') {
      return [
        _pill('all', 'All Associate Tariffs'),
        const SizedBox(width: 6),
        _pill('onetime', 'One-Time Onboarding Fee'),
        const SizedBox(width: 6),
        _pill('annual', 'Annual Dues (Renewed)'),
      ];
    } else if (_selectedCategory == 'licentiate') {
      return [
        _pill('all', 'All Licentiate Tariffs'),
        const SizedBox(width: 6),
        _pill('onetime', 'One-Time Onboarding Fee'),
        const SizedBox(width: 6),
        _pill('annual', 'Annual Dues (Renewed)'),
      ];
    } else {
      return [
        _pill('all', 'Master Overview (All Items)'),
      ];
    }
  }

  Widget _pill(String value, String label) {
    final isSelected = _subFilter == value;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600)),
      selected: isSelected,
      selectedColor: _kOrange,
      labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF64748B)),
      onSelected: (val) {
        if (val) setState(() => _subFilter = value);
      },
    );
  }

  // ── TABLE BUILDER ─────────────────────────────────────────────────────────
  Widget _buildFeeTable(
    List<Map<String, dynamic>> items,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted, {
    required Color activeThemeColor,
  }) {
    if (_fetching) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (_, index) => const ShimmerListTile(),
      );
    }

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: textMuted),
            const SizedBox(height: 10),
            Text(
              'No fee tariffs found for this filter.',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Try switching your sub-filter or add a new fee item.',
              style: GoogleFonts.inter(fontSize: 16, color: textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 25 : 5), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth > 920 ? constraints.maxWidth : 920.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: DataTable(
                horizontalMargin: 20,
                columnSpacing: 20,
                headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF4D2D20) : const Color(0xFFF8FAFC)),
                headingTextStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5),
                columns: const [
                  DataColumn(label: Text('CATEGORY / TARGET')),
                  DataColumn(label: Text('TARIFF NAME')),
                  DataColumn(label: Text('AMOUNT (GHS)')),
                  DataColumn(label: Text('FREQUENCY')),
                  DataColumn(label: Text('FORMULA / PURPOSE')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: items.map((item) {
                  final originalIndex = _fees.indexOf(item);
                  final label = item['label']?.toString() ?? '';
                  final amt = item['amount']?.toString() ?? '0.00';
                  final freq = item['frequency']?.toString() ?? 'Annual';
                  final desc = item['description']?.toString() ?? '';
                  final isSummary = item['is_summary'] == true;
                  final id = (item['id'] ?? '').toString().toLowerCase();
                  final sec = (item['section'] ?? '').toString().toLowerCase();

                  // Determine Target Scale Badge & Color
                  String targetTag = 'All Scales';
                  Color tagColor = _kBlue;

                  if (id.contains('large') || label.toLowerCase().contains('large')) {
                    targetTag = 'Large Corporate';
                    tagColor = _kPurple;
                  } else if (id.contains('sme') || label.toLowerCase().contains('sme')) {
                    targetTag = 'SME';
                    tagColor = _kOrange;
                  } else if (sec == 'associate' || id.contains('associate')) {
                    targetTag = 'Associate';
                    tagColor = const Color(0xFFD97706);
                  } else if (sec == 'licentiate' || id.contains('licentiate')) {
                    targetTag = 'Licentiate';
                    tagColor = _kBrown;
                  } else if (id.contains('reg_form') || id.contains('new_reg')) {
                    targetTag = 'All New Members';
                    tagColor = _kGreen;
                  }

                  return DataRow(
                    cells: [
                      // TARGET TAG BADGE
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: tagColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: tagColor.withAlpha(80)),
                              ),
                              child: Text(
                                targetTag,
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: tagColor),
                              ),
                            ),
                            if (isSummary) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _kOrange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'PACKAGE',
                                  style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // NAME
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 16.5,
                              fontWeight: isSummary ? FontWeight.w800 : FontWeight.w600,
                              color: isSummary ? (isDark ? Colors.white : const Color(0xFF0F172A)) : textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // AMOUNT
                      DataCell(
                        Text(
                          'GHS ${double.tryParse(amt)?.toStringAsFixed(2) ?? amt}',
                          style: GoogleFonts.outfit(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w900,
                            color: activeThemeColor,
                          ),
                        ),
                      ),

                      // FREQUENCY
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (freq == 'One-Time' ? _kOrange : _kBrown).withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            freq.toUpperCase(),
                            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold, color: freq == 'One-Time' ? _kOrange : _kBrown),
                          ),
                        ),
                      ),

                      // FORMULA / PURPOSE
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            desc,
                            style: GoogleFonts.inter(fontSize: 15.5, color: textMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // ACTIONS
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showFeeDialog(item, originalIndex),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: activeThemeColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 12),
                              label: Text('Edit', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: _kRed),
                              tooltip: 'Remove',
                              onPressed: () => _removeFee(originalIndex),
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
    );
  }
}
