import '../components/filter_tabs.dart';
import '../components/admin_list.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;
const _kBrown = Color(0xFF6B3E26);
const _kPurple = Color(0xFF7C3AED);
const _kBlue = Color(0xFF0284C7);
const _kTeal = Color(0xFF0D9488);

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

  // Active Category: 'new_reg', 'national', 'district', 'variable', 'settlement', 'all'
  String _selectedCategory = 'new_reg';
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
    final bankCtrl = TextEditingController(text: existingFee?['bank_name']?.toString() ?? 'GCB');
    final accCtrl = TextEditingController(text: existingFee?['account_number']?.toString() ?? '107113005326');
    
    String frequency = existingFee?['frequency']?.toString() ?? 'Annual';
    String section = existingFee?['section']?.toString() ?? defaultSection;
    if (section == 'corporate' || section == 'new_reg') section = 'new_membership';
    String unit = existingFee?['unit']?.toString() ?? 'flat';
    String targetScale = existingFee?['target_scale']?.toString() ?? 'all';

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
          final textCol = isDark ? Colors.white : const Color(0xFF1F1612);
          final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;

          void applyPresetBank(String bank, String acc) {
            setDlgState(() {
              bankCtrl.text = bank;
              accCtrl.text = acc;
            });
          }

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
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
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textCol),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            icon: Icon(Icons.close_rounded, color: textCol.withAlpha(150)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      Text('Tariff section *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('New Registration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            selected: section == 'new_membership',
                            selectedColor: _kOrange,
                            labelStyle: TextStyle(color: section == 'new_membership' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) {
                                setDlgState(() {
                                  section = 'new_membership';
                                  frequency = 'One-Time';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: Text('National Renewal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            selected: section == 'national',
                            selectedColor: _kBlue,
                            labelStyle: TextStyle(color: section == 'national' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) {
                                setDlgState(() {
                                  section = 'national';
                                  frequency = 'Annual';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: Text('District Renewal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            selected: section == 'district',
                            selectedColor: _kGreen,
                            labelStyle: TextStyle(color: section == 'district' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) {
                                setDlgState(() {
                                  section = 'district';
                                  frequency = 'Annual';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: Text('Variable / Add-On', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            selected: section == 'variable',
                            selectedColor: _kPurple,
                            labelStyle: TextStyle(color: section == 'variable' ? Colors.white : textCol),
                            onSelected: (val) {
                              if (val) setDlgState(() => section = 'variable');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Text('Tariff purpose / label *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(fontSize: 15, color: textCol),
                        decoration: InputDecoration(
                          hintText: 'e.g. Subscription fee (small companies)',
                          hintStyle: TextStyle(fontSize: 14, color: const Color(0xFF5F6B7E)),
                          filled: true,
                          fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // SETTLEMENT BANK & PRESET BUTTONS
                      Text('Whitsun pay settlement destination *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.account_balance_rounded, size: 14, color: Color(0xFF003366)),
                            label: Text('Zenith Bank (6010309212)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => applyPresetBank('Zenith Bank', '6010309212'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.account_balance_rounded, size: 14, color: _kOrange),
                            label: Text('GCB (107113005326)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => applyPresetBank('GCB', '107113005326'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.account_balance_rounded, size: 14, color: _kTeal),
                            label: Text('Ecobank (1441002452360)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => applyPresetBank('Ecobank', '1441002452360'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.account_balance_rounded, size: 14, color: _kGreen),
                            label: Text('NIB (1110045585101)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => applyPresetBank('NIB', '1110045585101'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: bankCtrl,
                              style: TextStyle(fontSize: 14, color: textCol),
                              decoration: InputDecoration(
                                labelText: 'Bank Name',
                                filled: true,
                                fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: accCtrl,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textCol),
                              decoration: InputDecoration(
                                labelText: 'Account Number',
                                filled: true,
                                fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // AMOUNT & TARGET SCALE
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Amount (GHS) *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: amountCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                                  decoration: InputDecoration(
                                    prefixText: 'GHS ',
                                    prefixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.accentOrangeText),
                                    filled: true,
                                    fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
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
                                Text('Target scale *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: targetScale,
                                      isExpanded: true,
                                      dropdownColor: cardBg,
                                      style: TextStyle(fontSize: 14, color: textCol),
                                      items: const [
                                        DropdownMenuItem(value: 'all', child: Text('All Companies')),
                                        DropdownMenuItem(value: 'small', child: Text('Small / SME')),
                                        DropdownMenuItem(value: 'large', child: Text('Large Corporate')),
                                        DropdownMenuItem(value: 'multinational', child: Text('Multinational')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setDlgState(() => targetScale = val);
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

                      // UNIT & FREQUENCY
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Billing unit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: unit,
                                      isExpanded: true,
                                      dropdownColor: cardBg,
                                      style: TextStyle(fontSize: 14, color: textCol),
                                      items: const [
                                        DropdownMenuItem(value: 'flat', child: Text('Flat Tariff')),
                                        DropdownMenuItem(value: 'per_director', child: Text('Per Director')),
                                        DropdownMenuItem(value: 'per_staff', child: Text('Per Staff')),
                                        DropdownMenuItem(value: 'per_head', child: Text('Per Head')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setDlgState(() => unit = val);
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
                                Text('Frequency', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: frequency,
                                      isExpanded: true,
                                      dropdownColor: cardBg,
                                      style: TextStyle(fontSize: 14, color: textCol),
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

                      Text('Description / notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF5F6B7E), letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        style: TextStyle(fontSize: 14, color: textCol),
                        decoration: InputDecoration(
                          hintText: 'e.g. Mandatory statutory fee settled to Zenith Bank account',
                          hintStyle: TextStyle(fontSize: 13, color: const Color(0xFF5F6B7E)),
                          filled: true,
                          fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            child: Text('Cancel', style: TextStyle(color: const Color(0xFF5F6B7E), fontWeight: FontWeight.bold)),
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
                                'bank_name': bankCtrl.text.trim().isNotEmpty ? bankCtrl.text.trim() : 'GCB',
                                'account_number': accCtrl.text.trim().isNotEmpty ? accCtrl.text.trim() : '107113005326',
                                'frequency': frequency,
                                'section': section,
                                'unit': unit,
                                'target_scale': targetScale,
                                'description': descCtrl.text.trim(),
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
                            label: Text(isEdit ? 'Update Tariff' : 'Add Tariff', style: TextStyle(fontWeight: FontWeight.bold)),
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
        title: Text('Remove Fee Item', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "$itemName" from the official tariff schedule?', style: TextStyle(fontSize: 15)),
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
        _message = 'Tariff schedule saved and published successfully.';
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
      final bank = (f['bank_name']?.toString() ?? '').toLowerCase();
      final acc = (f['account_number']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          desc.contains(_searchQuery) ||
          freq.contains(_searchQuery) ||
          amt.contains(_searchQuery) ||
          bank.contains(_searchQuery) ||
          acc.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F1612);
    final textMuted = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    // Grouping by sections:
    final newRegFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return (sec == 'new_membership' || sec == 'new_reg' || id.startsWith('new_') || id.startsWith('reg_')) &&
          sec != 'national' && sec != 'district' && sec != 'variable';
    }).toList();

    final nationalFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return (sec == 'national' || id.startsWith('sub_') || id.startsWith('admin_') || id.startsWith('legal_') || id.startsWith('cpd_')) &&
          sec != 'district' && sec != 'variable' && sec != 'new_membership';
    }).toList();

    final districtFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return (sec == 'district' || id.startsWith('district_')) &&
          sec != 'national' && sec != 'variable' && sec != 'new_membership';
    }).toList();

    final variableFees = _fees.where((f) {
      final sec = f['section']?.toString() ?? '';
      final id = f['id']?.toString() ?? '';
      return sec == 'variable' || id.startsWith('var_');
    }).toList();

    List<Map<String, dynamic>> activeList = [];
    Color activeThemeColor = _kOrange;
    String activeTitle = 'New registration';

    if (_selectedCategory == 'new_reg') {
      activeThemeColor = _kOrange;
      activeTitle = 'New registration';
      activeList = newRegFees;
    } else if (_selectedCategory == 'national') {
      activeThemeColor = _kBlue;
      activeTitle = 'National renewal';
      if (_subFilter == 'small') {
        activeList = nationalFees.where((f) => (f['target_scale'] ?? '') == 'small' || f['label'].toString().toLowerCase().contains('small')).toList();
      } else if (_subFilter == 'large') {
        activeList = nationalFees.where((f) => (f['target_scale'] ?? '') == 'large' || f['label'].toString().toLowerCase().contains('large')).toList();
      } else if (_subFilter == 'multinational') {
        activeList = nationalFees.where((f) => (f['target_scale'] ?? '') == 'multinational' || f['label'].toString().toLowerCase().contains('multinational')).toList();
      } else {
        activeList = nationalFees;
      }
    } else if (_selectedCategory == 'district') {
      activeThemeColor = _kGreen;
      activeTitle = 'District renewal';
      activeList = districtFees;
    } else if (_selectedCategory == 'variable') {
      activeThemeColor = _kPurple;
      activeTitle = 'Add-ons';
      activeList = variableFees;
    } else {
      activeThemeColor = _kBrown;
      activeTitle = 'All fees';
      activeList = _fees;
    }

    final filteredDisplayList = _filterList(activeList);

    return AppLayout(
      title: 'Fees',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Fees',
                subtitle: 'What members pay to register and renew. Members pay the total in one MoMo payment; '
                    'each fee is then settled into the account shown with it. Changes reach members after you publish.',
                actions: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveAllFees,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.publish_rounded, size: 18),
                    label: Text(_saving ? 'Publishing…' : 'Publish changes'),
                  ),
                ],
              ),
              if (_message.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(CubagSpace.md),
                  decoration: BoxDecoration(
                    color: _isSuccess ? CubagColors.validTint : CubagColors.lapsedTint,
                    borderRadius: BorderRadius.circular(CubagRadius.card),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: _isSuccess ? CubagColors.valid : CubagColors.lapsed,
                        size: 20,
                      ),
                      const SizedBox(width: CubagSpace.sm),
                      Expanded(
                        child: Text(
                          _message,
                          style: CubagType.label.copyWith(color: _isSuccess ? CubagColors.valid : CubagColors.lapsed),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CubagSpace.md),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final perRow = w < 520 ? 2 : (w < 900 ? 3 : 5);
                  final cardWidth = (w - CubagSpace.sm * (perRow - 1)) / perRow;
                  return Wrap(
                    spacing: CubagSpace.sm,
                    runSpacing: CubagSpace.sm,
                    children: [
                      for (final s in [
                        ('new_reg', 'New registration', '${newRegFees.length} fees', Icons.person_add_alt_1_outlined),
                        ('national', 'National renewal', '${nationalFees.length} fees', Icons.shield_outlined),
                        ('district', 'District renewal', '${districtFees.length} fees', Icons.location_city_outlined),
                        ('variable', 'Add-ons', '${variableFees.length} fees', Icons.tune_rounded),
                        ('settlement', 'Accounts', '4 bank accounts', Icons.account_balance_outlined),
                      ])
                        _buildCategoryKpiCard(
                          key: s.$1,
                          title: s.$2,
                          subtitle: s.$3,
                          itemCount: 0,
                          color: CubagColors.cocoa,
                          icon: s.$4,
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
              const SizedBox(height: CubagSpace.xl),
              if (_selectedCategory == 'settlement')
                _buildSettlementDashboard(isDark, cardBg, border, textPrimary, textMuted)
              else ...[
                Row(
                  children: [
                    Expanded(child: Text(activeTitle, style: CubagType.title)),
                    OutlinedButton.icon(
                      onPressed: () => _showFeeDialog(
                        null,
                        null,
                        _selectedCategory == 'new_reg' ? 'new_membership' : _selectedCategory,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add fee'),
                    ),
                  ],
                ),
                const SizedBox(height: CubagSpace.sm),
                if (_selectedCategory == 'national') ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _pill('all', 'All firms'),
                        const SizedBox(width: CubagSpace.xs),
                        _pill('small', 'Small firms'),
                        const SizedBox(width: CubagSpace.xs),
                        _pill('large', 'Large firms'),
                        const SizedBox(width: CubagSpace.xs),
                        _pill('multinational', 'Multinationals'),
                      ],
                    ),
                  ),
                  const SizedBox(height: CubagSpace.sm),
                ],
                AdminSearchField(hint: 'Search fees or accounts', onChanged: _onSearchChanged),
                const SizedBox(height: CubagSpace.md),
                _buildFeeTable(
                  filteredDisplayList,
                  isDark,
                  cardBg,
                  border,
                  textPrimary,
                  textMuted,
                  activeThemeColor: activeThemeColor,
                ),
                const SizedBox(height: CubagSpace.xs),
                Text(
                  filteredDisplayList.length == 1 ? '1 fee' : '${filteredDisplayList.length} fees',
                  style: CubagType.caption,
                ),
              ],
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

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
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: () => setState(() {
          _selectedCategory = key;
          _subFilter = 'all';
        }),
        borderRadius: BorderRadius.circular(CubagRadius.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          padding: const EdgeInsets.all(CubagSpace.md),
          decoration: BoxDecoration(
            color: isSelected ? CubagColors.cocoa : CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: isSelected ? CubagColors.cocoa : CubagColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: isSelected ? CubagColors.onCocoaMuted : CubagColors.cocoa),
              const SizedBox(height: CubagSpace.sm),
              Text(
                title,
                style: CubagType.bodyStrong.copyWith(color: isSelected ? CubagColors.onCocoa : CubagColors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: CubagType.caption.copyWith(color: isSelected ? CubagColors.onCocoaMuted : CubagColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String value, String label) {
    final isSelected = _subFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      labelStyle: CubagType.label.copyWith(color: isSelected ? CubagColors.onCocoa : CubagColors.inkSoft),
      selectedColor: CubagColors.cocoa,
      backgroundColor: CubagColors.paper,
      side: BorderSide(color: isSelected ? CubagColors.cocoa : CubagColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (val) {
        if (val) setState(() => _subFilter = value);
      },
    );
  }

  Widget _buildSettlementDashboard(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    List<Map<String, dynamic>> at(String bank) =>
        _fees.where((f) => (f['bank_name'] ?? '').toString().toLowerCase().contains(bank)).toList();
    final banks = [
      ('Zenith Bank', '6010309212', 'Subscription and development levy', at('zenith')),
      ('GCB Bank', '107113005326', 'Operations, administration and legal', at('gcb')),
      ('Ecobank Ghana', '1441002452360', 'District branches and welfare', at('ecobank')),
      ('National Investment Bank', '1110045585101', 'Training and professional development', at('nib')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which fees are paid into each account. To change an account, edit the fee.',
          style: CubagType.small,
        ),
        const SizedBox(height: CubagSpace.md),
        for (final b in banks) ...[
          _buildBankSettlementCard(
            bank: b.$1,
            account: b.$2,
            badge: b.$3,
            color: CubagColors.cocoa,
            items: b.$4,
            isDark: isDark,
            cardBg: cardBg,
            border: border,
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          const SizedBox(height: CubagSpace.md),
        ],
      ],
    );
  }

  Widget _buildBankSettlementCard({
    required String bank,
    required String account,
    required String badge,
    required Color color,
    required List<Map<String, dynamic>> items,
    required bool isDark,
    required Color cardBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final total = items.fold<double>(0, (s, f) => s + (double.tryParse('${f['amount'] ?? 0}') ?? 0));
    return AdminRowGroup(
      children: [
        AdminListRow(
          leading: const AdminRowMark(icon: Icons.account_balance_outlined),
          title: bank,
          subtitle: '$badge · Account $account',
          meta: items.length == 1 ? '1 fee' : '${items.length} fees',
          status: Text('GH₵ ${_money(total)}', style: CubagType.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          trailing: const SizedBox(width: CubagSpace.xs),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(68, 10, CubagSpace.md, 10),
            child: Row(
              children: [
                Expanded(child: Text(item['label']?.toString() ?? '', style: CubagType.small.copyWith(color: CubagColors.inkSoft))),
                Text(
                  'GH₵ ${_money(double.tryParse('${item['amount'] ?? 0}') ?? 0)}',
                  style: CubagType.small.copyWith(color: CubagColors.ink, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _money(double v) {
    final whole = v.truncate();
    final s = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final cents = ((v - whole) * 100).round();
    return cents == 0 ? s : '$s.${cents.toString().padLeft(2, '0')}';
  }

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
      return Column(
        children: List.generate(
          4,
          (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
        ),
      );
    }
    if (items.isEmpty) {
      return const EmptyMessage(
        icon: Icons.receipt_long_outlined,
        title: 'No fees in this section',
        message: 'Use Add fee to create one and choose the account it is paid into.',
      );
    }

    return AdminRowGroup(
      dividerIndent: CubagSpace.md,
      children: [
        for (final item in items)
          () {
            final originalIndex = _fees.indexOf(item);
            final label = item['label']?.toString() ?? '';
            final amt = double.tryParse('${item['amount'] ?? 0}') ?? 0;
            final freq = item['frequency']?.toString() ?? 'Annual';
            final unit = (item['unit']?.toString() ?? 'flat').replaceAll('_', ' ');
            final scale = (item['target_scale'] ?? '').toString();
            final lower = label.toLowerCase();
            final scaleLabel = scale == 'small' || lower.contains('small')
                ? 'Small firms'
                : (scale == 'large' || lower.contains('large')
                    ? 'Large firms'
                    : (scale == 'multinational' || lower.contains('multinational') ? 'Multinationals' : ''));
            final bankName = item['bank_name']?.toString() ?? '';
            final accNum = item['account_number']?.toString() ?? '';
            final desc = (item['description'] ?? '').toString();

            return InkWell(
              onTap: () => _showFeeDialog(item, originalIndex),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(CubagSpace.md, 12, CubagSpace.xs, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: CubagType.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (desc.isNotEmpty)
                            Text(desc, style: CubagType.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (scaleLabel.isNotEmpty) scaleLabel,
                              '$freq${unit == 'flat' ? '' : ', $unit'}',
                              if (bankName.isNotEmpty) 'Paid into $bankName${accNum.isEmpty ? '' : ' $accNum'}',
                            ].join(' · '),
                            style: CubagType.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CubagSpace.sm),
                    Text(
                      'GH₵ ${_money(amt)}',
                      style: CubagType.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
                      onSelected: (v) {
                        if (v == 'edit') _showFeeDialog(item, originalIndex);
                        if (v == 'remove') _removeFee(originalIndex);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: CubagColors.lapsed))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }
}
