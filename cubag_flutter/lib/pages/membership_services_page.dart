import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../components/app_layout.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kDarkBrown = Color(0xFF3E2418); // Deep Dark Contrast
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = Color(0xFF2B211D); // Deep Body Text
const _kMuted = Color(0xFF6F625B); // Secondary Muted Text
const _kBorder = Color(0xFFE8DED6); // Soft Warm Border

class MembershipServicesPage extends StatefulWidget {
  const MembershipServicesPage({super.key});

  @override
  State<MembershipServicesPage> createState() => _MembershipServicesPageState();
}

class _MembershipServicesPageState extends State<MembershipServicesPage> {
  bool _loadingFees = true;
  Map<String, dynamic> _memberInfo = {};

  // 1. Upfront Registration Fee
  String _registrationFeeAmount = '600.00';
  bool _isRegFeePaid = false;

  // 2. New Membership Dues (Entrance Package)
  List<Map<String, dynamic>> _packageBreakdown = [];
  String _packageTitle = 'Clearing & Forwarding Only';
  String _packageTotal = '1620.00';
  bool _isPackageFeePaid = false;

  // 3. Annual Renewal Dues
  List<Map<String, dynamic>> _renewalBreakdown = [];
  String _renewalTitle = 'Annual Renewal Dues';
  String _renewalTotal = '2170.00';
  Map<String, dynamic>? _renewalApp;

  @override
  void initState() {
    super.initState();
    _loadMemberServices();
    SocketService().socket?.on('member_updated', _onSocketUpdate);
    SocketService().socket?.on('payment_approved', _onSocketUpdate);
    SocketService().socket?.on('fees_updated', _onSocketUpdate);
    SocketService().socket?.on('tasks_updated', _onSocketUpdate);
  }

  void _onSocketUpdate(dynamic _) {
    if (mounted) _loadMemberServices();
  }

  @override
  void dispose() {
    SocketService().socket?.off('member_updated', _onSocketUpdate);
    SocketService().socket?.off('payment_approved', _onSocketUpdate);
    SocketService().socket?.off('fees_updated', _onSocketUpdate);
    SocketService().socket?.off('tasks_updated', _onSocketUpdate);
    super.dispose();
  }

