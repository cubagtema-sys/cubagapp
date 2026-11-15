import '../components/filter_tabs.dart';
import '../components/admin_dialog.dart';
import '../components/cubag_ui.dart';
import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../utils/session_storage.dart';
import '../services/api_service.dart';
import '../design/cubag_design.dart';

const _kCardBg = Color(0xFF22140E);

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
        _pwMessage = 'Fill in all three password boxes.';
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
        // The backend revokes all older sessions and returns a fresh token.
        final newToken = res.data is Map ? res.data['token'] : null;
        if (newToken is String && newToken.isNotEmpty) {
          await SessionStorage.instance.setString('cubag_token', newToken);
        }
        if (!mounted) return;
        setState(() {
          _pwMessage = 'Password changed.';
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
        _pwMessage = 'Could not change the password. Try again.';
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
    final cardBg = isDark ? _kCardBg : CubagColors.paper;
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

    return AppLayout(
      title: 'Settings',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminHeader(
                title: 'Settings',
                subtitle:
                    'Your account and password, and how members\' standing scores are worked out.',
                actions: [
                  StatusChip(
                    switch ((_user['role']?.toString() ?? 'admin').toLowerCase()) {
                      'super_admin' => 'Super admin',
                      'sub_admin' => 'Sub-admin',
                      _ => 'Admin',
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              FilterTabs(
                tabs: const [('0', 'Account'), ('1', 'Standing score')],
                selected: '${_tabController.index}',
                onSelected: (k) => setState(() => _tabController.index = int.parse(k)),
              ),
              const SizedBox(height: CubagSpace.lg),

              if (_fetchingUser && _user.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(),
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

  Widget _section({required String title, String? subtitle, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: CubagSpace.lg),
      padding: const EdgeInsets.all(CubagSpace.xl),
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: CubagType.headline),
          if (subtitle != null) ...[
            const SizedBox(height: CubagSpace.xxs),
            Text(subtitle, style: CubagType.small),
          ],
          const SizedBox(height: CubagSpace.lg),
          ...children,
        ],
      ),
    );
  }

  Widget _notice(String message, bool success) => Container(
        margin: const EdgeInsets.only(bottom: CubagSpace.md),
        padding: const EdgeInsets.all(CubagSpace.sm),
        decoration: BoxDecoration(
          color: success ? CubagColors.validTint : CubagColors.lapsedTint,
          borderRadius: BorderRadius.circular(CubagRadius.control),
        ),
        child: Row(
          children: [
            Icon(success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18, color: success ? CubagColors.valid : CubagColors.lapsed),
            const SizedBox(width: CubagSpace.xs),
            Expanded(
              child: Text(message, style: CubagType.small.copyWith(color: success ? CubagColors.valid : CubagColors.lapsed)),
            ),
          ],
        ),
      );

  Widget _buildAccountSecurityTab(
    Color cardBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
    Color inputBg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          title: 'Your profile',
          subtitle: 'The account you are signed in with. Ask a super admin to change your name or email.',
          children: [
            AdminDetailRow('Name', _user['name']?.toString() ?? ''),
            AdminDetailRow('Email', _user['email']?.toString() ?? ''),
            AdminDetailRow('Role', _roleLabel()),
          ],
        ),
        _section(
          title: 'Password',
          subtitle: 'The new password needs at least 6 characters.',
          children: [
            if (_pwMessage.isNotEmpty) _notice(_pwMessage, _pwSuccess),
            AdminField(
              label: 'Current password',
              child: _pwField('', _currentCtrl, _showCurrent, () => setState(() => _showCurrent = !_showCurrent), inputBg, borderCol, textCol, subTextCol),
            ),
            AdminFieldPair(
              AdminField(
                label: 'New password',
                child: _pwField('', _newCtrl, _showNew, () => setState(() => _showNew = !_showNew), inputBg, borderCol, textCol, subTextCol),
              ),
              AdminField(
                label: 'Type it again',
                child: _pwField('', _confirmCtrl, _showConfirm, () => setState(() => _showConfirm = !_showConfirm), inputBg, borderCol, textCol, subTextCol),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _changingPw ? null : _changePassword,
                child: Text(_changingPw ? 'Changing…' : 'Change password'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComplianceRulesTab(
    Color cardBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
    Color inputBg,
  ) {
    if (_fetchingSettings) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    Widget pair(String a, TextEditingController ca, String b, TextEditingController cb) => AdminFieldPair(
          AdminField(label: a, child: _weightField('', ca, inputBg, borderCol, textCol, subTextCol)),
          AdminField(label: b, child: _weightField('', cb, inputBg, borderCol, textCol, subTextCol)),
        );
    return _section(
      title: 'Standing score',
      subtitle: 'Each member gets a standing score out of 100. Set how many points each item is worth.',
      children: [
        if (_settingsMessage.isNotEmpty) _notice(_settingsMessage, _settingsSuccess),
        Text('Dues', style: CubagType.label.copyWith(color: CubagColors.cocoa)),
        const SizedBox(height: CubagSpace.xs),
        pair('Paid on time', _payPunctualCtrl, 'Payment history', _payHistoryCtrl),
        Text('Licence', style: CubagType.label.copyWith(color: CubagColors.cocoa)),
        const SizedBox(height: CubagSpace.xs),
        pair('Licence active', _licActiveCtrl, 'Licence expired', _licInactiveCtrl),
        Text('Taking part', style: CubagType.label.copyWith(color: CubagColors.cocoa)),
        const SizedBox(height: CubagSpace.xs),
        pair('Tasks done', _taskCtrl, 'Polls answered', _surveyCtrl),
        Text('Annual general meeting', style: CubagType.label.copyWith(color: CubagColors.cocoa)),
        const SizedBox(height: CubagSpace.xs),
        pair('Attended', _agmActiveCtrl, 'Absent or no record', _agmInactiveCtrl),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _savingSettings ? null : _saveSettings,
            child: Text(_savingSettings ? 'Saving…' : 'Save'),
          ),
        ),
      ],
    );
  }

  String _roleLabel() => switch ((_user['role']?.toString() ?? 'admin').toLowerCase()) {
        'super_admin' => 'Super admin',
        'sub_admin' => 'Sub-admin',
        _ => 'Admin',
      };

  Widget _pwField(
    String label,
    TextEditingController ctrl,
    bool visible,
    VoidCallback onToggle,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return TextField(
      controller: ctrl,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide password' : 'Show password',
          icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: onToggle,
        ),
      ),
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
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(suffixText: 'points'),
    );
  }
}
