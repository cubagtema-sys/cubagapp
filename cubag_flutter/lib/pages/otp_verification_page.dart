import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../components/app_logo.dart';
import '../utils/app_logger.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kDarkBrown = Color(0xFF3E2418); // Deep Dark Contrast
const _kCream = Color(0xFFF8F4F0); // Light Background Cream
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = Color(0xFF2B211D); // Deep Body Text
const _kMuted = Color(0xFF6F625B); // Secondary Muted Text
const _kBorder = Color(0xFFE8DED6); // Soft Warm Border

class OTPVerificationPage extends StatefulWidget {
  final String? email;
  const OTPVerificationPage({super.key, this.email});
  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _ctrls = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;
  String _error = '';
  int _countdown = 60;
  bool _canResend = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _countdown = 60;
    _canResend = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _ctrls.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final cleanEmail = (widget.email ?? '').trim().toLowerCase();
      final res = await ApiService().post(
        '/auth/verify-otp',
        data: {'email': cleanEmail, 'otp': code},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        context.go('/dashboard');
      } else {
        setState(
          () => _error = res.data['message'] ?? 'Invalid or expired code',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Connection error. Please try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ApiService().post(
        '/auth/resend-otp',
        data: {'email': (widget.email ?? '').trim().toLowerCase()},
      );
    } catch (e, st) {
      AppLogger.error('otp_verification_page', e, st);
    }
    if (!mounted) return;
    for (final c in _ctrls) {
      c.clear();
    }
    _nodes[0].requestFocus();
    _startTimer();
    setState(() => _resending = false);
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
                Icons.lock_person_outlined,
                'Secure Two-Factor Authentication',
              ),
              const SizedBox(height: 20),
              _sidebarFeature(
                Icons.mark_email_read_outlined,
                'Verification Code via Email',
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
              'Verify Your Email',
              style: GoogleFonts.outfit(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _kText,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'We sent a 6-digit code to:\n${widget.email ?? "your registered email"}',
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

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            6,
            (i) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _ctrls[i],
                  focusNode: _nodes[i],
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _kText,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _kWhite,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _kBorder, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kOrange, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
                    if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _verify,
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
                    'Verify & Activate',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: _canResend
              ? TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending...' : 'Resend Code',
                    style: const TextStyle(
                      color: _kOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                )
              : Text(
                  'Resend code in $_countdown s',
                  style: TextStyle(color: _kMuted, fontSize: 16),
                ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => context.go('/register'),
            child: const Text(
              'Wrong email? Go Back',
              style: TextStyle(
                color: _kBrown,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
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
