import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../core/router.dart';
import '../utils/validators.dart';
import '../components/auth_scaffold.dart';
import '../design/cubag_design.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  int _step = 1;
  bool _loading = false;
  String _error = '';


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

  List<String> _selectedDistricts = ['Tema Port'];

  final Map<String, String?> _form = {
    'portOfOperation': 'Tema Port',
    'memberType': 'Corporate',
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
          if (_selectedDistricts.isEmpty) {
            _selectedDistricts = [res.first['name'].toString()];
          }
          _form['portOfOperation'] = _selectedDistricts.join(', ');
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
        _err('Choose your company size.');
        return;
      }
      if (_form['feeCategory'] == null || _form['feeCategory']!.isEmpty) {
        _err('Choose what your company is licensed to do.');
        return;
      }
    }

    if (primaryName.isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        phone.isEmpty) {
      _err(
        isCorporate
            ? 'Enter your company name, email address and phone number.'
            : 'Please provide your full name, email address, and phone number.',
      );
      return;
    }

    if (!AppValidators.isValidEmail(_emailCtrl.text)) {
      _err('Please enter a valid email address (e.g. name@company.com).');
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
        _err('Enter the contact person\'s name.');
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
      _err('Enter your office address.');
      return;
    }

    final digi = _digitalAddressCtrl.text.trim();
    final cleanDigi = digi.replaceAll('-', '').trim();
    if (digi.isEmpty) {
      _err('Enter your Ghana digital address (GhanaPostGPS).');
      return;
    }
    if (cleanDigi.length < 6 || cleanDigi.length > 10) {
      _err('Please enter a valid Ghana Digital Address (e.g. GA-1834-9023).');
      return;
    }

    final cleanTin = _tinCtrl.text.trim().toUpperCase();
    if (cleanTin.isEmpty) {
      _err('Enter your company TIN.');
      return;
    }
    if (cleanTin.length > 11) {
      _err('Taxpayer Identification Number (TIN) cannot exceed 11 characters.');
      return;
    }

    if (_selectedDistricts.isEmpty) {
      _err('Choose at least one district.');
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
    final pwError = AppValidators.newPasswordError(_pwCtrl.text, _cpwCtrl.text);
    if (pwError != null) {
      _err(pwError);
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
          'portOfOperation': _form['portOfOperation'] ?? _selectedDistricts.join(', '),
          'districts': _selectedDistricts,
          'memberType': 'Corporate',
          'memberScale': _form['companyScale'] ?? 'sme',
          'companyScale': _form['companyScale'] ?? 'sme',
          'feeCategory': _form['feeCategory'] ?? 'cf_only',
          'password': _pwCtrl.text,
          'otp': _otpCtrl.text.trim(),
          'email_otp': _otpCtrl.text.trim(),
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
    } catch (e) {
      if (!mounted) return;
      String msg = 'Registration failed. Please try again.';
      if (e is DioException) {
        if (e.response?.data is Map && e.response?.data['message'] != null) {
          msg = e.response!.data['message'].toString();
        } else if (e.type == DioExceptionType.connectionTimeout ||
                   e.type == DioExceptionType.connectionError) {
          msg = 'Connection error. Please check your internet connection.';
        }
      }
      _err(msg);
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
    _locationCtrl.dispose();
    _digitalAddressCtrl.dispose();
    _tinCtrl.dispose();
    super.dispose();
  }

  // ── Steps ───────────────────────────────────────────────────────────────
  static const _stepNames = ['Your company', 'Company details', 'Verify email', 'Create password'];

  static const _scales = [
    ('sme', 'SME', 'Registered customs clearing and logistics enterprise.'),
    ('large_corporate', 'Large corporate', 'Corporate enterprise operating across registered locations.'),
  ];

  static const _categories = [
    ('cf_only', 'Clearing and forwarding',
        'Customs clearance, port declarations and freight forwarding.'),
    ('consolidation', 'Consolidation',
        'Cargo grouping, LCL consolidation and de-consolidation, warehousing.'),
    ('cf_consolidation', 'Consolidation, clearing and forwarding',
        'The full scope: consolidation, forwarding and customs clearance.'),
  ];

  static const _fallbackDistricts = [
    'Accra International Airport', 'Aflao Border Port', 'Elubo Border Port',
    'Paga Border Port', 'Takoradi Port', 'Tema Port',
  ];

  Future<void> _resendOtp() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await ApiService().post(
        '/auth/send-otp',
        data: {'email': _emailCtrl.text.trim().toLowerCase()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We sent a new code.')),
        );
      }
    } catch (_) {
      if (mounted) _err('We could not send a new code. Please try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _back() {
    if (_loading) return;
    if (_step > 1) {
      setState(() {
        _step -= 1;
        _error = '';
      });
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    return AuthScaffold(
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Apply for membership', style: CubagType.title),
          const SizedBox(height: CubagSpace.xxs),
          Text('Step $_step of 4: ${_stepNames[_step - 1]}', style: CubagType.small),
          const SizedBox(height: CubagSpace.sm),
          _StepBar(step: _step, total: 4),
          const SizedBox(height: CubagSpace.lg),
          if (_error.isNotEmpty) ...[
            AuthNote(message: _error),
            const SizedBox(height: CubagSpace.md),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                1 => _stepCompany(),
                2 => _stepDetails(),
                3 => _stepVerify(),
                _ => _stepPassword(),
              },
            ),
          ),
          const SizedBox(height: CubagSpace.xl),
          const Divider(),
          const SizedBox(height: CubagSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already a member?', style: CubagType.small),
              TextButton(
                onPressed: _loading ? null : () => context.go('/login'),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gap() => const SizedBox(height: CubagSpace.md);

  Widget _input(
    String label,
    TextEditingController c, {
    String? hint,
    String? helper,
    TextInputType? type,
    List<TextInputFormatter>? formatters,
    TextCapitalization caps = TextCapitalization.none,
    Iterable<String>? autofill,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthFieldLabel(label),
        TextFormField(
          controller: c,
          enabled: !_loading,
          keyboardType: type,
          inputFormatters: formatters,
          textCapitalization: caps,
          autofillHints: autofill,
          textInputAction: TextInputAction.next,
          style: CubagType.body.copyWith(color: CubagColors.ink),
          decoration: InputDecoration(hintText: hint, helperText: helper, helperMaxLines: 3),
        ),
        _gap(),
      ],
    );
  }

  Widget _primary(String label, VoidCallback onPressed) => FilledButton(
        onPressed: _loading ? null : onPressed,
        child: _loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: CubagColors.muted),
              )
            : Text(label),
      );

  Widget _stepCompany() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Company size', style: CubagType.label),
        const SizedBox(height: CubagSpace.xs),
        for (final (v, title, desc) in _scales)
          _ChoiceTile(
            title: title,
            description: desc,
            selected: _form['companyScale'] == v,
            onTap: _loading ? null : () => setState(() => _form['companyScale'] = v),
          ),
        const SizedBox(height: CubagSpace.md),
        const Text('What your company is licensed to do', style: CubagType.label),
        const SizedBox(height: CubagSpace.xs),
        for (final (v, title, desc) in _categories)
          _ChoiceTile(
            title: title,
            description: desc,
            selected: _form['feeCategory'] == v,
            onTap: _loading ? null : () => setState(() => _form['feeCategory'] = v),
          ),
        const SizedBox(height: CubagSpace.md),
        _input('Company or agency name', _companyCtrl,
            hint: 'e.g. Global Logistics Ghana Ltd',
            caps: TextCapitalization.words,
            autofill: const [AutofillHints.organizationName]),
        _input('Email address', _emailCtrl,
            hint: 'name@company.com',
            type: TextInputType.emailAddress,
            autofill: const [AutofillHints.email]),
        _input('Phone number', _phoneCtrl,
            hint: '024 412 3456',
            type: TextInputType.phone,
            autofill: const [AutofillHints.telephoneNumber],
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ]),
        const SizedBox(height: CubagSpace.xs),
        _primary('Continue', _step1Next),
      ],
    );
  }

  Widget _stepDetails() {
    final districts = (_portsList.isNotEmpty
            ? _portsList.map((p) => p['name'].toString()).toList()
            : List<String>.from(_fallbackDistricts))
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _input('Contact person', _nameCtrl,
            hint: 'e.g. John Mensah, Managing Director',
            caps: TextCapitalization.words,
            autofill: const [AutofillHints.name],
            formatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'.]"))]),
        _input('Office address', _locationCtrl,
            hint: 'e.g. Suite 4, Community 1, Tema',
            autofill: const [AutofillHints.fullStreetAddress]),
        _input('Ghana digital address', _digitalAddressCtrl,
            hint: 'e.g. GA-183-9023',
            caps: TextCapitalization.characters,
            formatters: [GhanaDigitalAddressFormatter()]),
        _input('Company TIN', _tinCtrl,
            hint: 'e.g. C0012345678',
            caps: TextCapitalization.characters,
            formatters: [
              LengthLimitingTextInputFormatter(11),
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
            ]),
        _input('CUBAG membership number (optional)', _agcCtrl,
            hint: 'e.g. CUBAG-0123',
            helper: 'New applicants can leave this blank. The Secretariat assigns one on approval.'),
        const Text('Districts you operate in', style: CubagType.label),
        const SizedBox(height: CubagSpace.xxs),
        const Text('District clearance fees apply for each district you choose.', style: CubagType.small),
        const SizedBox(height: CubagSpace.sm),
        Wrap(
          spacing: CubagSpace.xs,
          runSpacing: CubagSpace.xs,
          children: [
            for (final d in districts)
              FilterChip(
                label: Text(d),
                selected: _selectedDistricts.contains(d),
                showCheckmark: true,
                checkmarkColor: CubagColors.actionPressed,
                onSelected: _loading
                    ? null
                    : (on) => setState(() {
                          if (on) {
                            if (!_selectedDistricts.contains(d)) _selectedDistricts.add(d);
                          } else if (_selectedDistricts.length > 1) {
                            _selectedDistricts.remove(d);
                          }
                          _form['portOfOperation'] = _selectedDistricts.join(', ');
                        }),
              ),
          ],
        ),
        const SizedBox(height: CubagSpace.xl),
        _primary('Send verification code', _step2Next),
      ],
    );
  }

  Widget _stepVerify() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'We sent a 6-digit code to ${_emailCtrl.text.trim()}. Enter it to confirm your email.',
          style: CubagType.body,
        ),
        const SizedBox(height: CubagSpace.lg),
        const AuthFieldLabel('Code'),
        TextFormField(
          controller: _otpCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onFieldSubmitted: (_) => _verifyOtp(),
          style: CubagType.figure.copyWith(fontSize: 20, letterSpacing: 6),
          decoration: const InputDecoration(hintText: '6-digit code'),
        ),
        const SizedBox(height: CubagSpace.xl),
        _primary('Verify email', _verifyOtp),
        const SizedBox(height: CubagSpace.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No code?', style: CubagType.small),
            TextButton(
              onPressed: _loading ? null : _resendOtp,
              child: const Text('Send a new one'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepPassword() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('You\'ll use this with your email to sign in.', style: CubagType.body),
          const SizedBox(height: CubagSpace.lg),
          const AuthFieldLabel('Password'),
          PasswordField(
            controller: _pwCtrl,
            enabled: !_loading,
            hint: 'At least 8 characters',
            autofillHints: const [AutofillHints.newPassword],
            action: TextInputAction.next,
          ),
          _gap(),
          const AuthFieldLabel('Confirm password'),
          PasswordField(
            controller: _cpwCtrl,
            enabled: !_loading,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _register(),
          ),
          const SizedBox(height: CubagSpace.sm),
          const Text(
            'After you create your account, you\'ll upload your company documents '
            'and pay the registration fee. The Secretariat then reviews your application.',
            style: CubagType.small,
          ),
          const SizedBox(height: CubagSpace.xl),
          _primary('Create account', _register),
        ],
      ),
    );
  }
}

/// A selectable option with a short explanation (radio semantics).
class _ChoiceTile extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;
  const _ChoiceTile({
    required this.title,
    required this.description,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.xs),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Material(
          color: selected ? CubagColors.actionTint : CubagColors.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CubagRadius.control),
            side: BorderSide(
              color: selected ? CubagColors.action : CubagColors.lineStrong,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(CubagRadius.control),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(CubagSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? CubagColors.action : CubagColors.muted,
                    size: 22,
                  ),
                  const SizedBox(width: CubagSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: CubagType.bodyStrong),
                        const SizedBox(height: 2),
                        Text(description, style: CubagType.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the applicant is in the four steps.
class _StepBar extends StatelessWidget {
  final int step;
  final int total;
  const _StepBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $step of $total',
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? CubagColors.action : CubagColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
