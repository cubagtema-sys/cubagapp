import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../components/app_logo.dart';

// Dynamic Palette
bool get _isDark => ThemeService.instance.isDark;
Color get _kBrown => const Color(0xFF6B3E26);
Color get _kAccent => const Color(0xFFFF5000);
Color get _kBg => _isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8F4F0);
Color get _kCardBg => _isDark ? const Color(0xFF281710) : Colors.white;
Color get _kCream =>
    _isDark ? const Color(0xFF4D2D20) : const Color(0xFFF8F4F0);
Color get _kBorder =>
    _isDark ? const Color(0xFF4D2D20) : const Color(0xFFF8F4F0);
Color get _kText => _isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
Color get _kMuted =>
    _isDark ? const Color(0xFFC8ADA0) : const Color(0xFF7A6B63);
Color get _kGreen => const Color(0xFF2E7D32);
Color get _kRed => const Color(0xFFC62828);

class ComplaintsPortalPage extends StatefulWidget {
  final int initialTab;
  final String? initialTrackingId;

  const ComplaintsPortalPage({
    super.key,
    this.initialTab = 0,
    this.initialTrackingId,
  });

  @override
  State<ComplaintsPortalPage> createState() => _ComplaintsPortalPageState();
}

class _ComplaintsPortalPageState extends State<ComplaintsPortalPage> {
  late int _activeTab; // 0 = Lodge Complaint, 1 = Track Complaint
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _entityCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Search Controller for Tracking
  final _trackCtrl = TextEditingController();

  // Form Selections
  String _selectedCategory = 'Broker Misconduct';
  String _selectedPort = 'Accra International Airport';

  bool _submitting = false;
  bool _tracking = false;
  String? _newComplaintId;
  Map<String, dynamic>? _trackedComplaint;
  String? _trackError;

  static const List<String> _kCategories = [
    'Broker Misconduct',
    'Port Clearance Delays & Demurrage',
    'GRA / Customs Tariff & Valuation Dispute',
    'Unlicensed Broker / Impersonation Report',
    'Secretariat & Association Service Issue',
    'General Trade & Shipping Grievance',
  ];

