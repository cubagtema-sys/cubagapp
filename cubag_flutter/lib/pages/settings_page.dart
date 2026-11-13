import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/in_app_legal_viewer.dart';
import '../utils/session_storage.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../design/cubag_design.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _changingPw = false;
  bool _loading = false;
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _message = '';
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  static const _kBrown = Color(0xFF6B3E26);
  static const _kOrange = CubagColors.action;
  static const _kGreen = CubagColors.valid;
  static const _kRed = CubagColors.lapsed;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      BiometricService().isBiometricAvailable().then((avail) {
        if (mounted) setState(() => _biometricAvailable = avail);
      });
      BiometricService().isBiometricEnabled().then((enabled) {
        if (mounted) setState(() => _biometricEnabled = enabled);
      });
    }
  }

  Future<String?> _askPasswordForBiometrics() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Confirm your password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your password to turn on biometric sign-in for this device. '
              'Your password is not stored on the device.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _changePassword() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _message = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final res = await ApiService().post(
        '/auth/change-password',
        data: {
          'current_password': _currentCtrl.text,
          'new_password': _newCtrl.text,
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        // The backend revokes all older sessions and returns a fresh token.
        final newToken = res.data is Map ? res.data['token'] : null;
        if (newToken is String && newToken.isNotEmpty) {
          await SessionStorage.instance.setString('cubag_token', newToken);
        }
        // SEC-14: a password change revokes every biometric device credential.
        // Re-enrol this device with the new password so Face ID keeps working.
        if (!kIsWeb && _biometricEnabled) {
          final enrolError = await BiometricService().enroll(_newCtrl.text);
          if (enrolError != null) {
            await BiometricService().clearLocal();
            if (mounted) setState(() => _biometricEnabled = false);
          }
        }
        if (!mounted) return;
        setState(() {
          _message = 'Password updated successfully';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _changingPw = false;
              _message = '';
              _currentCtrl.clear();
              _newCtrl.clear();
              _confirmCtrl.clear();
            });
          }
        });
      } else {
        final msg = res.data is Map
            ? (res.data['message'] ?? 'Update failed')
            : 'Update failed';
        setState(() => _message = msg);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Connection error. Please try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmDeleteAccount(
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: 1.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _kRed, size: 24),
            const SizedBox(width: 8),
            Text(
              'Delete Account',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: text,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete your CUBAG member account?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kRed.withValues(alpha: 0.2)),
              ),
              child: const Text(
                'This action is irreversible. All member profile data, certificates, uploaded verification documents, and payment history will be permanently erased.',
                style: TextStyle(
                  fontSize: 13,
                  color: _kRed,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final res = await ApiService().delete('/auth/delete-account');
      if (res.statusCode == 200 || res.statusCode == 204) {
        // The server has revoked this account's device credentials; forget ours.
        await BiometricService().clearLocal();
        await AuthService().logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been deleted.'),
            ),
          );
          context.go('/login');
        }
        return;
      }
    } catch (e) {
      debugPrint('Delete account API error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to complete account deletion at this time. Please contact support@cubag.org.gh',
          ),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final text = isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;
    final muted = isDark ? const Color(0xFFC8ADA0) : CubagColors.muted;
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

    return AppLayout(
      title: 'Settings',
      scrollable: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: !_changingPw
                  ? _buildMenu(cardBg, border, text, muted, surfaceRaised)
                  : _buildPasswordForm(cardBg, border, text, muted, surfaceRaised),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section 1: Security & Preferences
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Security',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kBrown,
                  ),
                ),
              ),
              Divider(height: 1, color: border),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: _kBrown,
                    size: 16,
                  ),
                ),
                title: Text(
                  'Change Password',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: text,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 18,
                ),
                onTap: () => setState(() => _changingPw = true),
              ),
              if (!kIsWeb && _biometricAvailable) ...[
                Divider(height: 1, color: border),
                SwitchListTile(
                  value: _biometricEnabled,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  activeThumbColor: _kOrange,
                  activeTrackColor: _kOrange.withValues(alpha: 0.3),
                  secondary: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: surfaceRaised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: border, width: 1.0),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: _kBrown,
                      size: 16,
                    ),
                  ),
                  title: Text(
                    'Biometric / Face ID Sign-In',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  subtitle: Text(
                    'Sign in with your face or fingerprint',
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                  onChanged: (v) async {
                    if (v) {
                      final verified = await BiometricService().authenticate(
                        reason: 'Verify identity to enable biometric sign-in',
                      );
                      if (!verified || !mounted) return;
                      // SEC-14: enabling needs the account password once; the
                      // server then issues a credential for this device only.
                      final password = await _askPasswordForBiometrics();
                      if (password == null || password.isEmpty) return;
                      final error = await BiometricService().enroll(password);
                      if (!mounted) return;
                      if (error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error)),
                        );
                        return;
                      }
                    } else {
                      await BiometricService().disable();
                    }
                    if (mounted) setState(() => _biometricEnabled = v);
                  },
                ),
              ],
              Divider(height: 1, color: border),
              SwitchListTile(
                value: _notificationsEnabled,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                activeThumbColor: _kOrange,
                activeTrackColor: _kOrange.withValues(alpha: 0.3),
                onChanged: (v) async {
                  setState(() => _notificationsEnabled = v);
                  try {
                    await ApiService().post(
                      '/auth/update-preferences',
                      data: {'push_notifications': v},
                    );
                  } catch (_) {
                    if (mounted) setState(() => _notificationsEnabled = !v);
                  }
                },
                secondary: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: _kBrown,
                    size: 16,
                  ),
                ),
                title: Text(
                  'Push Notifications',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: text,
                  ),
                ),
                subtitle: Text(
                  'Notices, payments and reminders',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 2: Contact & Secretariat
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Contact',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kBrown,
                  ),
                ),
              ),
              Divider(height: 1, color: border),
              _contactItem(
                Icons.call_rounded,
                'Call the Secretariat',
                '+233 (0) 302 123 456',
                () async {
                  final uri = Uri.parse('tel:+233302123456');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
                text,
                muted,
                border,
                surfaceRaised,
              ),
              Divider(height: 1, color: border),
              _contactItem(
                Icons.mail_outline_rounded,
                'Email',
                'support@cubag.org.gh',
                () async {
                  final uri = Uri.parse('mailto:support@cubag.org.gh');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
                text,
                muted,
                border,
                surfaceRaised,
              ),
              Divider(height: 1, color: border),
              _contactItem(
                Icons.confirmation_number_outlined,
                'Support',
                'Ask a question or make a complaint',
                () => context.go('/engagement'),
                text,
                muted,
                border,
                surfaceRaised,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 3: Legal & Governance
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Legal',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kBrown,
                  ),
                ),
              ),
              Divider(height: 1, color: border),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: const Icon(
                    Icons.privacy_tip_outlined,
                    color: _kBrown,
                    size: 16,
                  ),
                ),
                title: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: text,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 18,
                ),
                onTap: () => InAppLegalViewer.showPrivacyPolicy(context),
              ),
              Divider(height: 1, color: border),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: _kBrown,
                    size: 16,
                  ),
                ),
                title: Text(
                  'Terms of Service',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: text,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 18,
                ),
                onTap: () => InAppLegalViewer.showTermsOfService(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 4: Deactivation
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kRed.withValues(alpha: 0.3), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Account',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kRed,
                  ),
                ),
              ),
              Divider(height: 1, color: _kRed.withValues(alpha: 0.2)),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kRed.withValues(alpha: 0.2), width: 1.0),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: _kRed,
                    size: 16,
                  ),
                ),
                title: const Text(
                  'Delete account',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _kRed,
                  ),
                ),
                subtitle: Text(
                  'Permanently close your CUBAG account',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                  ),
                ),
                trailing: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kRed,
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right_rounded,
                        color: _kRed,
                        size: 18,
                      ),
                onTap: _loading
                    ? null
                    : () => _confirmDeleteAccount(
                          cardBg,
                          border,
                          text,
                          muted,
                          surfaceRaised,
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _contactItem(
    IconData icon,
    String label,
    String sub,
    VoidCallback onTap,
    Color text,
    Color muted,
    Color border,
    Color surfaceRaised,
  ) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: surfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 1.0),
        ),
        child: Icon(icon, color: _kBrown, size: 16),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: text,
        ),
      ),
      subtitle: Text(
        sub,
        style: TextStyle(
          fontSize: 12,
          color: muted,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: muted,
        size: 18,
      ),
    );
  }

  Widget _buildPasswordForm(
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) {
    Widget? messageWidget;
    if (_message.isNotEmpty) {
      final isSuccess = _message.contains('success');
      final msgColor = isSuccess ? _kGreen : _kRed;
      final msgBg = isSuccess
          ? _kGreen.withValues(alpha: 0.08)
          : _kRed.withValues(alpha: 0.08);

      messageWidget = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: msgBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: msgColor.withValues(alpha: 0.3), width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
              color: msgColor,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _message,
                style: TextStyle(
                  color: msgColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change Password',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter your current credentials to verify authorization, then define your new password.',
            style: TextStyle(
              fontSize: 13,
              color: muted,
            ),
          ),
          const SizedBox(height: 20),
          _pwField(
            'Current Password',
            _currentCtrl,
            _showCurrent,
            () => setState(() => _showCurrent = !_showCurrent),
            cardBg,
            border,
            text,
            muted,
            surfaceRaised,
          ),
          const SizedBox(height: 14),
          _pwField(
            'New Password',
            _newCtrl,
            _showNew,
            () => setState(() => _showNew = !_showNew),
            cardBg,
            border,
            text,
            muted,
            surfaceRaised,
          ),
          const SizedBox(height: 14),
          _pwField(
            'Confirm New Password',
            _confirmCtrl,
            _showConfirm,
            () => setState(() => _showConfirm = !_showConfirm),
            cardBg,
            border,
            text,
            muted,
            surfaceRaised,
          ),
          if (messageWidget != null) ...[
            const SizedBox(height: 14),
            messageWidget,
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _changingPw = false;
                    _message = '';
                    _currentCtrl.clear();
                    _newCtrl.clear();
                    _confirmCtrl.clear();
                  }),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    side: BorderSide(color: border, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: text,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    elevation: 0,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Update',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pwField(
    String label,
    TextEditingController ctrl,
    bool show,
    VoidCallback toggle,
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) {
    return TextField(
      controller: ctrl,
      obscureText: !show,
      style: TextStyle(color: text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: muted,
          fontSize: 13.5,
        ),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: muted,
          size: 16,
        ),
        filled: true,
        fillColor: surfaceRaised,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBrown, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        suffixIcon: IconButton(
          tooltip: show ? 'Hide password' : 'Show password',
          icon: Icon(
            show ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: muted,
            size: 16,
          ),
          onPressed: toggle,
        ),
      ),
    );
  }
}
