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
    final bg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);
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
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP EXECUTIVE HEADER ─────────────────────────────────────────
            AdminHeader(
              title: 'Fees',
              subtitle: 'Set what members pay to register and renew, and which account each fee goes to.',
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
                    _saving ? 'Saving…' : 'Save and publish',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── SETTLEMENT ROUTING CALLOUT ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kBlue.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBlue.withAlpha(80), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_rounded, color: _kBlue, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : const Color(0xFF6B5E55),
                        ),
                        children: const [
                          TextSpan(
                            text: 'One payment, several accounts. ',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _kBlue),
                          ),
                          TextSpan(
                            text: 'Members pay their total in one MoMo payment; each fee below is settled into the account shown next to it.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
                      child: Text(_message, style: TextStyle(color: _isSuccess ? _kGreen : _kRed, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // ── CATEGORY KPI CARDS ───────────────────────────────────────────
            Text(
              'Sections',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 650;
                final isTablet = constraints.maxWidth < 1100;
                final cardWidth = isMobile
                    ? constraints.maxWidth
                    : (isTablet ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 48) / 5);

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCategoryKpiCard(
                      key: 'new_reg',
                      title: 'New registration',
                      subtitle: '${newRegFees.length} fees',
                      itemCount: newRegFees.length,
                      color: _kOrange,
                      icon: Icons.person_add_alt_1_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'national',
                      title: 'National renewal',
                      subtitle: '${nationalFees.length} fees',
                      itemCount: nationalFees.length,
                      color: _kBlue,
                      icon: Icons.shield_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'district',
                      title: 'District renewal',
                      subtitle: '${districtFees.length} fees',
                      itemCount: districtFees.length,
                      color: _kGreen,
                      icon: Icons.location_city_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'variable',
                      title: 'Add-ons',
                      subtitle: '${variableFees.length} fees',
                      itemCount: variableFees.length,
                      color: _kPurple,
                      icon: Icons.tune_rounded,
                      width: cardWidth,
                      isDark: isDark,
                      cardBg: cardBg,
                      border: border,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                    _buildCategoryKpiCard(
                      key: 'settlement',
                      title: 'Accounts',
                      subtitle: 'Zenith, GCB, Ecobank, NIB',
                      itemCount: 4,
                      color: _kTeal,
                      icon: Icons.account_balance_wallet_rounded,
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

            // If Settlement tab is selected, show Settlement Dashboard
            if (_selectedCategory == 'settlement') ...[
              _buildSettlementDashboard(isDark, cardBg, border, textPrimary, textMuted),
            ] else ...[
              // TOOLBAR & SEARCH
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border, width: 1.2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
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
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: activeThemeColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Sub-filter Pills (for National)
                        if (_selectedCategory == 'national') ...[
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _pill('all', 'All Statutory Fees'),
                                  const SizedBox(width: 6),
                                  _pill('small', 'Small / SME'),
                                  const SizedBox(width: 6),
                                  _pill('large', 'Large Corporate'),
                                  const SizedBox(width: 6),
                                  _pill('multinational', 'Multinational'),
                                ],
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),

                        // Add Item Button
                        OutlinedButton.icon(
                          onPressed: () => _showFeeDialog(null, null, _selectedCategory == 'new_reg' ? 'new_membership' : _selectedCategory),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: activeThemeColor,
                            side: BorderSide(color: activeThemeColor.withAlpha(100)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text('Add fee', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Search Bar
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: isDark ? CubagColors.ink : CubagColors.sand,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border),
                            ),
                            child: TextField(
                              onChanged: _onSearchChanged,
                              style: TextStyle(fontSize: 14, color: textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search fees or accounts',
                                hintStyle: TextStyle(fontSize: 13, color: textMuted),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${filteredDisplayList.length} fees',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // STRUCTURED TARIFF DATA TABLE
              _buildFeeTable(
                filteredDisplayList,
                isDark,
                cardBg,
                border,
                textPrimary,
                textMuted,
                activeThemeColor: activeThemeColor,
              ),
            ],

            const SizedBox(height: 24),
          ],
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
              ? [BoxShadow(color: color.withAlpha(40), blurRadius: 10, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withAlpha(isDark ? 15 : 4), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isSelected ? 255 : (isDark ? 40 : 25)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: isSelected ? Colors.white : color, size: 18),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                    child: Text('Active', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isSelected ? (isDark ? Colors.white : color) : textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? (isDark ? Colors.white70 : CubagColors.inkSoft) : textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String value, String label) {
    final isSelected = _subFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600)),
      selected: isSelected,
      selectedColor: _kBlue,
      labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF6B5E55)),
      onSelected: (val) {
        if (val) setState(() => _subFilter = value);
      },
    );
  }

  Widget _buildSettlementDashboard(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final zenithItems = _fees.where((f) => (f['bank_name'] ?? '').toString().toLowerCase().contains('zenith')).toList();
    final gcbItems = _fees.where((f) => (f['bank_name'] ?? '').toString().toLowerCase().contains('gcb')).toList();
    final ecobankItems = _fees.where((f) => (f['bank_name'] ?? '').toString().toLowerCase().contains('ecobank')).toList();
    final nibItems = _fees.where((f) => (f['bank_name'] ?? '').toString().toLowerCase().contains('nib')).toList();

    return Column(
      children: [
        _buildBankSettlementCard(
          bank: 'Zenith Bank',
          account: '6010309212',
          badge: 'Primary Subscription & Development Levy',
          color: const Color(0xFF003366),
          items: zenithItems,
          isDark: isDark,
          cardBg: cardBg,
          border: border,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        const SizedBox(height: 12),
        _buildBankSettlementCard(
          bank: 'GCB Bank',
          account: '107113005326',
          badge: 'Operations, Administration & Legal Compliance',
          color: _kOrange,
          items: gcbItems,
          isDark: isDark,
          cardBg: cardBg,
          border: border,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        const SizedBox(height: 12),
        _buildBankSettlementCard(
          bank: 'Ecobank Ghana',
          account: '1441002452360',
          badge: 'District Branches, Clearance & District Welfare',
          color: _kTeal,
          items: ecobankItems,
          isDark: isDark,
          cardBg: cardBg,
          border: border,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        const SizedBox(height: 12),
        _buildBankSettlementCard(
          bank: 'NIB (National Investment Bank)',
          account: '1110045585101',
          badge: 'CPD Training & Professional Development',
          color: _kGreen,
          items: nibItems,
          isDark: isDark,
          cardBg: cardBg,
          border: border,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.account_balance_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(bank, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(6)),
                          child: Text('Acc: $account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(badge, style: TextStyle(fontSize: 12, color: textMuted)),
                  ],
                ),
              ),
              Text(
                '${items.length} Tariffs Mapped',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              final amt = item['amount']?.toString() ?? '0.00';
              final label = item['label']?.toString() ?? '';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? CubagColors.ink : CubagColors.sand,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: textPrimary)),
                    const SizedBox(width: 6),
                    Text('GHS $amt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
              );
            }).toList(),
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
              'No fee tariffs found in this section.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Click "Add Fee Item" above to create an entry with custom settlement accounts.',
              style: TextStyle(fontSize: 13, color: textMuted),
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
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth > 950 ? constraints.maxWidth : 950.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: DataTable(
                horizontalMargin: 16,
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF22140E) : const Color(0xFFFAF6F0)),
                headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5),
                columns: const [
                  DataColumn(label: Text('Section')),
                  DataColumn(label: Text('Fee')),
                  DataColumn(label: Text('Paid into')),
                  DataColumn(label: Text('Amount (GHS)')),
                  DataColumn(label: Text('Unit / freq')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: items.map((item) {
                  final originalIndex = _fees.indexOf(item);
                  final label = item['label']?.toString() ?? '';
                  final amt = item['amount']?.toString() ?? '0.00';
                  final freq = item['frequency']?.toString() ?? 'Annual';
                  final unit = item['unit']?.toString() ?? 'flat';
                  final sec = (item['section'] ?? '').toString();
                  final scale = (item['target_scale'] ?? '').toString();
                  final bankName = item['bank_name']?.toString() ?? 'GCB';
                  final accNum = item['account_number']?.toString() ?? '107113005326';

                  String scaleLabel = 'All Scales';
                  Color scaleColor = _kBlue;
                  if (scale == 'small' || label.toLowerCase().contains('small')) {
                    scaleLabel = 'Small / SME';
                    scaleColor = _kOrange;
                  } else if (scale == 'large' || label.toLowerCase().contains('large')) {
                    scaleLabel = 'Large Corporate';
                    scaleColor = _kPurple;
                  } else if (scale == 'multinational' || label.toLowerCase().contains('multinational')) {
                    scaleLabel = 'Multinational';
                    scaleColor = _kRed;
                  } else if (sec == 'district') {
                    scaleLabel = 'District Clearance';
                    scaleColor = _kGreen;
                  } else if (sec == 'new_membership') {
                    scaleLabel = 'Onboarding';
                    scaleColor = _kTeal;
                  }

                  Color bankBadgeColor = _kOrange;
                  if (bankName.toLowerCase().contains('zenith')) {
                    bankBadgeColor = const Color(0xFF003366);
                  } else if (bankName.toLowerCase().contains('ecobank')) {
                    bankBadgeColor = _kTeal;
                  } else if (bankName.toLowerCase().contains('nib')) {
                    bankBadgeColor = _kGreen;
                  }

                  return DataRow(
                    cells: [
                      // SCALE BADGE
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scaleColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scaleColor.withAlpha(80)),
                          ),
                          child: Text(
                            scaleLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: scaleColor),
                          ),
                        ),
                      ),

                      // NAME
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if ((item['description'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item['description'].toString(),
                                  style: TextStyle(fontSize: 11, color: textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // SETTLEMENT ACCOUNT
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: bankBadgeColor.withAlpha(18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: bankBadgeColor.withAlpha(60)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_rounded, size: 14, color: bankBadgeColor),
                              const SizedBox(width: 6),
                              Text(
                                '$bankName • $accNum',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: bankBadgeColor),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // AMOUNT
                      DataCell(
                        Text(
                          'GHS ${double.tryParse(amt)?.toStringAsFixed(2) ?? amt}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: activeThemeColor,
                          ),
                        ),
                      ),

                      // UNIT / FREQ
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(freq, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textPrimary)),
                            if (unit != 'flat')
                              Text(unit.replaceAll('_', ' '), style: TextStyle(fontSize: 10, color: AppColors.accentOrangeText)),
                          ],
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
                              label: Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
