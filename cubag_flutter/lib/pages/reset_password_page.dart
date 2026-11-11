import 'package:flutter/material.dart';

import 'forgot_password_page.dart';

/// Opened from the link in the reset email (/reset-password?token=&email=).
/// Same flow and design as Forgot password, starting at "Choose a new
/// password" with the emailed code already filled in.
class ResetPasswordPage extends StatelessWidget {
  final String? email;
  final String? token;
  const ResetPasswordPage({super.key, this.email, this.token});

  @override
  Widget build(BuildContext context) {
    return ForgotPasswordPage(initialEmail: email, initialCode: token);
  }
}
