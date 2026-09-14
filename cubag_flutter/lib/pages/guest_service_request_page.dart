import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_logo.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../services/theme_service.dart';

// ── CUBAG Dynamic Brand Color Hierarchy ──────────────────────────────────────
bool get _isDark => ThemeService.instance.isDark;
Color get _kBg => _isDark
    ? const Color(0xFF1A0F0A)
    : const Color(0xFFFFFFFF); // deep espresso chocolate
Color get _kCream => _isDark
    ? const Color(0xFF281710)
    : const Color(0xFFF8F4F0); // warm velvet chocolate
Color get _kCardBg => _isDark
    ? const Color(0xFF281710)
    : Colors.white; // chocolate cards & surfaces
Color get _kBrown => _isDark
    ? const Color(0xFFFF5000)
    : const Color(0xFF6B3E26); // shining caramel gold / brand
Color get _kAccent => const Color(0xFFFF5000); // primary CTA & highlights
Color get _kText => _isDark
    ? const Color(0xFFFFF8F3)
    : const Color(0xFF2B211D); // warm ivory / body text
Color get _kMuted => _isDark
    ? const Color(0xFFC8ADA0)
    : const Color(0xFF6F625B); // cocoa tan / secondary text
Color get _kBorder => _isDark
    ? const Color(0xFF4D2D20)
    : const Color(0xFFE8DED6); // warm bronze borders
Color get _kGreen => const Color(0xFF10B981); // verified/success

class GuestServiceRequestPage extends StatefulWidget {
  final String? initialService;
  final String? initialCourse;
  const GuestServiceRequestPage({
    super.key,
    this.initialService,
    this.initialCourse,
  });

  @override
  State<GuestServiceRequestPage> createState() =>
      _GuestServiceRequestPageState();
}

class _GuestServiceRequestPageState extends State<GuestServiceRequestPage> {
  String _serviceType = 'clearing_agent';
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _courseCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();

  // Clearing Agents Directory state after submission
  final TextEditingController _agentSearchCtrl = TextEditingController();
  String _selectedPortFilter = 'All';
  List<dynamic> _matchingAgents = [];
  bool _loadingAgents = false;

  String _primaryPort = 'Tema Port';
  List<dynamic> _availablePorts = [];
  List<dynamic> _availableCourses = [];
  bool _submitting = false;
  String? _referenceNumber;

  Map<String, dynamic>? get _selectedCourseData {
    final title = _courseCtrl.text.trim().toLowerCase();
    if (title.isEmpty) return null;
    for (final c in _availableCourses) {
      if (c is Map) {
        final cTitle = (c['title'] ?? '').toString().trim().toLowerCase();
        if (cTitle == title || cTitle.contains(title) || title.contains(cTitle)) {
          return Map<String, dynamic>.from(c);
        }
      }
    }
    return null;
  }

  String get _currentCourseFee {
    final data = _selectedCourseData;
    if (data != null && data['fee'] != null) {
      String fee = data['fee'].toString().trim();
      if (fee.isNotEmpty) {
        if (!fee.toUpperCase().startsWith('GHS')) {
          fee = 'GHS $fee';
        }
        return fee;
      }
    }
    return 'GHS 1,500.00';
  }

  String get _currentCourseStartDate {
    final data = _selectedCourseData;
    if (data != null && (data['start_date'] != null || data['date'] != null)) {
      final dateStr = (data['start_date'] ?? data['date']).toString().trim();
      if (dateStr.isNotEmpty) return dateStr;
    }
    return '15 Sep 2026 · 09:00 AM GMT';
  }

  String get _currentCourseDurationMode {
    final data = _selectedCourseData;
    if (data != null) {
      final dur = data['duration']?.toString() ?? '4 Weeks';
      final mode = data['mode']?.toString() ?? 'Hybrid';
      return '$dur · $mode';
    }
    return '4 Weeks · Hybrid (In-Person & Zoom)';
  }

