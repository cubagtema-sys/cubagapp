import 'dart:async' show unawaited;
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
import '../services/push_notification_service.dart';
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

    // Prompt push notifications permission and sync FCM device token
    unawaited(PushNotificationService().requestPermissionsAndSyncToken());

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

    // Prompt push notifications permission and sync FCM device token
    unawaited(PushNotificationService().requestPermissionsAndSyncToken());

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
        body: _buildLoginFormOnlyLayout(),
      ),
    );
  }

  Widget _buildLoginFormOnlyLayout() {
    final w = MediaQuery.sizeOf(context).width;
    final isNarrow = w < 380;
    final isMobile = w < 600;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 12 : 18,
            vertical: isNarrow ? 8 : 16,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 16 : (isMobile ? 22 : 30),
                vertical: isNarrow ? 16 : (isMobile ? 22 : 30),
              ),
              decoration: BoxDecoration(
                color: _kWhite,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildForm(showLogo: true, isMobile: isMobile),
            ),
          ),
        ),
      ),
    );
  }





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
                    icon: defaultTargetPlatform == TargetPlatform.iOS
                        ? FaceIdIcon(
                            size: isMobile ? 20 : 22,
                            color: _kBrown,
                          )
                        : Icon(
                            Icons.fingerprint_rounded,
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

/// Authentic Apple Face ID Vector Icon
class FaceIdIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FaceIdIcon({
    super.key,
    this.size = 22,
    this.color = const Color(0xFF6B3E26),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FaceIdPainter(color: color),
      ),
    );
  }
}

class _FaceIdPainter extends CustomPainter {
  final Color color;

  _FaceIdPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = (w * 0.08).clamp(1.5, 2.4);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cornerLen = w * 0.24;
    final r = w * 0.12;

    // 1. Top-Left Corner
    final tl = Path()
      ..moveTo(0, cornerLen)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(cornerLen, 0);
    canvas.drawPath(tl, paint);

    // 2. Top-Right Corner
    final tr = Path()
      ..moveTo(w - cornerLen, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, cornerLen);
    canvas.drawPath(tr, paint);

    // 3. Bottom-Left Corner
    final bl = Path()
      ..moveTo(0, h - cornerLen)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..lineTo(cornerLen, h);
    canvas.drawPath(bl, paint);

    // 4. Bottom-Right Corner
    final br = Path()
      ..moveTo(w - cornerLen, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, h - cornerLen);
    canvas.drawPath(br, paint);

    // 5. Left Eye
    canvas.drawLine(
      Offset(w * 0.35, h * 0.34),
      Offset(w * 0.35, h * 0.44),
      paint,
    );

    // 6. Right Eye
    canvas.drawLine(
      Offset(w * 0.65, h * 0.34),
      Offset(w * 0.65, h * 0.44),
      paint,
    );

    // 7. Nose
    final nose = Path()
      ..moveTo(w * 0.50, h * 0.40)
      ..lineTo(w * 0.50, h * 0.57)
      ..lineTo(w * 0.58, h * 0.57);
    canvas.drawPath(nose, paint);

    // 8. Smile
    final smile = Path()
      ..moveTo(w * 0.33, h * 0.69)
      ..quadraticBezierTo(w * 0.50, h * 0.81, w * 0.67, h * 0.69);
    canvas.drawPath(smile, paint);
  }

  @override
  bool shouldRepaint(covariant _FaceIdPainter oldDelegate) =>
      oldDelegate.color != color;
}
