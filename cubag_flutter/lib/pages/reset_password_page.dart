import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../components/app_logo.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kDarkBrown = Color(0xFF3E2418); // Deep Dark Contrast
const _kCream = Color(0xFFF8F4F0); // Light Background Cream
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = Color(0xFF2B211D); // Deep Body Text
const _kMuted = Color(0xFF6F625B); // Secondary Muted Text
const _kBorder = Color(0xFFE8DED6); // Soft Warm Border

class ResetPasswordPage extends StatefulWidget {
  final String? email;
  final String? token;
  const ResetPasswordPage({super.key, this.email, this.token});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _pwCtrl = TextEditingController();
  final _cpwCtrl = TextEditingController();
  bool _loading = false;
  bool _success = false;
  bool _showPw = false;
  bool _showCpw = false;
  String _error = '';

  Future<void> _reset() async {
    if (_pwCtrl.text != _cpwCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (_pwCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiService().post(
        '/auth/reset-password',
        data: {
          'email': widget.email ?? '',
          'code': widget.token ?? '',
          'new_password': _pwCtrl.text,
        },
      );
      if (res.statusCode == 200) {
        setState(() => _success = true);
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) context.go('/login');
      } else {
        setState(
          () => _error = res.data['message'] ?? 'Failed to reset password.',
        );
      }
    } catch (_) {
      setState(() => _error = 'Connection error. Please try again later.');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: _kCream,
      body: isWide ? _buildWideLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildWideLayout() => Row(
    children: [
      Expanded(flex: 4, child: _buildSidebar()),
      Expanded(flex: 6, child: _buildFormPanel()),
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
            child: _buildFormContent(isMobile: true),
          ),
        ),
      ),
    ),
  );

  Widget _buildSidebar() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_kBrown, _kDarkBrown],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 60, borderRadius: 14),
              const SizedBox(height: 24),
              Text(
                'CUBAG',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enterprise Mobility Platform',
                style: GoogleFonts.outfit(
                  color: Colors.white.withAlpha(220),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 48),
              _sidebarFeature(
                Icons.lock_reset_outlined,
                'Password Reset Service',
              ),
              const SizedBox(height: 20),
              _sidebarFeature(
                Icons.security_outlined,
                'Secure Data Transmission',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sidebarFeature(IconData icon, String label) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _kOrange.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _kOrange, size: 20),
      ),
      const SizedBox(width: 14),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ],
  );

  Widget _buildFormPanel() => Container(
    color: _kWhite,
    child: Center(
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(48),
          constraints: const BoxConstraints(maxWidth: 480),
          child: _buildFormContent(isMobile: false),
        ),
      ),
    ),
  );

  Widget _buildFormContent({bool isMobile = false}) {
    if (widget.email == null || widget.token == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 56, borderRadius: 12, showShadow: true),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0x19ef4444),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Color(0xFFef4444),
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Invalid Link',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _kText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The password reset link is invalid or missing required parameters.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kMuted, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/forgot-password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Request New Link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, size: 18, color: _kBrown),
            label: const Text(
              'Return to CUBAG Homepage',
              style: TextStyle(
                color: _kBrown,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      );
    }

    if (_success) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 56, borderRadius: 12, showShadow: true),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0x1910b981),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF10b981),
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Password Reset',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _kText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your password has been updated successfully. Redirecting to login...',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kMuted, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Back to Login',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 18,
                color: _kBrown,
              ),
              label: const Text(
                'Back to Sign In',
                style: TextStyle(
                  color: _kBrown,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined, size: 16, color: _kOrange),
              label: const Text(
                'Home',
                style: TextStyle(
                  color: _kOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              const AppLogo(size: 56, borderRadius: 12, showShadow: true),
              const SizedBox(height: 16),
            ],
            Text(
              'Set New Password',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _kText,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a new, secure password for your account.',
              style: TextStyle(color: _kMuted, fontSize: 16, height: 1.3),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (_error.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
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
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error,
                    style: const TextStyle(
                      color: Color(0xFFb91c1c),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text(
          'New Password',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: _kText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pwCtrl,
          obscureText: !_showPw,
          style: TextStyle(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Enter new password',
            filled: true,
            fillColor: _kWhite,
            prefixIcon: Icon(Icons.lock_outline, color: _kBrown, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _showPw
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _kMuted,
                size: 20,
              ),
              onPressed: () => setState(() => _showPw = !_showPw),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kBorder, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kOrange, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Confirm Password',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: _kText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cpwCtrl,
          obscureText: !_showCpw,
          style: TextStyle(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Confirm new password',
            filled: true,
            fillColor: _kWhite,
            prefixIcon: Icon(Icons.lock_outline, color: _kBrown, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _showCpw
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _kMuted,
                size: 20,
              ),
              onPressed: () => setState(() => _showCpw = !_showCpw),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kBorder, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kOrange, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Update Password',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: _kBrown,
            ),
            label: const Text(
              'Back to Sign In',
              style: TextStyle(
                color: _kBrown,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, size: 18, color: _kBrown),
            label: const Text(
              'Return to CUBAG Homepage',
              style: TextStyle(
                color: _kBrown,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
