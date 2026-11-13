import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../components/app_layout.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = CubagColors.action; // Primary Orange CTA
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = CubagColors.ink; // Deep Body Text
const _kMuted = CubagColors.muted; // Secondary Muted Text
const _kBorder = CubagColors.line; // Soft Warm Border

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
  double _renewalAmountPaid = 0.0;
  double _renewalBalanceDue = 0.0;
  bool _allowInstallments = true;
  double _minInstallmentAmount = 0.0;
  bool _isPartiallyPaid = false;
  List<dynamic> _installments = [];

  @override
  void initState() {
    super.initState();
    final auth = AuthService();
    _isPackageFeePaid = auth.isPackageFeePaid ||
        auth.goodStanding ||
        auth.membershipStatus == 'active' ||
        (auth.membershipNumber?.isNotEmpty == true &&
            !auth.membershipNumber!.toLowerCase().contains('pending'));
    _isRegFeePaid = auth.isRegistrationFeePaid;
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
        if (rawRenBreakdown is List && rawRenBreakdown.isNotEmpty) {
          _renewalBreakdown = rawRenBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
        if (data['renewal_fee_title'] != null && data['renewal_fee_title'].toString().isNotEmpty) {
          _renewalTitle = data['renewal_fee_title'].toString();
        }
        if (data['renewal_fee_amount'] != null) {
          final amt = double.tryParse(data['renewal_fee_amount'].toString());
          if (amt != null && amt > 0) {
            _renewalTotal = amt.toStringAsFixed(2);
          }
        }
        _renewalAmountPaid = double.tryParse(data['renewal_amount_paid']?.toString() ?? '0') ?? 0.0;
        _renewalBalanceDue = double.tryParse(data['renewal_balance_due']?.toString() ?? '') ??
            (double.tryParse(_renewalTotal) != null ? (double.parse(_renewalTotal) - _renewalAmountPaid).clamp(0.0, double.infinity) : 0.0);
        _allowInstallments = data['renewal_allow_installments'] != false;
        _minInstallmentAmount = double.tryParse(data['renewal_min_installment_amount']?.toString() ?? '0') ?? 0.0;
        _isPartiallyPaid = data['renewal_is_partially_paid'] == true;
        _installments = ApiService.ensureList(data['renewal_installments']);

        _isPackageFeePaid = data['package_fee_paid'] == true;
        _isRegFeePaid = data['registration_fee_paid'] == true ||
            data['registration_paid'] == true ||
            data['application_fee_paid'] == true;
      }

      if (mounted && appRes != null && appRes.data is Map) {
        final apps = appRes.data['applications'];
        if (apps is List) {
          Map<String, dynamic>? candidate;
          for (final a in apps) {
            if (a is Map && a['type'] == 'renewal') {
              final m = Map<String, dynamic>.from(a);
              final status = m['status']?.toString().toLowerCase();
              final pAmt = double.tryParse(m['payment_amount']?.toString() ?? '');
              if (candidate == null) {
                candidate = m;
              } else if (candidate['status'] == 'draft' && status != 'draft') {
                candidate = m;
              } else if ((pAmt != null && pAmt > 0) &&
                  (double.tryParse(candidate['payment_amount']?.toString() ?? '') ?? 0) <= 0) {
                candidate = m;
              }
            }
          }

          if (candidate != null) {
            _renewalApp = candidate;
            final pAmt = double.tryParse(_renewalApp!['payment_amount']?.toString() ?? '');
            if (pAmt != null && pAmt > 0) {
              _renewalTotal = pAmt.toStringAsFixed(2);
            }
            if (_renewalApp!['amount_paid'] != null) {
              _renewalAmountPaid = double.tryParse(_renewalApp!['amount_paid']?.toString() ?? '0') ?? _renewalAmountPaid;
            }
            if (_renewalApp!['allow_installments'] != null) {
              _allowInstallments = _renewalApp!['allow_installments'] == true || _renewalApp!['allow_installments'].toString().toLowerCase() == 'true';
            }
            if (_renewalApp!['min_installment_amount'] != null) {
              _minInstallmentAmount = double.tryParse(_renewalApp!['min_installment_amount']?.toString() ?? '0') ?? _minInstallmentAmount;
            }
            final curTot = double.tryParse(_renewalTotal) ?? 0.0;
            _renewalBalanceDue = (curTot - _renewalAmountPaid).clamp(0.0, double.infinity);
            if (_renewalApp!['status'] == 'partially_paid' || (_renewalAmountPaid > 0.01 && _renewalBalanceDue > 0.01)) {
              _isPartiallyPaid = true;
            }

            if (_renewalApp!['bill_title'] != null && _renewalApp!['bill_title'].toString().trim().isNotEmpty) {
              _renewalTitle = _renewalApp!['bill_title'].toString().trim();
            }
            if (_renewalApp!['fee_breakdown'] != null) {
              try {
                final rawBd = _renewalApp!['fee_breakdown'] is String
                    ? jsonDecode(_renewalApp!['fee_breakdown'])
                    : _renewalApp!['fee_breakdown'];
                if (rawBd is List && rawBd.isNotEmpty) {
                  _renewalBreakdown = rawBd
                      .map((x) => Map<String, dynamic>.from(x as Map))
                      .toList();
                }
              } catch (_) {}
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

      // Reconcile breakdown line items with total renewal amount.
      // If there is an amount discrepancy (e.g. hardcoded 1.00 tariff vs 25.00 bill issued by admin),
      // rebuild the line items to match the actual billed amount so member sees exact bill.
      final curTotalAmt = double.tryParse(_renewalTotal) ?? 0.0;
      if (curTotalAmt > 0) {
        double itemsSum = 0.0;
        for (final item in _renewalBreakdown) {
          final a = double.tryParse(item['amount']?.toString().replaceAll(',', '') ?? '0') ?? 0.0;
          itemsSum += a;
        }
        if ((itemsSum - curTotalAmt).abs() > 0.01) {
          final itemLabel = _renewalTitle.isNotEmpty &&
                  !_renewalTitle.toLowerCase().contains('licentiate') &&
                  !_renewalTitle.toLowerCase().contains('associate')
              ? _renewalTitle
              : 'Annual Renewal Dues';
          _renewalBreakdown = [
            {'label': itemLabel, 'amount': curTotalAmt.toStringAsFixed(2)}
          ];
          if (_renewalTitle.toLowerCase().contains('licentiate') ||
              _renewalTitle.toLowerCase().contains('associate')) {
            _renewalTitle = 'Annual Renewal Dues';
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFees = false);
  }

  /// "GH₵ 1,620.00" from a number or numeric string.
  String _ghs(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;
    final parts = n.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'GH₵ $whole.${parts[1]}';
  }

  /// Server titles arrive in capitals ("CLEARING & FORWARDING ONLY (SMEs)").
  String _sentence(String t) {
    if (t.isEmpty || t != t.toUpperCase().replaceAll('SMES', 'SMEs')) return t;
    final keep = {'SMEs', 'SME', 'CUBAG', 'CTI', 'CPD'};
    var first = true;
    return t.split(' ').map((w) {
      final bare = w.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (keep.contains(bare) || bare.isEmpty) return w;
      final out = first ? w[0] + w.substring(1).toLowerCase() : w.toLowerCase();
      first = false;
      return out;
    }).join(' ');
  }

  /// Show line items only when they add up to the total; otherwise the
  /// total alone (unset fees used to show GH₵ 0.00 lines under a real total).
  List<Map<String, dynamic>> _itemsMatchingTotal(List<Map<String, dynamic>> items, String total) {
    final t = double.tryParse(total.replaceAll(',', '')) ?? 0;
    final sum = items.fold<double>(0, (a, i) => a + (double.tryParse(i['amount']?.toString().replaceAll(',', '') ?? '') ?? 0));
    return (sum - t).abs() < 0.01 ? items : const [];
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

  String _stripMembershipCategories(String input) {
    return input
        .replaceAll(RegExp(r'\b(Associate|Licentiate|Corporate)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : _kWhite;
    final textColor = isDark ? const Color(0xFFFFF8F3) : _kText;
    final subTextColor = isDark ? const Color(0xFFC8ADA0) : _kMuted;
    final borderColor = isDark ? const Color(0xFF3D261C) : _kBorder;

    final memberName = authService.userName ?? (_memberInfo['name']?.toString() ?? 'CUBAG Member');
    final companyName = authService.userCompany ?? (_memberInfo['company']?.toString() ?? 'Licensed Freight Forwarder');

    final bool isPkgPaid = _isPackageFeePaid ||
        authService.isPackageFeePaid ||
        authService.goodStanding ||
        authService.membershipStatus == 'active' ||
        _memberInfo['package_fee_paid'] == true ||
        _memberInfo['is_good_standing'] == true;

    final String? resolvedMemNo = (authService.membershipNumber?.isNotEmpty == true &&
            !authService.membershipNumber!.toLowerCase().contains('pending'))
        ? authService.membershipNumber
        : (_memberInfo['membership_number']?.toString().trim().isNotEmpty == true &&
                !_memberInfo['membership_number'].toString().toLowerCase().contains('pending')
            ? _memberInfo['membership_number'].toString().trim()
            : null);

    final memNo = resolvedMemNo ??
        (isPkgPaid
            ? 'CUBAG-2026-${(_memberInfo['id'] ?? '001').toString().padLeft(4, '0')}'
            : (_loadingFees ? '—' : 'PENDING DUES SETTLEMENT'));

    final rawMemberType = (_memberInfo['member_type'] ?? _memberInfo['memberType'] ?? authService.memberType ?? '').toString().toLowerCase();
    final isLicentiate = rawMemberType.contains('licentiate') || rawMemberType.contains('individual');
    final isAssociate = rawMemberType.contains('associate') || rawMemberType.contains('affiliate');
    final isCorporate = !isLicentiate && !isAssociate;

    final rawScale = _memberInfo['company_scale'] ?? _memberInfo['member_scale'] ?? authService.companyScale;
    final scaleStr = rawScale != null ? _formatScale(rawScale) : (_loadingFees ? '—' : 'SME');
    final verifyUrl = (resolvedMemNo != null && resolvedMemNo.isNotEmpty)
        ? 'https://cubag-api-server.fly.dev/#/verify-member?id=$resolvedMemNo'
        : (isPkgPaid && memNo != '—' && !memNo.contains('PENDING') ? 'https://cubag-api-server.fly.dev/#/verify-member?id=$memNo' : '');

    final rawExpiry = _memberInfo['license_expiry_date']?.toString();
    final expiry = (rawExpiry == null || rawExpiry == 'None' || rawExpiry == 'null' || rawExpiry.isEmpty) ? null : rawExpiry;
    final daysLeft = expiry != null ? DateTime.tryParse(expiry)?.difference(DateTime.now()).inDays : null;
    final String renewalStatus = _renewalApp?['status']?.toString().toLowerCase() ?? '';
    final bool isRenewalPaid = _memberInfo['is_renewal_paid'] == true ||
        _memberInfo['renewal_paid'] == true ||
        renewalStatus == 'approved' ||
        renewalStatus == 'payment_confirmed';
    final bool isRenewalSubmitted = _memberInfo['renewal_payment_submitted'] == true ||
        renewalStatus == 'payment_submitted';
    final bool isBillPaid = isRenewalPaid || isRenewalSubmitted;
    final bool isRenewalDueSoon = !isBillPaid && daysLeft != null && daysLeft <= 30 && daysLeft >= 0;
    final bool isRenewalExpired = !isBillPaid && daysLeft != null && daysLeft < 0;

    final double? renewalBillAmt = (_renewalApp != null && _renewalApp!['payment_amount'] != null)
        ? double.tryParse(_renewalApp!['payment_amount']?.toString() ?? '')
        : double.tryParse(_memberInfo['renewal_fee_amount']?.toString() ?? '');
    final bool hasCalculatedRenewalBill = 
        (_renewalApp != null &&
        ((renewalBillAmt != null && renewalBillAmt > 0) ||
         _renewalBreakdown.isNotEmpty ||
         renewalStatus == 'awaiting_payment' ||
         renewalStatus == 'payment_pending' ||
         renewalStatus == 'payment_submitted')) ||
        (_renewalBreakdown.isNotEmpty) ||
        (renewalBillAmt != null && renewalBillAmt > 0);
    final bool showRenewalFigures = isBillPaid || hasCalculatedRenewalBill;
    final bool isUnderReview = renewalStatus == 'submitted' || renewalStatus == 'under_review';
    final bool isRevision = renewalStatus == 'revision_requested';

    final bool isGoodStanding = _memberInfo['is_good_standing'] == true ||
        _memberInfo['good_standing'] == true ||
        _isPackageFeePaid ||
        _memberInfo['status'] == 'active' ||
        authService.goodStanding ||
        authService.membershipStatus == 'active';

    return AppLayout(
      title: 'Membership',
      hideSearch: false,
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Digital Membership & Profile Card ──────────────────────
              Text('Your membership card', style: CubagType.title),
              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, cardConstraints) {
                  final isNarrow = cardConstraints.maxWidth < 620;
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isNarrow ? 20 : 28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF381F14), Color(0xFF1E110A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF5A3522), width: 1.0),
                    ),
                    child: isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isGoodStanding
                                      ? CubagColors.valid.withAlpha(30)
                                      : _kOrange.withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isGoodStanding
                                        ? CubagColors.valid.withAlpha(120)
                                        : _kOrange.withAlpha(120),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isGoodStanding
                                            ? CubagColors.valid
                                            : _kOrange,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isGoodStanding
                                          ? 'Active, in good standing'
                                          : (_loadingFees ? 'Checking status…' : 'Membership dues not yet paid'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                companyName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                memberName,
                                style: TextStyle(
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
                                        'Membership ID',
                                        style: TextStyle(
                                          color: AppColors.accentOrangeText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        memNo,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          fontFeatures: const [FontFeature.tabularFigures()],
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
                                          'Classification',
                                          style: TextStyle(
                                            color: AppColors.accentOrangeText,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          scaleStr,
                                          style: TextStyle(
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
                              const Divider(color: Colors.white12, height: 1),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: verifyUrl.isNotEmpty
                                        ? QrImageView(
                                            data: verifyUrl,
                                            version: QrVersions.auto,
                                            size: 72.0,
                                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                                          )
                                        : const SizedBox(
                                            width: 72,
                                            height: 72,
                                            child: Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: _kOrange,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Verification code',
                                          style: TextStyle(
                                            color: AppColors.accentOrangeText,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Anyone can scan this to confirm your membership is valid.',
                                          style: TextStyle(
                                            color: Colors.white.withAlpha(200),
                                            fontSize: 13,
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isGoodStanding
                                            ? CubagColors.valid.withAlpha(30)
                                            : _kOrange.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isGoodStanding
                                              ? CubagColors.valid.withAlpha(120)
                                              : _kOrange.withAlpha(120),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isGoodStanding
                                                  ? CubagColors.valid
                                                  : _kOrange,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isGoodStanding
                                                ? 'Active, in good standing'
                                                : (_loadingFees ? 'Checking status…' : 'Membership dues not yet paid'),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      companyName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      memberName,
                                      style: TextStyle(
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
                                              'Membership ID',
                                              style: TextStyle(
                                                color: AppColors.accentOrangeText,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              memNo,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                fontFeatures: const [FontFeature.tabularFigures()],
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
                                                'Classification',
                                                style: TextStyle(
                                                  color: AppColors.accentOrangeText,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                scaleStr,
                                                style: TextStyle(
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
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: verifyUrl.isNotEmpty
                                        ? QrImageView(
                                            data: verifyUrl,
                                            version: QrVersions.auto,
                                            size: 100.0,
                                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                                          )
                                        : const SizedBox(
                                            width: 100,
                                            height: 100,
                                            child: Center(
                                              child: SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: _kOrange,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Scan to verify',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(180),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
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
              Text('Fees and dues', style: CubagType.title),
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
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderColor, width: 1.0),
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
                                'Registration fee',
                                style: TextStyle(
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
                                    ? CubagColors.valid.withAlpha(25)
                                    : _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isRegFeePaid ? 'Paid' : 'Not yet paid',
                                style: TextStyle(
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
                          'Paid once, when you apply, before your documents are checked.',
                          style: TextStyle(
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
                              Expanded(
                                child: Text(
                                  'Registration form',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _ghs(_registrationFeeAmount),
                                style: TextStyle(
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
                              'Total',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              _ghs(_registrationFeeAmount),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accentOrangeText,
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
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderColor, width: 1.0),
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
                                'New membership dues',
                                style: TextStyle(
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
                                    ? CubagColors.valid.withAlpha(25)
                                    : _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isPackageFeePaid ? 'Paid' : 'Not yet paid',
                                style: TextStyle(
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
                          'One-time package for ${_sentence(_packageTitle)}.',
                          style: TextStyle(
                            fontSize: 14,
                            color: subTextColor,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ..._itemsMatchingTotal(_packageBreakdown, _packageTotal).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item['label']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  _ghs(item['amount']?.toString() ?? ''),
                                  style: TextStyle(
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
                              'Total',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              _ghs(_packageTotal),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accentOrangeText,
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
                              label: const Text('Pay membership dues'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                if (isPkgPaid) ...[
                  const SizedBox(height: 20),

                  // ── Section 3: Annual Renewal Breakdown ──
                  Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderColor, width: 1.0),
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
                                    ? (_stripMembershipCategories(_renewalTitle).isNotEmpty &&
                                            !_stripMembershipCategories(_renewalTitle).toLowerCase().contains('annual renewal dues')
                                        ? 'Annual renewal: ${_sentence(_stripMembershipCategories(_renewalTitle))}'
                                        : 'Annual renewal')
                                    : 'Annual renewal',
                                style: TextStyle(
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
                                    ? CubagColors.valid.withAlpha(25)
                                    : (_isPartiallyPaid
                                        ? CubagColors.due.withAlpha(25)
                                        : (hasCalculatedRenewalBill
                                            ? CubagColors.due.withAlpha(25)
                                            : (isUnderReview
                                                ? CubagColors.due.withAlpha(25)
                                                : (isRevision || isRenewalExpired
                                                    ? CubagColors.lapsed.withAlpha(25)
                                                    : (isRenewalDueSoon
                                                        ? CubagColors.due.withAlpha(25)
                                                        : _kOrange.withAlpha(25)))))),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isRenewalPaid
                                    ? 'Paid'
                                    : (_isPartiallyPaid
                                        ? 'Part paid · ${_ghs(_renewalBalanceDue)} left'
                                        : (hasCalculatedRenewalBill
                                            ? 'Bill issued'
                                            : (isUnderReview
                                                ? 'Being reviewed'
                                                : (isRevision
                                                    ? 'Changes needed'
                                                    : (isRenewalExpired
                                                        ? 'Overdue'
                                                        : (isRenewalDueSoon
                                                            ? 'Due in $daysLeft days'
                                                            : 'Not yet billed')))))),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isRenewalPaid
                                      ? const Color(0xFF059669)
                                      : (_isPartiallyPaid || hasCalculatedRenewalBill || isUnderReview
                                          ? CubagColors.due
                                          : (isRevision || isRenewalExpired
                                              ? CubagColors.lapsed
                                              : (isRenewalDueSoon
                                                  ? CubagColors.due
                                                  : _kOrange))),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          showRenewalFigures
                              ? (hasCalculatedRenewalBill || isBillPaid
                                  ? 'Official renewal bill issued by the CUBAG Secretariat.'
                                  : 'Official renewal tariff breakdown mapped strictly to your registered profile.')
                              : (isUnderReview
                                  ? 'Renewal compliance documents submitted and undergoing secretariat verification.'
                                  : (isRevision
                                      ? 'Secretariat has requested updates on your submitted renewal documents.'
                                      : 'Official renewal tariff is dynamically assessed and calculated after document upload.')),
                          style: TextStyle(
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
                                    ? CubagColors.due.withAlpha(90)
                                    : (isRevision
                                        ? CubagColors.lapsed.withAlpha(90)
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
                                                ? CubagColors.due
                                                : (isRevision ? CubagColors.lapsed : _kOrange))
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
                                            ? CubagColors.due
                                            : (isRevision ? CubagColors.lapsed : _kOrange),
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
                                            style: TextStyle(
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
                                            style: TextStyle(
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
                                      style: TextStyle(
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
                            final rawLabel = item['label']?.toString() ?? '';
                            final cleaned = _stripMembershipCategories(rawLabel);
                            final displayLabel = cleaned.isNotEmpty ? cleaned : 'Annual Renewal Fee';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayLabel,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _ghs(item['amount']?.toString() ?? ''),
                                    style: TextStyle(
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
                                'Total',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                _ghs(_renewalTotal),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.accentOrangeText,
                                ),
                              ),
                            ],
                          ),
                          if (isBillPaid) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: (isRenewalPaid ? CubagColors.valid : CubagColors.due).withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: (isRenewalPaid ? CubagColors.valid : CubagColors.due).withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isRenewalPaid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                                    color: isRenewalPaid ? const Color(0xFF059669) : CubagColors.due,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isRenewalPaid
                                          ? (expiry != null
                                              ? 'Annual cycle active & paid • Valid until ${_formatDate(expiry)} ($daysLeft days remaining)'
                                              : 'Annual renewal dues paid • Membership cycle active')
                                          : 'Renewal payment submitted • Verification in progress by Secretariat',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isRenewalPaid
                                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                            : (isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Opacity(
                              opacity: 0.45,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: null,
                                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                  label: Text(
                                    'Pay renewal dues',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_isPartiallyPaid) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: CubagColors.due.withAlpha(15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: CubagColors.due.withAlpha(60)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pie_chart_rounded, color: CubagColors.due, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Paying in instalments',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF92400E),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF059669).withAlpha(20),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Provisional good standing',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF059669),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: ((double.tryParse(_renewalTotal) ?? 0) > 0)
                                          ? (_renewalAmountPaid / (double.tryParse(_renewalTotal)!)).clamp(0.0, 1.0)
                                          : 0.0,
                                      minHeight: 8,
                                      backgroundColor: isDark ? Colors.white12 : CubagColors.line,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Total billed', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: subTextColor)),
                                          const SizedBox(height: 2),
                                          Text(_ghs(_renewalTotal), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text('Paid to date', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF059669))),
                                          const SizedBox(height: 2),
                                          Text(_ghs(_renewalAmountPaid.toStringAsFixed(2)), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Balance due', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: CubagColors.due)),
                                          const SizedBox(height: 2),
                                          Text(_ghs(_renewalBalanceDue.toStringAsFixed(2)), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: CubagColors.due)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (_installments.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ..._installments.map((inst) {
                                final iAmt = double.tryParse(inst['amount']?.toString() ?? '0') ?? 0.0;
                                final iDate = inst['date']?.toString().split('T').first ?? inst['created_at']?.toString().split('T').first ?? '';
                                final iStatus = inst['status']?.toString().toUpperCase() ?? 'CONFIRMED';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withAlpha(5) : CubagColors.sand,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Instalment: ${_ghs(iAmt)} ($iDate)',
                                        style: TextStyle(fontSize: 12, color: textColor),
                                      ),
                                      const Spacer(),
                                      Text(
                                        iStatus,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
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
                                onPressed: () {
                                  final feeName = Uri.encodeComponent(_renewalTitle);
                                  context.go('/payments?fee=$feeName&amount=${_renewalBalanceDue.toStringAsFixed(2)}&is_installment=true&min_amount=${_minInstallmentAmount.toStringAsFixed(2)}&max_amount=${_renewalBalanceDue.toStringAsFixed(2)}&app_id=${_renewalApp?['id'] ?? ''}');
                                },
                                icon: const Icon(Icons.payment_rounded, size: 18),
                                label: Text(
                                  'Pay balance (${_ghs(_renewalBalanceDue)})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ] else if (hasCalculatedRenewalBill) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: CubagColors.due.withAlpha(18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: CubagColors.due.withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.receipt_long_rounded, color: CubagColors.due, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _allowInstallments
                                          ? 'Your bill of ${_ghs(_renewalTotal)} is ready. Pay in full or in instalments${_minInstallmentAmount > 0 ? " (minimum ${_ghs(_minInstallmentAmount)})" : ""}.'
                                          : 'Your renewal bill of ${_ghs(_renewalTotal)} is ready to pay.',
                                      style: TextStyle(
                                        fontSize: 13.5,
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
                                onPressed: () {
                                  final feeName = Uri.encodeComponent(_renewalTitle);
                                  context.go('/payments?fee=$feeName&amount=$_renewalTotal&is_installment=$_allowInstallments&min_amount=${_minInstallmentAmount.toStringAsFixed(2)}&max_amount=$_renewalTotal&app_id=${_renewalApp?['id'] ?? ''}');
                                },
                                icon: const Icon(Icons.payment_rounded, size: 18),
                                label: Text(
                                  _allowInstallments ? 'Pay Renewal Dues (Full or Part-Payment)' : 'Pay renewal dues',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            if (isRenewalExpired) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: CubagColors.lapsed.withAlpha(18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: CubagColors.lapsed.withAlpha(50)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: CubagColors.lapsed, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Your membership expired on ${_formatDate(expiry)}. Renew to become active again.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (isRenewalDueSoon && expiry != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: CubagColors.due.withAlpha(18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: CubagColors.due.withAlpha(50)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.alarm_rounded, color: CubagColors.due, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Renewal is open: $daysLeft days left. Renewing early keeps your remaining days.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
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
                                        'First submit your renewal documents. Once the Secretariat approves them, it issues your renewal bill here.',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            // Faded out Pay Renewal Dues button (disabled because docs must be vetted and bill issued first)
                            Opacity(
                              opacity: 0.45,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: null,
                                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                                  label: Text(
                                    'Pay renewal dues (submit documents first)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Active Step 1 button: Submit Renewal Documents
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
                                  elevation: 0,
                                ),
                                onPressed: () => context.go('/compliance'),
                                icon: const Icon(Icons.upload_file_rounded, size: 18),
                                label: Text(
                                  'Submit renewal documents',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
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
                  label: const Text('Compliance and documents'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBrown,
                    side: const BorderSide(color: _kBrown, width: 1.5),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    ),
  );
}
}