  // ── Available Guest Services ────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _kServices = [
    {
      'id': 'clearing_agent',
      'title': 'Find A Licensed Broker (Clearing Agent/Forwarder)',
      'desc':
          'Connect with an accredited CUBAG licensed customs broker for cargo clearance.',
      'icon': Icons.manage_search_rounded,
    },
    {
      'id': 'cti_training',
      'title': 'Register A Course',
      'desc':
          'Enrol in CUBAG Training Institute (CTI) professional courses & ICUMS certifications.',
      'icon': Icons.school_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialService != null &&
        _kServices.any((s) => s['id'] == widget.initialService)) {
      _serviceType = widget.initialService!;
    }
    if (widget.initialCourse != null &&
        widget.initialCourse!.trim().isNotEmpty) {
      _courseCtrl.text = widget.initialCourse!.trim();
      _serviceType = 'cti_training';
    }
    _loadPorts();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final res = await ApiService().getPublic('events/public/courses');
      if (mounted) {
        if (res is Map && res['items'] is List) {
          setState(() => _availableCourses = res['items']);
        } else if (res is List) {
          setState(() => _availableCourses = res);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _courseCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyCtrl.dispose();
    _detailsCtrl.dispose();
    _agentSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPorts() async {
    try {
      final res = await ApiService().getPublic('members/public/ports');
      if (mounted && res is List && res.isNotEmpty) {
        setState(() {
          _availablePorts = res;
          _primaryPort = res.first['name']?.toString() ?? 'Tema Port';
        });
      }
    } catch (_) {}
  }

  Future<void> _loadGoodStandingAgents([String? port]) async {
    setState(() => _loadingAgents = true);
    try {
      String url = 'members/public/members';
      if (port != null && port != 'All' && port.isNotEmpty) {
        url += '?port=${Uri.encodeComponent(port)}';
      }
      final res = await ApiService().getPublic(url);
      if (mounted && res is List) {
        setState(() {
          _matchingAgents = res;
          _loadingAgents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAgents = false);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_serviceType == 'cti_training') {
      _showCoursePaymentDialog();
      return;
    }
    await _executeSubmission();
  }

  Future<void> _executeSubmission({
    bool isPaid = false,
    String? paymentMethod,
  }) async {
    setState(() => _submitting = true);
    try {
      final courseVal = _courseCtrl.text.trim();
      final payload = {
        'service_type': _serviceType,
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'primary_port': _primaryPort,
        'course_name': _serviceType == 'cti_training' ? courseVal : null,
        'payment_status': isPaid ? 'paid' : 'pending',
        'payment_method': paymentMethod ?? 'Mobile Money (Paystack)',
        'fee_paid': _serviceType == 'cti_training' ? _currentCourseFee : null,
        'details': _serviceType == 'cti_training' && courseVal.isNotEmpty
            ? 'Course Enrolment: $courseVal\nPayment Status: Paid in Full ($_currentCourseFee)\n\n${_detailsCtrl.text.trim()}'
                .trim()
            : _detailsCtrl.text.trim(),
      };

      final res = await ApiService().postPublic(
        'members/public/guest-service',
        payload,
      );
      if (mounted && res is Map && res['reference_number'] != null) {
        setState(() {
          _referenceNumber = res['reference_number'].toString();
          _selectedPortFilter = _primaryPort;
        });
        // Immediately load matching Good Standing Clearing Agents for cargo clearance
        if (_serviceType == 'clearing_agent') {
          _loadGoodStandingAgents(_primaryPort);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit request: $e')));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  String _detectCarrier(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 3) return 'MTN Mobile Money';
    final prefix = clean.substring(0, 3);
    // MTN: 024, 025, 053, 054, 055, 059
    if (['024', '025', '053', '054', '055', '059'].contains(prefix)) {
      return 'MTN Mobile Money';
    }
    // Telecel (Vodafone): 020, 050
    if (['020', '050'].contains(prefix)) {
      return 'Telecel Cash';
    }
    // AT (AirtelTigo): 026, 056, 027, 057
    if (['026', '056', '027', '057'].contains(prefix)) {
      return 'AT Money';
    }
    return 'MTN Mobile Money';
  }

  void _showCoursePaymentDialog() {
    String selectedNetwork = _detectCarrier(_phoneCtrl.text.trim());
    final momoPhoneCtrl = TextEditingController(text: _phoneCtrl.text.trim());
    bool processingPayment = false;
    String paymentStep = 'input'; // 'input' or 'waiting_approval'
    String activeTxRef = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return Container(
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _kBorder),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: paymentStep == 'waiting_approval'
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kBrown.withAlpha(20),
                            border: Border.all(color: _kBrown.withAlpha(40), width: 2),
                          ),
                          child: Icon(
                            Icons.phone_android_rounded,
                            color: _kBrown,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Awaiting Approval',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A Mobile Money prompt has been sent to ${momoPhoneCtrl.text} ($selectedNetwork).\nOpen your phone and enter your PIN to approve.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: _kMuted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Carrier specific USSD approval notice
                        () {
                          String noticeTitle = 'MTN MoMo Approval Notice';
                          String noticeText =
                              'If the prompt does not pop up, dial *170# → Option 6 (My Wallet) → Option 3 (My Approvals) on your phone to approve.';

                          if (selectedNetwork.contains('Telecel') || selectedNetwork.contains('Vodafone')) {
                            noticeTitle = 'Telecel (Vodafone) Approval Notice';
                            noticeText =
                                'If the prompt does not pop up, dial *110# → Option 4 (My Account) → Option 5 (Pending Approvals) on your phone to approve.';
                          } else if (selectedNetwork.contains('AT') || selectedNetwork.contains('Airtel')) {
                            noticeTitle = 'AT (AirtelTigo) Approval Notice';
                            noticeText =
                                'If the prompt does not pop up, dial *110# → Option 5 (My Wallet) → Pending Approvals on your phone to approve.';
                          }

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _kBrown.withAlpha(12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _kBrown.withAlpha(30)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      color: _kBrown,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      noticeTitle,
                                      style: GoogleFonts.outfit(
                                        color: _kBrown,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  noticeText,
                                  style: GoogleFonts.inter(
                                    color: _kText,
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }(),

                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _kCream,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Amount Due:',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kMuted,
                                ),
                              ),
                              Text(
                                _currentCourseFee,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _kAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: processingPayment
                                ? null
                                : () async {
                                    setDlgState(() => processingPayment = true);
                                    try {
                                      dynamic confirmRes;
                                      try {
                                        confirmRes = await ApiService().postPublic(
                                          'payments/public/confirm-momo/$activeTxRef',
                                          {},
                                        );
                                      } catch (_) {
                                        confirmRes = await ApiService().postPublic(
                                          'members/public/confirm-momo/$activeTxRef',
                                          {},
                                        );
                                      }
                                      final isPaid = confirmRes is Map && (confirmRes['is_paid'] == true || confirmRes['status'] == 'paid');
                                      if (isPaid) {
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        setState(() {
                                          _referenceNumber = activeTxRef;
                                          _selectedPortFilter = _primaryPort;
                                        });
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(
                                              content: const Text('Payment verified and course slot reserved!'),
                                              backgroundColor: _kGreen,
                                            ),
                                          );
                                        }
                                      } else {
                                        setDlgState(() => processingPayment = false);
                                        final msg = (confirmRes is Map && confirmRes['message'] != null)
                                            ? confirmRes['message'].toString()
                                            : 'Payment is still awaiting authorization on your phone. Please approve with your MoMo PIN and try again.';
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(
                                              content: Text(msg),
                                              backgroundColor: const Color(0xFFF59E0B),
                                              duration: const Duration(seconds: 4),
                                            ),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      setDlgState(() => processingPayment = false);
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                            content: Text('Payment pending: Please approve on your phone and try again.'),
                                            backgroundColor: Color(0xFFF59E0B),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: processingPayment
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                            label: Text(
                              processingPayment ? 'Verifying...' : "I've Approved — Check Now",
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10b981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setDlgState(() => paymentStep = 'input'),
                          child: Text(
                            'Change Phone Number / Network',
                            style: GoogleFonts.inter(
                              color: _kMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _kBrown.withAlpha(20),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.school_rounded, color: _kBrown, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'CTI Course Checkout',
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: _kText,
                                      ),
                                    ),
                                    Text(
                                      'Mobile Money Payment Authorization',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _kMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, color: _kMuted),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Course & Fee Summary Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _kCream,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _courseCtrl.text.trim().isNotEmpty
                                    ? _courseCtrl.text.trim()
                                    : 'CTI Customs & Trade Professional Course',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _kText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '📅 Cohort Start: $_currentCourseStartDate · $_currentCourseDurationMode',
                                style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Course Fee:',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _kMuted,
                                    ),
                                  ),
                                  Text(
                                    _currentCourseFee,
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: _kAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        Text(
                          'Mobile Money Network',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kBrown,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Payment method chips (MoMo networks only - auto selected by phone number)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'MTN Mobile Money',
                            'Telecel Cash',
                            'AT Money',
                          ].map((network) {
                            final selected = selectedNetwork == network;
                            return ChoiceChip(
                              avatar: selected
                                  ? const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white)
                                  : null,
                              label: Text(network),
                              selected: selected,
                              selectedColor: _kAccent,
                              backgroundColor: _kCream,
                              labelStyle: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : _kText,
                              ),
                              side: BorderSide(
                                color: selected ? _kAccent : _kBorder,
                                width: 1.5,
                              ),
                              onSelected: (val) {
                                if (val) setDlgState(() => selectedNetwork = network);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'Mobile Money Number (10 Digits)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: momoPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          onChanged: (val) {
                            setDlgState(() {
                              selectedNetwork = _detectCarrier(val);
                            });
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style: GoogleFonts.inter(fontSize: 14, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'e.g. 0244123456',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: _kMuted),
                            prefixIcon: Icon(Icons.phone_android_rounded, size: 18, color: _kBrown),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              child: Text(
                                selectedNetwork.split(' ').first,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _kAccent,
                                ),
                              ),
                            ),
                            filled: true,
                            fillColor: _kCream,
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _kBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _kBrown, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 14, color: _kGreen),
                            const SizedBox(width: 6),
                            Text(
                              'Secured Mobile Money Gateway (STK Push)',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _kMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: processingPayment
                                ? null
                                : () async {
                                    final phoneVal = momoPhoneCtrl.text.trim();
                                    if (phoneVal.length != 10) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please enter a valid 10-digit MoMo number'),
                                        ),
                                      );
                                      return;
                                    }
                                    setDlgState(() => processingPayment = true);
                                    try {
                                      dynamic res;
                                      try {
                                        res = await ApiService().postPublic(
                                          'members/public/initiate-momo',
                                          {
                                            'name': _nameCtrl.text.trim(),
                                            'phone': phoneVal,
                                            'email': _emailCtrl.text.trim(),
                                            'course_name': _courseCtrl.text.trim().isNotEmpty
                                                ? _courseCtrl.text.trim()
                                                : 'CTI Professional Course',
                                            'amount': _currentCourseFee,
                                            'network': selectedNetwork,
                                            'service_type': 'cti_training',
                                          },
                                        );
                                      } catch (_) {
                                        res = await ApiService().postPublic(
                                          'payments/public/initiate-momo',
                                          {
                                            'name': _nameCtrl.text.trim(),
                                            'phone': phoneVal,
                                            'email': _emailCtrl.text.trim(),
                                            'course_name': _courseCtrl.text.trim().isNotEmpty
                                                ? _courseCtrl.text.trim()
                                                : 'CTI Professional Course',
                                            'amount': _currentCourseFee,
                                            'network': selectedNetwork,
                                            'service_type': 'cti_training',
                                          },
                                        );
                                      }
                                      setDlgState(() {
                                        processingPayment = false;
                                        if (res is Map && res['reference_number'] != null) {
                                          activeTxRef = res['reference_number'].toString();
                                          paymentStep = 'waiting_approval';
                                        } else {
                                          paymentStep = 'waiting_approval';
                                          activeTxRef = 'CTI-${DateTime.now().millisecondsSinceEpoch}';
                                        }
                                      });
                                    } catch (e) {
                                      setDlgState(() {
                                        processingPayment = false;
                                        activeTxRef = 'CTI-${DateTime.now().millisecondsSinceEpoch}';
                                        paymentStep = 'waiting_approval';
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: processingPayment
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Pay $_currentCourseFee Now',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  // ── Custom App Dropdown Picker (In-App Bottom Sheet / Dialog) ─────────────
  Future<void> _showCustomPicker({
    required String title,
    required List<Map<String, dynamic>> items,
    required String selectedValue,
    required Function(String) onSelected,
  }) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    String searchQuery = '';
    final ScrollController scrollCtrl = ScrollController();

    Widget pickerContent(BuildContext ctx, StateSetter setModalState) {
      final filteredItems = items.where((item) {
        if (searchQuery.isEmpty) return true;
        final q = searchQuery.toLowerCase();
        final label = (item['label'] ?? '').toString().toLowerCase();
        final desc = (item['desc'] ?? '').toString().toLowerCase();
        final val = (item['value'] ?? '').toString().toLowerCase();
        return label.contains(q) || desc.contains(q) || val.contains(q);
      }).toList();

      return Container(
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kBrown,
                        ),
                      ),
                      if (items.length > 5) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${filteredItems.length} of ${items.length} options available',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _kMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: _kMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Divider(color: _kBorder),

            // Search input when more than 5 options exist
            if (items.length > 5) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: TextField(
                  autofocus: false,
                  onChanged: (val) =>
                      setModalState(() => searchQuery = val.trim()),
                  style: GoogleFonts.inter(fontSize: 14, color: _kText),
                  decoration: InputDecoration(
                    hintText: 'Search port, border station, or terminal...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: _kMuted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: _kBrown,
                    ),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 16,
                              color: _kMuted,
                            ),
                            onPressed: () =>
                                setModalState(() => searchQuery = ''),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Fixed-height scrollable list with visible scrollbar
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: isMobile
                    ? MediaQuery.of(context).size.height * 0.55
                    : 380,
              ),
              child: filteredItems.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 36,
                            color: _kMuted.withAlpha(150),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No matching ports found',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: _kText,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Try typing a different name or station code.',
                            style: GoogleFonts.inter(
                              color: _kMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      controller: scrollCtrl,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: scrollCtrl,
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, idx) {
                          final item = filteredItems[idx];
                          final isSelected = item['value'] == selectedValue;

                          return InkWell(
                            onTap: () {
                              onSelected(item['value'] as String);
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _kBrown.withAlpha(18)
                                    : _kCream,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? _kBrown : _kBorder,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (item['icon'] != null) ...[
                                    Icon(
                                      item['icon'] as IconData,
                                      size: 20,
                                      color: isSelected ? _kBrown : _kMuted,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['label'] as String,
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            color: isSelected
                                                ? _kBrown
                                                : _kText,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (item['desc'] != null &&
                                            (item['desc'] as String)
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            item['desc'] as String,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: _kMuted,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: _kBrown,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: pickerContent(ctx, setModalState),
          ),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Dialog(
            backgroundColor: _kCardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: pickerContent(ctx, setModalState),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 750;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Background subtle canvas
          Positioned.fill(child: Container(color: _kBg)),

          SafeArea(
            child: Column(
              children: [
                // ── Top Header with Logo at Top-Left ────────────────────────
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    border: Border(
                      bottom: BorderSide(color: _kBorder, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Back action button
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: _kBrown,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        onPressed: () =>
                            context.canPop() ? context.pop() : context.go('/'),
                        tooltip: 'Return to Home',
                      ),
                      const SizedBox(width: 6),

                      // CUBAG Logo & Brand at top left corner
                      const AppLogo(size: 32, borderRadius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'CUBAG',
                                  style: GoogleFonts.outfit(
                                    color: _kBrown,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kAccent.withAlpha(25),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'PUBLIC DESK',
                                    style: GoogleFonts.outfit(
                                      color: _kAccent,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _serviceType == 'clearing_agent'
                                  ? 'Find A Licensed Broker (Clearing Agent/Forwarder)'
                                  : 'Register A Course',
                              style: GoogleFonts.inter(
                                color: _kMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Member Login CTA (Always firmly visible on screen)
                      OutlinedButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: Icon(
                          Icons.login_rounded,
                          size: 15,
                          color: _kBrown,
                        ),
                        label: Text(
                          isMobile ? 'Sign In' : 'Member Sign In',
                          style: GoogleFonts.outfit(
                            color: _kBrown,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _kBrown.withAlpha(120),
                            width: 1.2,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable Form Body ─────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _referenceNumber != null ? 860 : 720,
                        ),
                        child: _referenceNumber != null
                            ? _buildSuccessView(isMobile)
                            : _buildFormCard(isMobile),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(bool isMobile) {
    final currentService = _kServices.firstWhere(
      (s) => s['id'] == _serviceType,
      orElse: () => _kServices.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isDark ? 40 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headline
            Text(
              _serviceType == 'clearing_agent'
                  ? 'Find A Licensed Broker (Clearing Agent/Forwarder)'
                  : 'Register A Course',
              style: GoogleFonts.outfit(
                color: _kBrown,
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _serviceType == 'clearing_agent'
                  ? 'Submit your cargo clearance details below. You will instantly be matched with accredited CUBAG licensed brokers, clearing agents, and freight forwarders across Ghana.'
                  : 'Submit your enrolment details below for CTI certification and professional courses.',
              style: GoogleFonts.inter(
                color: _kMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // ── Service Type Display (Locked to Prevent Misdirection) ─────
            _formLabel('Service Type'),
            const SizedBox(height: 8),
            _customDropdownButton(
              icon: currentService['icon'] as IconData,
              title: currentService['title'] as String,
              subtitle: currentService['desc'] as String,
              isLocked: true,
              onTap: () {},
            ),
            const SizedBox(height: 20),

            // ── Course Name Field (Shown for CTI Training Course Registration) ──
            if (_serviceType == 'cti_training') ...[
              _formLabel('Select CTI Course *'),
              const SizedBox(height: 8),
              if (_availableCourses.isNotEmpty) ...[
                _customDropdownButton(
                  icon: Icons.school_rounded,
                  title: _courseCtrl.text.isNotEmpty
                      ? _courseCtrl.text
                      : 'Choose a CTI Course',
                  subtitle: _courseCtrl.text.isNotEmpty
                      ? 'Course Fee: $_currentCourseFee · $_currentCourseDurationMode'
                      : 'Pick from courses configured by CUBAG Secretariat',
                  onTap: () {
                    final courseItems = _availableCourses.map((c) {
                      final cTitle = c['title']?.toString() ?? 'CTI Course';
                      final rawFee = (c['fee']?.toString() ?? 'GHS 1,500.00').trim();
                      final formattedFee = rawFee.toUpperCase().startsWith('GHS')
                          ? rawFee
                          : 'GHS $rawFee';
                      final cDur = c['duration']?.toString() ?? '4 Weeks';
                      final cMode = c['mode']?.toString() ?? 'Hybrid';
                      final cDate = (c['start_date'] ?? c['date'] ?? 'Upcoming').toString();
                      return {
                        'label': cTitle,
                        'value': cTitle,
                        'desc': '$formattedFee · $cDur ($cMode) · Starts $cDate',
                        'icon': Icons.school_outlined,
                      };
                    }).toList();

                    _showCustomPicker(
                      title: 'Select CTI Professional Course',
                      items: courseItems,
                      selectedValue: _courseCtrl.text,
                      onSelected: (val) {
                        setState(() {
                          _courseCtrl.text = val;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),
              ] else ...[
                _textInput(
                  controller: _courseCtrl,
                  hint: 'e.g. Customs Valuation & Tariff Classification',
                  icon: Icons.menu_book_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please specify or enter the course name'
                      : null,
                ),
                const SizedBox(height: 20),
              ],
            ],

            // ── Port / Customs Station Selector ─────────────────────────────
            _formLabel('Primary Port of Cargo Operation *'),
            const SizedBox(height: 8),
            _customDropdownButton(
              icon: Icons.anchor_rounded,
              title: _primaryPort,
              subtitle:
                  'Select destination port, border post, or air cargo station',
              onTap: () {
                final portItems = _availablePorts.isNotEmpty
                    ? _availablePorts
                          .map(
                            (p) => {
                              'label': p['name']?.toString() ?? 'Port',
                              'value': p['name']?.toString() ?? 'Port',
                              'desc':
                                  '${p['code'] ?? 'GHA'} · ${p['type'] ?? 'Port Terminal'}',
                              'icon': Icons.location_on_outlined,
                            },
                          )
                          .toList()
                    : [
                        {
                          'label': 'Accra International Airport',
                          'value': 'Accra International Airport',
                          'desc': 'Air Cargo Freight Terminal (GH-ACC)',
                          'icon': Icons.flight_land_rounded,
                        },
                        {
                          'label': 'Aflao Border Post',
                          'value': 'Aflao Border Post',
                          'desc': 'Eastern Land Frontier Border Post',
                          'icon': Icons.local_shipping_outlined,
                        },
                        {
                          'label': 'Elubo Border Post',
                          'value': 'Elubo Border Post',
                          'desc': 'Western Land Frontier Border Post',
                          'icon': Icons.local_shipping_outlined,
                        },
                        {
                          'label': 'Takoradi Port',
                          'value': 'Takoradi Port',
                          'desc': 'Western Maritime Terminal (GH-TKD)',
                          'icon': Icons.directions_boat_rounded,
                        },
                        {
                          'label': 'Tema Port',
                          'value': 'Tema Port',
                          'desc': 'Main Maritime Terminal (GH-TEM)',
                          'icon': Icons.directions_boat_rounded,
                        },
                      ];

                portItems.sort(
                  (a, b) =>
                      a['label'].toString().compareTo(b['label'].toString()),
                );

                _showCustomPicker(
                  title: 'Select Port / Clearance Station',
                  items: portItems,
                  selectedValue: _primaryPort,
                  onSelected: (val) => setState(() => _primaryPort = val),
                );
              },
            ),
            const SizedBox(height: 20),

            // ── Full Name & Company Row ────────────────────────────────────
            if (isMobile) ...[
              _formLabel('Your Full Name *'),
              const SizedBox(height: 8),
              _textInput(
                controller: _nameCtrl,
                hint: 'e.g. Kwame Mensah',
                icon: Icons.person_outline_rounded,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your full name'
                    : null,
              ),
              const SizedBox(height: 20),
              _formLabel('Company / Business Entity (Optional)'),
              const SizedBox(height: 8),
              _textInput(
                controller: _companyCtrl,
                hint: 'e.g. Accra Import Trading Ltd',
                icon: Icons.business_outlined,
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel('Your Full Name *'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _nameCtrl,
                          hint: 'e.g. Kwame Mensah',
                          icon: Icons.person_outline_rounded,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter your full name'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel('Company / Business (Optional)'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _companyCtrl,
                          hint: 'e.g. Accra Import Trading Ltd',
                          icon: Icons.business_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ── Contact Phone & Email Row ───────────────────────────────────
            if (isMobile) ...[
              _formLabel('Phone Number (10 Digits) *'),
              const SizedBox(height: 8),
              _textInput(
                controller: _phoneCtrl,
                hint: 'e.g. 0244123456',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a contact phone number';
                  }
                  final digits = v.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10) {
                    return 'Phone number must be exactly 10 digits (e.g. 0244123456)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _formLabel('Email Address *'),
              const SizedBox(height: 8),
              _textInput(
                controller: _emailCtrl,
                hint: 'e.g. info@company.com.gh',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter an email address';
                  }
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel('Phone Number (10 Digits) *'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _phoneCtrl,
                          hint: 'e.g. 0244123456',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter a contact phone number';
                            }
                            final digits = v.replaceAll(RegExp(r'\D'), '');
                            if (digits.length != 10) {
                              return 'Phone number must be exactly 10 digits (e.g. 0244123456)';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel('Email Address *'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _emailCtrl,
                          hint: 'e.g. info@company.com.gh',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter an email address';
                            }
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ── Request Details / Cargo Notes ──────────────────────────────
            _formLabel(
              _serviceType == 'clearing_agent'
                  ? 'Cargo Description & Clearance Requirements *'
                  : 'Course Notes & Enrolment Details *',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _detailsCtrl,
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please provide brief details about your cargo or request'
                  : null,
              style: GoogleFonts.inter(color: _kText, fontSize: 14),
              decoration: InputDecoration(
                hintText: _serviceType == 'clearing_agent'
                    ? 'e.g. 1x40ft container of electrical accessories arriving at Tema Port. Need assistance with ICUMS declaration, GRA duty assessment, and port delivery.'
                    : 'e.g. Enrolling 2 staff members in CTI ICUMS Classification Course for September 2026 intake.',
                hintStyle: GoogleFonts.inter(color: _kMuted, fontSize: 13),
                filled: true,
                fillColor: _kCream,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBrown, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Submit Button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _serviceType == 'clearing_agent'
                            ? 'Find Licensed Brokers Now'
                            : 'Proceed to Course Payment ($_currentCourseFee)',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customDropdownButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLocked = false,
  }) {
    return InkWell(
      onTap: isLocked ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: isLocked
              ? (_isDark ? const Color(0xFF281710) : const Color(0xFFF8F4F0))
              : _kCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLocked ? _kBrown.withAlpha(60) : _kBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _kBrown),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLocked) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kBrown.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'LOCKED',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: _kBrown,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isLocked
                  ? Icons.lock_outline_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _kBrown,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: _kBrown),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _kText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _formLabel(String label) => Text(
    label,
    style: GoogleFonts.outfit(
      color: _kBrown,
      fontSize: 13,
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _textInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      maxLength: maxLength,
      validator: validator,
      buildCounter: maxLength != null
          ? (context, {required currentLength, required isFocused, maxLength}) =>
              null
          : null,
      style: GoogleFonts.inter(color: _kText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _kMuted, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: _kMuted),
        filled: true,
        fillColor: _kCream,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kBrown, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST-SUBMISSION RESULTS VIEW: Reference + Accredited Agents in Good Standing
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSuccessView(bool isMobile) {
    final query = _agentSearchCtrl.text.trim().toLowerCase();
    final displayedAgents = _matchingAgents.where((m) {
      final role = (m['role'] ?? '').toString().toLowerCase();
      if ([
            'admin',
            'super_admin',
            'sub_admin',
            'staff',
            'system',
          ].contains(role) ||
          m['is_admin'] == true) {
        return false;
      }
      final isGood =
          (m['is_good_standing'] == true ||
              m['good_standing'] == true ||
              [
                'active',
                'approved',
              ].contains((m['status'] ?? '').toString().toLowerCase())) &&
          ![
            'pending',
            'rejected',
            'suspended',
            'expelled',
            'inactive',
          ].contains((m['status'] ?? '').toString().toLowerCase());
      if (!isGood) return false;

      if (query.isEmpty) return true;
      final name = (m['name'] ?? '').toString().toLowerCase();
      final company = (m['company'] ?? '').toString().toLowerCase();
      final memNo = (m['membership_number'] ?? '').toString().toLowerCase();
      final port = (m['primary_port'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          company.contains(query) ||
          memNo.contains(query) ||
          port.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Top Confirmation Reference Card ─────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 40 : 8),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _kGreen.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: _kGreen,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _serviceType == 'cti_training'
                              ? 'Request Logged with CUBAG Secretariat!'
                              : 'Request Logged with CUBAG Secretariat!',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _serviceType == 'cti_training'
                              ? 'CTI Reference: ${_referenceNumber != null ? _referenceNumber!.replaceAll('GSR-', 'CTI-') : 'CTI-2026-E3A678'} · Port: $_primaryPort'
                              : 'Tracking Ref: ${_referenceNumber ?? ''} · Port: $_primaryPort',
                          style: GoogleFonts.inter(
                            color: _kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 18, color: _kBrown),
                    tooltip: 'Copy Reference',
                    onPressed: () {
                      if (_referenceNumber != null) {
                        final copyText = _serviceType == 'cti_training'
                            ? _referenceNumber!.replaceAll('GSR-', 'CTI-')
                            : _referenceNumber!;
                        Clipboard.setData(
                          ClipboardData(text: copyText),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$copyText copied to clipboard!'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              if (_serviceType == 'cti_training') ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.school_rounded, color: _kBrown, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _courseCtrl.text.trim().isNotEmpty
                                  ? _courseCtrl.text.trim()
                                  : 'CTI Customs & Trade Professional Course',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _kText,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _kGreen.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Paid ($_currentCourseFee)',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _kGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _detailRow(Icons.calendar_today_rounded, 'Cohort Date', _currentCourseStartDate),
                      const SizedBox(height: 10),
                      _detailRow(Icons.timer_outlined, 'Duration & Mode', _currentCourseDurationMode),
                      const SizedBox(height: 10),
                      _detailRow(Icons.location_on_outlined, 'Training Center', 'CTI Academy, Tema Port & Zoom Online'),
                      const SizedBox(height: 10),
                      _detailRow(Icons.person_outline_rounded, 'Enrolled Participant', '${_nameCtrl.text.trim()} (${_phoneCtrl.text.trim()})'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final courseName = _courseCtrl.text.trim().isNotEmpty
                          ? _courseCtrl.text.trim()
                          : 'CTI Customs & Trade Course';
                      final ctiRef = _referenceNumber != null
                          ? _referenceNumber!.replaceAll('GSR-', 'CTI-')
                          : 'CTI-2026-E3A678';
                      await CalendarService.addEventToCalendar(
                        title: 'CUBAG CTI: $courseName',
                        description: 'CTI Reference: $ctiRef\nParticipant: ${_nameCtrl.text}\nVenue: CTI Training Center, Tema Port & Zoom',
                        location: 'CTI Training Center, Tema Port & Zoom',
                        startDate: DateTime(2026, 9, 15, 9, 0),
                        endDate: DateTime(2026, 9, 15, 16, 0),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📅 Event added to your calendar!'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.event_available_rounded, size: 20),
                    label: Text(
                      'Add to Calendar',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (_serviceType != 'cti_training') ...[  
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text(
                    '💡 Below are accredited CUBAG Clearing Agents matching your port. Click any broker below to view their verified credentials, contact details, and direct connections.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF1e40af),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_serviceType != 'cti_training') ...[  
          const SizedBox(height: 24),

          // ── 2. Accredited Clearing Agents Header & Search ──────────────────
          Container(
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 40 : 8),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACCREDITED CLEARING AGENTS',
                        style: GoogleFonts.outfit(
                          color: _kBrown,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Verified Customs Brokers',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _kText,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 14, color: _kGreen),
                        const SizedBox(width: 4),
                        Text(
                          'Good Standing Only',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Box
              Container(
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: TextField(
                  controller: _agentSearchCtrl,
                  onChanged: (val) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, color: _kText),
                  decoration: InputDecoration(
                    hintText:
                        'Search clearing agents by name, company, license #...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: _kMuted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: _kBrown,
                    ),
                    suffixIcon: _agentSearchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: _kMuted,
                            ),
                            onPressed: () {
                              _agentSearchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Port Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      [
                        'All',
                        'Accra International Airport',
                        'Aflao Border Post',
                        'Elubo Border Post',
                        'Takoradi Port',
                        'Tema Port',
                      ].map((port) {
                        final isSel = _selectedPortFilter == port;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              port,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSel ? Colors.white : _kText,
                              ),
                            ),
                            selected: isSel,
                            selectedColor: _kBrown,
                            backgroundColor: _kCream,
                            side: BorderSide(color: isSel ? _kBrown : _kBorder),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPortFilter = port);
                                _loadGoodStandingAgents(port);
                              }
                            },
                          ),
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── 3. List of Agents ─────────────────────────────────────────
              if (_loadingAgents)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: _kAccent),
                  ),
                )
              else if (displayedAgents.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 36, color: _kMuted),
                      const SizedBox(height: 8),
                      Text(
                        'No clearing agents found',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing the search box or selecting "All" ports.',
                        style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedAgents.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final agent = displayedAgents[idx];
                    return _buildAgentCard(agent);
                  },
                ),
              ],
            ),
          ),
        ],  // end of if (_serviceType != 'cti_training')

        // ── Bottom Action Buttons (always shown) ─────────────────────────────
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _referenceNumber = null;
                    _nameCtrl.clear();
                    _companyCtrl.clear();
                    _phoneCtrl.clear();
                    _emailCtrl.clear();
                    _detailsCtrl.clear();
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _kBrown, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Submit Another Request',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: _kBrown,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Return to Home',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Clearing Agent Row Card ───────────────────────────────────────────────
  Widget _buildAgentCard(Map<dynamic, dynamic> m) {
    final company =
        m['company']?.toString() ??
        m['name']?.toString() ??
        'Accredited Broker';
    final name = m['name']?.toString() ?? '';
    final memNo = m['membership_number']?.toString() ?? 'CUBAG-2026-000';
    final port = m['primary_port']?.toString() ?? 'Tema Port';
    final type = m['member_type']?.toString() ?? 'Licentiate';

    return Container(
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showAgentProfileModal(m),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kBrown.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.business_outlined,
                    color: _kBrown,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    company,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _kText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color: _kGreen,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name.isNotEmpty && name != company
                            ? '$name · $port'
                            : port,
                        style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kBrown.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              memNo,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _kBrown,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _kMuted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'View Profile & Contact',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _kAccent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: _kAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Clearing Agent Individual Details Modal ───────────────────────────────
  void _showAgentProfileModal(Map<dynamic, dynamic> m) {
    final company =
        m['company']?.toString() ??
        m['name']?.toString() ??
        'Accredited Broker';
    final name = m['name']?.toString() ?? '';
    final memNo = m['membership_number']?.toString() ?? 'CUBAG-2026-000';
    final port = m['primary_port']?.toString() ?? 'Tema Port';
    final type = m['member_type']?.toString() ?? 'Licentiate';
    final licNo = m['license_number']?.toString() ?? 'GRA-LIC-VALID';
    final phone = m['phone']?.toString() ?? '';
    final email = m['email']?.toString() ?? '';
    final location =
        m['location']?.toString() ?? 'Accra / Tema Maritime District, Ghana';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kGreen.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.verified_rounded, color: _kGreen, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                company,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Accredited CUBAG Clearing Agent',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _kGreen,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty && name != company) ...[
                      _modalDetailRow('Lead Broker / Director', name),
                      Divider(color: _kBorder, height: 16),
                    ],
                    _modalDetailRow('Membership ID', memNo),
                    Divider(color: _kBorder, height: 16),
                    _modalDetailRow('Member ID #', licNo),
                    Divider(color: _kBorder, height: 16),
                    _modalDetailRow('Port of Operation', port),
                    Divider(color: _kBorder, height: 16),
                    _modalDetailRow('Member Category', type),
                    Divider(color: _kBorder, height: 16),
                    _modalDetailRow('Office Location', location),
                    if (phone.isNotEmpty) ...[
                      Divider(color: _kBorder, height: 16),
                      _modalDetailRow('Direct Phone', phone),
                    ],
                    if (email.isNotEmpty) ...[
                      Divider(color: _kBorder, height: 16),
                      _modalDetailRow('Official Email', email),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (phone.isNotEmpty) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.phone_outlined, size: 16),
                        label: Text(
                          'Call Broker',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (email.isNotEmpty) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrown,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.email_outlined, size: 16),
                        label: Text(
                          'Send Email',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'mailto:$email?subject=Clearing%20Enquiry%20via%20CUBAG%20Portal',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Close',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modalDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _kMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kText,
            ),
          ),
        ),
      ],
    );
  }
}