  Future<void> _loadMemberServices() async {
    try {
      final api = ApiService();
      dynamic meRes;
      dynamic docRes;
      dynamic appRes;

      try {
        final results = await Future.wait([
          api.get('/auth/me'),
          api.get('/documents/requirements'),
        ]);
        meRes = results[0];
        docRes = results[1];
      } catch (_) {}

      try {
        appRes = await api.get('/compliance/my-applications');
      } catch (_) {}

      if (mounted && meRes != null && meRes.data is Map) {
        final data =
            (meRes.data['member'] ?? meRes.data) as Map<String, dynamic>;
        _memberInfo = data;

        final rawRenBreakdown = data['renewal_fee_breakdown'];
        if (rawRenBreakdown is List) {
          _renewalBreakdown = rawRenBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
        _renewalTitle =
            data['renewal_fee_title']?.toString() ?? 'Annual Renewal Dues';
        _renewalTotal = data['renewal_fee_amount']?.toString() ?? '2170.00';
        _isPackageFeePaid = data['package_fee_paid'] == true;
        _isRegFeePaid = data['registration_fee_paid'] == true ||
            data['registration_paid'] == true ||
            data['application_fee_paid'] == true;
      }

      if (mounted && appRes != null && appRes.data is Map) {
        final apps = appRes.data['applications'];
        if (apps is List) {
          for (final a in apps) {
            if (a is Map && a['type'] == 'renewal') {
              _renewalApp = Map<String, dynamic>.from(a);
              final pAmt = double.tryParse(_renewalApp!['payment_amount']?.toString() ?? '');
              if (pAmt != null && pAmt > 0) {
                _renewalTotal = pAmt.toStringAsFixed(2);
              }
              if (_renewalApp!['fee_breakdown'] != null) {
                try {
                  final rawBd = _renewalApp!['fee_breakdown'] is String
                      ? jsonDecode(_renewalApp!['fee_breakdown'])
                      : _renewalApp!['fee_breakdown'];
                  if (rawBd is List) {
                    _renewalBreakdown = rawBd
                        .map((x) => Map<String, dynamic>.from(x as Map))
                        .toList();
                  }
                } catch (_) {}
              }
              break;
            }
          }
        }
      }

      if (mounted && docRes != null && docRes.data is Map) {
        final docData = docRes.data as Map;
        _registrationFeeAmount =
            docData['registration_fee_amount']?.toString() ?? '600.00';
        if (docData['registration_fee_paid'] == true || docData['application_fee_paid'] == true) {
          _isRegFeePaid = true;
        }

        _packageTitle =
            docData['fee_category_title']?.toString() ?? 'Clearing & Forwarding Only';
        _packageTotal =
            docData['package_fee_amount']?.toString() ??
            docData['registration_package_amount']?.toString() ??
            '1620.00';

        final rawPkgBreakdown = docData['registration_fee_breakdown'];
        if (rawPkgBreakdown is List) {
          _packageBreakdown = rawPkgBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFees = false);
  }

  String _formatScale(String? scale) {
    final s = (scale ?? '').toLowerCase();
    if (s.contains('large') || s.contains('corporate')) {
      return 'Large Corporate';
    }
    return 'SME';
  }

  String _formatDate(String? str) {
    if (str == null) return '—';
    final d = DateTime.tryParse(str);
    if (d == null) return '—';
    return '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : _kWhite;
    final textColor = isDark ? Colors.white : _kText;
    final subTextColor = isDark ? Colors.white70 : _kMuted;
    final borderColor = isDark ? const Color(0xFF4D2D20) : _kBorder;

    final memberName = authService.userName ?? 'CUBAG Member';
    final companyName = authService.userCompany ?? 'Licensed Freight Forwarder';
    final bool isPkgPaid = _isPackageFeePaid;
    final memNo = isPkgPaid
        ? ((authService.membershipNumber?.isNotEmpty == true &&
                !authService.membershipNumber!.toLowerCase().contains('pending'))
            ? authService.membershipNumber!
            : (_memberInfo['membership_number']?.toString().trim().isNotEmpty == true &&
                    !_memberInfo['membership_number'].toString().toLowerCase().contains('pending')
                ? _memberInfo['membership_number'].toString().trim()
                : 'CUBAG-2026-${(_memberInfo['id'] ?? '001').toString().padLeft(4, '0')}'))
        : 'PENDING DUES SETTLEMENT';
    final rawMemberType = (_memberInfo['member_type'] ?? _memberInfo['memberType'] ?? '').toString().toLowerCase();
    final isLicentiate = rawMemberType.contains('licentiate') || rawMemberType.contains('individual');
    final isAssociate = rawMemberType.contains('associate') || rawMemberType.contains('affiliate');
    final isCorporate = !isLicentiate && !isAssociate;

    final scaleStr = _formatScale(
      _memberInfo['company_scale'] ?? _memberInfo['member_scale'],
    );
    final verifyUrl = isPkgPaid ? 'https://cubag.org/verify-member?id=$memNo' : '';

    final rawExpiry = _memberInfo['license_expiry_date']?.toString();
    final expiry = (rawExpiry == null || rawExpiry == 'None' || rawExpiry == 'null' || rawExpiry.isEmpty) ? null : rawExpiry;
    final daysLeft = expiry != null ? DateTime.tryParse(expiry)?.difference(DateTime.now()).inDays : null;
    final bool isRenewalPaid = _memberInfo['is_renewal_paid'] == true || _memberInfo['renewal_paid'] == true;
    final bool isRenewalDueSoon = !isRenewalPaid && daysLeft != null && daysLeft <= 30 && daysLeft >= 0;
    final bool isRenewalExpired = !isRenewalPaid && daysLeft != null && daysLeft < 0;

    final String renewalStatus = _renewalApp?['status']?.toString().toLowerCase() ?? '';
    final double? renewalBillAmt = _renewalApp != null
        ? double.tryParse(_renewalApp!['payment_amount']?.toString() ?? '')
        : null;
    final bool hasCalculatedRenewalBill = !isRenewalPaid &&
        _renewalApp != null &&
        ((renewalBillAmt != null && renewalBillAmt > 0) || renewalStatus == 'payment_pending');
    final bool showRenewalFigures = isRenewalPaid || hasCalculatedRenewalBill;
    final bool isUnderReview = renewalStatus == 'submitted' || renewalStatus == 'under_review';
    final bool isRevision = renewalStatus == 'revision_requested';

    final bool isGoodStanding = _memberInfo['is_good_standing'] == true ||
        _memberInfo['good_standing'] == true ||
        _isPackageFeePaid ||
        _memberInfo['status'] == 'active' ||
        authService.goodStanding ||
        authService.membershipStatus == 'active';

    return AppLayout(
      title: 'Membership Services',
      hideSearch: false,
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Digital Membership & Profile Card ──────────────────────
              Text(
                'DIGITAL MEMBERSHIP CARD',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _kBrown,
                ),
              ),
              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, cardConstraints) {
                  final isNarrow = cardConstraints.maxWidth < 620;
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isNarrow ? 20 : 28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kBrown, _kDarkBrown],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _kDarkBrown.withAlpha(50),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isGoodStanding
                                          ? const Color(0xFF10b981).withAlpha(40)
                                          : _kOrange.withAlpha(40),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isGoodStanding
                                            ? const Color(0xFF10b981).withAlpha(80)
                                            : _kOrange.withAlpha(80),
                                      ),
                                    ),
                                    child: Text(
                                      isGoodStanding
                                          ? '🟢 ACTIVE GOOD STANDING'
                                          : '🟡 PENDING PACKAGE SETTLEMENT',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                companyName,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                memberName,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withAlpha(220),
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 24,
                                runSpacing: 12,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'MEMBERSHIP ID',
                                        style: GoogleFonts.outfit(
                                          color: _kOrange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        memNo,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isCorporate)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CLASSIFICATION',
                                          style: GoogleFonts.outfit(
                                            color: _kOrange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          scaleStr,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Divider(color: Colors.white24, height: 1),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: QrImageView(
                                      data: verifyUrl,
                                      version: QrVersions.auto,
                                      size: 72.0,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'OFFICIAL QR VERIFICATION',
                                          style: GoogleFonts.outfit(
                                            color: _kOrange,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Scan to verify member credentials and status in live directory',
                                          style: GoogleFonts.outfit(
                                            color: Colors.white.withAlpha(200),
                                            fontSize: 14,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isGoodStanding
                                                ? const Color(0xFF10b981).withAlpha(40)
                                                : _kOrange.withAlpha(40),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: isGoodStanding
                                                  ? const Color(0xFF10b981).withAlpha(80)
                                                  : _kOrange.withAlpha(80),
                                            ),
                                          ),
                                          child: Text(
                                            isGoodStanding
                                                ? '🟢 ACTIVE IN GOOD STANDING'
                                                : '🟡 PENDING PACKAGE SETTLEMENT',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      companyName,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      memberName,
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withAlpha(220),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Wrap(
                                      spacing: 24,
                                      runSpacing: 10,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'MEMBERSHIP ID',
                                              style: GoogleFonts.outfit(
                                                color: _kOrange,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              memNo,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (isCorporate)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CLASSIFICATION',
                                                style: GoogleFonts.outfit(
                                                  color: _kOrange,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                scaleStr,
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 24),

                              // ── QR Code ─────────────────────────────────────────────
                              Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: QrImageView(
                                      data: verifyUrl,
                                      version: QrVersions.auto,
                                      size: 100.0,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'SCAN TO VERIFY',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white.withAlpha(180),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // ── 2. Registered Services & Dues Breakdown ───────────────────
              Text(
                'YOUR REGISTERED SERVICES & DUES BREAKDOWN',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _kBrown,
                ),
              ),
              const SizedBox(height: 12),

              if (_loadingFees)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // ── Section 1: Registration Fee (Upfront) ──
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: borderColor, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '1. REGISTRATION FEE (ONE-TIME)',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isRegFeePaid
                                    ? const Color(0xFF10b981).withAlpha(25)
                                    : _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isRegFeePaid ? 'PAID IN FULL' : 'PENDING PAYMENT',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: _isRegFeePaid
                                      ? const Color(0xFF059669)
                                      : _kOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Paid separately upon registration before statutory documents are vetted.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: subTextColor,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Registration Form & Dossier Fee',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                'GHS $_registrationFeeAmount',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Registration Fee:',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'GHS $_registrationFeeAmount',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _kOrange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Section 2: New Membership Dues (Entrance Package) ──
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: borderColor, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '2. NEW MEMBERSHIP DUES: ${_packageTitle.toUpperCase()}',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isPackageFeePaid
                                    ? const Color(0xFF10b981).withAlpha(25)
                                    : _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isPackageFeePaid ? 'PAID IN FULL' : 'PENDING SETTLEMENT',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: _isPackageFeePaid
                                      ? const Color(0xFF059669)
                                      : _kOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Specific entrance package breakdown for your registered company classification and scope.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: subTextColor,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ..._packageBreakdown.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item['label']?.toString() ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  'GHS ${item['amount']?.toString() ?? ''}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total New Membership Dues:',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'GHS $_packageTotal',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _kOrange,
                              ),
                            ),
                          ],
                        ),
                        if (!_isPackageFeePaid) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kOrange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => context.go('/payments?fee=New Membership Dues'),
                              icon: const Icon(Icons.payment_rounded, size: 16),
                              label: const Text('Pay New Membership Dues'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Section 3: Annual Renewal Breakdown ──
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: borderColor, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                showRenewalFigures
                                    ? '3. ANNUAL RENEWAL DUES: ${_renewalTitle.toUpperCase()}'
                                    : '3. ANNUAL RENEWAL DUES',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isRenewalPaid
                                    ? const Color(0xFF10b981).withAlpha(25)
                                    : (hasCalculatedRenewalBill
                                        ? const Color(0xFFF59E0B).withAlpha(25)
                                        : (isUnderReview
                                            ? const Color(0xFFF59E0B).withAlpha(25)
                                            : (isRevision || isRenewalExpired
                                                ? const Color(0xFFEF4444).withAlpha(25)
                                                : (isRenewalDueSoon
                                                    ? const Color(0xFFF59E0B).withAlpha(25)
                                                    : _kOrange.withAlpha(25))))),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isRenewalPaid
                                    ? 'PAID & ACTIVE'
                                    : (hasCalculatedRenewalBill
                                        ? 'OFFICIAL BILL ISSUED'
                                        : (isUnderReview
                                            ? 'UNDER VETTING'
                                            : (isRevision
                                                ? 'REVISION REQUIRED'
                                                : (isRenewalExpired
                                                    ? 'RENEWAL OVERDUE'
                                                    : (isRenewalDueSoon
                                                        ? 'DUE IN $daysLeft DAYS'
                                                        : 'ASSESSMENT PENDING'))))),
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isRenewalPaid
                                      ? const Color(0xFF059669)
                                      : (hasCalculatedRenewalBill || isUnderReview
                                          ? const Color(0xFFD97706)
                                          : (isRevision || isRenewalExpired
                                              ? const Color(0xFFDC2626)
                                              : (isRenewalDueSoon
                                                  ? const Color(0xFFD97706)
                                                  : _kOrange))),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          showRenewalFigures
                              ? 'Official renewal tariff breakdown mapped strictly to your registered profile.'
                              : (isUnderReview
                                  ? 'Renewal compliance documents submitted and undergoing secretariat verification.'
                                  : (isRevision
                                      ? 'Secretariat has requested updates on your submitted renewal documents.'
                                      : 'Official renewal tariff is dynamically assessed and calculated after document upload.')),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: subTextColor,
                            height: 1.35,
                          ),
                        ),
                        if (!showRenewalFigures) ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF352016) : const Color(0xFFFBF7F4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isUnderReview
                                    ? const Color(0xFFF59E0B).withAlpha(90)
                                    : (isRevision
                                        ? const Color(0xFFDC2626).withAlpha(90)
                                        : _kOrange.withAlpha(60)),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: (isUnderReview
                                                ? const Color(0xFFF59E0B)
                                                : (isRevision ? const Color(0xFFDC2626) : _kOrange))
                                            .withAlpha(25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        isUnderReview
                                            ? Icons.hourglass_top_rounded
                                            : (isRevision
                                                ? Icons.warning_amber_rounded
                                                : Icons.assignment_outlined),
                                        color: isUnderReview
                                            ? const Color(0xFFD97706)
                                            : (isRevision ? const Color(0xFFDC2626) : _kOrange),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isUnderReview
                                                ? 'Documents Submitted & Under Vetting'
                                                : (isRevision
                                                    ? 'Document Revision Required'
                                                    : 'Renewal Figures Calculated After Document Upload'),
                                            style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            isUnderReview
                                                ? 'Your renewal statutory documents have been uploaded and are currently being audited by the secretariat. Your itemized renewal dues breakdown will be generated once vetting is completed.'
                                                : (isRevision
                                                    ? 'The secretariat has reviewed your submission and requested document updates. Please upload the revised certificates to proceed with renewal dues calculation.'
                                                    : 'Official annual renewal dues are not fixed — they are dynamically calculated after your required statutory documents and company scale are uploaded and verified by the secretariat.'),
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              height: 1.45,
                                              color: subTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kOrange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => context.go('/compliance'),
                                    icon: Icon(
                                      isUnderReview
                                          ? Icons.fact_check_outlined
                                          : (isRevision
                                              ? Icons.upload_file_rounded
                                              : Icons.cloud_upload_outlined),
                                      size: 18,
                                    ),
                                    label: Text(
                                      isUnderReview
                                          ? 'Track Renewal & Vetting Status'
                                          : (isRevision
                                              ? 'Submit Revised Documents'
                                              : 'Upload Renewal Documents to Calculate Dues'),
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          ..._renewalBreakdown.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item['label']?.toString() ?? '',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    'GHS ${item['amount']?.toString() ?? ''}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Annual Renewal Dues:',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                'GHS $_renewalTotal',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: _kOrange,
                                ),
                              ),
                            ],
                          ),
                          if (isRenewalPaid && expiry != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10b981).withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF10b981).withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Annual cycle active & paid • Valid until ${_formatDate(expiry)} ($daysLeft days remaining)',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (hasCalculatedRenewalBill) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.receipt_long_rounded, color: Color(0xFFD97706), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Official renewal bill issued • Payment of GHS $_renewalTotal is due',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () => context.go('/payments?fee=Annual%20Renewal%20Dues&amount=$_renewalTotal'),
                                icon: const Icon(Icons.payment_rounded, size: 18),
                                label: Text(
                                  'Pay Annual Renewal Dues (GHS $_renewalTotal)',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ] else if (isRenewalDueSoon && expiry != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.alarm_rounded, color: Color(0xFFD97706), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Annual renewal window open ($daysLeft days left) • Renews for 365 days preserving remaining days',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (isRenewalExpired) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626).withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFDC2626).withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Membership expired on ${_formatDate(expiry)} • Please renew to restore active standing',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: _kOrange.withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _kOrange.withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: _kOrange, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Annual renewal dues of GHS $_renewalTotal are scheduled for your active membership tier.',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // ── Quick Action Button ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/compliance'),
                  icon: const Icon(Icons.folder_shared_outlined, size: 20),
                  label: const Text('Manage Compliance & Documents'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBrown,
                    side: const BorderSide(color: _kBrown, width: 1.5),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
