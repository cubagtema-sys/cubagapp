import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../components/app_logo.dart';
import '../core/router.dart';
import '../services/theme_service.dart';

// Balanced CUBAG Dynamic Palette
bool get _isDark => ThemeService.instance.isDark;
Color get _kBrown => const Color(0xFF6B3E26); // Primary Brown
Color get _kOrange => const Color(0xFFFF5000); // Primary Orange CTA
Color get _kDarkBrown => const Color(0xFF3E2418); // Deep Dark Contrast
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
  bool _bioEnabled = false;

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
    if (savedId != null && mounted) {
      setState(() {
        _identifierCtrl.text = savedId;
        _rememberMe = true;
        if (savedMode != null) _loginMode = savedMode;
      });
    }
  }

  Future<void> _checkBiometric() async {
    if (kIsWeb) return;
    final available = await _bioService.isBiometricAvailable();
    final enabled = await _bioService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
      if (available && enabled) {
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
      setState(
        () => _error = 'No saved credentials. Please sign in manually first.',
      );
      return;
    }
    final authenticated = await _bioService.authenticate();
    if (!authenticated || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final authService = Provider.of<AuthService>(context, listen: false);
    final identifier = creds['email']!;
    final error = await authService.login(identifier, creds['password']!);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }

    final role = authService.userRole;
    context.go(
      (role == 'admin' || role == 'sub_admin' || role == 'super_admin')
          ? '/admin/dashboard'
          : '/dashboard',
    );
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final error = await authService.login(identifier, _passCtrl.text);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_identifier', raw);
      await prefs.setString('remembered_mode', _loginMode);
    } else {
      await prefs.remove('remembered_identifier');
      await prefs.remove('remembered_mode');
    }

    if (_bioAvailable && !kIsWeb) {
      final alreadyEnabled = await _bioService.isBiometricEnabled();
      if (!alreadyEnabled && mounted) {
        bool? consent = _rememberMe;
        if (!_rememberMe) {
          consent = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(
                'Enable Biometric Login?',
                style: TextStyle(color: Colors.grey),
              ),
              content: const Text(
                'Would you like to use fingerprint or face recognition next time?',
                style: TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(
                    'Not Now',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: _kOrange),
                  child: const Text(
                    'Enable',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
        if (consent == true) {
          await _bioService.saveCredentials(raw, _passCtrl.text);
          await _bioService.setBiometricEnabled(true);
        }
      } else if (alreadyEnabled) {
        await _bioService.saveCredentials(raw, _passCtrl.text);
      }
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

  Widget _loginTab(String mode, IconData icon, String label) {
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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
              Icon(icon, size: 16, color: isActive ? _kOrange : _kMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
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
            child: _buildForm(showLogo: true),
          ),
        ),
      ),
    ),
  );

  Widget _buildBrandPanel() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_kBrown, _kDarkBrown],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -50,
          bottom: -50,
          child: Icon(
            Icons.directions_boat,
            size: 300,
            color: Colors.white.withAlpha(15),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 64, borderRadius: 16),
              const SizedBox(height: 32),
              Text(
                'CUBAG',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 50,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Customs Brokers Association of Ghana',
                style: GoogleFonts.outfit(
                  color: Colors.white.withAlpha(230),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'The official gateway for licensed customs clearing and logistics firms in Ghana.',
                style: TextStyle(
                  color: Colors.white.withAlpha(190),
                  fontSize: 16,
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
    padding: const EdgeInsets.all(48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Member Services',
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _kText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Secure, fast, and unified customs management platform.',
          style: TextStyle(color: _kMuted, fontSize: 15),
        ),
        const SizedBox(height: 40),
        _infoCard(
          icon: Icons.shield_outlined,
          title: 'Secure Access & Credentials',
          desc:
              'Manage your verified broker profile, track standing scores, and renew certifications.',
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: Icons.map_outlined,
          title: 'Vessel & Cargo Intelligence',
          desc:
              'Access live maritime AIS tracking feeds, port schedules, and customs clearance timelines.',
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: Icons.wallet_outlined,
          title: 'Integrated Payments Gateway',
          desc:
              'Settle annual dues and platform charges directly using Mobile Money instantly.',
        ),
      ],
    ),
  );

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String desc,
  }) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _kWhite,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(6),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: _kBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kOrange.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _kBrown, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                desc,
                style: TextStyle(color: _kMuted, fontSize: 14, height: 1.5),
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
              child: _buildForm(showLogo: showLogo),
            ),
          ),
        ),
      );

  Widget _buildForm({required bool showLogo}) {
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
                'Welcome Back',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _kText,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to the CUBAG Member Portal',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kMuted, fontSize: 17, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        if (_error != null)
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
                    _error!,
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

        Container(
          decoration: BoxDecoration(
            color: _kCream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _loginTab('email', Icons.email_outlined, 'Email'),
              _loginTab('phone', Icons.phone_outlined, 'Phone'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _inputLabel(_loginMode == 'email' ? 'Email Address' : 'Phone Number'),
        const SizedBox(height: 8),
        TextFormField(
          enabled: !_loading,
          controller: _identifierCtrl,
          style: TextStyle(
            color: _kText,
            fontSize: 16,
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
          ),
        ),
        const SizedBox(height: 20),

        _inputLabel('Password'),
        const SizedBox(height: 8),
        TextFormField(
          enabled: !_loading,
          controller: _passCtrl,
          focusNode: _passFocusNode,
          obscureText: !_showPw && _passFocused,
          style: TextStyle(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: _inputDecoration(
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(
                _showPw
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _kMuted,
                size: 20,
              ),
              onPressed: _loading
                  ? null
                  : () => setState(() => _showPw = !_showPw),
            ),
          ),
        ),

        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _rememberMe,
                    activeColor: _kOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    onChanged: !_loading
                        ? (v) => setState(() => _rememberMe = v ?? false)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: !_loading
                      ? () => setState(() => _rememberMe = !_rememberMe)
                      : null,
                  child: Text(
                    'Keep me signed in',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _loading ? _kMuted : _kText,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _loading ? null : () => context.go('/forgot-password'),
              child: Text(
                'Forgot?',
                style: TextStyle(
                  color: _kBrown,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _loading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _loading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Signing in...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Sign In to Account',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
          ),
        ),

        if (_loading) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Signing in, please wait...',
              style: TextStyle(color: _kMuted, fontSize: 15),
            ),
          ),
        ],

        if (_bioAvailable && _bioEnabled && !kIsWeb) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: _kBorder)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Expanded(child: Divider(color: _kBorder)),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _handleBiometricLogin,
              icon: const Icon(Icons.fingerprint_rounded, size: 24),
              label: const Text(
                'Biometric Login',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBrown,
                side: BorderSide(color: _kBrown, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 36),

        Center(
          child: GestureDetector(
            onTap: () => context.go('/register'),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "New to CUBAG? ",
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: 'Create an Account',
                    style: TextStyle(
                      color: _kOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: () => context.go('/'),
            icon: Icon(Icons.home_outlined, size: 18, color: _kBrown),
            label: Text(
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
