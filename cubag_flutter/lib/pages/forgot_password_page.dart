import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/auth_scaffold.dart';
import '../design/cubag_design.dart';
import '../services/api_service.dart';
import '../utils/validators.dart';

enum _Step { request, setPassword, done }

/// The code from what the member typed or pasted: the 8 digits, or the
/// whole link from the reset email (…reset-password?token=12345678&…).
String extractResetCode(String input) {
  final fromLink = RegExp(r'token=(\d{8})').firstMatch(input);
  if (fromLink != null) return fromLink.group(1)!;
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.length == 8 ? digits : input.trim();
}


/// Password reset, entirely in the app:
///  1. email -> "Send code" (POST /auth/forgot-password; the server answers the
///     same whether or not the account exists),
///  2. the 8-digit code from the email + new password (POST /auth/reset-password),
///  3. done -> sign in.
/// The emailed link opens /reset-password, which lands on step 2 with the
/// code already filled in.
class ForgotPasswordPage extends StatefulWidget {
  final String? initialEmail;
  final String? initialCode;
  const ForgotPasswordPage({super.key, this.initialEmail, this.initialCode});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _cpwCtrl = TextEditingController();
  final _pwFocus = FocusNode();
  final _cpwFocus = FocusNode();

  late _Step _step;
  bool _loading = false;
  String? _error;
  String? _notice;

  /// Came from the emailed link: the code is known, don't ask for it.
  bool get _codeFromLink => (widget.initialCode ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';
    _codeCtrl.text = widget.initialCode ?? '';
    _step = _codeFromLink ? _Step.setPassword : _Step.request;
  }

  @override
  void dispose() {
    for (final c in [_emailCtrl, _codeCtrl, _pwCtrl, _cpwCtrl]) {
      c.dispose();
    }
    _pwFocus.dispose();
    _cpwFocus.dispose();
    super.dispose();
  }

