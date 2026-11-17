import '../utils/payment_codes.dart';
import '../components/admin_dialog.dart';
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
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
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

  // Active Category: 'new_reg', 'national', 'district', 'variable', 'settlement', 'all'
  String _selectedCategory = 'new_reg';
  String _subFilter = 'all';

  Timer? _debounce;

  /// The payment code list, from the server (Admin > Fees > Payment codes).
  List<PaymentCode> _codes = [];
  bool _loadingCodes = true;

  Future<void> _fetchCodes() async {
    try {
      final codes = await PaymentCode.fetch();
      if (mounted) {
        setState(() {
          _codes = codes;
          _loadingCodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCodes = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchFees();
    _fetchCodes();
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
    final amountCtrl = TextEditingController(text: existingFee?['amount']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existingFee?['description']?.toString() ?? '');
    final bankCtrl = TextEditingController(text: existingFee?['bank_name']?.toString() ?? 'GCB');
    final accCtrl = TextEditingController(text: existingFee?['account_number']?.toString() ?? '107113005326');
    final codeCtrl = TextEditingController(text: existingFee?['payment_code']?.toString() ?? '');
    String frequency = existingFee?['frequency']?.toString() ?? 'Annual';
    if (!const ['One-Time', 'Annual'].contains(frequency)) frequency = 'Annual';
    String section = existingFee?['section']?.toString() ?? defaultSection;
    if (section == 'corporate' || section == 'new_reg') section = 'new_membership';
    if (!const ['new_membership', 'national', 'district', 'variable'].contains(section)) section = 'new_membership';
    String unit = existingFee?['unit']?.toString() ?? 'flat';
    if (!const ['flat', 'per_director', 'per_staff', 'per_head'].contains(unit)) unit = 'flat';
    String targetScale = existingFee?['target_scale']?.toString() ?? 'all';
    if (!const ['all', 'small', 'large', 'multinational'].contains(targetScale)) targetScale = 'all';
    String? error;

    const banks = [
      ('Zenith Bank', '6010309212'),
      ('GCB', '107113005326'),
      ('Ecobank', '1441002452360'),
      ('NIB', '1110045585101'),
    ];

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final knownBank = banks.where((b) => b.$1 == bankCtrl.text && b.$2 == accCtrl.text).firstOrNull;

          void submit() {
            final name = nameCtrl.text.trim();
            final amt = amountCtrl.text.trim();
            if (name.isEmpty || double.tryParse(amt.replaceAll(',', '')) == null) {
              setDlgState(() => error = 'Add a name and an amount in cedis.');
              return;
            }
            final feeData = <String, dynamic>{
              'id': existingFee?['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
              'label': name,
              'amount': amt.replaceAll(',', ''),
              'bank_name': bankCtrl.text.trim().isNotEmpty ? bankCtrl.text.trim() : 'GCB',
              'account_number': accCtrl.text.trim().isNotEmpty ? accCtrl.text.trim() : '107113005326',
              'frequency': frequency,
              'section': section,
              'unit': unit,
              'target_scale': targetScale,
              'description': descCtrl.text.trim(),
              if (codeCtrl.text.trim().isNotEmpty) 'payment_code': codeCtrl.text.trim().toUpperCase(),
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
          }

          return AdminDialog(
            title: isEdit ? 'Edit fee' : 'Add fee',
            subtitle: 'Saving publishes the fee list straight away. New amounts apply to bills issued from now on.',
            maxWidth: 620,
            actions: [
              TextButton(onPressed: () => Navigator.of(dlgCtx).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: submit, child: Text(isEdit ? 'Save and publish' : 'Add and publish')),
            ],
            children: [
              AdminField(
                label: 'Section',
                child: AdminChoice<String>(
                  options: const [
                    ('new_membership', 'New registration'),
                    ('national', 'National renewal'),
                    ('district', 'District renewal'),
                    ('variable', 'Add-on'),
                  ],
                  value: section,
                  onChanged: (v) => setDlgState(() {
                    section = v;
                    if (v == 'new_membership') frequency = 'One-Time';
                    if (v == 'national' || v == 'district') frequency = 'Annual';
                  }),
                ),
              ),
              AdminField(
                label: 'Name',
                child: TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(hintText: 'For example: Subscription fee (small firms)'),
                ),
              ),
              AdminFieldPair(
                AdminField(
                  label: 'Amount',
                  child: TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: 'GH₵ ', hintText: '0.00'),
                  ),
                ),
                AdminField(
                  label: 'How often',
                  child: AdminChoice<String>(
                    options: const [('One-Time', 'Once'), ('Annual', 'Every year')],
                    value: frequency,
                    onChanged: (v) => setDlgState(() => frequency = v),
                  ),
                ),
              ),
              AdminFieldPair(
                AdminField(
                  label: 'Who pays it',
                  child: DropdownMenu<String>(
                    initialSelection: targetScale,
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'all', label: 'All firms'),
                      DropdownMenuEntry(value: 'small', label: 'Small firms'),
                      DropdownMenuEntry(value: 'large', label: 'Large firms'),
                      DropdownMenuEntry(value: 'multinational', label: 'Multinationals'),
                    ],
                    onSelected: (v) => setDlgState(() => targetScale = v ?? 'all'),
                  ),
                ),
                AdminField(
                  label: 'Charged',
                  child: DropdownMenu<String>(
                    initialSelection: unit,
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'flat', label: 'Once per firm'),
                      DropdownMenuEntry(value: 'per_director', label: 'Per director'),
                      DropdownMenuEntry(value: 'per_staff', label: 'Per staff member'),
                      DropdownMenuEntry(value: 'per_head', label: 'Per person'),
                    ],
                    onSelected: (v) => setDlgState(() => unit = v ?? 'flat'),
                  ),
                ),
              ),
              AdminField(
                label: 'Paid into',
                help: knownBank == null ? 'A custom account. Check the number carefully.' : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminChoice<String>(
                      options: [for (final b in banks) (b.$1, b.$1), ('other', 'Other account')],
                      value: knownBank?.$1 ?? 'other',
                      onChanged: (v) => setDlgState(() {
                        codeCtrl.clear(); // the code must match the new account
                        final b = banks.where((b) => b.$1 == v).firstOrNull;
                        if (b != null) {
                          bankCtrl.text = b.$1;
                          accCtrl.text = b.$2;
                        } else {
                          bankCtrl.clear();
                          accCtrl.clear();
                        }
                      }),
                    ),
                    if (knownBank == null) ...[
                      const SizedBox(height: CubagSpace.sm),
                      AdminFieldPair(
                        TextField(
                          controller: bankCtrl,
                          onChanged: (_) => setDlgState(() {}),
                          decoration: const InputDecoration(labelText: 'Bank'),
                        ),
                        TextField(
                          controller: accCtrl,
                          onChanged: (_) => setDlgState(() => codeCtrl.clear()),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Account number'),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: CubagSpace.xs),
                      Text('Account ${knownBank.$2}', style: CubagType.caption),
                    ],
                  ],
                ),
              ),
              Builder(builder: (_) {
                final account = accCtrl.text.replaceAll(RegExp(r'\s+'), '');
                final def = defaultPaymentCode(_codes, section: section, bank: bankCtrl.text, account: account);
                final forAccount = _codes.where((c) => c.active && c.accountNumber == account).toList();
                final chosen = codeCtrl.text.trim().toUpperCase();
                final defLabel = _codes.where((c) => c.code == def).map((c) => c.label).firstOrNull ?? '';
                return AdminField(
                  label: 'Payment code',
                  help: forAccount.isEmpty
                      ? 'No payment code is set up for this account yet. Add one under Payment codes, '
                          'or WhitsunPay will not know where to pay this fee.'
                      : 'WhitsunPay uses the code to pay this fee into the account above. '
                          'Only codes for that account are listed.',
                  child: DropdownMenu<String>(
                    key: ValueKey('code-$account'),
                    initialSelection: forAccount.any((c) => c.code == chosen) ? chosen : '',
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(value: '', label: 'Automatic: $def${defLabel.isEmpty ? '' : ' ($defLabel)'}'),
                      for (final c in forAccount) DropdownMenuEntry(value: c.code, label: '${c.code}: ${c.label}'),
                    ],
                    onSelected: (v) => setDlgState(() => codeCtrl.text = v ?? ''),
                  ),
                );
              }),
              AdminField(
                label: 'Note (optional)',
                child: TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'What the fee is for'),
                ),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
  }

  void _removeFee(int index) {
    if (index < 0 || index >= _fees.length) return;
    final itemToRemove = _fees[index];
    final itemName = itemToRemove['label']?.toString() ?? 'Fee Item';

    showAdminConfirm(
      context,
      title: 'Remove this fee?',
      message: '"$itemName" is taken off the fee list and the change is published straight away.',
      confirmLabel: 'Remove',
      destructive: true,
    ).then((ok) {
      if (!ok || !mounted) return;
      setState(() => _fees.removeAt(index));
      _saveAllFees();
    });
  }

  Future<void> _saveAllFees() async {
    setState(() {
      _saving = true;
      _message = '';
    });

    try {
      final res = await _api.post('admin/fees', data: _fees);
      if ((res.statusCode ?? 500) >= 300) {
        // Refused (for example a payment code pointing at two accounts): say why, publish nothing.
        final msg = res.data is Map ? res.data['message']?.toString() : null;
        setState(() {
          _saving = false;
          _isSuccess = false;
          _message = msg ?? 'The fees were not saved. Try again.';
        });
        return;
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
        _message = 'Fees saved and published.';
      });
    } catch (e, st) {
      AppLogger.error('admin_fees_save', e, st);
      setState(() {
        _saving = false;
        _isSuccess = false;
        _message = 'The fees were not saved. Check the connection and try again.';
      });
    } finally {
      if (_isSuccess) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _message = '');
        });
      }
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
                  final perRow = w < 520 ? 2 : (w < 900 ? 3 : 6);
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
                        ('codes', 'Payment codes', _loadingCodes ? 'Loading' : '${_codes.where((c) => c.active).length} codes', Icons.qr_code_2_outlined),
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
              if (_selectedCategory == 'codes')
                _buildCodesView()
              else if (_selectedCategory == 'settlement')
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

  static const _feeTypes = [
    ('new_membership', 'New registration'),
    ('national', 'National renewal'),
    ('district', 'District renewal'),
    ('variable', 'Add-ons'),
    ('cti', 'Courses'),
    ('guest', 'Guest services'),
  ];

  Future<bool> _saveCodes(List<PaymentCode> next) async {
    try {
      final res = await _api.post('admin/payment-codes', data: {'codes': next.map((c) => c.toJson()).toList()});
      if ((res.statusCode ?? 500) < 300) {
        final list = (res.data is Map ? res.data['codes'] : null) as List? ?? [];
        setState(() {
          _codes = list.map((e) => PaymentCode.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          _isSuccess = true;
          _message = 'Payment codes saved. Tell WhitsunPay about any new or changed code.';
        });
        return true;
      }
      setState(() {
        _isSuccess = false;
        _message = (res.data is Map ? res.data['message']?.toString() : null) ?? 'The payment codes were not saved.';
      });
    } catch (_) {
      setState(() {
        _isSuccess = false;
        _message = 'The payment codes were not saved. Check the connection and try again.';
      });
    }
    return false;
  }

  Future<void> _showCodeDialog([PaymentCode? existing]) async {
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final bankCtrl = TextEditingController(text: existing?.bankName ?? '');
    final accCtrl = TextEditingController(text: existing?.accountNumber ?? '');
    final wordsCtrl = TextEditingController(text: existing?.keywords.join(', ') ?? '');
    final types = {...?existing?.sections};
    bool saving = false;
    String? error;
    const banks = [
      ('Zenith Bank', '6010309212'),
      ('GCB', '107113005326'),
      ('Ecobank', '1441002452360'),
      ('NIB', '1110045585101'),
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final known = banks.where((b) => b.$1 == bankCtrl.text && b.$2 == accCtrl.text).firstOrNull;
          Future<void> save() async {
            final entry = PaymentCode(
              code: codeCtrl.text.trim().toUpperCase(),
              label: labelCtrl.text.trim(),
              bankName: bankCtrl.text.trim(),
              accountNumber: accCtrl.text.replaceAll(RegExp(r'\s+'), ''),
              // Older fees use other names for new-member fees; keep them working.
              sections: {...types, if (types.contains('new_membership')) ...['new_reg', 'corporate']}.toList(),
              keywords: wordsCtrl.text.split(',').map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty).toList(),
              active: existing?.active ?? true,
            );
            if (existing == null && _codes.any((c) => c.code == entry.code)) {
              setD(() => error = '${entry.code} already exists.');
              return;
            }
            setD(() {
              saving = true;
              error = null;
            });
            final next = existing == null
                ? [..._codes, entry]
                : [for (final c in _codes) c.code == existing.code ? entry : c];
            final ok = await _saveCodes(next);
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.pop(ctx);
            } else {
              setD(() {
                saving = false;
                error = _message;
              });
            }
          }

          return AdminDialog(
            title: existing == null ? 'Add payment code' : 'Edit ${existing.code}',
            subtitle: 'WhitsunPay pays every amount with this code into the account below. '
                'After saving, give WhitsunPay the new code and account.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Saving…' : 'Save')),
            ],
            children: [
              AdminFieldPair(
                AdminField(
                  label: 'Code',
                  help: 'Capital letters, numbers and hyphens. For example LEV, SUB, ADM.',
                  child: TextField(
                    controller: codeCtrl,
                    enabled: existing == null,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                AdminField(
                  label: 'What it is for',
                  child: TextField(controller: labelCtrl, decoration: const InputDecoration(hintText: 'For example: Port levy')),
                ),
              ),
              AdminField(
                label: 'Paid into',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminChoice<String>(
                      options: [for (final b in banks) (b.$1, b.$1), ('other', 'Other account')],
                      value: known?.$1 ?? (bankCtrl.text.isEmpty && accCtrl.text.isEmpty ? '' : 'other'),
                      onChanged: (v) => setD(() {
                        final b = banks.where((b) => b.$1 == v).firstOrNull;
                        bankCtrl.text = b?.$1 ?? '';
                        accCtrl.text = b?.$2 ?? '';
                      }),
                    ),
                    const SizedBox(height: CubagSpace.sm),
                    AdminFieldPair(
                      TextField(controller: bankCtrl, onChanged: (_) => setD(() {}), decoration: const InputDecoration(labelText: 'Bank')),
                      TextField(
                        controller: accCtrl,
                        onChanged: (_) => setD(() {}),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Account number'),
                      ),
                    ),
                  ],
                ),
              ),
              AdminField(
                label: 'Use automatically for (optional)',
                help: 'Fees of these types paid into this account get this code unless a fee picks another.',
                child: Wrap(
                  spacing: CubagSpace.xs,
                  runSpacing: CubagSpace.xs,
                  children: [
                    for (final t in _feeTypes)
                      FilterChip(
                        label: Text(t.$2),
                        selected: types.contains(t.$1),
                        showCheckmark: false,
                        selectedColor: CubagColors.cocoa,
                        labelStyle: CubagType.label.copyWith(
                          color: types.contains(t.$1) ? CubagColors.onCocoa : CubagColors.inkSoft,
                        ),
                        backgroundColor: CubagColors.paper,
                        side: BorderSide(color: types.contains(t.$1) ? CubagColors.cocoa : CubagColors.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        onSelected: (on) => setD(() => on ? types.add(t.$1) : types.remove(t.$1)),
                      ),
                  ],
                ),
              ),
              AdminField(
                label: 'Words that identify it (optional)',
                help: 'For payments made without a fee list, such as office payments. Separate with commas.',
                child: TextField(controller: wordsCtrl, decoration: const InputDecoration(hintText: 'For example: port levy')),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCodesView() {
    String typeNames(List<String> s) =>
        _feeTypes.where((t) => s.contains(t.$1)).map((t) => t.$2).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Payment codes', style: CubagType.title)),
            OutlinedButton.icon(
              onPressed: _loadingCodes ? null : () => _showCodeDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add payment code'),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.xxs),
        Text(
          'Every MoMo payment reaches the WhitsunPay account with these codes. WhitsunPay pays each code into its account. '
          'A code you switch off is no longer given to new payments.',
          style: CubagType.small,
        ),
        const SizedBox(height: CubagSpace.md),
        if (_loadingCodes)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (_codes.isEmpty)
          const EmptyMessage(icon: Icons.qr_code_2_outlined, title: 'Could not load the payment codes')
        else
          AdminRowGroup(
            dividerIndent: CubagSpace.md,
            children: [
              for (final c in _codes)
                AdminListRow(
                  leading: SizedBox(
                    width: 84,
                    child: Text(c.code, style: CubagType.label.copyWith(color: c.active ? CubagColors.cocoa : CubagColors.muted)),
                  ),
                  title: c.label,
                  subtitle: '${c.bankName} ${c.accountNumber}',
                  meta: c.sections.isEmpty ? null : 'Automatic for ${typeNames(c.sections)}',
                  onTap: () => _showCodeDialog(c),
                  trailing: Tooltip(
                    message: c.active ? 'Given to new payments' : 'Switched off',
                    child: Switch(
                      value: c.active,
                      onChanged: (on) => _saveCodes([for (final x in _codes) x.code == c.code ? x.copyWith(active: on) : x]),
                    ),
                  ),
                ),
            ],
          ),
      ],
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
                              if (!_loadingCodes) paymentCodeFor(item, _codes),
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
