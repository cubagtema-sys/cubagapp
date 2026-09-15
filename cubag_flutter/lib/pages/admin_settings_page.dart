import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kBlue = Color(0xFF3b82f6);
const _kRed = Color(0xFFef4444);
const _kCardBg = Color(0xFF281710);

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic> _user = {};
  bool _fetchingUser = true;

  // Password reset state
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _changingPw = false;
  String _pwMessage = '';
  bool _pwSuccess = false;

  // Compliance settings state
  Map<String, dynamic> _complianceSettings = {};
  bool _fetchingSettings = true;
  bool _savingSettings = false;
  String _settingsMessage = '';
  bool _settingsSuccess = false;

  final _payPunctualCtrl = TextEditingController();
  final _payHistoryCtrl = TextEditingController();
  final _licActiveCtrl = TextEditingController();
  final _licInactiveCtrl = TextEditingController();
  final _taskCtrl = TextEditingController();
  final _surveyCtrl = TextEditingController();
  final _agmActiveCtrl = TextEditingController();
  final _agmInactiveCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUser();
    _fetchSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _payPunctualCtrl.dispose();
    _payHistoryCtrl.dispose();
    _licActiveCtrl.dispose();
    _licInactiveCtrl.dispose();
    _taskCtrl.dispose();
    _surveyCtrl.dispose();
    _agmActiveCtrl.dispose();
    _agmInactiveCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUser() async {
    if (_user.isEmpty) setState(() => _fetchingUser = true);
    await ApiService().fetchDataWithCache('/auth/me', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data != null && data is Map) {
        setState(() {
          _user = Map<String, dynamic>.from(data);
          _fetchingUser = false;
        });
      } else if (hasError || !isCached) {
        setState(() => _fetchingUser = false);
      }
    });
  }

  Future<void> _fetchSettings() async {
    if (_complianceSettings.isEmpty) setState(() => _fetchingSettings = true);
    await ApiService().fetchDataWithCache('/compliance-settings', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data != null && data is Map) {
        setState(() {
          _complianceSettings = Map<String, dynamic>.from(data);
          _payPunctualCtrl.text =
              _complianceSettings['payment_punctual']?.toString() ?? '25';
          _payHistoryCtrl.text =
              _complianceSettings['payment_history']?.toString() ?? '15';
          _licActiveCtrl.text =
              _complianceSettings['license_active']?.toString() ?? '15';
          _licInactiveCtrl.text =
              _complianceSettings['license_inactive']?.toString() ?? '5';
          _taskCtrl.text =
              _complianceSettings['task_completion']?.toString() ?? '15';
          _surveyCtrl.text =
              _complianceSettings['survey_completion']?.toString() ?? '10';
          _agmActiveCtrl.text =
              _complianceSettings['agm_active']?.toString() ?? '10';
          _agmInactiveCtrl.text =
              _complianceSettings['agm_inactive']?.toString() ?? '5';
          _fetchingSettings = false;
        });
      } else if (hasError || !isCached) {
        setState(() => _fetchingSettings = false);
      }
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _savingSettings = true;
      _settingsMessage = '';
    });
    try {
      final res = await ApiService().put(
        '/compliance-settings',
        data: {
          'payment_punctual': int.tryParse(_payPunctualCtrl.text) ?? 25,
          'payment_history': int.tryParse(_payHistoryCtrl.text) ?? 15,
          'license_active': int.tryParse(_licActiveCtrl.text) ?? 15,
          'license_inactive': int.tryParse(_licInactiveCtrl.text) ?? 5,
          'task_completion': int.tryParse(_taskCtrl.text) ?? 15,
          'survey_completion': int.tryParse(_surveyCtrl.text) ?? 10,
          'agm_active': int.tryParse(_agmActiveCtrl.text) ?? 10,
          'agm_inactive': int.tryParse(_agmInactiveCtrl.text) ?? 5,
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          _settingsSuccess = true;
          _settingsMessage = 'Compliance scoring rules updated successfully.';
        });
      } else {
        setState(() {
          _settingsSuccess = false;
          _settingsMessage =
              'Update failed. Please review values and try again.';
        });
      }
    } catch (e) {
      setState(() {
        _settingsSuccess = false;
        _settingsMessage = 'Failed to save settings: $e';
      });
    } finally {
      if (mounted) setState(() => _savingSettings = false);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _settingsMessage = '');
      });
    }
  }

  Future<void> _changePassword() async {
    final cur = _currentCtrl.text.trim();
    final newP = _newCtrl.text.trim();
    final conf = _confirmCtrl.text.trim();

    if (cur.isEmpty || newP.isEmpty || conf.isEmpty) {
      setState(() {
        _pwMessage = 'Please fill out all password fields.';
        _pwSuccess = false;
      });
      return;
    }

    if (newP.length < 6) {
      setState(() {
        _pwMessage = 'New password must be at least 6 characters.';
        _pwSuccess = false;
      });
      return;
    }

    if (newP != conf) {
      setState(() {
        _pwMessage = 'New passwords do not match.';
        _pwSuccess = false;
      });
      return;
    }

    setState(() {
      _changingPw = true;
      _pwMessage = '';
    });

    try {
      final res = await ApiService().post(
        '/auth/change-password',
        data: {'current_password': cur, 'new_password': newP},
      );

      if (res.statusCode == 200) {
        setState(() {
          _pwMessage = 'Password updated successfully.';
          _pwSuccess = true;
          _currentCtrl.clear();
          _newCtrl.clear();
          _confirmCtrl.clear();
        });
      } else {
        setState(() {
          _pwMessage =
              res.data?['message']?.toString() ?? 'Failed to update password';
          _pwSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _pwMessage = 'Password update failed: $e';
        _pwSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _changingPw = false);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _pwMessage = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textCol = isDark ? const Color(0xFFFFF8F3) : const Color(0xFF1A0F0A);
    final subTextCol = isDark
        ? const Color(0xFFC8ADA0)
        : const Color(0xFF64748b);
    final inputBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(150)
        : const Color(0xFFf8fafc);

    return AppLayout(
      title: 'Platform Settings',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Title & Subtitle ─────────────────────────────────────
              AdminHeader(
                title: 'System & Platform Settings',
                subtitle:
                    'Configure admin credentials, profile security, and compliance scoring rules.',
                actions: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kAdminOrange.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAdminOrange.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: kAdminOrange,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Super Admin Access',
                          style: GoogleFonts.outfit(
                            color: kAdminOrange,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Navigation Tabs ─────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderCol),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _kOrange,
                  indicatorWeight: 3,
                  labelColor: _kOrange,
                  unselectedLabelColor: subTextCol,
                  labelStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  unselectedLabelStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.manage_accounts_outlined, size: 18),
                      text: 'Account & Security',
                    ),
                    Tab(
                      icon: Icon(Icons.rule_rounded, size: 18),
                      text: 'Compliance Rules',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Tab Contents ────────────────────────────────────────────────
              if (_fetchingUser && _user.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: _kOrange),
                  ),
                )
              else
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    final idx = _tabController.index;
                    if (idx == 0) {
                      return _buildAccountSecurityTab(
                        cardBg,
                        borderCol,
                        textCol,
                        subTextCol,
                        inputBg,
                      );
                    }
                    return _buildComplianceRulesTab(
                      cardBg,
                      borderCol,
                      textCol,
                      subTextCol,
                      inputBg,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. ACCOUNT & SECURITY TAB
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildAccountSecurityTab(
    Color cardBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
    Color inputBg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile Info Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: _kBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Profile Overview',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: textCol,
                        ),
                      ),
                      Text(
                        'Account details associated with your logged-in administrator token.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: subTextCol,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _readOnlyField(
                      'Full Name',
                      _user['name']?.toString() ?? 'Administrator',
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _readOnlyField(
                      'Email Address',
                      _user['email']?.toString() ?? 'admin@cubag.org',
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _readOnlyField(
                      'Role / Privileges',
                      (_user['role']?.toString() ?? 'admin').toUpperCase(),
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _readOnlyField(
                      'Session Status',
                      'Active & Authenticated',
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Password Reset Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: _kOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security & Password Reset',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: textCol,
                        ),
                      ),
                      Text(
                        'Update your administrator portal login password regularly for security.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: subTextCol,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_pwMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _pwSuccess
                        ? _kGreen.withAlpha(20)
                        : _kRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _pwSuccess
                          ? _kGreen.withAlpha(60)
                          : _kRed.withAlpha(60),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pwSuccess
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: _pwSuccess ? _kGreen : _kRed,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pwMessage,
                          style: GoogleFonts.inter(
                            color: _pwSuccess ? _kGreen : _kRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              _pwField(
                'Current Password *',
                _currentCtrl,
                _showCurrent,
                () => setState(() => _showCurrent = !_showCurrent),
                inputBg,
                borderCol,
                textCol,
                subTextCol,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _pwField(
                      'New Password *',
                      _newCtrl,
                      _showNew,
                      () => setState(() => _showNew = !_showNew),
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _pwField(
                      'Confirm New Password *',
                      _confirmCtrl,
                      _showConfirm,
                      () => setState(() => _showConfirm = !_showConfirm),
                      inputBg,
                      borderCol,
                      textCol,
                      subTextCol,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _changingPw ? null : _changePassword,
                  icon: _changingPw
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.key_rounded, size: 18),
                  label: Text(
                    'Update Password',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. COMPLIANCE RULES TAB
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildComplianceRulesTab(
    Color cardBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
    Color inputBg,
  ) {
    if (_fetchingSettings) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: _kOrange)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rule_folder_outlined,
                  color: _kGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compliance Scoring Weights',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: textCol,
                    ),
                  ),
                  Text(
                    'Weights determine how member rating scores (0 - 100%) are calculated across activities.',
                    style: GoogleFonts.inter(fontSize: 16, color: subTextCol),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_settingsMessage.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _settingsSuccess
                    ? _kGreen.withAlpha(20)
                    : _kRed.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _settingsSuccess
                      ? _kGreen.withAlpha(60)
                      : _kRed.withAlpha(60),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _settingsSuccess
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: _settingsSuccess ? _kGreen : _kRed,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _settingsMessage,
                      style: GoogleFonts.inter(
                        color: _settingsSuccess ? _kGreen : _kRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 1. Payment Points
          Text(
            '1. Payment & Financial Standing Points',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textCol,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _weightField(
                  'Punctual Annual Payments (pts)',
                  _payPunctualCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _weightField(
                  'Payment History & Consistency (pts)',
                  _payHistoryCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Customs Licensing Points
          Text(
            '2. Customs Operating License Standing',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textCol,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _weightField(
                  'Active Valid Member ID (pts)',
                  _licActiveCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _weightField(
                  'Expired / Inactive License (pts)',
                  _licInactiveCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. Operational Tasks & Surveys
          Text(
            '3. Association Engagements & Surveys',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textCol,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _weightField(
                  'Task Submissions & Compliance Checks',
                  _taskCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _weightField(
                  'Survey & Feedback Participation',
                  _surveyCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 4. AGM Attendance
          Text(
            '4. AGM & Executive Meetings Attendance',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textCol,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _weightField(
                  'Active AGM Attended (pts)',
                  _agmActiveCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _weightField(
                  'Absent / No Record (pts)',
                  _agmInactiveCtrl,
                  inputBg,
                  borderCol,
                  textCol,
                  subTextCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _savingSettings ? null : _saveSettings,
              icon: _savingSettings
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                'Save Compliance Scoring Weights',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // REUSABLE FIELD HELPERS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _readOnlyField(
    String label,
    String value,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol),
          ),
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textCol,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _pwField(
    String label,
    TextEditingController ctrl,
    bool show,
    VoidCallback toggle,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: !show,
          decoration: InputDecoration(
            filled: true,
            fillColor: inputBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderCol),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderCol),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kOrange, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                show
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: subTextCol,
              ),
              onPressed: toggle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _weightField(
    String label,
    TextEditingController ctrl,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            filled: true,
            fillColor: inputBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderCol),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderCol),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kOrange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