  String _messageFrom(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
      if (e.response == null) return 'Unable to reach the server. Check your connection and try again.';
    }
    return fallback;
  }

  Future<void> _sendCode({bool resend = false}) async {
    final email = _emailCtrl.text.trim();
    if (!AppValidators.isValidEmail(email)) {
      setState(() => _error = 'Enter the email address on your membership.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await ApiService().post('/auth/forgot-password', data: {'email': email});
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _step = _Step.setPassword;
          _notice = resend ? 'We sent a new code.' : null;
        });
      } else {
        final d = res.data;
        setState(() => _error = (d is Map ? d['message']?.toString() : null) ??
            'We could not send a code. Please try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _messageFrom(e, 'We could not send a code. Please try again.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setPassword() async {
    final code = _codeFromLink ? _codeCtrl.text.trim() : extractResetCode(_codeCtrl.text);
    if (!_codeFromLink && !RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 8-digit code from the email.');
      return;
    }
    final pwError = AppValidators.newPasswordError(_pwCtrl.text, _cpwCtrl.text);
    if (pwError != null) {
      setState(() => _error = pwError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await ApiService().post('/auth/reset-password', data: {
        'email': _emailCtrl.text.trim(),
        'code': code,
        'new_password': _pwCtrl.text,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _step = _Step.done);
      } else {
        final d = res.data;
        setState(() => _error = (d is Map ? d['message']?.toString() : null) ??
            'We could not change your password. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _messageFrom(e, 'We could not change your password. Please try again.'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: _loading
          ? null
          : () {
              if (_step == _Step.setPassword && !_codeFromLink) {
                setState(() {
                  _step = _Step.request;
                  _error = null;
                  _notice = null;
                });
              } else {
                context.go('/login');
              }
            },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: switch (_step) {
          _Step.request => _request(),
          _Step.setPassword => _setPasswordForm(),
          _Step.done => _done(),
        },
      ),
    );
  }

  List<Widget> _messages() => [
        if (_error != null) ...[AuthNote(message: _error!), const SizedBox(height: CubagSpace.md)],
        if (_notice != null) ...[
          AuthNote(message: _notice!, success: true),
          const SizedBox(height: CubagSpace.md),
        ],
      ];

  Widget _request() {
    return Column(
      key: const ValueKey('request'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Reset your password', style: CubagType.title),
        const SizedBox(height: CubagSpace.xxs),
        const Text(
          'Enter the email on your membership and we\'ll send you an 8-digit code.',
          style: CubagType.small,
        ),
        const SizedBox(height: CubagSpace.lg),
        ..._messages(),
        const AuthFieldLabel('Email address'),
        TextFormField(
          controller: _emailCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.send,
          onFieldSubmitted: (_) => _sendCode(),
          style: CubagType.body.copyWith(color: CubagColors.ink),
          decoration: const InputDecoration(hintText: 'name@company.com'),
        ),
        const SizedBox(height: CubagSpace.xl),
        FilledButton(
          onPressed: _loading ? null : _sendCode,
          child: Text(_loading ? 'Sending…' : 'Send code'),
        ),
        const SizedBox(height: CubagSpace.sm),
        TextButton(
          onPressed: _loading ? null : () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _setPasswordForm() {
    final email = _emailCtrl.text.trim();
    return AutofillGroup(
      key: const ValueKey('set'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_codeFromLink ? 'Choose a new password' : 'Check your email', style: CubagType.title),
          const SizedBox(height: CubagSpace.xxs),
          Text(
            _codeFromLink
                ? 'For $email. Use at least 8 characters.'
                : 'If there\'s an account for $email, we\'ve emailed you a code (or a reset link). It expires in 1 hour.',
            style: CubagType.small,
          ),
          const SizedBox(height: CubagSpace.lg),
          ..._messages(),
          if (!_codeFromLink) ...[
            const AuthFieldLabel('Code'),
            TextFormField(
              controller: _codeCtrl,
              enabled: !_loading,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              autocorrect: false,
              // A pasted reset link is turned into its code straight away.
              onChanged: (v) {
                if (v.contains('token=')) {
                  final c = extractResetCode(v);
                  _codeCtrl.value = TextEditingValue(
                    text: c,
                    selection: TextSelection.collapsed(offset: c.length),
                  );
                }
              },
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _pwFocus.requestFocus(),
              style: CubagType.figure.copyWith(fontSize: 20, letterSpacing: 4),
              decoration: const InputDecoration(
                hintText: '8-digit code',
                helperText: 'Or paste the reset link from the email.',
              ),
            ),
            const SizedBox(height: CubagSpace.md),
          ],
          const AuthFieldLabel('New password'),
          PasswordField(
            controller: _pwCtrl,
            focusNode: _pwFocus,
            enabled: !_loading,
            hint: 'At least 8 characters',
            autofillHints: const [AutofillHints.newPassword],
            action: TextInputAction.next,
            onSubmitted: (_) => _cpwFocus.requestFocus(),
          ),
          const SizedBox(height: CubagSpace.md),
          const AuthFieldLabel('Confirm new password'),
          PasswordField(
            controller: _cpwCtrl,
            focusNode: _cpwFocus,
            enabled: !_loading,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _setPassword(),
          ),
          const SizedBox(height: CubagSpace.xl),
          FilledButton(
            onPressed: _loading ? null : _setPassword,
            child: Text(_loading ? 'Saving…' : 'Set new password'),
          ),
          if (!_codeFromLink) ...[
            const SizedBox(height: CubagSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No code?', style: CubagType.small),
                TextButton(
                  onPressed: _loading ? null : () => _sendCode(resend: true),
                  child: const Text('Send a new one'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _done() {
    return Column(
      key: const ValueKey('done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: CubagColors.validTint, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: CubagColors.valid, size: 30),
        ),
        const SizedBox(height: CubagSpace.lg),
        const Text('Password changed', style: CubagType.title),
        const SizedBox(height: CubagSpace.xxs),
        const Text(
          'Sign in with your new password. For your security, other devices '
          'signed in to your account have been signed out.',
          style: CubagType.body,
        ),
        const SizedBox(height: CubagSpace.xl),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
