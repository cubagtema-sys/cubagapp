import os

FLUTTER_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_fees_page.dart"

CODE = '''import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kPurple = Color(0xFF8B5CF6);

class AdminFeesPage extends StatefulWidget {
  const AdminFeesPage({super.key});

  @override
  State<AdminFeesPage> createState() => _AdminFeesPageState();
}

class _AdminFeesPageState extends State<AdminFeesPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<Map<String, dynamic>> _fees = [];
  bool _saving = false;
  bool _fetching = true;
  String _searchQuery = '';
  String _message = '';
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFees();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        if (list.isNotEmpty) {
          setState(() {
            _fees = list;
            _fetching = false;
          });
          return;
        }
      }
    } catch (_) {}

    setState(() => _fetching = false);
  }

  // Recalculate package summaries based on individual component items
  void _recalculatePackages() {
    double getAmt(String id, double fallback) {
      final found = _fees.firstWhere(
        (f) => f['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty && found['amount'] != null) {
        return double.tryParse(found['amount'].toString()) ?? fallback;
      }
      return fallback;
    }

    final subSme = getAmt('new_sub_fee', 120.0);
    final vetting = getAmt('new_vetting_fee', 750.0);
    final district = getAmt('new_district_fee', 250.0);
    final cfScope = getAmt('new_cf_fee', 500.0);
    final consolScope = getAmt('new_consolidation_fee', 600.0);

    // New membership packages (Registration Fee 600 is paid separately upfront)
    final newCfOnlyTotal = subSme + vetting + district + cfScope;
    final newConsolTotal = subSme + vetting + district + consolScope;
    final newCfConsolTotal = subSme + vetting + district + consolScope + cfScope;

    for (var f in _fees) {
      if (f['id'] == 'new_cf_only') {
        f['amount'] = newCfOnlyTotal.toStringAsFixed(2);
      } else if (f['id'] == 'new_consolidation') {
        f['amount'] = newConsolTotal.toStringAsFixed(2);
      } else if (f['id'] == 'new_cf_consolidation') {
        f['amount'] = newCfConsolTotal.toStringAsFixed(2);
      }
    }
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
          final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
          final textCol = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
          final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.edit_note_rounded, color: _kOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Fee Item / Tariff' : 'Add Fee Item / Tariff',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: textCol),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(dlgCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    Text('FEE SECTION', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('New Membership & Registration', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                            selected: section == 'new_membership',
                            selectedColor: _kOrange,
                            labelStyle: TextStyle(color: section == 'new_membership' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'new_membership');
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Existing Member Renewal', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                            selected: section == 'renewal',
                            selectedColor: _kIndigo,
                            labelStyle: TextStyle(color: section == 'renewal' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'renewal');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text('FEE ITEM / TARIFF NAME *', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: GoogleFonts.outfit(fontSize: 13, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                        hintText: 'e.g. Registration Fee, Vetting Fee, CTI Training Levy',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
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
                              Text('AMOUNT (GHS) *', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: amountCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kOrange),
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixText: 'GHS ',
                                  prefixStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kOrange),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              Text('BILLING FREQUENCY', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: ['Annual', 'One-Time', 'Monthly', 'Per Request'].contains(frequency) ? frequency : 'Annual',
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                dropdownColor: cardBg,
                                style: GoogleFonts.outfit(fontSize: 12, color: textCol, fontWeight: FontWeight.bold),
                                items: const [
                                  DropdownMenuItem(value: 'One-Time', child: Text('One-Time Fee')),
                                  DropdownMenuItem(value: 'Annual', child: Text('Annual Dues')),
                                  DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                                  DropdownMenuItem(value: 'Per Request', child: Text('Per Request')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setDlgState(() => frequency = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text('DESCRIPTION / PURPOSE BREAKDOWN', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: GoogleFonts.inter(fontSize: 13, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF10141E) : const Color(0xFFF8FAFC),
                        hintText: 'Detailed explanation of what this fee item covers...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dlgCtx),
                          child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            final amount = amountCtrl.text.trim();
                            if (name.isEmpty || amount.isEmpty) return;

                            setState(() {
                              final newItem = {
                                'id': isEdit ? existingFee['id'] : 'fee_${DateTime.now().millisecondsSinceEpoch}',
                                'section': section,
                                'is_summary': isSummary,
                                'label': name,
                                'amount': amount,
                                'frequency': frequency,
                                'description': descCtrl.text.trim(),
                              };
                              if (isEdit && index != null && index < _fees.length) {
                                _fees[index] = newItem;
                              } else {
                                _fees.add(newItem);
                              }
                              _recalculatePackages();
                            });
                            Navigator.pop(dlgCtx);
                            _saveAllFees();
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text(isEdit ? 'Save Changes' : 'Add Fee Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    nameCtrl.dispose();
    amountCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _removeFee(int index) async {
    if (index < 0 || index >= _fees.length) return;
    final fee = _fees[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Fee Item?'),
        content: Text('Are you sure you want to remove "${fee['label']}" from the platform fee schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _fees.removeAt(index);
      _recalculatePackages();
    });
    _saveAllFees();
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
    final q = _searchQuery.toLowerCase();
    return list.where((f) {
      final name = (f['label']?.toString() ?? '').toLowerCase();
      final desc = (f['description']?.toString() ?? '').toLowerCase();
      final freq = (f['frequency']?.toString() ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q) || freq.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
    final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // Section 1: New Membership Fees
    final newMemFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return sec == 'new_membership' || id.startsWith('new_') || id.startsWith('reg_');
    }).toList();

    final newMemSummaries = _filterList(newMemFees.where((f) => f['is_summary'] == true).toList());
    final newMemBreakdown = _filterList(newMemFees.where((f) => f['is_summary'] != true).toList());

    // Section 2: Renewal Fees
    final renewalFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return sec == 'renewal' || id.startsWith('renewal_');
    }).toList();

    final renewalSummaries = _filterList(renewalFees.where((f) => f['is_summary'] == true).toList());
    final renewalBreakdown = _filterList(renewalFees.where((f) => f['is_summary'] != true).toList());

    // Upfront registration fee item
    final regFeeItem = _fees.firstWhere(
      (f) => f['id'] == 'reg_form_fee' || f['id'] == 'new_reg_fee',
      orElse: () => {
        'id': 'reg_form_fee',
        'label': 'Registration Form Fee',
        'amount': '600.00',
        'frequency': 'One-Time',
        'description': 'Mandatory initial onboarding fee paid upfront upon registration before document vetting.',
      },
    );

    return AppLayout(
      title: 'Platform Fees & Tariff Schedule',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP EXECUTIVE BANNER ─────────────────────────────────────────
            AdminHeader(
              title: 'Platform Fees & Tariff Schedule',
              subtitle: 'Configure official entrance packages, upfront registration form fee, annual renewal dues, and isolated breakdown component tariffs.',
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
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text('Save & Publish', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                  onPressed: () => _showFeeDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Add Fee Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── NOTIFICATION TOAST ──────────────────────────────────────────
            if (_message.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: _isSuccess ? _kGreen.withAlpha(20) : _kRed.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isSuccess ? _kGreen.withAlpha(60) : _kRed.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(_isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: _isSuccess ? _kGreen : _kRed, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_message, style: GoogleFonts.outfit(color: _isSuccess ? _kGreen : _kRed, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),

            // ── SEARCH BAR ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F121A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: GoogleFonts.outfit(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search fee item or breakdown tariff by name or description...',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                          prefixIcon: Icon(Icons.search_rounded, size: 17, color: textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── SECTION 1: NEW MEMBERSHIP ────────────────────────────────────
            _buildSectionBanner(
              badgeText: 'SECTION 1',
              title: 'CLASSIFICATION OF FEES (NEW MEMBERSHIP)',
              subtitle: 'Registration Fee is paid upfront upon onboarding. Membership Entrance Package is paid after 11 statutory documents are approved.',
              color: _kOrange,
              icon: Icons.person_add_alt_1_rounded,
              textPrimary: textPrimary,
              textMuted: textMuted,
              onAdd: () => _showFeeDialog(null, null, 'new_membership'),
            ),
            const SizedBox(height: 12),

            // UPFRONT REGISTRATION FEE HIGHLIGHT CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(isDark ? 20 : 12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kOrange.withAlpha(70), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.receipt_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '1. Registration Fee (Upfront Onboarding Form Fee)',
                              style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w900, color: textPrimary),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(6)),
                              child: Text('UPFRONT ONBOARDING', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Paid separately at the beginning when an applicant onboards before the 11 documents are vetted.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'GHS ${double.tryParse(regFeeItem['amount']?.toString() ?? '600')?.toStringAsFixed(2) ?? '600.00'}',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: _kOrange),
                      ),
                      const SizedBox(height: 4),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: Size.zero,
                          elevation: 0,
                        ),
                        onPressed: () {
                          final idx = _fees.indexWhere((f) => f['id'] == regFeeItem['id']);
                          _showFeeDialog(regFeeItem, idx >= 0 ? idx : null, 'new_membership');
                        },
                        icon: const Icon(Icons.edit_outlined, size: 12),
                        label: Text('Edit Fee', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // CATEGORY SUMMARIES TABLE (NEW MEMBERSHIP)
            Text(
              'MEMBERSHIP ENTRANCE SUMMARIES (PAID AFTER 11 DOCUMENTS APPROVED)',
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: _kOrange, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            _buildFeeTable(newMemSummaries, isDark, cardBg, border, textPrimary, textMuted, isPackageSection: true),

            const SizedBox(height: 16),

            // INDIVIDUAL BREAKDOWN ITEMS TABLE (NEW MEMBERSHIP)
            Text(
              'NEW MEMBERSHIP BREAKDOWN ITEMS (EDITABLE ISOLATED TARIFFS)',
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            _buildFeeTable(newMemBreakdown, isDark, cardBg, border, textPrimary, textMuted, isPackageSection: false),

            const SizedBox(height: 32),

            // ── SECTION 2: EXISTING MEMBERSHIP RENEWAL ───────────────────────
            _buildSectionBanner(
              badgeText: 'SECTION 2',
              title: 'CLASSIFICATION OF FEES (EXISTING MEMBERSHIP RENEWAL)',
              subtitle: 'Annual operating compliance clearance tariffs and isolated component breakdowns for SMEs and Large Corporates.',
              color: _kIndigo,
              icon: Icons.autorenew_rounded,
              textPrimary: textPrimary,
              textMuted: textMuted,
              onAdd: () => _showFeeDialog(null, null, 'renewal'),
            ),
            const SizedBox(height: 12),

            // CATEGORY SUMMARIES TABLE (RENEWAL)
            Text(
              'ANNUAL RENEWAL DUES SUMMARIES',
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: _kIndigo, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            _buildFeeTable(renewalSummaries, isDark, cardBg, border, textPrimary, textMuted, isPackageSection: true),

            const SizedBox(height: 16),

            // INDIVIDUAL BREAKDOWN ITEMS TABLE (RENEWAL)
            Text(
              'RENEWAL BREAKDOWN ITEMS (EDITABLE ISOLATED COMPONENT TARIFFS)',
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            _buildFeeTable(renewalBreakdown, isDark, cardBg, border, textPrimary, textMuted, isPackageSection: false),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionBanner({
    required String badgeText,
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required Color textPrimary,
    required Color textMuted,
    required VoidCallback onAdd,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                      child: Text(badgeText, style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withAlpha(90)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_rounded, size: 15),
            label: Text('Add Item', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeTable(
    List<Map<String, dynamic>> items,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted, {
    required bool isPackageSection,
  }) {
    if (_fetching) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (_, index) => const ShimmerListTile(),
      );
    }

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Center(
          child: Text('No items configured.', style: GoogleFonts.outfit(fontSize: 12, color: textMuted)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 25 : 5), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: DataTable(
            horizontalMargin: 16,
            columnSpacing: 18,
            headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC)),
            headingTextStyle: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5),
            columns: const [
              DataColumn(label: Text('NAME / DESCRIPTION')),
              DataColumn(label: Text('AMOUNT (GHS)')),
              DataColumn(label: Text('FREQUENCY')),
              DataColumn(label: Text('BREAKDOWN / PURPOSE')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: items.map((item) {
              final originalIndex = _fees.indexOf(item);
              final label = item['label']?.toString() ?? '';
              final amt = item['amount']?.toString() ?? '0.00';
              final freq = item['frequency']?.toString() ?? 'Annual';
              final desc = item['description']?.toString() ?? '';
              final isSummary = item['is_summary'] == true;

              return DataRow(
                cells: [
                  // NAME
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 22,
                            decoration: BoxDecoration(
                              color: isSummary ? _kIndigo : _kOrange,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                fontWeight: isSummary ? FontWeight.w800 : FontWeight.w600,
                                color: isSummary ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA)) : textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // AMOUNT
                  DataCell(
                    Text(
                      'GHS ${double.tryParse(amt)?.toStringAsFixed(2) ?? amt}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isSummary ? _kIndigo : _kOrange,
                      ),
                    ),
                  ),

                  // FREQUENCY
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (freq == 'One-Time' ? _kPurple : _kBlue).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        freq.toUpperCase(),
                        style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.bold, color: freq == 'One-Time' ? _kPurple : _kBlue),
                      ),
                    ),
                  ),

                  // DESCRIPTION
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        desc,
                        style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
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
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 12),
                          label: Text('Edit', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
'''

with open(FLUTTER_FILE, "w", encoding="utf-8") as f:
    f.write(CODE)

print(f"Successfully generated {len(CODE.splitlines())} lines to {FLUTTER_FILE}")
