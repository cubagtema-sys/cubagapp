import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../components/app_logo.dart';
import '../core/router.dart';
import '../services/theme_service.dart';

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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _identifierCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocusNode = FocusNode();
  bool _loading = false;
  bool _showPw = false;
  bool _rememberMe = false;
  bool _passFocused = false;
  String? _error;
  String _loginMode = 'email';

  final BiometricService _bioService = BiometricService();
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _passFocusNode.addListener(() {
      if (_passFocusNode.hasFocus && !_passFocused && mounted) {
        setState(() {
          _passFocused = true;
        });
      }
    });
    _loadSavedIdentifier();
    _checkBiometric();
  }

  Future<void> _loadSavedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('remembered_identifier');
    final savedMode = prefs.getString('remembered_mode');
    bool bioEnabled = false;
    if (!kIsWeb) {
      bioEnabled = await _bioService.isBiometricEnabled();
    }
    if (mounted) {
      setState(() {
        if (savedId != null) {
          _identifierCtrl.text = savedId;
        }
        if (savedMode != null) _loginMode = savedMode;
        if (savedId != null || bioEnabled) {
          _rememberMe = true;
        }
      });
    }
  }

  Future<void> _showServerConfigDialog() async {
    final ctrl = TextEditingController(text: ApiService.baseUrl);
    bool testing = false;
    String? testResult;
    bool? testSuccess;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: _kWhite,
          title: Row(
            children: [
              Icon(Icons.dns_rounded, color: _kBrown, size: 24),
              const SizedBox(width: 10),
              Text(
                'Server Configuration',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: _kText),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backend API Base URL:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kMuted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  style: TextStyle(color: _kText, fontSize: 14, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'https://cubag-api-server.fly.dev/api/v1',
                    filled: true,
                    fillColor: _kCream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _kOrange, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                if (testResult != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: testSuccess == true ? const Color(0xFFf0fdf4) : const Color(0xFFfef2f2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: testSuccess == true ? const Color(0xFFbbf7d0) : const Color(0xFFfecaca),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          testSuccess == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: testSuccess == true ? const Color(0xFF16a34a) : const Color(0xFFdc2626),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: TextStyle(
                              color: testSuccess == true ? const Color(0xFF15803d) : const Color(0xFFb91c1c),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.cloud_done_rounded, size: 16),
                      label: const Text('Production (Fly.io)'),
                      onPressed: () {
                        setDialogState(() {
                          ctrl.text = 'https://cubag-api-server.fly.dev/api/v1';
                          testResult = null;
                        });
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.computer_rounded, size: 16),
                      label: const Text('Localhost (127.0.0.1:5005)'),
                      onPressed: () {
                        setDialogState(() {
                          ctrl.text = 'http://127.0.0.1:5005/api/v1';
                          testResult = null;
                        });
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.wifi_rounded, size: 16),
                      label: const Text('LAN IP (192.168.4.127)'),
                      onPressed: () {
                        setDialogState(() {
                          ctrl.text = 'http://192.168.4.127:5005/api/v1';
                          testResult = null;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: testing ? null : () async {
                setDialogState(() {
                  testing = true;
                  testResult = 'Pinging server...';
                  testSuccess = null;
                });
                final ok = await ApiService.testConnection(ctrl.text.trim());
                setDialogState(() {
                  testing = false;
                  testSuccess = ok;
                  testResult = ok
                      ? 'Connected successfully! Server is responding.'
                      : 'Unable to reach server. Make sure your device is on the same Wi-Fi.';
                });
              },
              child: testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Test Connection', style: TextStyle(color: _kBrown, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                await ApiService.updateBaseUrl(ctrl.text.trim());
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (mounted) {
                  setState(() {
                    _error = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Server updated to: ${ApiService.baseUrl}'),
                      backgroundColor: const Color(0xFF16a34a),
                    ),
                  );
                }
              },
              child: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkBiometric() async {
    if (kIsWeb) return;
    final available = await _bioService.isBiometricAvailable();
    final enabled = await _bioService.isBiometricEnabled();
    final creds = await _bioService.getSavedCredentials();
    // If the user just explicitly logged out, do not auto-prompt Face ID and
    // sign them straight back in. They can still tap the biometric button.
    final suppressAuto = AuthService.suppressAutoBiometric;
    if (suppressAuto) AuthService.suppressAutoBiometric = false;
    if (mounted) {
      setState(() {
        _bioAvailable = available;
      });
      if (!suppressAuto && available && enabled && creds != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loading) {
            _handleBiometricLogin();
          }
        });
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final creds = await _bioService.getSavedCredentials();
    if (creds == null) {
      if (mounted) {
        setState(
          () => _error = 'Please sign in with your email and password once to save for Face ID / Touch ID.',
        );
      }
      return;
    }
    final authenticated = await _bioService.authenticate(
      reason: 'Scan Face ID or Touch ID to sign in to CUBAG',
    );
    if (!authenticated || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final authService = Provider.of<AuthService>(context, listen: false);
    final identifier = creds['email']!;
    final error = await authService.login(identifier, creds['password']!);

    if (error != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
      return;
    }

    if (mounted) {
      final role = authService.userRole;
      if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
        preloadAdminLibraries();
        context.go('/admin/dashboard');
      } else {
        preloadMemberLibraries();
        final status = authService.membershipStatus.toLowerCase().trim();
        final isDocApproved = status == 'active' || status == 'approved';
        final isRegFeePaid = authService.isRegistrationFeePaid;
        if (isDocApproved && isRegFeePaid) {
          context.go('/dashboard');
        } else {
          context.go('/application-documents');
        }
      }
    }
  }

  Future<void> _handleLogin() async {
    final raw = _identifierCtrl.text.trim();
    if (raw.isEmpty || _passCtrl.text.isEmpty) {
      setState(
        () => _error =
            'Please enter your ${_loginMode == 'email' ? 'email' : 'phone number'} and password.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final identifier = _loginMode == 'email' ? raw.toLowerCase() : raw;
    final password = _passCtrl.text;
    final authService = Provider.of<AuthService>(context, listen: false);

    // 1. Remember identifier if chosen
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_identifier', raw);
        await prefs.setString('remembered_mode', _loginMode);
      } else {
        await prefs.remove('remembered_identifier');
        await prefs.remove('remembered_mode');
      }
    } catch (_) {}

    // 2. Perform authentication with backend
    final error = await authService.login(identifier, password);

    // 3. Keep me signed in seamlessly handles Face ID / Touch ID enrollment
    if (error == null) {
      if (!kIsWeb && _bioAvailable) {
        try {
          if (_rememberMe) {
            await _bioService.saveCredentials(identifier, password);
            await _bioService.setBiometricEnabled(true);
            debugPrint('[Login] Seamlessly enrolled Face ID / Biometrics via Keep Me Signed In for $identifier');
          } else {
            await _bioService.setBiometricEnabled(false);
            await _bioService.clearCredentials();
            debugPrint('[Login] Deactivated biometrics as Keep Me Signed In was unchecked');
          }
        } catch (e) {
          debugPrint('[Login] Biometric setup error: $e');
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
      return;
    }

    if (mounted) {
      final role = authService.userRole;
      if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
        preloadAdminLibraries();
        context.go('/admin/dashboard');
      } else {
        preloadMemberLibraries();
        final status = authService.membershipStatus.toLowerCase().trim();
        final isDocApproved = status == 'active' || status == 'approved';
        final isRegFeePaid = authService.isRegistrationFeePaid;
        if (isDocApproved && isRegFeePaid) {
          context.go('/dashboard');
        } else {
          context.go('/application-documents');
        }
      }
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    _passFocusNode.dispose();
    super.dispose();
  }

  Widget _loginTab(String mode, IconData icon, String label, {bool isMobile = false}) {
    final isActive = _loginMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: _loading
            ? null
            : () => setState(() {
                _loginMode = mode;
                _identifierCtrl.clear();
                _error = null;
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 11),
          decoration: BoxDecoration(
            color: isActive ? _kWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive ? Border.all(color: _kBorder) : null,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(8),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isMobile ? 14 : 16, color: isActive ? _kOrange : _kMuted),
              SizedBox(width: isMobile ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: isMobile ? 13.5 : 15,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive ? _kBrown : _kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1050;
    final isTablet = size.width > 700 && size.width <= 1050;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: _isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: _kCream,
      systemNavigationBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: _kCream,
        body: isDesktop
            ? _buildThreeColumnLayout()
            : (isTablet ? _buildTwoColumnLayout() : _buildMobileLayout()),
      ),
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

  Widget _buildMobileLayout() {
    final w = MediaQuery.sizeOf(context).width;
    final isNarrow = w < 380;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 12 : 18,
            vertical: isNarrow ? 6 : 10,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 16 : 22,
                vertical: isNarrow ? 16 : 20,
              ),
              decoration: BoxDecoration(
                color: _kWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _buildForm(showLogo: true, isMobile: true),
            ),
          ),
        ),
      ),
    );
  }

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
                style: GoogleFonts.outfit(
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
                style: GoogleFonts.outfit(
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
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACCREDITED MEMBER ROLL',
                      style: GoogleFonts.outfit(
                        color: _kOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Instant verification for licensed brokers, clearing agents, and freight forwarders.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withAlpha(210),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
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
          'Member Services',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Unified portal for Ghana trade logistics and port clearance.',
          style: GoogleFonts.inter(color: _kMuted, fontSize: 14.5),
        ),
        const SizedBox(height: 32),
        _infoCard(
          icon: Icons.shield_outlined,
          title: 'Licensed Verification',
          desc:
              'Verify operational standing across Ghana ports before clearing cargo.',
        ),
        const SizedBox(height: 18),
        _infoCard(
          icon: Icons.school_outlined,
          title: 'CTI Training Institute',
          desc:
              'Access professional tariff, HS classification, and ICUMS certification cohorts.',
        ),
        const SizedBox(height: 18),
        _infoCard(
          icon: Icons.track_changes_rounded,
          title: 'Dispute & Grievance Desk',
          desc:
              'Track demurrage disputes, clearance issues, and case investigations in real time.',
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
                style: GoogleFonts.outfit(
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
              child: _buildForm(showLogo: showLogo, isMobile: false),
            ),
          ),
        ),
      );

  Widget _buildForm({required bool showLogo, bool isMobile = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showLogo) ...[
                AppLogo(
                  size: isMobile ? 42 : 56,
                  borderRadius: isMobile ? 10 : 14,
                  showShadow: true,
                ),
                SizedBox(height: isMobile ? 10 : 16),
              ],
              Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: isMobile ? 24 : 32,
                  fontWeight: FontWeight.w900,
                  color: _kText,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: isMobile ? 4 : 6),
              Text(
                'Sign in to the CUBAG Member Portal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kMuted,
                  fontSize: isMobile ? 13.5 : 16,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isMobile ? 16 : 24),

        if (_error != null) ...[
          Container(
            margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 10 : 14,
            ),
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
                    _error!,
                    style: TextStyle(
                      color: const Color(0xFFb91c1c),
                      fontSize: isMobile ? 13.5 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error!.toLowerCase().contains('reach') ||
              _error!.toLowerCase().contains('server') ||
              _error!.toLowerCase().contains('connection'))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Center(
                child: TextButton.icon(
                  onPressed: _showServerConfigDialog,
                  icon: const Icon(Icons.settings_ethernet_rounded, size: 16, color: Color(0xFFb91c1c)),
                  label: Text(
                    'Configure Server Connection (${ApiService.activeHost})',
                    style: const TextStyle(
                      color: Color(0xFFb91c1c),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
        ],

        Container(
          decoration: BoxDecoration(
            color: _kCream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _loginTab('email', Icons.email_outlined, 'Email', isMobile: isMobile),
              _loginTab('phone', Icons.phone_outlined, 'Phone', isMobile: isMobile),
            ],
          ),
        ),
        SizedBox(height: isMobile ? 14 : 20),

        _inputLabel(_loginMode == 'email' ? 'Email Address' : 'Phone Number', isMobile: isMobile),
        SizedBox(height: isMobile ? 4 : 6),
        TextFormField(
          enabled: !_loading,
          controller: _identifierCtrl,
          style: TextStyle(
            color: _kText,
            fontSize: isMobile ? 14.5 : 16,
            fontWeight: FontWeight.w600,
          ),
          keyboardType: _loginMode == 'email'
              ? TextInputType.emailAddress
              : TextInputType.phone,
          inputFormatters: _loginMode == 'phone'
              ? [FilteringTextInputFormatter.deny(RegExp(r'[a-zA-Z]'))]
              : null,
          decoration: _inputDecoration(
            hint: _loginMode == 'email' ? 'name@agency.com' : '024 000 0000',
            icon: _loginMode == 'email'
                ? Icons.mail_outline
                : Icons.phone_android_outlined,
            isMobile: isMobile,
          ),
        ),
        SizedBox(height: isMobile ? 10 : 16),

        _inputLabel('Password', isMobile: isMobile),
        SizedBox(height: isMobile ? 4 : 6),
        TextFormField(
          enabled: !_loading,
          controller: _passCtrl,
          focusNode: _passFocusNode,
          obscureText: !_showPw && _passFocused,
          style: TextStyle(
            color: _kText,
            fontSize: isMobile ? 14.5 : 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: _inputDecoration(
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            isMobile: isMobile,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_bioAvailable && !kIsWeb)
                  IconButton(
                    tooltip: defaultTargetPlatform == TargetPlatform.iOS
                        ? 'Sign in with Face ID'
                        : 'Sign in with Biometrics',
                    icon: Icon(
                      defaultTargetPlatform == TargetPlatform.iOS
                          ? Icons.face_rounded
                          : Icons.fingerprint_rounded,
                      color: _kBrown,
                      size: isMobile ? 20 : 22,
                    ),
                    onPressed: _loading ? null : _handleBiometricLogin,
                  ),
                IconButton(
                  icon: Icon(
                    _showPw
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _kMuted,
                    size: isMobile ? 19 : 20,
                  ),
                  onPressed: _loading
                      ? null
                      : () => setState(() => _showPw = !_showPw),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: isMobile ? 8 : 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: _kOrange,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      onChanged: !_loading
                          ? (v) => setState(() => _rememberMe = v ?? false)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: !_loading
                          ? () => setState(() => _rememberMe = !_rememberMe)
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Keep me signed in',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isMobile ? 12.5 : 14.5,
                                fontWeight: FontWeight.w600,
                                color: _loading ? _kMuted : _kText,
                              ),
                            ),
                          ),
                          if (_bioAvailable && !kIsWeb) ...[
                            const SizedBox(width: 4),
                            Icon(
                              defaultTargetPlatform == TargetPlatform.iOS
                                  ? Icons.face_rounded
                                  : Icons.fingerprint_rounded,
                              size: 14,
                              color: _rememberMe ? _kOrange : _kMuted,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _loading ? null : () => context.go('/forgot-password'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot?',
                style: TextStyle(
                  color: _kBrown,
                  fontSize: isMobile ? 12.5 : 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 24),

        SizedBox(
          width: double.infinity,
          height: isMobile ? 48 : 54,
          child: ElevatedButton(
            onPressed: _loading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _loading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Signing in...',
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Sign In to Account',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),

        if (_loading) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Signing in, please wait...',
              style: TextStyle(color: _kMuted, fontSize: 13.5),
            ),
          ),
        ],

        SizedBox(height: isMobile ? 14 : 22),

        Center(
          child: GestureDetector(
            onTap: () => context.go('/register'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "New to CUBAG? ",
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: 'Create an Account',
                      style: TextStyle(
                        color: _kOrange,
                        fontWeight: FontWeight.w800,
                        fontSize: isMobile ? 14 : 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputLabel(String text, {bool isMobile = false}) => Text(
    text,
    style: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: isMobile ? 13 : 15,
      color: _kText,
    ),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
    bool isMobile = false,
  }) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: _kBrown, size: isMobile ? 18 : 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: _kWhite,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _kBorder, width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _kOrange, width: 1.8),
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: isMobile ? 11 : 16,
    ),
    hintStyle: TextStyle(
      color: _kMuted.withAlpha(180),
      fontSize: isMobile ? 13.5 : 15,
    ),
  );
}
