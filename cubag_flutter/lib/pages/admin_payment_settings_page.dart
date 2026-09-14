import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);

class AdminPaymentSettingsPage extends StatefulWidget {
  const AdminPaymentSettingsPage({super.key});
  @override
  State<AdminPaymentSettingsPage> createState() => _AdminPaymentSettingsPageState();
}

class _AdminPaymentSettingsPageState extends State<AdminPaymentSettingsPage> {
  final _api = ApiService();
  bool _loading = false;
  bool _success = false;
  bool _fetching = true;

  List<Map<String, dynamic>> _banks = [
    {
      'bankName': 'GCB Bank Limited',
      'accountName': 'Customs Brokers Association Ghana (CUBAG)',
      'accountNumber': '1011130022445',
      'branch': 'High Street Branch, Accra',
      'isDefault': true,
      'type': 'bank',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() => _fetching = true);
    await _api.fetchDataWithCache('settings/cubag_payment_settings_v2', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data is Map) {
        if (data['bankAccounts'] is List) {
          final list = (data['bankAccounts'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .where((b) => b['type'] != 'momo')
              .toList();
          if (list.isNotEmpty) {
            setState(() {
              _banks = list;
              _fetching = false;
            });
            return;
          }
        }
      }
      setState(() => _fetching = false);
    });
  }

  void _addBank() {
    setState(() {
      _banks.add({
        'bankName': '',
        'accountName': 'Customs Brokers Association Ghana',
        'accountNumber': '',
        'branch': '',
        'isDefault': _banks.isEmpty,
        'type': 'bank',
      });
    });
  }

  void _removeBank(int index) {
    setState(() {
      _banks.removeAt(index);
    });
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _success = false;
    });

    final allAccounts = _banks.map((b) => {...b, 'type': 'bank'}).toList();

    final res = await _api.postData('settings/cubag_payment_settings_v2', {
      'bankAccounts': allAccounts,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    setState(() {
      _loading = false;
      _success = res != null;
    });

    if (_success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(
                'Bank settlement accounts saved successfully!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _success = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final inputBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);

    return AppLayout(
      title: 'Payment & Settlement Settings',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──────────────────────────────────────────────────────
            AdminHeader(
              title: 'Settlement Accounts & Banking Details',
              subtitle:
                  'Configure official CUBAG recipient bank accounts, branch locations, and settlement instructions for wire transfers and member dues.',
              actions: [
                ElevatedButton.icon(
                  onPressed: _addBank,
                  icon: const Icon(Icons.account_balance_rounded, size: 16),
                  label: Text(
                    'Add Bank Account',
                    style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_fetching) ...[
              const ShimmerListTile(),
              const SizedBox(height: 12),
              const ShimmerListTile(),
            ] else ...[
              // ── OFFICIAL BANK ACCOUNTS SECTION ─────────────────────────
              _buildSectionHeader(
                icon: Icons.account_balance_rounded,
                title: 'Official Association Bank Accounts',
                subtitle: 'Direct wire transfer and branch deposit receiving channels for invoices & member dues',
                badgeText: '${_banks.length} Accounts',
                badgeColor: _kOrange,
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
              const SizedBox(height: 14),

              if (_banks.isEmpty)
                _buildEmptyPlaceholder(
                  'No bank accounts configured yet.',
                  'Click "Add Bank Account" to establish receiving bank instructions for members.',
                  cardBg,
                  border,
                  textPrimary,
                  textMuted,
                )
              else
                ..._banks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final bank = entry.value;
                  return _buildBankCard(
                    index: i,
                    data: bank,
                    isDark: isDark,
                    cardBg: cardBg,
                    inputBg: inputBg,
                    border: border,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onDelete: () => _removeBank(i),
                    onChanged: (key, val) {
                      setState(() {
                        _banks[i][key] = val;
                      });
                    },
                  );
                }),

              const SizedBox(height: 28),

              // ── SAVE BUTTON BAR ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 25 : 5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: _kOrange, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enforce Security & Live Publication',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'Changes reflect immediately across member payment checkout screens and invoice PDFs.',
                            style: GoogleFonts.inter(fontSize: 16, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _save,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _loading ? 'Saving Settings...' : 'Save & Publish Settings',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
            ],
          ],
        ),
      ),
    );
  }

  // ── SECTION HEADER WIDGET ─────────────────────────────────────────────────
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: badgeColor.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: badgeColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 15.5, color: textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── EMPTY PLACEHOLDER ─────────────────────────────────────────────────────
  Widget _buildEmptyPlaceholder(
    String title,
    String subtitle,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 36, color: textMuted),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 16, color: textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── BANK ACCOUNT CARD ─────────────────────────────────────────────────────
  Widget _buildBankCard({
    required int index,
    required Map<String, dynamic> data,
    required bool isDark,
    required Color cardBg,
    required Color inputBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
    required VoidCallback onDelete,
    required void Function(String key, dynamic value) onChanged,
  }) {
    final bankName = (data['bankName'] ?? '').toString();
    final accountNumber = (data['accountNumber'] ?? '').toString();
    final branch = (data['branch'] ?? '').toString();
    final accountName = (data['accountName'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: _kOrange, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  bankName.isNotEmpty ? bankName : 'Bank Account #${index + 1}',
                  style: GoogleFonts.outfit(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                if (data['isDefault'] == true) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PRIMARY',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Remove Bank Account',
                  icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),

          // Card Form Body
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildInputField(
                        label: 'BANK / FINANCIAL INSTITUTION *',
                        hint: 'e.g. GCB Bank Limited, Ecobank, Stanbic',
                        value: bankName,
                        inputBg: inputBg,
                        border: border,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        onChanged: (v) => onChanged('bankName', v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: _buildInputField(
                        label: 'BRANCH LOCATION',
                        hint: 'e.g. High Street Branch, Accra',
                        value: branch,
                        inputBg: inputBg,
                        border: border,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        onChanged: (v) => onChanged('branch', v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildInputField(
                        label: 'ACCOUNT BENEFICIARY / HOLDER NAME *',
                        hint: 'e.g. Customs Brokers Association Ghana',
                        value: accountName,
                        inputBg: inputBg,
                        border: border,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        onChanged: (v) => onChanged('accountName', v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: _buildInputField(
                        label: 'ACCOUNT NUMBER *',
                        hint: 'e.g. 1011130022445',
                        value: accountNumber,
                        inputBg: inputBg,
                        border: border,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        isNumeric: true,
                        onChanged: (v) => onChanged('accountNumber', v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TEXT FIELD HELPER ─────────────────────────────────────────────────────
  Widget _buildInputField({
    required String label,
    required String hint,
    required String value,
    required Color inputBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
    bool isNumeric = false,
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted.withAlpha(150)),
            filled: true,
            fillColor: inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kOrange, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
