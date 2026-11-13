import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../utils/session_storage.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../components/app_logo.dart';
import '../design/cubag_design.dart';

/// Opening screen (mobile and web): the association's seal, name and motto
/// on cocoa, one short fade-in, then on to sign in / home. Matches the
/// signed-out screens so the hand-over is seamless.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;
  bool _navigated = false;
  bool _needsManualUnlock = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/logo.jpeg'), context);
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      FlutterNativeSplash.remove();
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(curve);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Web: index.html already shows this same splash while the app
      // downloads, so start fully visible (no blink) and hold briefly.
      if (kIsWeb) {
        _controller.value = 1;
        Future.delayed(const Duration(milliseconds: 1200), _navigateNext);
        return;
      }
      // Respect "reduce motion": no animation, just a short pause.
      if (MediaQuery.of(context).disableAnimations) {
        _controller.value = 1;
        Future.delayed(const Duration(milliseconds: 400), _navigateNext);
      } else {
        _controller.forward().then((_) => _navigateNext());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    final auth = AuthService();
    await auth.ensureInitialized();
    if (!mounted) return;

    final token = SessionStorage.instance.getStringSync('cubag_token');
    final bool loggedIn = (token != null && token.isNotEmpty) || auth.isAuthenticated;

    // Design preview (debug builds only, compiled out of release): sign in
    // with a demo account and/or open a given screen, so screens can be
    // reviewed on a simulator without typing. Set with --dart-define.
    if (!kReleaseMode) {
      const demoEmail = String.fromEnvironment('DESIGN_LOGIN_EMAIL');
      const startRoute = String.fromEnvironment('DESIGN_START_ROUTE');
      if (demoEmail.isNotEmpty) { // fresh session: a stale preview token would 401
        final err = await auth.login(
          demoEmail,
          const String.fromEnvironment('DESIGN_LOGIN_PASSWORD'),
        );
        debugPrint('[DesignPreview] demo sign-in: ${err ?? 'ok'}');
        if (!mounted) return;
        if (err == null && startRoute.isEmpty) {
          _proceedAfterLogin(auth);
          return;
        }
      }
      if (startRoute.isNotEmpty) {
        // A comma-separated list tours the screens, 10 s each.
        final routes = startRoute.split(',');
        final router = GoRouter.of(context);
        router.go(routes.first);
        for (final r in routes.skip(1)) {
          await Future<void>.delayed(const Duration(seconds: 10));
          debugPrint('[DesignPreview] tour -> $r');
          router.go(r);
        }
        return;
      }
    }

    if (loggedIn) {
      if (!kIsWeb) {
        final bioService = BiometricService();
        final bioEnabled = await bioService.isBiometricEnabled();
        if (bioEnabled) {
          final passed = await bioService.authenticate(
            reason: 'Scan Face ID or Touch ID to unlock CUBAG',
          );
          if (!passed) {
            _navigated = false;
            if (mounted) {
              setState(() => _needsManualUnlock = true);
            }
            return;
          }
        }
      }
      _proceedAfterLogin(auth);
      return;
    }

    context.go('/login');
  }

  void _proceedAfterLogin(AuthService auth) {
    final role = SessionStorage.instance.getStringSync('cubag_role') ?? auth.userRole;
    if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
      if (!kIsWeb && !(!kReleaseMode && const bool.fromEnvironment('DESIGN_ADMIN_PREVIEW'))) {
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
    } else {
      context.go('/application-documents');
    }
  }

  void _onSkip() {
    if (!mounted) return;
    _controller.stop();
    _navigated = true;

    final token = SessionStorage.instance.getStringSync('cubag_token');
    final auth = AuthService();
    final bool loggedIn = (token != null && token.isNotEmpty) || auth.isAuthenticated;

    if (loggedIn) {
      _proceedAfterLogin(auth);
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubagColors.cocoa,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _needsManualUnlock ? null : _onSkip,
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: CubagSpace.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: CubagColors.paper,
                          ),
                          padding: const EdgeInsets.all(5),
                          child: const AppLogo(size: 112, borderRadius: 56, showShadow: false),
                        ),
                        const SizedBox(height: CubagSpace.xl),
                        Text(
                          'Customs Brokers\nAssociation of Ghana',
                          semanticsLabel: 'Customs Brokers Association of Ghana',
                          textAlign: TextAlign.center,
                          style: CubagType.display.copyWith(color: CubagColors.onCocoa),
                        ),
                        const SizedBox(height: CubagSpace.xs),
                        Text(
                          'Honesty and Efficiency',
                          textAlign: TextAlign.center,
                          style: CubagType.body.copyWith(color: CubagColors.onCocoaMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_needsManualUnlock)
              Positioned(
                left: CubagSpace.lg,
                right: CubagSpace.lg,
                bottom: MediaQuery.paddingOf(context).bottom + CubagSpace.xxl,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            _navigated = false;
                            _navigateNext();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: CubagColors.paper,
                            foregroundColor: CubagColors.cocoa,
                          ),
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Unlock with Face ID'),
                        ),
                        const SizedBox(height: CubagSpace.xs),
                        TextButton(
                          onPressed: () async {
                            await AuthService().logout();
                            if (context.mounted) context.go('/login');
                          },
                          style: TextButton.styleFrom(foregroundColor: CubagColors.onCocoa),
                          child: const Text('Sign in with another account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
