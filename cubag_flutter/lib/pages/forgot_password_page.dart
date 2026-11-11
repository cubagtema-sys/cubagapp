import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../components/app_logo.dart';
import '../utils/app_colors.dart';

// Balanced CUBAG Dynamic Palette
bool get _isDark => ThemeService.instance.isDark;
Color get _kBrown => const Color(0xFF6B3E26); // Primary Brown
Color get _kOrange => const Color(0xFFFF5000); // Primary Orange CTA
Color get _kCream => _isDark
    ? const Color(0xFF281710)
    : const Color(0xFFF8F4F0); // Warm Velvet Chocolate / Light Cream
Color get _kWhite => _isDark
    ? const Color(0xFF1A0F0A)
    : const Color(0xFFFFFFFF); // Chocolate Card / White Surfaces
Color get _kText => _isDark
    ? const Color(0xFFFFF8F3)
    : const Color(0xFF2B211D); // Warm Ivory / Deep Body Text
Color get _kMuted => _isDark
    ? const Color(0xFFC8ADA0)
    : const Color(0xFF6F625B); // Cocoa Tan / Muted Text
Color get _kBorder => _isDark
    ? const Color(0xFF4D2D20)
    : const Color(0xFFE8DED6); // Bronze / Warm Border

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String _error = '';

  Future<void> _submit() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiService().post(
        '/auth/forgot-password',
        data: {'email': _emailCtrl.text.trim()},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _sent = true);
      } else {
        setState(
          () => _error =
              res.data['message'] ??
              "We couldn't find an account with that email.",
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Connection failed. Please check your network.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1050;
    final isTablet = size.width > 700 && size.width <= 1050;

    return Scaffold(
      backgroundColor: _kCream,
      body: isDesktop
          ? _buildThreeColumnLayout()
          : (isTablet ? _buildTwoColumnLayout() : _buildMobileLayout()),
    );
  }

  Widget _buildThreeColumnLayout() => Row(
    children: [
      Expanded(flex: 35, child: _buildBrandPanel()),
      Expanded(flex: 35, child: _buildInfoPanel()),
      Expanded(flex: 30, child: _buildFormPanel(padding: 40, showLogo: false)),
    ],
  );

  Widget _buildTwoColumnLayout() => Row(
    children: [
      Expanded(flex: 45, child: _buildBrandPanel()),
      Expanded(flex: 55, child: _buildFormPanel(padding: 50, showLogo: false)),
    ],
  );

  Widget _buildMobileLayout() => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _kWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(6),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildFormContent(showLogo: true),
          ),
        ),
      ),
    ),
  );

  Widget _buildBrandPanel() => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF1E140F),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2B1B14),
          Color(0xFF160D09),
        ],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -30,
          bottom: -30,
          child: Icon(
            Icons.directions_boat_rounded,
            size: 260,
            color: Colors.white.withAlpha(8),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 48, borderRadius: 12),
              const SizedBox(height: 28),
              Text(
                'CUBAG',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 3,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Customs Brokers Association of Ghana',
                style: GoogleFonts.inter(
                  color: const Color(0xFFF8F4F0),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Connecting customs clearance, freight forwarding, and international trade professionals across Ghana.',
                style: GoogleFonts.inter(
                  color: const Color(0xFFC8ADA0),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildInfoPanel() => Container(
    decoration: BoxDecoration(
      color: _kCream,
      border: Border(right: BorderSide(color: _kBorder, width: 1)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Security Center',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ensure your member account remains secure and authorized.',
          style: GoogleFonts.inter(color: _kMuted, fontSize: 14.5),
        ),
        const SizedBox(height: 32),
        _infoCard(
          icon: Icons.verified_user_outlined,
          title: 'Authorized Retrieval',
          desc:
              'Password recovery is restricted to verified member accounts with registered credentials.',
        ),
        const SizedBox(height: 18),
        _infoCard(
          icon: Icons.lock_reset_outlined,
          title: 'Secure Reset Links',
          desc:
              'We use temporary, encrypted single-use tokens sent to your inbox to protect against unauthorized access.',
        ),
        const SizedBox(height: 18),
        _infoCard(
          icon: Icons.contact_support_outlined,
          title: 'Need Assistance?',
          desc:
              'If you no longer have access to your registered contact info, please contact the CUBAG Secretariat.',
        ),
      ],
    ),
  );

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String desc,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _kWhite,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kBrown.withAlpha(18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _kBrown, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: GoogleFonts.inter(
                  color: _kMuted,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildFormPanel({double padding = 60, required bool showLogo}) =>
      Container(
        color: _kWhite,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _buildFormContent(showLogo: showLogo),
            ),
          ),
        ),
      );

  Widget _buildFormContent({required bool showLogo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showLogo) ...[
                const AppLogo(size: 60, borderRadius: 14, showShadow: true),
                const SizedBox(height: 20),
              ],
              Text(
                'Reset Password',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _kText,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Enter your email and we'll send you a link to reset your password.",
                textAlign: TextAlign.center,
                style: TextStyle(color: _kMuted, fontSize: 17, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        if (_sent) ...[
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mark_email_read_outlined,
                    color: _kBrown,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your Inbox',
                  style: GoogleFonts.inter(
                    color: _kText,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'If an account exists for ${_emailCtrl.text.trim()}, you will receive a password reset link shortly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _kMuted, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          if (_error.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFfef2f2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFfee2e2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFef4444),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(
                        color: Color(0xFFb91c1c),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          _inputLabel('Recovery Email'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
              color: _kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(
              hint: 'name@agency.com',
              icon: Icons.mail_outline,
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Send Reset Link',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),

          Center(
            child: GestureDetector(
              onTap: () => context.go('/login'),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "Remember your password? ",
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: 'Sign In',
                      style: TextStyle(
                        color: AppColors.accentOrangeText,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _inputLabel(String text) => Text(
    text,
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _kText),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: _kBrown, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: _kWhite,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _kBorder, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _kOrange, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    hintStyle: TextStyle(color: _kMuted.withAlpha(180)),
  );
}