  static const List<String> _kPorts = [
    'Accra International Airport',
    'Aflao Border Port',
    'Elubo Border Port',
    'Paga Border Port',
    'Takoradi Port',
    'Tema Port',
  ];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    if (widget.initialTrackingId != null &&
        widget.initialTrackingId!.isNotEmpty) {
      _activeTab = 1;
      _trackCtrl.text = widget.initialTrackingId!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _trackComplaint());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _entityCtrl.dispose();
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _trackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
        '/complaints/submit',
        data: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim().toLowerCase(),
          'phone': _phoneCtrl.text.trim(),
          'category': _selectedCategory,
          'port': _selectedPort,
          'target_entity': _entityCtrl.text.trim(),
          'subject': _subjectCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final compId = res.data['complaint_id']?.toString() ?? 'CMP-2026';
        setState(() {
          _submitting = false;
          _newComplaintId = compId;
        });
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data['message']?.toString() ?? 'Submission failed',
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Network error submitting complaint. Please try again.',
          ),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  Future<void> _trackComplaint() async {
    final query = _trackCtrl.text.trim().toUpperCase();
    if (query.isEmpty) {
      setState(() {
        _trackError =
            'Please enter your Complaint Tracking ID (e.g. CMP-2026-12345).';
        _trackedComplaint = null;
      });
      return;
    }

    setState(() {
      _tracking = true;
      _trackError = null;
    });

    try {
      final res = await ApiService().getPublic('complaints/track/$query');
      if (!mounted) return;
      if (res != null && res['success'] == true && res['data'] != null) {
        setState(() {
          _trackedComplaint = res['data'] as Map<String, dynamic>;
          _trackError = null;
          _tracking = false;
        });
      } else {
        setState(() {
          _trackedComplaint = null;
          _trackError =
              res?['message']?.toString() ??
              'No complaint found with ID: $query';
          _tracking = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _trackedComplaint = null;
        _trackError =
            'Unable to fetch complaint status. Please verify the ID and try again.';
        _tracking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            _buildTopBar(isMobile),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 32,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Eyebrow & Headline
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _kAccent.withAlpha(20),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _kAccent.withAlpha(50),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.support_agent_rounded,
                                size: 14,
                                color: _kAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'STAKEHOLDER GRIEVANCE MECHANISM',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: _kAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Public Complaints & Dispute Portal',
                          style: GoogleFonts.outfit(
                            fontSize: isMobile ? 24 : 30,
                            fontWeight: FontWeight.w900,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Lodge issues with shipping lines, terminal operators, customs bottlenecks or port authorities for official CUBAG advocacy and resolution.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 15 : 16,
                            color: _kMuted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Tab selector
                        _buildTabSelector(),
                        const SizedBox(height: 24),

                        // Active Tab View
                        if (_activeTab == 0)
                          _newComplaintId != null
                              ? _buildSuccessCard(isMobile)
                              : _buildLodgeForm(isMobile)
                        else
                          _buildTrackingView(isMobile),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: _kCardBg,
        border: Border(bottom: BorderSide(color: _kBorder, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: _isDark ? Colors.white : _kBrown,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            tooltip: 'Return to Home',
          ),
          const SizedBox(width: 6),
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
                        color: _isDark ? Colors.white : _kBrown,
                        fontSize: 17,
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
                        'GRIEVANCE DESK',
                        style: GoogleFonts.outfit(
                          color: _kAccent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Complaints & Tracking Order',
                  style: GoogleFonts.inter(
                    color: _isDark ? Colors.white.withAlpha(220) : _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/login'),
            icon: Icon(
              Icons.login_rounded,
              size: 15,
              color: _isDark ? Colors.white : _kBrown,
            ),
            label: Text(
              isMobile ? 'Sign In' : 'Member Sign In',
              style: GoogleFonts.outfit(
                color: _isDark ? Colors.white : _kBrown,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: _isDark
                    ? Colors.white.withAlpha(120)
                    : _kBrown.withAlpha(120),
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
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              title: 'Lodge A Complaint',
              icon: Icons.edit_note_rounded,
              isSelected: _activeTab == 0,
              onTap: () => setState(() => _activeTab = 0),
            ),
          ),
          Expanded(
            child: _tabButton(
              title: 'Track Complaint Order',
              icon: Icons.track_changes_rounded,
              isSelected: _activeTab == 1,
              onTap: () => setState(() => _activeTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kBrown.withAlpha(50),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : _kMuted),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ① LODGE COMPLAINT FORM
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildLodgeForm(bool isMobile) {
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
            Text(
              'Lodge an Official Complaint / Grievance',
              style: GoogleFonts.outfit(
                color: _kBrown,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your submission will be immediately assigned to the CUBAG Secretariat Standing Committee.',
              style: GoogleFonts.inter(color: _kMuted, fontSize: 14.5),
            ),
            const SizedBox(height: 24),

            // Complainant Name & Contact
            if (isMobile) ...[
              _formLabel('Your Full Name *'),
              const SizedBox(height: 8),
              _textInput(
                controller: _nameCtrl,
                hint: 'e.g. Kwame Mensah',
                icon: Icons.person_outline_rounded,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your full name'
                    : null,
              ),
              const SizedBox(height: 16),
              _formLabel('Phone Number (10 Digits) *'),
              const SizedBox(height: 8),
              _textInput(
                controller: _phoneCtrl,
                hint: 'e.g. 0244123456',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your phone number';
                  }
                  if (v.trim().length != 10) {
                    return 'Phone number must be exactly 10 digits';
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
                        _formLabel('Your Full Name *'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _nameCtrl,
                          hint: 'e.g. Kwame Mensah',
                          icon: Icons.person_outline_rounded,
                          formatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z\s]'),
                            ),
                          ],
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
                        _formLabel('Phone Number (10 Digits) *'),
                        const SizedBox(height: 8),
                        _textInput(
                          controller: _phoneCtrl,
                          hint: 'e.g. 0244123456',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.number,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your phone number';
                            }
                            if (v.trim().length != 10) {
                              return 'Phone number must be exactly 10 digits';
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
            const SizedBox(height: 16),

            // Email Address
            _formLabel('Email Address (for Status Updates) *'),
            const SizedBox(height: 8),
            _textInput(
              controller: _emailCtrl,
              hint: 'e.g. kwame@company.com.gh',
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
            const SizedBox(height: 20),

            // Category Dropdown
            _formLabel('Complaint Category *'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: _kBrown),
                  items: _kCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            style: GoogleFonts.inter(
                              color: _kText,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Port of Incident
            _formLabel('Primary Port / Clearance Station *'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedPort,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: _kBrown),
                  items: _kPorts
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p,
                            style: GoogleFonts.inter(
                              color: _kText,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPort = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Target Entity / Broker / Agency (Optional)
            _formLabel(
              'Entity, Clearing Agency, or Officer Involved (Optional)',
            ),
            const SizedBox(height: 8),
            _textInput(
              controller: _entityCtrl,
              hint: 'e.g. Alpha Freight Services Ltd or Officer / Broker Name',
              icon: Icons.business_outlined,
            ),
            const SizedBox(height: 20),

            // Subject / Title
            _formLabel('Complaint Subject / Summary *'),
            const SizedBox(height: 8),
            _textInput(
              controller: _subjectCtrl,
              hint:
                  'e.g. Unauthorized Demurrage Surcharge at Tema Port Container Terminal',
              icon: Icons.title_rounded,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter a brief subject'
                  : null,
            ),
            const SizedBox(height: 20),

            // Description
            _formLabel('Detailed Description of Incident / Evidence *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descCtrl,
              maxLines: 5,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please describe the issue in detail'
                  : null,
              style: GoogleFonts.inter(color: _kText, fontSize: 16),
              decoration: InputDecoration(
                hintText:
                    'Provide full details including declaration numbers, BL numbers, dates, personnel names, and financial amounts involved...',
                hintStyle: GoogleFonts.inter(color: _kMuted, fontSize: 15),
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

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitComplaint,
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
                        'Submit Formal Complaint',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
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

  // ──────────────────────────────────────────────────────────────────────────
  // ② POST-SUBMISSION SUCCESS VIEW
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSuccessCard(bool isMobile) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      'Complaint Logged Successfully!',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your formal grievance is now registered with the CUBAG Secretariat.',
                      style: GoogleFonts.inter(color: _kMuted, fontSize: 14.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: _kBorder),
          const SizedBox(height: 20),

          Text(
            'YOUR COMPLAINT TRACKING ID:',
            style: GoogleFonts.outfit(
              color: _kMuted,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _kCream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_rounded, color: _kBrown, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    _newComplaintId ?? '',
                    style: GoogleFonts.spaceMono(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kBrown,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: _kBrown, size: 18),
                  tooltip: 'Copy Tracking ID',
                  onPressed: () {
                    if (_newComplaintId != null) {
                      Clipboard.setData(ClipboardData(text: _newComplaintId!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Complaint ID copied to clipboard!'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _newComplaintId = null;
                      _nameCtrl.clear();
                      _emailCtrl.clear();
                      _phoneCtrl.clear();
                      _entityCtrl.clear();
                      _subjectCtrl.clear();
                      _descCtrl.clear();
                    });
                  },
                  icon: Icon(Icons.add_rounded, size: 16, color: _kBrown),
                  label: Text(
                    'Lodge Another',
                    style: GoogleFonts.outfit(
                      color: _kBrown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _kBrown.withAlpha(120)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final id = _newComplaintId;
                    setState(() {
                      _activeTab = 1;
                      _trackCtrl.text = id ?? '';
                      _newComplaintId = null;
                    });
                    _trackComplaint();
                  },
                  icon: const Icon(Icons.track_changes_rounded, size: 16),
                  label: Text(
                    'Track Live Status',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ③ TRACK COMPLAINT ORDER VIEW
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTrackingView(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tracking Search Bar Card
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
              Text(
                'Enter Complaint Tracking ID',
                style: GoogleFonts.outfit(
                  color: _kBrown,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Format: CMP-YYYY-XXXXX (found on your submission receipt)',
                style: GoogleFonts.inter(color: _kMuted, fontSize: 14),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _kCream,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: TextField(
                        controller: _trackCtrl,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _trackComplaint(),
                        style: GoogleFonts.spaceMono(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. CMP-2026-92945',
                          hintStyle: GoogleFonts.spaceMono(
                            fontSize: 15,
                            color: _kMuted,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: _kBrown,
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _tracking ? null : _trackComplaint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrown,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _tracking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Track Order',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),

              if (_trackError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _kRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kRed.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: _kRed, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _trackError!,
                          style: GoogleFonts.inter(color: _kRed, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Live Complaint Tracking Order Status Result Card
        if (_trackedComplaint != null)
          _buildTrackingResultCard(_trackedComplaint!, isMobile),
      ],
    );
  }

  Widget _buildTrackingResultCard(Map<String, dynamic> c, bool isMobile) {
    final status = (c['status'] ?? 'Received').toString();
    final timeline = (c['timeline'] as List<dynamic>?) ?? [];

    Color statusColor = _kAccent;
    if (['resolved', 'closed'].contains(status.toLowerCase())) {
      statusColor = _kGreen;
    }
    if (['investigating', 'under review'].contains(status.toLowerCase())) {
      statusColor = const Color(0xFF1565C0);
    }

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Status Badge Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPLAINT TRACKING ORDER',
                      style: GoogleFonts.outfit(
                        color: _kBrown,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      c['complaint_id']?.toString() ?? '',
                      style: GoogleFonts.spaceMono(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withAlpha(60)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: _kBorder),
          const SizedBox(height: 20),

          // Details Grid
          _detailRow('Subject / Title', c['subject']?.toString() ?? '—'),
          _detailRow('Category', c['category']?.toString() ?? '—'),
          _detailRow('Port Station', c['port']?.toString() ?? '—'),
          if (c['target_entity'] != null &&
              c['target_entity'].toString().isNotEmpty)
            _detailRow('Involved Entity', c['target_entity'].toString()),
          _detailRow(
            'Assigned Committee',
            c['assigned_to']?.toString() ?? 'Secretariat Grievance Committee',
          ),
          _detailRow(
            'Date Logged',
            c['created_at']?.toString().split('T').first ?? '—',
          ),

          const SizedBox(height: 24),
          Text(
            'LIVE INVESTIGATION TIMELINE',
            style: GoogleFonts.outfit(
              color: _kBrown,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),

          // Stepper Timeline
          ...timeline.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value as Map<String, dynamic>;
            final isDone = item['done'] == true;
            final isActive = item['active'] == true;
            final isLast = idx == timeline.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? _kGreen
                              : (isActive ? _kAccent : _kCream),
                          border: Border.all(
                            color: isDone
                                ? _kGreen
                                : (isActive ? _kAccent : _kBorder),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Text(
                                  '${item['step'] ?? idx + 1}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.white : _kMuted,
                                  ),
                                ),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: isDone ? _kGreen.withAlpha(120) : _kBorder,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item['title']?.toString() ?? '',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDone || isActive ? _kText : _kMuted,
                                ),
                              ),
                              if (item['date'] != null &&
                                  item['date'] != 'Pending')
                                Text(
                                  item['date'].toString(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: _kMuted,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['desc']?.toString() ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              color: _kMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          if (c['resolution_notes'] != null &&
              c['resolution_notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kGreen.withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, color: _kGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Official Secretariat Resolution Notice:',
                        style: GoogleFonts.outfit(
                          color: _kGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c['resolution_notes'].toString(),
                    style: GoogleFonts.inter(
                      color: _kText,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                color: _kMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: _kText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formLabel(String label) => Text(
    label,
    style: GoogleFonts.outfit(
      color: _kBrown,
      fontSize: 15,
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _textInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      validator: validator,
      style: GoogleFonts.inter(color: _kText, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _kMuted, fontSize: 15),
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
}
