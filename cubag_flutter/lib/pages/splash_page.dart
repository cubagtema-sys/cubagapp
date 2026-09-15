import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/session_storage.dart';
import '../services/auth_service.dart';

/// Professional Animated Quad-Split Splash Screen for CUBAG.
/// Features a high-end 4-piece geometric convergence animation where the
/// 4 quadrants of the CUBAG emblem fly in from diagonal space, fuse seamlessly
/// with a radiant golden pulse, and reveal luxury typography and motto.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _navigated = false;

  // Quadrant Transformations (0.0 -> 0.55)
  late Animation<Offset> _tlOffset;
  late Animation<Offset> _trOffset;
  late Animation<Offset> _blOffset;
  late Animation<Offset> _brOffset;

  late Animation<double> _tlRotate;
  late Animation<double> _trRotate;
  late Animation<double> _blRotate;
  late Animation<double> _brRotate;

  late Animation<double> _quadrantScale;
  late Animation<double> _quadrantOpacity;

  // Fusion Shockwave & Pulse (0.50 -> 0.80)
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;
  late Animation<double> _sheenProgress;

  // Text & UI Reveal (0.55 -> 0.95)
  late Animation<double> _titleOpacity;
  late Animation<double> _titleSpacing;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _subtitleOpacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/logo.jpeg'), context);
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // ── 1. Quadrant Convergence (0.0 -> 0.55) ───────────────────────────────
    final quadCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );

    _tlOffset = Tween<Offset>(
      begin: const Offset(-220, -220),
      end: Offset.zero,
    ).animate(quadCurve);

    _trOffset = Tween<Offset>(
      begin: const Offset(220, -220),
      end: Offset.zero,
    ).animate(quadCurve);

    _blOffset = Tween<Offset>(
      begin: const Offset(-220, 220),
      end: Offset.zero,
    ).animate(quadCurve);

    _brOffset = Tween<Offset>(
      begin: const Offset(220, 220),
      end: Offset.zero,
    ).animate(quadCurve);

    _tlRotate = Tween<double>(begin: -0.45, end: 0.0).animate(quadCurve);
    _trRotate = Tween<double>(begin: 0.45, end: 0.0).animate(quadCurve);
    _blRotate = Tween<double>(begin: 0.45, end: 0.0).animate(quadCurve);
    _brRotate = Tween<double>(begin: -0.45, end: 0.0).animate(quadCurve);

    _quadrantScale = Tween<double>(begin: 0.4, end: 1.0).animate(quadCurve);
    _quadrantOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );

    // ── 2. Fusion & Pulse Shockwave (0.50 -> 0.80) ──────────────────────────
    _pulseScale = Tween<double>(begin: 0.6, end: 2.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.50, 0.80, curve: Curves.easeOutQuart),
      ),
    );

    _pulseOpacity = Tween<double>(begin: 0.85, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.50, 0.80, curve: Curves.easeOut),
      ),
    );

    _sheenProgress = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.85, curve: Curves.easeInOut),
      ),
    );

    // ── 3. Typography & Subtitle (0.55 -> 0.95) ────────────────────────────
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.75, curve: Curves.easeIn),
      ),
    );

    _titleSpacing = Tween<double>(begin: 14.0, end: 6.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.88, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.92, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.90, curve: Curves.easeIn),
      ),
    );

    // Start animation and navigate upon completion
    _controller.forward().then((_) => _navigateNext());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    final token = SessionStorage.instance.getStringSync('cubag_token');
    final auth = AuthService();
    final bool loggedIn = (token != null && token.isNotEmpty) || auth.isAuthenticated;

    if (loggedIn) {
      final role = SessionStorage.instance.getStringSync('cubag_role') ?? auth.userRole;
      if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
        if (!kIsWeb) {
          context.go('/admin-unavailable');
        } else {
          context.go('/admin/dashboard');
        }
        return;
      }
      final status = (SessionStorage.instance.getStringSync('cubag_member_status') ??
              SessionStorage.instance.getStringSync('cubag_status') ??
              auth.membershipStatus)
          .toLowerCase()
          .trim();
      final regPaidStr = SessionStorage.instance.getStringSync('cubag_registration_fee_paid');
      final bool isRegFeePaid = regPaidStr == 'true' || auth.isRegistrationFeePaid;
      final bool isDocApproved = status == 'active' || status == 'approved';
      if (isDocApproved && isRegFeePaid) {
        context.go('/dashboard');
        return;
      } else {
        context.go('/application-documents');
        return;
      }
    }

    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    const double totalSize = 140.0;
    const double halfSize = totalSize / 2;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0F0A),
      body: GestureDetector(
        onTap: _navigateNext,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // ── Fast Skip Button ──────────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              right: 20,
              child: GestureDetector(
                onTap: _navigateNext,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          // ── Background Architectural Luxury Grid ──────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _LuxuryGridPainter(),
            ),
          ),

          // ── Radial Ambient Core Glow ──────────────────────────────────────
          Center(
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF5000).withAlpha(45),
                    const Color(0xFF6B3E26).withAlpha(25),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Main Animated Convergence Scene ───────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 1. The 4 Quadrants Emblem ──
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Shockwave Fusion Pulse Ring
                        if (_controller.value > 0.48)
                          Transform.scale(
                            scale: _pulseScale.value,
                            child: Opacity(
                              opacity: _pulseOpacity.value.clamp(0.0, 1.0),
                              child: Container(
                                width: totalSize + 24,
                                height: totalSize + 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFF5000),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF5000)
                                          .withAlpha(140),
                                      blurRadius: 28,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Logo Container / Quadrant Assembly
                        Container(
                          width: totalSize,
                          height: totalSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(180),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: const Color(0xFFFF5000).withAlpha(
                                  (_controller.value * 70).toInt(),
                                ),
                                blurRadius: 40,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Stack(
                              children: [
                                // Top-Left Quadrant
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  width: halfSize,
                                  height: halfSize,
                                  child: _buildQuadrant(
                                    offset: _tlOffset.value,
                                    rotation: _tlRotate.value,
                                    alignment: Alignment.topLeft,
                                    totalSize: totalSize,
                                    halfSize: halfSize,
                                  ),
                                ),

                                // Top-Right Quadrant
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  width: halfSize,
                                  height: halfSize,
                                  child: _buildQuadrant(
                                    offset: _trOffset.value,
                                    rotation: _trRotate.value,
                                    alignment: Alignment.topRight,
                                    totalSize: totalSize,
                                    halfSize: halfSize,
                                  ),
                                ),

                                // Bottom-Left Quadrant
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  width: halfSize,
                                  height: halfSize,
                                  child: _buildQuadrant(
                                    offset: _blOffset.value,
                                    rotation: _blRotate.value,
                                    alignment: Alignment.bottomLeft,
                                    totalSize: totalSize,
                                    halfSize: halfSize,
                                  ),
                                ),

                                // Bottom-Right Quadrant
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  width: halfSize,
                                  height: halfSize,
                                  child: _buildQuadrant(
                                    offset: _brOffset.value,
                                    rotation: _brRotate.value,
                                    alignment: Alignment.bottomRight,
                                    totalSize: totalSize,
                                    halfSize: halfSize,
                                  ),
                                ),

                                // Golden Light Sheen Pass
                                if (_controller.value > 0.52)
                                  Positioned.fill(
                                    child: Transform.rotate(
                                      angle: 0.4,
                                      child: Transform.translate(
                                        offset: Offset(
                                          _sheenProgress.value * totalSize,
                                          0,
                                        ),
                                        child: Container(
                                          width: 30,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Colors.white.withAlpha(90),
                                                const Color(0xFFFF5000)
                                                    .withAlpha(120),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // ── 2. CUBAG Brand Title ──
                    Opacity(
                      opacity: _titleOpacity.value.clamp(0.0, 1.0),
                      child: Text(
                        'C U B A G',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: _titleSpacing.value,
                          color: const Color(0xFFFFFFFF),
                          shadows: [
                            Shadow(
                              color: const Color(0xFFFF5000).withAlpha(120),
                              blurRadius: 18,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── 3. Subtitle & Ghana Badge ──
                    SlideTransition(
                      position: _subtitleSlide,
                      child: Opacity(
                        opacity: _subtitleOpacity.value.clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A0F0A),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      const Color(0xFFFF5000).withAlpha(60),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shield_rounded,
                                    color: Color(0xFFFF5000),
                                    size: 13,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'CUSTOMS BROKERS ASSOCIATION OF GHANA',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: const Color(0xFFE8DED6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Advancing Customs Excellence • Facilitating Global Trade',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF9E8E84),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Bottom Progress Indicator & Version ───────────────────────────
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SizedBox(
                  width: 90,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 2.5,
                      backgroundColor: const Color(0xFF281710),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF5000),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'CUBAG PORTAL',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: const Color(0xFF5E4E44),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildQuadrant({
    required Offset offset,
    required double rotation,
    required Alignment alignment,
    required double totalSize,
    required double halfSize,
  }) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: _quadrantScale.value,
          child: Opacity(
            opacity: _quadrantOpacity.value.clamp(0.0, 1.0),
            child: ClipRect(
              child: OverflowBox(
                alignment: alignment,
                minWidth: totalSize,
                maxWidth: totalSize,
                minHeight: totalSize,
                maxHeight: totalSize,
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  width: totalSize,
                  height: totalSize,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    width: totalSize,
                    height: totalSize,
                    color: const Color(0xFFFF5000),
                    alignment: Alignment.center,
                    child: const Text(
                      'C',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 50,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle luxury background architectural grid lines
class _LuxuryGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF5000).withAlpha(12)
      ..strokeWidth = 0.6;

    const double step = 44.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
