import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../components/app_logo.dart';
import '../components/custom_dropdown.dart';
import '../core/router.dart';
import '../utils/validators.dart';

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

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  int _step = 1;
  bool _loading = false;
  String _error = '';

  bool _showPw = false;
  bool _showConfirm = false;

  List<dynamic> _portsList = [];

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _agcCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _digitalAddressCtrl = TextEditingController();
  final _tinCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _cpwCtrl = TextEditingController();

  final Map<String, String?> _form = {
    'portOfOperation': 'Accra International Airport',
    'memberType': 'Licentiate',
    'companyScale': null,
    'feeCategory': null,
  };

  @override
  void initState() {
    super.initState();
    _loadPorts();
  }

  Future<void> _loadPorts() async {
    try {
      final res = await ApiService().getPublic('members/public/ports');
      if (mounted && res is List && res.isNotEmpty) {
        setState(() {
          _portsList = res;
          _form['portOfOperation'] = res.first['name'].toString();
        });
      }
    } catch (_) {}
  }

  void _err(String msg) => setState(() => _error = msg);

  void _step1Next() {
    final isCorporate = _form['memberType'] == 'Corporate';
    final primaryName = isCorporate
        ? _companyCtrl.text.trim()
        : _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (isCorporate) {
      if (_form['companyScale'] == null || _form['companyScale']!.isEmpty) {
        _err(
          'Please select your Company Classification (SME or Large Corporate) to proceed.',
        );
        return;
      }
      if (_form['feeCategory'] == null || _form['feeCategory']!.isEmpty) {
        _err('Please select your Operational Category to proceed.');
        return;
      }
    }

    if (primaryName.isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        phone.isEmpty) {
      _err(
        isCorporate
            ? 'Please enter your company name, email address, and phone number.'
            : 'Please provide your full name, email address, and phone number.',
      );
      return;
    }

    if (!isCorporate && !AppValidators.isValidName(primaryName)) {
      _err(
        'Please provide a valid Full Name (letters, hyphens, and apostrophes allowed).',
      );
      return;
    }

    final normalizedPhone = AppValidators.normalizePhoneNumber(phone);
    if (!AppValidators.isValidGhanaPhone(normalizedPhone)) {
      _err(
        'Phone number must be a valid 10-digit Ghanaian number (e.g. 0244123456 or +233244123456).',
      );
      return;
    }

    _err('');
    setState(() => _step = 2);
  }

  Future<void> _step2Next() async {
    final isCorporate = _form['memberType'] == 'Corporate';
    if (isCorporate) {
      if (_nameCtrl.text.trim().isEmpty) {
        _err('Please enter contact person name.');
        return;
      }
      if (!AppValidators.isValidName(_nameCtrl.text.trim())) {
        _err(
          'Contact person name must be valid (letters, hyphens, and apostrophes allowed).',
        );
        return;
      }
    }
    if (!isCorporate && _companyCtrl.text.trim().isEmpty) {
      _companyCtrl.text = _nameCtrl.text.trim();
    }

    if (_locationCtrl.text.trim().isEmpty) {
      _err('Please enter your physical office location / address.');
      return;
    }

    final digi = _digitalAddressCtrl.text.trim();
    final cleanDigi = digi.replaceAll('-', '').trim();
    if (digi.isEmpty) {
      _err('Please enter your Ghana Digital Address (GhanaPostGPS).');
      return;
    }
    if (cleanDigi.length < 6 || cleanDigi.length > 10) {
      _err('Please enter a valid Ghana Digital Address (e.g. GA-1834-9023).');
      return;
    }

    final cleanTin = _tinCtrl.text.trim().toUpperCase();
    if (cleanTin.isEmpty) {
      _err('Please enter your Taxpayer Identification Number (TIN).');
      return;
    }
    if (cleanTin.length > 11) {
      _err('Taxpayer Identification Number (TIN) cannot exceed 11 characters.');
      return;
    }

    _err('');
    setState(() => _loading = true);
    try {
      final res = await ApiService().post(
        '/auth/send-otp',
        data: {'email': _emailCtrl.text.trim().toLowerCase()},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _step = 3;
          _error = '';
        });
      } else {
        _err(res.data['message'] ?? 'Failed to send verification code.');
      }
    } catch (_) {
      if (!mounted) return;
      _err('Network error. Please try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.length != 6) {
      _err('Enter the 6-digit code sent to your email.');
      return;
    }
    _err('');
    setState(() => _loading = true);
    try {
      final res = await ApiService().post(
        '/auth/verify-email',
        data: {
          'email': _emailCtrl.text.trim().toLowerCase(),
          'token': _otpCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _step = 4;
          _error = '';
        });
      } else {
        _err(res.data['message'] ?? 'Invalid or expired code.');
      }
    } catch (_) {
      if (!mounted) return;
      _err('Connection error. Try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _register() async {
    if (_pwCtrl.text != _cpwCtrl.text) {
      _err('Passwords do not match.');
      return;
    }
    if (_pwCtrl.text.length < 8) {
      _err('Password must be at least 8 characters.');
      return;
    }
    _err('');
    setState(() => _loading = true);

    final isCorporate = _form['memberType'] == 'Corporate';
    final nameVal = isCorporate
        ? (_nameCtrl.text.trim().isNotEmpty
              ? _nameCtrl.text.trim()
              : _companyCtrl.text.trim())
        : _nameCtrl.text.trim();
    final companyVal = isCorporate
        ? _companyCtrl.text.trim()
        : (_companyCtrl.text.trim().isNotEmpty
              ? _companyCtrl.text.trim()
              : nameVal);

    try {
      final res = await ApiService().post(
        '/auth/register',
        data: {
          'name': nameVal,
          'email': _emailCtrl.text.trim().toLowerCase(),
          'phone': AppValidators.normalizePhoneNumber(_phoneCtrl.text),
          'company': companyVal,
          'licenseNumber': _licCtrl.text.trim(),
          'agencyCode': _agcCtrl.text.trim(),
          'location': _locationCtrl.text.trim(),
          'digitalAddress': _digitalAddressCtrl.text.trim(),
          'tin': _tinCtrl.text.trim(),
          'portOfOperation': _form['portOfOperation'],
          'memberType': _form['memberType'],
          'memberScale': isCorporate ? (_form['companyScale'] ?? 'sme') : null,
          'companyScale': isCorporate ? (_form['companyScale'] ?? 'sme') : null,
          'feeCategory': isCorporate ? (_form['feeCategory'] ?? 'cf_only') : null,
          'password': _pwCtrl.text,
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data;
        if (data is Map && data['token'] != null && data['user'] != null) {
          final authService = Provider.of<AuthService>(context, listen: false);
          await authService.setAuthSession(
            token: data['token'].toString(),
            user: Map<String, dynamic>.from(data['user'] as Map),
          );
          if (mounted) {
            preloadMemberLibraries();
            context.go('/application-documents');
          }
        } else {
          final authService = Provider.of<AuthService>(context, listen: false);
          final err = await authService.login(
            _emailCtrl.text.trim().toLowerCase(),
            _pwCtrl.text,
          );
          if (mounted) {
            if (err == null) {
              preloadMemberLibraries();
              context.go('/application-documents');
            } else {
              context.go('/login');
            }
          }
        }
      } else {
        _err(res.data['message'] ?? 'Registration failed.');
      }
    } catch (_) {
      if (!mounted) return;
      _err('Connection error. Please try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _licCtrl.dispose();
    _agcCtrl.dispose();
    _otpCtrl.dispose();
    _pwCtrl.dispose();
    _cpwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: _kCream,
      body: isWide ? _buildTwoColumnLayout() : _buildMobileLayout(),
    );
  }

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
          constraints: const BoxConstraints(maxWidth: 460),
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
            child: _buildFormContent(showLogo: true, isMobile: true),
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

  Widget _buildFormPanel({double padding = 60, required bool showLogo}) =>
      Container(
        color: _kWhite,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _buildFormContent(showLogo: showLogo),
            ),
          ),
        ),
      );

  Widget _buildFormContent({required bool showLogo, bool isMobile = false}) {
    final stepLabels = ['Identity', 'Professional', 'Verify', 'Security'];
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
                [
                  'Join CUBAG',
                  'Professional Profile',
                  'Verify Identity',
                  'Secure Account',
                ][_step - 1],
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
                [
                  'Provide contact information to register.',
                  'Tell us about your logistics agency.',
                  'Enter verification code sent to your email.',
                  'Choose a secure password for your account.',
                ][_step - 1],
                textAlign: TextAlign.center,
                style: TextStyle(color: _kMuted, fontSize: 17, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Step Progress Indicator
        if (isMobile) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $_step of 4',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _kMuted,
                ),
              ),
              Text(
                stepLabels[_step - 1],
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _kOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _step / 4.0,
              minHeight: 6,
              backgroundColor: _kBorder,
              valueColor: AlwaysStoppedAnimation<Color>(_kOrange),
            ),
          ),
        ] else ...[
          SizedBox(
            height: 60,
            child: Row(
              children: List.generate(4, (i) {
                final n = i + 1;
                final done = _step > n;
                final active = _step == n;

                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Divider(
                              thickness: 2,
                              color: i == 0
                                  ? Colors.transparent
                                  : (_step > i ? _kBrown : _kBorder),
                            ),
                          ),
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: done
                                  ? _kBrown
                                  : (active ? _kOrange : _kBorder),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: done
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    )
                                  : Text(
                                      '$n',
                                      style: TextStyle(
                                        color: done || active
                                            ? Colors.white
                                            : _kMuted,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              thickness: 2,
                              color: i == 3
                                  ? Colors.transparent
                                  : (_step > n ? _kBrown : _kBorder),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          stepLabels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: done
                                ? _kBrown
                                : (active ? _kOrange : _kMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
        const SizedBox(height: 28),

        if (_error.isNotEmpty)
          Container(
            width: double.infinity,
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

        if (_step == 1) _buildStep1(),
        if (_step == 2) _buildStep2(),
        if (_step == 3) _buildStep3(),
        if (_step == 4) _buildStep4(),

        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => context.go('/login'),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "Already have an account? ",
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: 'Sign In',
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
    String? hint,
    IconData? icon,
    List<TextInputFormatter>? formatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _inputLabel(label),
      const SizedBox(height: 8),
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        inputFormatters: formatters,
        textCapitalization: textCapitalization,
        style: TextStyle(
          color: _kText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: _inputDecoration(
          hint: hint ?? '',
          icon: icon ?? Icons.text_fields,
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _buildStep1() {
    final isCorporate = _form['memberType'] == 'Corporate';

    return Column(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _inputLabel('Membership Type'),
            const SizedBox(height: 10),
            _buildMemberTypeCards(),
            const SizedBox(height: 18),
          ],
        ),
        if (isCorporate) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inputLabel('Company Classification *'),
              const SizedBox(height: 4),
              Text(
                'Select your company classification scale:',
                style: TextStyle(fontSize: 14, color: _kMuted),
              ),
              const SizedBox(height: 8),
              _buildCompanyClassificationDropdown(),
              const SizedBox(height: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inputLabel('Operational Category *'),
              const SizedBox(height: 4),
              Text(
                'Select the licensed logistics scope for your company:',
                style: TextStyle(fontSize: 14, color: _kMuted),
              ),
              const SizedBox(height: 8),
              _buildCompanyCategoryDropdown(),
              const SizedBox(height: 18),
            ],
          ),
          _field(
            'Company / Agency Name',
            _companyCtrl,
            hint: 'e.g. Global Logistics Ghana Ltd',
            icon: Icons.business_outlined,
          ),
        ] else
          _field(
            'Full Name',
            _nameCtrl,
            hint: 'e.g. John Mensah',
            icon: Icons.person_outline,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
            ],
            textCapitalization: TextCapitalization.words,
          ),

        _field(
          'Email Address',
          _emailCtrl,
          type: TextInputType.emailAddress,
          hint: 'e.g. john@agency.com',
          icon: Icons.email_outlined,
        ),
        _field(
          'Phone Number',
          _phoneCtrl,
          type: TextInputType.number,
          hint: 'e.g. 0244123456',
          icon: Icons.phone_outlined,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _step1Next,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Next Step',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTypeCards() {
    const types = [
      {
        'value': 'Licentiate',
        'label': 'Licentiate',
        'icon': Icons.badge_outlined,
        'desc': 'Individual licensed customs broker',
      },
      {
        'value': 'Associate',
        'label': 'Associate',
        'icon': Icons.groups_outlined,
        'desc': 'Supporting partner / industry affiliate',
      },
      {
        'value': 'Corporate',
        'label': 'Corporate',
        'icon': Icons.business_outlined,
        'desc': 'Registered corporate agency / firm',
      },
    ];

    return Column(
      children: types.map((t) {
        final selected = _form['memberType'] == t['value'];
        return GestureDetector(
          onTap: () =>
              setState(() => _form['memberType'] = t['value'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? _kCream : _kWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _kOrange : _kBorder,
                width: selected ? 2 : 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _kOrange.withAlpha(20),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? _kOrange.withAlpha(25)
                        : _kBorder.withAlpha(60),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    t['icon'] as IconData,
                    color: selected ? _kBrown : _kMuted,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['label'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: selected ? _kBrown : _kText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t['desc'] as String,
                        style: TextStyle(fontSize: 14, color: _kMuted),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _kOrange : Colors.transparent,
                    border: Border.all(
                      color: selected ? _kOrange : _kBorder,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompanyClassificationDropdown() {
    const scales = [
      {
        'value': 'sme',
        'label': 'SME',
        'short': 'SME',
        'desc': 'Registered customs brokerage and logistics enterprise.',
        'icon': Icons.storefront_rounded,
      },
      {
        'value': 'large_corporate',
        'label': 'Large Corporate',
        'short': 'Large Corporate',
        'desc':
            'Corporate enterprise operating across registered locations.',
        'icon': Icons.corporate_fare_rounded,
      },
    ];

    final currentScale = _form['companyScale'];
    final selectedScale = currentScale != null
        ? scales.firstWhere(
            (s) => s['value'] == currentScale,
            orElse: () => scales.first,
          )
        : null;

    final isSelected = selectedScale != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: _kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _kOrange : _kBorder,
              width: isSelected ? 1.8 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _kOrange.withAlpha(15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentScale,
              isExpanded: true,
              hint: Row(
                children: [
                  Icon(
                    Icons.domain_verification_rounded,
                    color: _kMuted.withAlpha(180),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '-- Select Company Classification (Required) --',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kMuted.withAlpha(180),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: isSelected ? _kOrange : _kBrown,
                size: 24,
              ),
              dropdownColor: _kWhite,
              borderRadius: BorderRadius.circular(16),
              items: scales.map((s) {
                final isSel = s['value'] == currentScale;
                return DropdownMenuItem<String>(
                  value: s['value'] as String,
                  child: Row(
                    children: [
                      Icon(
                        s['icon'] as IconData,
                        color: isSel ? _kOrange : _kBrown,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              s['short'] as String,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSel
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSel ? _kOrange : _kText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _form['companyScale'] = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? (_isDark
                      ? const Color(0xFF1A0F0A).withAlpha(150)
                      : const Color(0xFFF8F4F0))
                : (_isDark
                      ? const Color(0xFF1A0F0A).withAlpha(80)
                      : const Color(0xFFF8F4F0)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? _kOrange.withAlpha(60)
                  : _kBorder.withAlpha(100),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.info_outline_rounded
                    : Icons.touch_app_outlined,
                color: isSelected ? _kOrange : _kMuted,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSelected
                      ? (selectedScale['desc'] as String)
                      : 'Please select your company classification: SME or Large Corporate.',
                  style: TextStyle(
                    fontSize: 14,
                    color: _kMuted,
                    height: 1.4,
                    fontStyle: isSelected ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyCategoryDropdown() {
    const categories = [
      {
        'value': 'cf_only',
        'label': 'CLEARING & FORWARDING',
        'desc':
            'Dedicated customs clearance, port declarations, and freight forwarding operations.',
        'icon': Icons.local_shipping_rounded,
      },
      {
        'value': 'consolidation',
        'label': 'CONSOLIDATION',
        'desc':
            'Cargo grouping, groupage management, LCL consolidation, de-consolidation, and warehousing.',
        'icon': Icons.inventory_2_rounded,
      },
      {
        'value': 'cf_consolidation',
        'label': 'CONSOLIDATION, CLEARING & FORWARDING',
        'desc':
            'Comprehensive full-spectrum logistics: cargo consolidation, forwarding & customs clearance.',
        'icon': Icons.hub_rounded,
      },
    ];

    final currentVal = _form['feeCategory'];
    final selectedCategory = currentVal != null
        ? categories.firstWhere(
            (c) => c['value'] == currentVal,
            orElse: () => categories.first,
          )
        : null;

    final isSelected = selectedCategory != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: _kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _kOrange : _kBorder,
              width: isSelected ? 1.8 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _kOrange.withAlpha(15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentVal,
              isExpanded: true,
              hint: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: _kMuted.withAlpha(180),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '-- Select Operational Category (Required) --',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kMuted.withAlpha(180),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: isSelected ? _kOrange : _kBrown,
                size: 24,
              ),
              dropdownColor: _kWhite,
              borderRadius: BorderRadius.circular(16),
              items: categories.map((cat) {
                final isSel = cat['value'] == currentVal;
                return DropdownMenuItem<String>(
                  value: cat['value'] as String,
                  child: Row(
                    children: [
                      Icon(
                        cat['icon'] as IconData,
                        color: isSel ? _kOrange : _kBrown,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cat['label'] as String,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSel
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSel ? _kOrange : _kText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _form['feeCategory'] = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? (_isDark
                      ? const Color(0xFF1A0F0A).withAlpha(150)
                      : const Color(0xFFF8F4F0))
                : (_isDark
                      ? const Color(0xFF1A0F0A).withAlpha(80)
                      : const Color(0xFFF8F4F0)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? _kOrange.withAlpha(60)
                  : _kBorder.withAlpha(100),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.info_outline_rounded
                    : Icons.touch_app_outlined,
                color: isSelected ? _kOrange : _kMuted,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSelected
                      ? (selectedCategory['desc'] as String)
                      : 'Please choose your primary licensed operational scope (Clearing & Forwarding, Consolidation, or Combined).',
                  style: TextStyle(
                    fontSize: 14,
                    color: _kMuted,
                    height: 1.4,
                    fontStyle: isSelected ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortCards() {
    List<DropdownItem<String>> portItems = _portsList.isNotEmpty
        ? _portsList
              .map(
                (p) => DropdownItem<String>(
                  value: p['name'].toString(),
                  label: p['name'].toString(),
                ),
              )
              .toList()
        : [
            const DropdownItem(
              value: 'Accra International Airport',
              label: 'Accra International Airport',
            ),
            const DropdownItem(
              value: 'Aflao Border Port',
              label: 'Aflao Border Port',
            ),
            const DropdownItem(
              value: 'Elubo Border Port',
              label: 'Elubo Border Port',
            ),
            const DropdownItem(value: 'Paga Border Port', label: 'Paga Border Port'),
            const DropdownItem(value: 'Takoradi Port', label: 'Takoradi Port'),
            const DropdownItem(value: 'Tema Port', label: 'Tema Port'),
          ];

    portItems.sort((a, b) => a.label.compareTo(b.label));

    return CustomDropdown<String>(
      value: _form['portOfOperation'] ?? 'Accra International Airport',
      items: portItems,
      onChanged: (val) => setState(() => _form['portOfOperation'] = val),
    );
  }

  Widget _buildStep2() {
    final isCorporate = _form['memberType'] == 'Corporate';

    return Column(
      children: [
        if (isCorporate)
          _field(
            'Contact Person / Authorized Representative',
            _nameCtrl,
            hint: 'e.g. John Mensah (Managing Director)',
            icon: Icons.person_outline,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
            ],
            textCapitalization: TextCapitalization.words,
          )
        else
          _field(
            'Agency or Company Name (Optional)',
            _companyCtrl,
            hint: 'e.g. Global Logistics Ltd',
            icon: Icons.business_outlined,
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kOrange.withAlpha(15),
            border: Border.all(color: _kOrange.withAlpha(40)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: _kBrown, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Note for New Applicants:',
                    style: TextStyle(
                      fontSize: 15,
                      color: _kBrown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "If you don't have these details yet, leave them blank. CUBAG will assign them upon approval.",
                style: TextStyle(fontSize: 14, color: _kText, height: 1.4),
              ),
            ],
          ),
        ),
        _field(
          'Membership ID / Number (Optional)',
          _agcCtrl,
          hint: 'e.g. CUBAG-0123',
          icon: Icons.badge_outlined,
        ),
        _field(
          'Physical Location / Office Address',
          _locationCtrl,
          hint: 'e.g. Suite 4, Community 1, Tema',
          icon: Icons.location_on_outlined,
        ),
        _field(
          'Ghana Digital Address (GhanaPostGPS)',
          _digitalAddressCtrl,
          hint: 'e.g. GA-1834-9023',
          icon: Icons.pin_drop_outlined,
          formatters: [GhanaDigitalAddressFormatter()],
          textCapitalization: TextCapitalization.characters,
        ),
        _field(
          'Company / Taxpayer TIN',
          _tinCtrl,
          hint: 'e.g. C0012345678',
          icon: Icons.subtitles_outlined,
          formatters: [
            LengthLimitingTextInputFormatter(11),
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          ],
          textCapitalization: TextCapitalization.characters,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _inputLabel('Primary Port of Operation'),
            const SizedBox(height: 10),
            _buildPortCards(),
            const SizedBox(height: 18),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBrown,
                  side: BorderSide(color: _kBrown, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(0, 56),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(
                    color: _kBrown,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _loading ? null : _step2Next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(0, 56),
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
                        'Verify Email',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() => Column(
    children: [
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _kOrange.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mark_email_read, color: _kBrown, size: 36),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Check your inbox for a 6-digit verification code.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _kMuted, fontSize: 17),
      ),
      const SizedBox(height: 32),
      TextFormField(
        controller: _otpCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: 12,
          color: _kText,
        ),
        decoration: InputDecoration(
          hintText: '000000',
          counterText: '',
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
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
      const SizedBox(height: 36),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _step = 2),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBrown,
                side: BorderSide(color: _kBrown, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(0, 56),
              ),
              child: Text(
                'Back',
                style: TextStyle(
                  color: _kBrown,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(0, 56),
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
                      'Verify Code',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildStep4() => Column(
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputLabel('Create Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _pwCtrl,
            obscureText: !_showPw,
            style: TextStyle(
              color: _kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(
              hint: 'At least 8 characters',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _showPw
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _kMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _inputLabel('Confirm Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _cpwCtrl,
            obscureText: !_showConfirm,
            style: TextStyle(
              color: _kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(
              hint: 'Repeat password',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _showConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _kMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _showConfirm = !_showConfirm),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _step = 3),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBrown,
                side: BorderSide(color: _kBrown, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(0, 56),
              ),
              child: Text(
                'Back',
                style: TextStyle(
                  color: _kBrown,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _loading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(0, 56),
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
                      'Complete Registration',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ],
  );
}
