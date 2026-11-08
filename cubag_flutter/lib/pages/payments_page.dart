import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart' show Response, FormData, MultipartFile;
import '../components/app_layout.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRed = Color(0xFFef4444);
const _kNavy = Color(0xFF1A0F0A);
const _kBlue = Color(0xFF0284C7);

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage>
    with SingleTickerProviderStateMixin {
  int _step = 1;
  final _amountCtrl = TextEditingController();
  String _reason = '';
  final String _method = 'momo';
  String _momoNetwork = '';
  String _momoPhone = '';
  int? _complianceAppId;
  String? _complianceType;
  List<dynamic> _complianceDocs = [];
  String _complianceStatus = '';
  bool _appLoading = false;
  bool _submittingApplication = false;
  bool _loading = false;
  bool _submittingPayment = false;
  bool _showSuccess = false;
  bool _showError = false;
  String _errorMsg = '';
  String _confirmedAmount = '';
  List<dynamic> _fees = [];
  Map<String, dynamic> _paySettings = {};
  Map<String, dynamic> _memberInfo = {};
  DateTime? _licenseExpiry;
  DateTime? _renewalOpenDate;
  bool _isLicenseBlocked = false;
  bool _isRegFeePaid = false;
  bool _isPackageFeePaid = false;
  bool _isCategoryLocked = false;
  bool _loadingData = true;
  int _pollAttempt = 0;
  final int _pollMax = 60; // 60 × 5s = 5 minutes
  bool _manualChecking = false;
  int? _currentPaymentId;
  String _currentTxRef = '';
  List<Map<String, dynamic>> _regFeeBreakdown = [];
  String _upfrontRegFeeStr = '600.00';
  String _packageFeeStr = '1620.00';
  List<Map<String, dynamic>> _renewalFeeBreakdown = [];
  double? _renewalFeeAmount;
  double _renewalAmountPaid = 0.0;
  double _renewalBalanceDue = 0.0;
  bool _allowInstallments = true;
  double _minInstallmentAmount = 0.0;
  bool _isPartiallyPaid = false;
  bool _isInstallmentMode = false;
  List<dynamic> _installments = [];

  // Renewal scope selection ('combined', 'national', 'district')
  String _renewalScope = 'combined';
  List<Map<String, dynamic>> _nationalBreakdown = [];
  List<Map<String, dynamic>> _districtBreakdown = [];
  double? _nationalRenewalTotal;
  double? _districtRenewalTotal;
  double? _combinedRenewalTotal;

  void _setRenewalScope(String scope) {
    setState(() {
      _renewalScope = scope;
      _complianceAppId = null;
      if (scope == 'national') {
        _complianceType = 'renewal_national';
        _renewalFeeBreakdown = List<Map<String, dynamic>>.from(_nationalBreakdown);
        final total = _nationalRenewalTotal ??
            _nationalBreakdown.fold<double>(
                0.0, (sum, it) => sum + (double.tryParse(it['amount']?.toString() ?? '0') ?? 0.0));
        _renewalFeeAmount = total;
        _amountCtrl.text = total.toStringAsFixed(2);
      } else if (scope == 'district') {
        _complianceType = 'renewal_district';
        _renewalFeeBreakdown = List<Map<String, dynamic>>.from(_districtBreakdown);
        final total = _districtRenewalTotal ??
            _districtBreakdown.fold<double>(
                0.0, (sum, it) => sum + (double.tryParse(it['amount']?.toString() ?? '0') ?? 0.0));
        _renewalFeeAmount = total;
        _amountCtrl.text = total.toStringAsFixed(2);
      } else {
        _complianceType = 'renewal';
        _renewalFeeBreakdown = [
          ..._nationalBreakdown,
          ..._districtBreakdown,
        ];
        final total = _combinedRenewalTotal ??
            ((_nationalRenewalTotal ?? 0.0) + (_districtRenewalTotal ?? 0.0));
        _renewalFeeAmount = total > 0 ? total : 1383.0;
        _amountCtrl.text = (_renewalFeeAmount ?? 1383.0).toStringAsFixed(2);
      }
    });
  }

  String _cleanFeeLabel(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*\((Small\s*/\s*SME|small companies|large companies|Large Corporate|multinationals?|small|sme)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(Associate|Licentiate|Corporate)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    final savedRegFee =
        SessionStorage.instance.getStringSync('cubag_reg_fee_amount');
    if (savedRegFee != null && savedRegFee.isNotEmpty) {
      _upfrontRegFeeStr = savedRegFee;
      _amountCtrl.text = savedRegFee;
    }
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.90, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 1. Instant Cache Paint (0ms) from synchronous Hive cache
    final cachedMe = ApiService.getCachedSync('/auth/me');
    if (cachedMe is Map && cachedMe.isNotEmpty) {
      _applyMemberData(Map<String, dynamic>.from(cachedMe));
      _loadingData = false;
    }

    // 2. Silent Background Sync
    _loadData(silent: _memberInfo.isNotEmpty);

    // Listen to real-time fee schedule changes from Admin
    SocketService().socket?.on('fees_updated', _onFeesUpdatedSocket);
  }

  void _applyMemberData(Map<String, dynamic> rawData, {bool regPaidFromDoc = false}) {
    _memberInfo = (rawData['member'] ?? rawData) as Map<String, dynamic>;

    final rawNational = _memberInfo['national_breakdown'];
    if (rawNational is List) {
      _nationalBreakdown = rawNational
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
    }
    final rawDistrict = _memberInfo['district_breakdown'];
    if (rawDistrict is List) {
      _districtBreakdown = rawDistrict
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
    }

    _nationalRenewalTotal = double.tryParse(_memberInfo['national_total']?.toString() ?? '');
    _districtRenewalTotal = double.tryParse(_memberInfo['district_total']?.toString() ?? '');
    _combinedRenewalTotal = double.tryParse(_memberInfo['combined_total']?.toString() ?? '') ??
        double.tryParse(_memberInfo['renewal_fee_amount']?.toString() ?? '');

    final rawRenewalBreakdown = _memberInfo['renewal_fee_breakdown'];
    if (rawRenewalBreakdown is List) {
      _renewalFeeBreakdown = rawRenewalBreakdown
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
    } else if (_nationalBreakdown.isNotEmpty || _districtBreakdown.isNotEmpty) {
      _renewalFeeBreakdown = [..._nationalBreakdown, ..._districtBreakdown];
    }

    final rawRenewalAmt = _memberInfo['renewal_fee_amount'];
    if (rawRenewalAmt != null) {
      _renewalFeeAmount = double.tryParse(rawRenewalAmt.toString());
    } else if (_combinedRenewalTotal != null) {
      _renewalFeeAmount = _combinedRenewalTotal;
    }

    _renewalAmountPaid = double.tryParse(_memberInfo['renewal_amount_paid']?.toString() ?? '0') ?? 0.0;
    _renewalBalanceDue = double.tryParse(_memberInfo['renewal_balance_due']?.toString() ?? '') ??
        (_renewalFeeAmount != null ? (_renewalFeeAmount! - _renewalAmountPaid).clamp(0.0, double.infinity) : 0.0);
    _allowInstallments = _memberInfo['renewal_allow_installments'] != false;
    _minInstallmentAmount = double.tryParse(_memberInfo['renewal_min_installment_amount']?.toString() ?? '0') ?? 0.0;
    _isPartiallyPaid = _memberInfo['renewal_is_partially_paid'] == true;
    _installments = ApiService.ensureList(_memberInfo['renewal_installments']);

    _isRegFeePaid = regPaidFromDoc ||
        _memberInfo['registration_fee_paid'] == true ||
        _memberInfo['registration_paid'] == true ||
        _memberInfo['application_fee_paid'] == true;
    _isPackageFeePaid = _memberInfo['package_fee_paid'] == true;

    final expiryRaw = _memberInfo['license_expiry_date'];
    _licenseExpiry = expiryRaw != null ? DateTime.tryParse(expiryRaw.toString()) : null;
    _isLicenseBlocked = false;
  }

  void _onFeesUpdatedSocket(dynamic _) {
    if (mounted) _loadData(silent: true);
  }

  @override
  void dispose() {
    SocketService().socket?.off('fees_updated', _onFeesUpdatedSocket);
    SocketService().socket?.off('payment_approved');
    _pulseController.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double _getCurrentBillTotal() {
    final r = _reason.toLowerCase();
    if (r.contains('renewal') || r.contains('annual dues')) {
      return _renewalBalanceDue > 0 ? _renewalBalanceDue : (_renewalFeeAmount ?? 0.0);
    }
    if (r.contains('registration') || r.contains('application')) {
      return double.tryParse(_upfrontRegFeeStr) ?? 600.0;
    }
    if (r.contains('package')) {
      return double.tryParse(_packageFeeStr) ?? 1620.0;
    }
    for (final f in _fees) {
      if (f is Map && f['label']?.toString().toLowerCase() == r) {
        final amt = double.tryParse(f['amount']?.toString().replaceAll(',', '') ?? '');
        if (amt != null && amt > 0) return amt;
      }
    }
    return double.tryParse(_amountCtrl.text) ?? 0.0;
  }

  String _normalizeGhanaPhone(String input) {
    var clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('233') && clean.length > 3) {
      clean = '0${clean.substring(3)}';
    }
    if (clean.length > 10) {
      clean = clean.substring(0, 10);
    }
    return clean;
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent && _memberInfo.isEmpty) {
      setState(() => _loadingData = true);
    }
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getPublic('settings/cubag_fees_v2'),
        api.getPublic('settings/cubag_payment_settings_v2'),
        api.get('/auth/me'),
        api.get('/documents/requirements'),
      ]);

      final feesData = results[0];
      final payData = results[1];
      final meRes = results[2];
      final docRes = results.length > 3 ? results[3] : null;

      String? dynamicRegAmt;
      String? dynamicPkgAmt;
      bool regPaidFromDoc = false;
      if (docRes is Response && docRes.data is Map) {
        final docData = docRes.data as Map;
        dynamicRegAmt = docData['registration_fee_amount']?.toString();
        if (dynamicRegAmt != null && double.tryParse(dynamicRegAmt) != null) {
          _upfrontRegFeeStr = double.parse(dynamicRegAmt).toStringAsFixed(2);
        }
        dynamicPkgAmt = docData['package_fee_amount']?.toString() ??
            docData['registration_package_amount']?.toString();
        if (dynamicPkgAmt != null && double.tryParse(dynamicPkgAmt) != null) {
          _packageFeeStr = double.parse(dynamicPkgAmt).toStringAsFixed(2);
        }
        regPaidFromDoc = docData['registration_fee_paid'] == true || docData['application_fee_paid'] == true;
        final rawBreakdown = docData['registration_fee_breakdown'];
        if (rawBreakdown is List) {
          _regFeeBreakdown = rawBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          if (feesData is List) _fees = feesData;
          if (payData is Map<String, dynamic>) _paySettings = payData;
          // Extract member info from /auth/me response
          if (meRes is Response && meRes.data is Map) {
            _applyMemberData(meRes.data as Map<String, dynamic>, regPaidFromDoc: regPaidFromDoc);
          } else {
            _isRegFeePaid = regPaidFromDoc;
          }

          // Check query parameters for fee pre-selection & redirect return route
          final state = GoRouterState.of(context);
          final redirectUrl = state.uri.queryParameters['redirect'];
          final queryFee = state.uri.queryParameters['fee'];
          final queryAmt = state.uri.queryParameters['amount'];
          final queryIsInstallment = state.uri.queryParameters['is_installment'] == 'true';
          final queryMinAmt = state.uri.queryParameters['min_amount'];
          final queryMaxAmt = state.uri.queryParameters['max_amount'];
          final queryAppId = state.uri.queryParameters['app_id'];

          if (queryAppId != null && queryAppId.isNotEmpty) {
            _complianceAppId = int.tryParse(queryAppId) ?? _complianceAppId;
          }
          if (queryIsInstallment) {
            _isInstallmentMode = true;
          }
          if (queryMinAmt != null && queryMinAmt.isNotEmpty) {
            _minInstallmentAmount = double.tryParse(queryMinAmt) ?? _minInstallmentAmount;
          }
          if (queryMaxAmt != null && queryMaxAmt.isNotEmpty) {
            _renewalBalanceDue = double.tryParse(queryMaxAmt) ?? _renewalBalanceDue;
          }

          if (queryAmt != null && queryAmt.isNotEmpty) {
            final parsedAmt = double.tryParse(queryAmt);
            if (parsedAmt != null) {
              _amountCtrl.text = parsedAmt.toStringAsFixed(2);
              if (queryFee == null || queryFee.toLowerCase().contains('renewal') || queryFee.toLowerCase().contains('annual')) {
                _renewalFeeAmount = parsedAmt;
              }
            }
          }
          
          if (queryFee != null && queryFee.isNotEmpty) {
            final qfLower = queryFee.toLowerCase();
            if (qfLower.contains('registration') || redirectUrl == '/application-documents') {
              _reason = 'Registration Fee';
              _isCategoryLocked = true;
            } else if (qfLower.contains('package') || qfLower.contains('entrance') || qfLower.contains('new member')) {
              _reason = 'New Membership Dues';
              _isCategoryLocked = true;
            } else if (qfLower.contains('renewal') || qfLower.contains('annual')) {
              if (!_isPackageFeePaid) {
                _reason = 'New Membership Dues';
                _isCategoryLocked = false;
              } else {
                _reason = 'Annual Renewal Dues';
              }
            } else if (qfLower.contains('cti') || qfLower.contains('course') || qfLower.contains('training')) {
              _reason = queryFee;
              _isCategoryLocked = true;
              if (queryAmt != null && queryAmt.isNotEmpty) {
                final pAmt = double.tryParse(queryAmt);
                if (pAmt != null && pAmt > 0) {
                  _amountCtrl.text = pAmt.toStringAsFixed(2);
                }
              }
            } else {
              _reason = queryFee;
            }
          } else if (redirectUrl == '/application-documents') {
            _reason = 'Registration Fee';
            _isCategoryLocked = true;
          } else if (!_isRegFeePaid) {
            _reason = 'Registration Fee';
          } else if (!_isPackageFeePaid) {
            _reason = 'New Membership Dues';
          } else if (_renewalFeeAmount != null && _renewalFeeAmount! > 0) {
            _reason = 'Annual Renewal Dues';
          } else {
            _reason = _isPackageFeePaid ? 'Annual Renewal Dues' : 'New Membership Dues';
          }

          if (_reason == 'Registration Fee') {
            _amountCtrl.text = _upfrontRegFeeStr;
          } else if (_reason == 'New Membership Dues' || _reason.toLowerCase().contains('package') || _reason.toLowerCase().contains('entrance') || _reason.toLowerCase().contains('new member')) {
            _reason = 'New Membership Dues';
            _amountCtrl.text = _packageFeeStr;
          } else if (_reason.toLowerCase().contains('renewal')) {
            if (!_isPackageFeePaid) {
              _reason = 'New Membership Dues';
              _amountCtrl.text = _packageFeeStr;
            } else if (queryAmt != null && queryAmt.isNotEmpty) {
              _amountCtrl.text = double.tryParse(queryAmt)?.toStringAsFixed(2) ?? queryAmt;
            } else if (_renewalFeeAmount != null && _renewalFeeAmount! > 0) {
              _amountCtrl.text = _renewalFeeAmount!.toStringAsFixed(2);
            } else {
              _amountCtrl.clear();
            }
          } else if (_reason.toLowerCase().contains('cti') || _reason.toLowerCase().contains('course')) {
            // Keep pre-filled course fee from query parameter
          } else if (_reason.isNotEmpty && _fees.isNotEmpty) {
            // Pre-fill fee amount directly from platform fees configuration (_fees)
            double? foundAmt;
            final rLower = _reason.toLowerCase().trim();
            for (var f in _fees) {
              final fLabel =
                  (f['label'] ?? f['name'] ?? f['fee_name'] ?? f['title'] ?? '')
                      .toString();
              final fName = fLabel.toLowerCase().trim();
              bool isMatch = fName == rLower;
              if (!isMatch) {
                if ((rLower.contains('registration') ||
                        rLower.contains('application')) &&
                    (fName.contains('registration') ||
                        fName.contains('application'))) {
                  isMatch = true;
                } else if ((rLower == 'licence fee' ||
                        rLower == 'license fee' ||
                        (rLower.contains('licence') &&
                            !rLower.contains('application') &&
                            !rLower.contains('renewal') &&
                            !rLower.contains('registration'))) &&
                    fName.contains('licence') &&
                    !fName.contains('application') &&
                    !fName.contains('renewal') &&
                    !fName.contains('registration')) {
                  isMatch = true;
                } else if (rLower.contains('renewal') &&
                    fName.contains('renewal')) {
                  isMatch = true;
                }
              }

              if (isMatch) {
                _reason = fLabel; // Set exact string so Dropdown item matches!
                final raw =
                    (f['amount'] ?? f['fee_amount'] ?? f['price'] ?? f['value'])
                        ?.toString();
                if (raw != null) {
                  foundAmt = double.tryParse(raw);
                }
                break;
              }
            }
            if (foundAmt != null && foundAmt > 0) {
              _amountCtrl.text = foundAmt.toStringAsFixed(2);
            }
          }
        });
      }
    } catch (e, st) {
      AppLogger.error('payments_page', e, st);
    }
    if (mounted) setState(() => _loadingData = false);
  }

  Future<void> _submitPayment() async {
    if (_loading || _submittingPayment) return;
    final amt = double.tryParse(_amountCtrl.text) ?? 0;
    if (amt <= 0) {
      setState(() {
        _errorMsg = 'Please enter a valid amount greater than 0.';
        _showError = true;
      });
      return;
    }
    if (_method == 'momo' && _momoNetwork.trim().isEmpty) {
      setState(() {
        _errorMsg = 'Please select your MoMo carrier (MTN, Telecel, or AirtelTigo).';
        _showError = true;
      });
      return;
    }
    if (_method == 'momo' && _momoPhone.trim().isEmpty) {
      setState(() {
        _errorMsg = 'Please enter your MoMo phone number.';
        _showError = true;
      });
      return;
    }
    final effectiveReason = _reason.trim().isEmpty
        ? 'Association Payment'
        : _reason;

    setState(() {
      _loading = true;
      _submittingPayment = true;
    });

    // For MoMo: jump to the waiting screen IMMEDIATELY (before network call)
    // so the user sees feedback right away instead of waiting ~30s for the API.
    if (_method == 'momo') {
      setState(() {
        _step = 5;
        _confirmedAmount = _amountCtrl.text;
        _pollAttempt = 0;
        _loading = false;
      });
    }

    try {
      final api = ApiService();
      final currentBillTot = _getCurrentBillTotal();
      final isInstallment = _isInstallmentMode ||
          (currentBillTot > 0 && amt < (currentBillTot - 0.01));
      final requestData = {
        'amount': amt,
        'description': effectiveReason,
        'method': 'momo',
        'network': _momoNetwork,
        'phone': _momoPhone,
        'receipt_url': null,
        'bank_name': null,
        'account_name': null,
        'account_number': null,
        'payment_ref': null,
        'notes': null,
        'is_installment': isInstallment,
        'installment_number': _installments.length + 1,
        'compliance_application_id': _complianceAppId,
      };
      if (_complianceAppId != null) {
        requestData['meta'] = {'compliance_application_id': _complianceAppId};
      }
      final res = await api.post('/payments', data: requestData);

      if (res.statusCode == 200 || res.statusCode == 201) {
        // ── License Active Guard (server returns 200 + error_code to avoid browser console errors)
        if (res.data is Map && res.data['error_code'] == 'LICENSE_ACTIVE') {
          final msg = res.data['message'] ?? 'Your license is still active.';
          final renewalOpens = res.data['renewal_opens'] ?? '';
          // Go back to step 4 (review) — not waiting for momo
          if (mounted) setState(() => _step = 4);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10b981).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF10b981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'License Active',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      msg,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Color(0xFF6b6375),
                      ),
                    ),
                    if (renewalOpens.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _kOrange.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kOrange.withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: _kOrange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Renewal opens on $renewalOpens',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _kOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            );
          }
          // ── Duplicate Bank Deposit Slip Guard (already submitted & pending verification)
        } else if (res.data is Map &&
            res.data['error_code'] == 'PAYMENT_ALREADY_SUBMITTED') {
          final resData = res.data as Map;
          final paymentId = resData['payment_id'];
          final txRef = resData['transaction_ref'] ?? '';

          // Suppress bill popup and invalidate caches
          await SessionStorage.instance.setString('cubag_renewal_submitted', 'true');
          ApiService.deleteCacheKeysMatching('/tasks');
          ApiService.deleteCacheKeysMatching('/payments');

          if (mounted) {
            setState(() {
              _currentPaymentId = paymentId;
              _currentTxRef = txRef;
              _confirmedAmount = _amountCtrl.text;
              _loading = false;
              _submittingPayment = false;
              _step = 5;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(resData['message']?.toString() ?? 'Deposit receipt already received and under review.'),
                backgroundColor: _kOrange,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          // ── Duplicate Completed Payment Guard
        } else if (res.data is Map &&
            res.data['error_code'] == 'PAYMENT_ALREADY_COMPLETED') {
          final msg = res.data['message'] ??
              'This payment has already been completed.';
          if (mounted) setState(() => _step = 4);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10b981).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF10b981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Already Paid',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  msg,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Color(0xFF6b6375),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/payment-history');
                    },
                    child: const Text(
                      'View Payment History',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          // ── Normal payment success
        } else if (_method == 'momo') {
          final resData = res.data is Map ? res.data as Map : {};
          final paymentId = resData['payment_id'];
          final txRef =
              resData['transaction_ref'] ?? resData['whitsun_ref'] ?? '';

          // Suppress renewal bill popup immediately and invalidate caches
          final rLower = effectiveReason.toLowerCase();
          if (rLower.contains('renewal') || rLower.contains('license') || rLower.contains('dues')) {
            await SessionStorage.instance.setString('cubag_renewal_submitted', 'true');
          }
          ApiService.deleteCacheKeysMatching('/tasks');
          ApiService.deleteCacheKeysMatching('/payments');

          // Update IDs now that we have them from the server, then start polling
          if (mounted) {
            setState(() {
              _currentPaymentId = paymentId;
              _currentTxRef = txRef;
            });
          }
          _pollWhitsunPayStatus(paymentId, txRef);
        } else {
          // ── Bank Transfer Submitted
          final resData = res.data is Map ? res.data as Map : {};
          final paymentId = resData['payment_id'];
          final txRef = resData['transaction_ref'] ?? '';

          // Suppress renewal bill popup immediately and invalidate caches
          final rLower = effectiveReason.toLowerCase();
          if (rLower.contains('renewal') || rLower.contains('license') || rLower.contains('dues')) {
            await SessionStorage.instance.setString('cubag_renewal_submitted', 'true');
          }
          ApiService.deleteCacheKeysMatching('/tasks');
          ApiService.deleteCacheKeysMatching('/payments');

          if (mounted) {
            setState(() {
              _currentPaymentId = paymentId;
              _currentTxRef = txRef;
              _confirmedAmount = _amountCtrl.text;
              _loading = false;
              _submittingPayment = false;
              _step = 5;
            });
          }
        }
      } else {
        final serverMsg = res.data is Map
            ? (res.data['message'] ?? res.data['error'])
            : null;
        if (mounted) {
          setState(() {
            // Return to step 4 (review) so the user can try again
            _step = 4;
            _errorMsg = serverMsg ?? 'Payment failed. Please try again.';
            _showError = true;
          });
        }
      }
    } catch (e) {
      String msg = 'Network error. Please try again.';
      if (e is Exception && e.toString().contains('400')) {
        msg =
            'Invalid payment parameters. Please check your amount and phone number.';
      }
      if (mounted) {
        setState(() {
          // Return to step 4 if already on step 5 (momo early-advance)
          if (_step == 5) _step = 4;
          _errorMsg = msg;
          _showError = true;
        });
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _submittingPayment = false;
      });
    }
  }



  bool get _requiresDocuments {
    return _isComplianceReason(_reason);
  }

  bool get _isNoDocPaymentReason {
    return !_requiresDocuments;
  }

  bool get _isRenewalFullyPaid {
    final r = _reason.toLowerCase();
    if (!r.contains('renewal') && !r.contains('annual dues')) return false;
    final isMarkedPaid = _memberInfo['is_renewal_paid'] == true ||
        _memberInfo['renewal_paid'] == true;
    if (isMarkedPaid) return true;
    if (_renewalAmountPaid > 0 && _renewalBalanceDue <= 0.01) return true;
    if (_renewalFeeAmount != null &&
        _renewalFeeAmount! > 0 &&
        _renewalAmountPaid >= (_renewalFeeAmount! - 0.01)) {
      return true;
    }
    return false;
  }

  bool _isComplianceReason(String? label) {
    if (label == null) return false;
    final value = label.toLowerCase();
    if (value.contains('application fee')) return false;
    return value.contains('renewal') ||
        value.contains('licence') ||
        value.contains('license');
  }

  String? _complianceTypeForReason(String? label) {
    if (label == null) return null;
    final value = label.toLowerCase();
    if (value.contains('application fee')) return null;
    if (value.contains('renewal')) {
      if (_renewalScope == 'national') return 'renewal_national';
      if (_renewalScope == 'district') return 'renewal_district';
      return 'renewal';
    }
    if (value.contains('licence') || value.contains('license')) {
      return 'customs_licence';
    }
    return null;
  }

  Future<void> _prepareComplianceApplication() async {
    if (_complianceType == null) return;
    if (_appLoading) return;
    setState(() {
      _appLoading = true;
    });
    try {
      if (_complianceAppId == null) {
        final res = await ApiService().post(
          '/compliance/applications',
          data: {
            'type': _complianceType,
            'scope': _renewalScope,
          },
        );
        final rawId = res.data['application_id'];
        _complianceAppId = rawId is int
            ? rawId
            : int.tryParse(rawId?.toString() ?? '');
        await ApiService.deleteCacheKeysMatching('compliance');
      }
      if (_complianceAppId != null) {
        await _loadComplianceApplicationDetails(_complianceAppId!);
      }
    } catch (e, st) {
      AppLogger.error('payments_page_compliance', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to create compliance application: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _appLoading = false);
    }
  }

  Future<void> _loadComplianceApplicationDetails(int appId) async {
    try {
      final res = await ApiService().get('/compliance/applications/$appId');
      if (!mounted) return;
      final app = res.data['application'] as Map<String, dynamic>? ?? {};
      final docs = ApiService.ensureList(res.data['documents']);
      setState(() {
        _complianceDocs = docs;
        _complianceStatus = app['status']?.toString() ?? '';
        _complianceType = app['type']?.toString() ?? _complianceType;
      });
    } catch (e, st) {
      AppLogger.error('payments_page_compliance', e, st);
    }
  }

  bool get _allComplianceDocsUploaded {
    return _complianceDocs.isNotEmpty &&
        _complianceDocs.every((d) => d['uploaded'] == true);
  }

  Future<void> _uploadComplianceDoc(Map<String, dynamic> docReq) async {
    if (_complianceAppId == null) return;
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final key = docReq['key']?.toString() ?? '';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Uploading ${result.files.length} document(s)…',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _kNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    try {
      final List<Future<void>> uploadTasks = [];

      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];

        uploadTasks.add(() async {
          late MultipartFile mpFile;
          if (file.bytes != null) {
            mpFile = MultipartFile.fromBytes(Uint8List.fromList(file.bytes!), filename: file.name);
          } else if (file.path != null && file.path!.isNotEmpty) {
            mpFile = await MultipartFile.fromFile(file.path!, filename: file.name);
          } else {
            final bytes = await file.xFile.readAsBytes();
            mpFile = MultipartFile.fromBytes(Uint8List.fromList(bytes), filename: file.name);
          }

          final formData = FormData.fromMap({
            'requirement': key,
            'label': docReq['label'] ?? key,
            'file': mpFile,
          });

          final res = await ApiService().upload(
            '/compliance/applications/${_complianceAppId!}/upload',
            formData,
          );

          if (res.statusCode != 200) {
            String errorMsg = 'Upload failed';
            if (res.data is Map && res.data['message'] != null) {
              errorMsg = res.data['message'].toString();
            } else if (res.data is String && (res.data as String).isNotEmpty) {
              errorMsg = res.data.toString();
            }
            throw Exception(errorMsg);
          }
        }());
      }

      await Future.wait(uploadTasks);

      if (!mounted) return;
      _showSnack('${docReq['label']} uploaded!', color: _kGreen);
      await _loadComplianceApplicationDetails(_complianceAppId!);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) _showSnack('Upload failed: $msg', color: _kRed);
    } finally {
      if (mounted) setState(() {});
    }
  }

  void _showSnack(
    String msg, {
    Color color = _kNavy,
    bool showProgress = false,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: showProgress
            ? Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      msg,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submitComplianceApplication() async {
    if (_complianceAppId == null || _submittingApplication) return;
    setState(() => _submittingApplication = true);
    try {
      final res = await ApiService().post(
        '/compliance/applications/${_complianceAppId!}/submit',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final nextStep = res.data['next_step']?.toString() ?? '';
        _showSnack(
          res.data['message'] ?? 'Application submitted.',
          color: _kGreen,
        );
        await _loadComplianceApplicationDetails(_complianceAppId!);
        if (nextStep == 'payment') {
          setState(() => _step = 3);
        }
      } else {
        final missing = ApiService.ensureList(res.data['missing']);
        final msg = missing.isNotEmpty
            ? 'Missing: ${missing.join(', ')}'
            : (res.data['message'] ?? 'Submission failed');
        _showSnack(msg, color: _kRed);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _submittingApplication = false);
    }
  }

  Future<void> _pollWhitsunPayStatus(int paymentId, String txRef) async {
    final api = ApiService();
    bool isComplete = false;

    // Real-time Socket.IO webhook listener — advances UI instantly when webhook fires (< 1s)
    final socket = SocketService().socket;
    void handleSocketApproval(dynamic data) {
      if (!mounted) return;
      final int? pId = data is Map
          ? int.tryParse(data['payment_id']?.toString() ?? '')
          : null;
      if (pId == paymentId) {
        isComplete = true;
        _handlePaymentSuccess();
      }
    }

    if (socket != null) {
      socket.on('payment_approved', handleSocketApproval);
    }

    while (!isComplete && _pollAttempt < _pollMax && mounted) {
      await Future.delayed(const Duration(seconds: 4));
      if (isComplete || !mounted || _currentPaymentId != paymentId) break;

      try {
        final res = await api.post(
          '/payments/verify-code',
          data: {
            'payment_id': paymentId,
            'transaction_ref': txRef,
            'whitsun_ref': txRef,
          },
        );

        if (_currentPaymentId != paymentId) break;

        if (res.statusCode == 200) {
          final resData = res.data is Map ? res.data as Map : {};
          final status = resData['status']?.toString().toLowerCase() ?? '';
          if (status == 'success' ||
              status == 'successful' ||
              status == 'completed') {
            isComplete = true;
            _handlePaymentSuccess();
          } else if (status == 'failed' ||
              status == 'declined' ||
              status == 'cancelled' ||
              status == 'reversed') {
            isComplete = true;
            if (mounted) {
              setState(() {
                _errorMsg =
                    resData['message'] ?? 'Payment was declined or cancelled.';
                _showError = true;
                _step = 1;
              });
            }
          }
        }
      } catch (e) {
        // continue
      }

      if (_currentPaymentId != paymentId) break;
      if (mounted) setState(() => _pollAttempt++);
    }

    if (socket != null) {
      socket.off('payment_approved', handleSocketApproval);
    }
  }

  Future<void> _handlePaymentSuccess() async {
    await ApiService.deleteCacheKeysMatching('auth/me');
    await ApiService.deleteCacheKeysMatching('tasks');
    await ApiService.deleteCacheKeysMatching('payments');
    await ApiService.deleteCacheKeysMatching('documents');
    await ApiService.deleteCacheKeysMatching('compliance');
    await ApiService.deleteCacheKeysMatching('license-history');
    SocketService().dataUpdateNotifier.value = 'payment_approved:${DateTime.now().millisecondsSinceEpoch}';

    try {
      final res = await ApiService().get('/auth/me');
      if (res.data != null && res.data is Map) {
        final d = (res.data['member'] ?? res.data) as Map;
        if (d['status'] != null) SessionStorage.instance.setString('cubag_status', d['status'].toString());
        if (d['license_expiry_date'] != null) SessionStorage.instance.setString('cubag_expiry', d['license_expiry_date'].toString());
        if (d['license_number'] != null) SessionStorage.instance.setString('cubag_license_number', d['license_number'].toString());
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _showSuccess = true;
        _step = 1;
        _amountCtrl.clear();
        _reason = '';
      });
    }
  }

  Future<void> _manualStatusCheck() async {
    if (_currentTxRef.isEmpty || _manualChecking) return;
    setState(() => _manualChecking = true);
    try {
      final api = ApiService();
      final res = await api.post(
        '/payments/verify-code',
        data: {
          'payment_id': _currentPaymentId,
          'transaction_ref': _currentTxRef,
          'whitsun_ref': _currentTxRef,
        },
      );
      if (!mounted) return;
      final resData = res.data is Map ? res.data as Map : {};
      final status = resData['status']?.toString().toLowerCase() ?? '';
      if (status == 'success' ||
          status == 'successful' ||
          status == 'completed') {
        _handlePaymentSuccess();
      } else if (status == 'failed' ||
          status == 'declined' ||
          status == 'cancelled') {
        setState(() {
          _errorMsg = resData['message'] ?? 'Payment declined.';
          _showError = true;
          _step = 1;
        });
      } else {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Still pending: ${resData['message'] ?? 'Please check your phone for the MoMo prompt.'}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            backgroundColor: _kOrange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Check failed — please try again.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }

    if (mounted) setState(() => _manualChecking = false);
  }

  Widget _overlay({required Widget child, bool isDark = false}) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(isDark ? 120 : 35),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E130D) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF3D261C)
                    : const Color(0xFFE8DED6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 50 : 15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  String _formatFeeAmount(dynamic amount) {
    if (amount == null) return '0.00';
    final raw = amount.toString().replaceAll(',', '').trim();
    final value = double.tryParse(raw) ?? 0.0;
    return value.toStringAsFixed(2);
  }

  String _monthName(int m) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bank = (_paySettings['bankAccounts'] as List?)?.firstOrNull ?? {};

    return AppLayout(
      title: 'Payment',
      scrollable: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadData(),
                  color: _kOrange,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                    children: [
                      Card(
                        color: isDark ? const Color(0xFF1E130D) : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Stepper indicator
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6),
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              child: Builder(
                                builder: (ctx) {
                                  final reqDocs = _requiresDocuments;
                                  final labels = reqDocs
                                      ? ['Details', 'Documents', 'Method', 'Review', 'Verify']
                                      : ['Details', 'Method', 'Review', 'Verify'];
                                  final stepMap = reqDocs
                                      ? {1: 0, 2: 1, 3: 2, 4: 3, 5: 4}
                                      : {1: 0, 3: 1, 4: 2, 5: 3};
                                  final curIdx = stepMap[_step] ?? 0;
                                  final totalSteps = labels.length;

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: List.generate(totalSteps, (i) {
                                      final isCompleted = curIdx > i;
                                      final isActive = curIdx == i;
                                      final n = i + 1;

                                      return Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Divider(
                                                    thickness: 2.5,
                                                    color: i == 0
                                                        ? Colors.transparent
                                                        : (curIdx >= i
                                                            ? _kOrange
                                                            : const Color(0xFFe2e8f0)),
                                                  ),
                                                ),
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: isCompleted
                                                        ? const Color(0xFF10b981)
                                                        : (isActive
                                                            ? _kOrange
                                                            : Colors.white),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isCompleted
                                                          ? const Color(0xFF10b981)
                                                          : (isActive
                                                              ? _kOrange
                                                              : const Color(0xFFcbd5e1)),
                                                      width: 2,
                                                    ),
                                                    boxShadow: isActive
                                                        ? [
                                                            BoxShadow(
                                                              color: _kOrange.withAlpha(50),
                                                              blurRadius: 6,
                                                              offset: const Offset(0, 2),
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                  child: Center(
                                                    child: isCompleted
                                                        ? const Icon(
                                                            Icons.check_rounded,
                                                            color: Colors.white,
                                                            size: 14,
                                                          )
                                                        : Text(
                                                            '$n',
                                                            style: GoogleFonts.inter(
                                                              color: isActive
                                                                  ? Colors.white
                                                                  : const Color(0xFF64748b),
                                                              fontWeight: FontWeight.w800,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Divider(
                                                    thickness: 2.5,
                                                    color: i == totalSteps - 1
                                                        ? Colors.transparent
                                                        : (curIdx > i
                                                            ? _kOrange
                                                            : const Color(0xFFe2e8f0)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              height: 18,
                                              child: isActive
                                                  ? Text(
                                                      labels[i],
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        color: _kOrange,
                                                        fontWeight: FontWeight.w800,
                                                        letterSpacing: 0.1,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
                            ),

                            // Step Form content
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: _buildStepContent(_kOrange, bank),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            size: 14,
                            color: Color(0xFF94a3b8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Secured by WhitsunPay PCI-DSS Compliance',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF64748b),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

                // Success Modal Overlay
                if (_showSuccess)
                  _overlay(
                    isDark: isDark,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF10b981), Color(0xFF059669)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Payment Confirmed!',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your transaction has been successfully processed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748b),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        if (_confirmedAmount.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFf0fdf4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFbbf7d0),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'AMOUNT PAID',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF16a34a),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'GH₵ ${double.tryParse(_confirmedAmount)?.toStringAsFixed(2) ?? _confirmedAmount}',
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF15803d),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Builder(
                          builder: (ctx) {
                            final redirectUrl = GoRouterState.of(
                              ctx,
                            ).uri.queryParameters['redirect'];
                            final returnToApp =
                                redirectUrl == '/application-documents';
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10b981),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() => _showSuccess = false);
                                      if (redirectUrl != null && redirectUrl.isNotEmpty) {
                                        context.go(redirectUrl);
                                      } else {
                                        context.go('/payment-history');
                                      }
                                    },
                                    child: Text(
                                      returnToApp
                                          ? 'Return to Complete Your Application'
                                          : (redirectUrl != null && (redirectUrl.contains('cti') || redirectUrl.contains('course'))
                                              ? 'Return to CTI Courses'
                                              : (redirectUrl != null && redirectUrl.isNotEmpty
                                                  ? 'Return to App'
                                                  : 'View Payment History')),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                if (redirectUrl != null && redirectUrl.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _showSuccess = false);
                                      context.go('/payment-history');
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF64748b),
                                    ),
                                    child: Text(
                                      'View Payment History',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _showSuccess = false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF64748b),
                          ),
                          child: Text(
                            'Close',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error Modal Overlay
                if (_showError)
                  _overlay(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFef4444), Color(0xFFdc2626)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Transaction Failed',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMsg,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF64748b),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A0F0A),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => setState(() => _showError = false),
                            child: Text(
                              'Try Again',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
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

  Widget _buildStepContent(Color primary, dynamic bank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_step == 1) {
      if (_loadingData) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40.0),
            child: CircularProgressIndicator(color: _kOrange),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT CATEGORY',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748b),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final regTitle = 'Registration Fee';
              final regAmtStr = _amountCtrl.text.isNotEmpty && _reason == regTitle
                  ? _amountCtrl.text
                  : (_upfrontRegFeeStr.isNotEmpty ? _upfrontRegFeeStr : '600.00');

              const packageTitle = 'New Membership Dues';
              final packageAmtStr = _packageFeeStr.isNotEmpty ? _packageFeeStr : '1620.00';

              const renewalTitle = 'Annual Renewal Dues';
              final renewalAmtStr =
                  _renewalFeeAmount != null && _renewalFeeAmount! > 0
                  ? _renewalFeeAmount!.toStringAsFixed(2)
                  : '2170.00';

              final List<DropdownItem<String>> dropdownItems = [];
              if (!_isRegFeePaid) {
                dropdownItems.add(
                  DropdownItem<String>(
                    value: regTitle,
                    label: '$regTitle · GH₵ $regAmtStr',
                  ),
                );
              }
              if (!_isPackageFeePaid) {
                dropdownItems.add(
                  DropdownItem<String>(
                    value: 'New Membership Dues',
                    label: '$packageTitle · GH₵ $packageAmtStr',
                  ),
                );
              }

              // Only include Annual Renewal Dues if user has paid their new membership dues
              if (_isPackageFeePaid) {
                dropdownItems.add(
                  DropdownItem<String>(
                    value: 'Annual Renewal Dues',
                    label: _renewalFeeAmount != null && _renewalFeeAmount! > 0
                        ? '$renewalTitle · GH₵ $renewalAmtStr'
                        : '$renewalTitle (Bill Pending Approval)',
                  ),
                );
              }

              // Add non-tier general service fees from platform settings if configured
              for (var f in _fees) {
                final label = (f['label'] ?? f['name'] ?? '').toString();
                final lLower = label.toLowerCase();
                if (lLower.contains('new member') ||
                    lLower.contains('sme') ||
                    lLower.contains('large corporate') ||
                    lLower.contains('registration') ||
                    lLower.contains('annual renewal') ||
                    lLower.contains('vetting') ||
                    lLower.contains('district') ||
                    lLower.contains('dues') ||
                    lLower.contains('subscription') ||
                    lLower.contains('consolidation') ||
                    lLower.contains('clearing') ||
                    lLower.contains('forwarding') ||
                    lLower.contains('training') ||
                    lLower.contains('bond') ||
                    lLower.contains('audit') ||
                    lLower.contains('legal') ||
                    lLower.contains('agm') ||
                    lLower.contains('welfare') ||
                    lLower.contains('levy') ||
                    lLower.contains('administrative')) {
                  continue; // Exclude component breakdown items & tier options from dropdown
                }
                if (!dropdownItems.any((it) => it.value == label)) {
                  dropdownItems.add(
                    DropdownItem<String>(
                      value: label,
                      label: '$label · GH₵ ${_formatFeeAmount(f['amount'])}',
                    ),
                  );
                }
              }

              dropdownItems.add(
                const DropdownItem<String>(
                  value: 'Other',
                  label: 'Other / Miscellaneous',
                ),
              );

              // Ensure _reason value exists in items so it is auto-selected in UI
              if (_reason.isNotEmpty &&
                  !dropdownItems.any((it) => it.value == _reason)) {
                String labelText =
                    '$_reason · GH₵ ${_amountCtrl.text.isNotEmpty ? _amountCtrl.text : "0.00"}';
                if (_reason.toLowerCase().contains('registration')) {
                  if (_isRegFeePaid) {
                    _reason = 'New Membership Dues';
                  } else {
                    _reason = regTitle;
                    labelText = '$regTitle · GH₵ $regAmtStr';
                    dropdownItems.insert(
                      0,
                      DropdownItem<String>(value: regTitle, label: labelText),
                    );
                  }
                } else if (_reason.toLowerCase().contains('new member') || _reason.toLowerCase().contains('package') || _reason.toLowerCase().contains('entrance')) {
                  _reason = 'New Membership Dues';
                  labelText = '$packageTitle · GH₵ $packageAmtStr';
                  dropdownItems.insert(
                    0,
                    DropdownItem<String>(value: 'New Membership Dues', label: labelText),
                  );
                } else if (_reason.toLowerCase().contains('renewal')) {
                  if (!_isPackageFeePaid) {
                    _reason = 'New Membership Dues';
                  } else {
                    labelText = _renewalFeeAmount != null && _renewalFeeAmount! > 0
                        ? '$renewalTitle · GH₵ ${_renewalFeeAmount!.toStringAsFixed(2)}'
                        : '$renewalTitle (Bill Pending Approval)';
                    dropdownItems.insert(
                      0,
                      DropdownItem<String>(value: _reason, label: labelText),
                    );
                  }
                } else {
                  dropdownItems.insert(
                    0,
                    DropdownItem<String>(value: _reason, label: labelText),
                  );
                }
              }

              return CustomDropdown<String>(
                value: _reason,
                hint: 'Select Payment Category',
                items: dropdownItems,
                enabled: !_isCategoryLocked,
                onChanged: (v) {
                  setState(() {
                    _reason = v;
                    if (v == 'Other') {
                      _amountCtrl.clear();
                      _complianceAppId = null;
                      _complianceType = null;
                      _complianceDocs = [];
                      _complianceStatus = '';
                    } else if (v.toLowerCase().contains('registration')) {
                      _amountCtrl.text = regAmtStr;
                      _complianceAppId = null;
                      _complianceType = null;
                      _complianceDocs = [];
                      _complianceStatus = '';
                    } else if (v.toLowerCase().contains('new member') || v.toLowerCase().contains('package') || v.toLowerCase().contains('entrance')) {
                      _amountCtrl.text = packageAmtStr;
                      _complianceAppId = null;
                      _complianceType = null;
                      _complianceDocs = [];
                      _complianceStatus = '';
                    } else if (v.toLowerCase().contains('renewal')) {
                      _setRenewalScope(_renewalScope);
                      _complianceAppId = null;
                      _complianceDocs = [];
                      _complianceStatus = '';
                    } else {
                      final fee = _fees.firstWhere(
                        (f) => (f['label'] ?? f['name'] ?? '').toString() == v,
                        orElse: () => null,
                      );
                      if (fee != null) {
                        _amountCtrl.text = _formatFeeAmount(fee['amount']);
                      }
                      _complianceAppId = null;
                      _complianceType = null;
                      _complianceDocs = [];
                      _complianceStatus = '';
                    }
                  });
                },
              );
            },
          ),
          // ── Payment mode selector (Full Balance vs Part-Payment / Installment) for ALL bills ──
          if (_reason.isNotEmpty && _allowInstallments && _getCurrentBillTotal() > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pie_chart_outline_rounded, size: 16, color: _kOrange),
                      const SizedBox(width: 8),
                      Text(
                        'PAYMENT OPTION',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: _kOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isInstallmentMode = false;
                              final fullBal = _getCurrentBillTotal();
                              _amountCtrl.text = fullBal > 0 ? fullBal.toStringAsFixed(2) : _amountCtrl.text;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: !_isInstallmentMode
                                  ? _kOrange.withAlpha(25)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !_isInstallmentMode
                                    ? _kOrange
                                    : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                width: !_isInstallmentMode ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Full Payment',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: !_isInstallmentMode
                                        ? _kOrange
                                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'GH₵ ${_getCurrentBillTotal().toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isInstallmentMode = true;
                              final billTot = _getCurrentBillTotal();
                              if (_minInstallmentAmount > 0) {
                                _amountCtrl.text = _minInstallmentAmount.toStringAsFixed(2);
                              } else if (billTot > 0) {
                                final half = (billTot / 2).clamp(1.0, billTot);
                                _amountCtrl.text = half.toStringAsFixed(2);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: _isInstallmentMode
                                  ? _kOrange.withAlpha(25)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isInstallmentMode
                                    ? _kOrange
                                    : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                width: _isInstallmentMode ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Installment',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: _isInstallmentMode
                                        ? _kOrange
                                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _minInstallmentAmount > 0
                                      ? 'Min GH₵ ${_minInstallmentAmount.toStringAsFixed(2)}'
                                      : 'Flexible Installment',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            _isInstallmentMode ? 'INSTALLMENT AMOUNT TO PAY' : 'AMOUNT TO PAY',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748b),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFf8fafc),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFcbd5e1).withAlpha(120),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFe2e8f0),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                    border: Border(
                      right: BorderSide(
                        color: const Color(0xFFcbd5e1).withAlpha(120),
                        width: 1.5,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'GH₵',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    onChanged: (v) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    readOnly: (_reason.isNotEmpty && _reason != 'Other') && !_isInstallmentMode,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A0F0A),
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      hintText: (_reason.toLowerCase().contains('renewal') && (_renewalFeeAmount == null || _renewalFeeAmount == 0))
                          ? 'Bill Pending (Submit Docs)'
                          : '0.00',
                      suffixIcon: _isInstallmentMode
                          ? const Tooltip(
                              message: 'Editable installment amount',
                              child: Icon(Icons.edit_note_rounded, color: _kOrange, size: 22),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isInstallmentMode) ...[
            Builder(
              builder: (ctx) {
                final enteredAmt = double.tryParse(_amountCtrl.text) ?? 0.0;
                final maxBal = _getCurrentBillTotal() > 0 ? _getCurrentBillTotal() : double.infinity;
                final minBal = _minInstallmentAmount > 0 ? _minInstallmentAmount : 1.0;

                if (_amountCtrl.text.isNotEmpty && enteredAmt < (minBal - 0.01)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Minimum installment is GH₵ ${minBal.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }
                if (_amountCtrl.text.isNotEmpty && enteredAmt > (maxBal + 0.01)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Cannot exceed remaining balance of GH₵ ${maxBal.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }
                if (minBal >= (maxBal - 0.01)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: _kAmber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Remaining balance due: GH₵ ${maxBal.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _kAmber,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 13, color: _kOrange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Installment active: enter partial amount to pay now (Min GH₵ ${minBal.toStringAsFixed(2)}). You can settle the remaining balance in future installments.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: _kOrange, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),

          // ── Fee Breakdown Card (Registration Fee vs New Membership Package) ──
          if (_reason.toLowerCase().contains('registration')) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFFF8F4F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kOrange.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'REGISTRATION FEE BREAKDOWN',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kOrange.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'One-Time',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Registration Fee',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A0F0A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Paid separately upon registration before statutory documents are vetted.',
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  color: isDark
                                      ? Colors.white60
                                      : const Color(0xFF64748b),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'GHS ${_amountCtrl.text.isNotEmpty ? _amountCtrl.text : "600.00"}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0f172a),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL PAYABLE',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text.isNotEmpty ? _amountCtrl.text : "600.00"}',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0f172a),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (_regFeeBreakdown.isNotEmpty &&
              (_reason.toLowerCase().contains('new member') ||
               _reason.toLowerCase().contains('package') ||
               _reason.toLowerCase().contains('entrance'))) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFFF8F4F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kOrange.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'NEW MEMBERSHIP DUES BREAKDOWN',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                            letterSpacing: 0.5,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ..._regFeeBreakdown.map((item) {
                    final rawLabel = item['label']?.toString() ?? '';
                    final cleanLabel = _cleanFeeLabel(rawLabel);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              cleanLabel,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'GHS ${item['amount']?.toString() ?? ''}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0f172a),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Payable:',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text}',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFea580c),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── Renewal Scope Selector Card (Combined vs National vs District) ──
          if (_reason.toLowerCase().contains('renewal')) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(8) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 25 : 6),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kOrange.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.alt_route_rounded,
                          color: _kOrange,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SELECT RENEWAL SCOPE',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _kOrange,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              'Choose your statutory renewal coverage',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildRenewalScopeTile(
                    scopeKey: 'combined',
                    title: 'Full Annual Renewal (National + District)',
                    subtitle: 'Statutory subscription, admin, legal-audit, CPD, & district clearance',
                    amount: _combinedRenewalTotal ?? (_renewalFeeAmount ?? 1383.0),
                    isDark: isDark,
                    isRecommended: true,
                  ),
                  const SizedBox(height: 10),
                  _buildRenewalScopeTile(
                    scopeKey: 'national',
                    title: 'National Renewal Dues Only',
                    subtitle: 'Statutory subscription, administrative fee, legal & audit, CPD course',
                    amount: _nationalRenewalTotal ?? 1133.0,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildRenewalScopeTile(
                    scopeKey: 'district',
                    title: 'District Clearance Only',
                    subtitle: 'District clearance for your registered operational port / district',
                    amount: _districtRenewalTotal ?? 250.0,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],

          // ── Installment Progress Overview Card (When partially paid or installments active) ──
          if (_reason.toLowerCase().contains('renewal') && (_renewalAmountPaid > 0 || _isPartiallyPaid || _isInstallmentMode)) ...[
            _buildInstallmentOverviewCard(isDark),
          ],

          // ── Itemized Fee Breakdown Card (For Annual Renewal Dues) ──
          if (_renewalFeeBreakdown.isNotEmpty &&
              _reason.toLowerCase().contains('renewal')) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFFF8F4F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kOrange.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'ANNUAL RENEWAL & DISTRICT CLEARANCE BREAKDOWN',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                            letterSpacing: 0.5,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  // National Section Header if present
                  Builder(builder: (context) {
                    final nationalItems = _renewalFeeBreakdown.where((x) => x['section'] == 'national').toList();
                    final districtItems = _renewalFeeBreakdown.where((x) => x['section'] == 'district').toList();
                    final otherItems = _renewalFeeBreakdown.where((x) => x['section'] != 'national' && x['section'] != 'district').toList();

                    Widget buildItemRow(Map<String, dynamic> item) {
                      final rawLabel = item['label']?.toString() ?? '';
                      final cleanLabel = _cleanFeeLabel(rawLabel);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cleanLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'GHS ${item['amount']?.toString() ?? ''}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0f172a),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nationalItems.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 14, color: _kBlue),
                              const SizedBox(width: 6),
                              Text(
                                'NATIONAL STATUTORY CHARGES',
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kBlue, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...nationalItems.map(buildItemRow),
                          const SizedBox(height: 10),
                        ],
                        if (districtItems.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.location_city_outlined, size: 14, color: _kGreen),
                              const SizedBox(width: 6),
                              Text(
                                'DISTRICT OPERATIONAL CLEARANCE',
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kGreen, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...districtItems.map(buildItemRow),
                          const SizedBox(height: 10),
                        ],
                        if (otherItems.isNotEmpty) ...[
                          ...otherItems.map(buildItemRow),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }),

                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isInstallmentMode ? 'Paying This Installment:' : 'Total Payable:',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text}',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFea580c),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── Inline license block warning (only for license/renewal/dues) ──
          if (_isLicenseBlocked && _reason.isNotEmpty) ...[
            () {
              final r = _reason.toLowerCase();
              final isLicenseReason =
                  r.contains('license') ||
                  r.contains('renewal') ||
                  r.contains('dues') ||
                  r.contains('annual fee');
              if (!isLicenseReason) return const SizedBox.shrink();
              final expiryStr = _licenseExpiry != null
                  ? '${_monthName(_licenseExpiry!.month)} ${_licenseExpiry!.day}, ${_licenseExpiry!.year}'
                  : '';
              final renewStr = _renewalOpenDate != null
                  ? '${_monthName(_renewalOpenDate!.month)} ${_renewalOpenDate!.day}, ${_renewalOpenDate!.year}'
                  : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF10b981).withAlpha(80),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF10b981),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your license is active until $expiryStr. '
                        'Renewal opens $renewStr (30 days before expiry).',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          height: 1.5,
                          color: const Color(0xFF065f46),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }(),
          ],

          Builder(
            builder: (ctx) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              final r = _reason.toLowerCase();
              final isLicenseReason =
                  r.contains('license') ||
                  r.contains('renewal') ||
                  r.contains('dues') ||
                  r.contains('annual fee');
              final isRenewal = r.contains('renewal');
              final amt = double.tryParse(_amountCtrl.text) ?? 0.0;
              final maxPayable = _renewalBalanceDue > 0
                  ? _renewalBalanceDue
                  : (_renewalFeeAmount ?? double.infinity);
              final minPayable = _minInstallmentAmount > 0
                  ? _minInstallmentAmount
                  : 1.0;

              final bool hasOfficialRenewalBill = isRenewal &&
                  ((_renewalFeeAmount != null && _renewalFeeAmount! > 0) ||
                      (_amountCtrl.text.isNotEmpty && amt > 0 && _complianceAppId != null));

              // If it's renewal but no official bill has been issued by admin yet:
              if (isRenewal && !hasOfficialRenewalBill) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(50)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Document submission is Step 1. The Secretariat will vet your documents and issue your official renewal bill before payment can be made.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Faded-out Pay button
                    Opacity(
                      opacity: 0.45,
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.lock_outline_rounded, size: 18),
                          label: Text(
                            'Pay Annual Renewal Dues (Documents Required)',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Active Step 1 button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await ApiService.deleteCacheKeysMatching('compliance');
                          if (!mounted) return;
                          context.go('/compliance');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(
                          'Submit Renewal Documents (Step 1)',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (_isRenewalFullyPaid) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B).withAlpha(40) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF059669).withAlpha(100), width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ANNUAL RENEWAL DUES SETTLED',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your Annual Renewal Dues (National & District Clearance) have already been fully paid and confirmed for the current operational cycle. No further renewal payment or document submission is required at this time.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: isDark ? Colors.white70 : const Color(0xFF065F46),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          disabledBackgroundColor: const Color(0xFF059669).withAlpha(120),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: Text(
                          'Annual Renewal Already Settled',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        label: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                );
              }

              bool isAmountValid = amt > 0;
              if (_isInstallmentMode) {
                if (amt < (minPayable - 0.01) || (maxPayable < double.infinity && amt > (maxPayable + 0.01))) {
                  isAmountValid = false;
                }
              }

              // Block only if: license is active AND reason is license-related
              final canContinue =
                  _reason.isNotEmpty &&
                  _amountCtrl.text.isNotEmpty &&
                  isAmountValid &&
                  !(_isLicenseBlocked && isLicenseReason);
              final isNoDoc = _isNoDocPaymentReason;
              return SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: canContinue
                      ? () async {
                          if (isNoDoc) {
                            setState(() => _step = 3);
                          } else {
                            if (_isComplianceReason(_reason)) {
                              _complianceType = _complianceTypeForReason(_reason);
                              await _prepareComplianceApplication();
                            }
                            if (mounted) setState(() => _step = 2);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: Text(
                    isNoDoc
                        ? 'Continue to Payment Method'
                        : 'Continue to Documents',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  label: const Icon(Icons.arrow_forward_rounded, size: 16),
                ),
              );
            },
          ),
        ],
      );
    }

    if (_step == 2) {
      if (!_requiresDocuments) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _step = 3);
        });
        return const SizedBox.shrink();
      }

      final title = _complianceType == 'renewal_national'
          ? 'National Renewal Documents'
          : (_complianceType == 'renewal_district'
              ? 'District Clearance Documents'
              : (_complianceType == 'renewal'
                  ? 'Membership Renewal Documents'
                  : 'Customs License Credentials'));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6),
                width: 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kOrange.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: _kOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STEP 2: SUPPORTING DOCUMENTS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _kOrange,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    await ApiService.deleteCacheKeysMatching('compliance');
                    if (!mounted) return;
                    context.go('/compliance');
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_new_rounded, size: 15, color: _kOrange),
                        const SizedBox(width: 6),
                        Text(
                          'Compliance Centre',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: _kOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (true) ...[
            if (_appLoading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2.5),
                      SizedBox(height: 14),
                      Text(
                        'Loading application details...',
                        style: TextStyle(
                          color: Color(0xFF64748b),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_complianceAppId == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.assignment_add,
                            color: _kOrange,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Application Entry',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A0F0A),
                                ),
                              ),
                              Text(
                                'Initiate your compliance application to upload required files.',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: const Color(0xFF64748b),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This payment category requires valid compliance documentation. Click below to start your application and upload required documents.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: const Color(0xFF475569),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _prepareComplianceApplication,
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Initialize Application',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Application Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary.withAlpha(15), primary.withAlpha(5)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.verified_rounded,
                        color: primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'APPLICATION STATUS',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF64748b),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _complianceStatus.isNotEmpty
                                ? _complianceStatus
                                      .replaceAll('_', ' ')
                                      .toUpperCase()
                                : 'DRAFT',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _complianceStatus == 'revision_requested'
                                  ? _kAmber
                                  : _kNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _allComplianceDocsUploaded
                            ? _kGreen.withAlpha(25)
                            : _kAmber.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _allComplianceDocsUploaded ? 'Ready' : 'Incomplete',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _allComplianceDocsUploaded ? _kGreen : _kAmber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Required Documents List
              Text(
                'REQUIRED DOCUMENTS',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748b),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Column(
                children: _complianceDocs.map((doc) {
                  final uploaded = doc['uploaded'] == true;
                  final requirement = doc['label']?.toString() ?? 'Document';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: uploaded
                            ? _kGreen.withAlpha(60)
                            : const Color(0xFFe2e8f0),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: uploaded
                                    ? _kGreen.withAlpha(20)
                                    : const Color(0xFFf1f5f9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                uploaded
                                    ? Icons.check_circle_rounded
                                    : Icons.upload_file_rounded,
                                color: uploaded ? _kGreen : const Color(0xFF64748b),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    requirement,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: const Color(0xFF1A0F0A),
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        uploaded ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                        size: 13,
                                        color: uploaded ? _kGreen : const Color(0xFF94a3b8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        uploaded
                                            ? 'Uploaded & Verified'
                                            : 'Required for submission',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: uploaded
                                              ? _kGreen
                                              : const Color(0xFF64748b),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () => _uploadComplianceDoc(doc),
                            icon: Icon(
                              uploaded
                                  ? Icons.refresh_rounded
                                  : Icons.file_upload_outlined,
                              size: 16,
                            ),
                            label: Text(
                              uploaded ? 'Replace Document' : 'Upload Document',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: uploaded
                                  ? const Color(0xFFf1f5f9)
                                  : primary,
                              foregroundColor: uploaded
                                  ? const Color(0xFF4D2D20)
                                  : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: uploaded ? const Color(0xFFcbd5e1) : Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],

          const SizedBox(height: 24),

          // Standard Navigation Bar for Step 2
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_isComplianceReason(_reason) &&
                        (_complianceStatus == 'draft' ||
                            _complianceStatus == 'revision_requested')) {
                      _submitComplianceApplication();
                    }
                    setState(() => _step = 3);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    'Continue to Payment Method',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _step = 1),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(
                    'Back to Fee Details',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFcbd5e1),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: const Color(0xFF64748b),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_step == 3) {
      final cleanDigits = _normalizeGhanaPhone(_momoPhone);
      final isPhoneValid = cleanDigits.length == 10;
      final canProceed = _momoNetwork.isNotEmpty && isPhoneValid;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Payment Channel: Mobile Money (Instant) ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_android_rounded,
                  color: _kOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PAYMENT CHANNEL',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: const Color(0xFF64748b),
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    'Mobile Money (Instant Verification)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: const Color(0xFF1A0F0A),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── CHANNEL: MOBILE MONEY ──
          Text(
            'SELECT MOBILE CARRIER',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: const Color(0xFF64748b),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final entry in const [
                  {'id': 'MTN', 'label': 'MTN'},
                  {'id': 'Telecel', 'label': 'Telecel'},
                  {'id': 'AirtelTigo', 'label': 'AirtelTigo'},
                ]) ...[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: entry['id'] == 'AirtelTigo' ? 0 : 8,
                      ),
                      child: GestureDetector(
                        onTap: () => setState(() => _momoNetwork = entry['id']!),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: _momoNetwork == entry['id']
                                ? _kOrange.withAlpha(18)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _momoNetwork == entry['id']
                                  ? _kOrange
                                  : const Color(0xFFcbd5e1),
                              width: _momoNetwork == entry['id'] ? 2.0 : 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_momoNetwork == entry['id']) ...[
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 15,
                                  color: _kOrange,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  entry['label']!,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: _momoNetwork == entry['id']
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: _momoNetwork == entry['id']
                                        ? _kOrange
                                        : const Color(0xFF334155),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Text(
                  'MOMO NUMBER',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: const Color(0xFF64748b),
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                if (_momoNetwork.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _kOrange.withAlpha(90),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: _kOrange,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _carrierName(_momoNetwork),
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: _kOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPhoneValid
                      ? _kOrange
                      : (_momoPhone.isNotEmpty
                          ? const Color(0xFF94a3b8)
                          : const Color(0xFFcbd5e1)),
                  width: isPhoneValid ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isPhoneValid
                        ? _kOrange.withAlpha(20)
                        : Colors.black.withAlpha(4),
                    blurRadius: isPhoneValid ? 10 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_iphone_rounded,
                    size: 22,
                    color: isPhoneValid ? _kOrange : const Color(0xFF94a3b8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _momoPhone,
                      onChanged: (v) {
                        final clean = _normalizeGhanaPhone(v);
                        setState(() {
                          _momoPhone = clean;
                        });
                      },
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                        color: const Color(0xFF1e293b),
                      ),
                      decoration: InputDecoration(
                        hintText: '024XXXXXXX (10 digits)',
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF94a3b8),
                          fontSize: 17,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                        counterText: "",
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _momoNetwork.isEmpty
                    ? 'Please select your mobile carrier (MTN, Telecel, or AirtelTigo) above.'
                    : (!isPhoneValid
                        ? 'Enter your 10-digit ${_carrierName(_momoNetwork)} number.'
                        : '✓ ${_carrierName(_momoNetwork)} (Push prompt ready)'),
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: (_momoNetwork.isNotEmpty && isPhoneValid)
                      ? _kOrange
                      : const Color(0xFF64748b),
                  fontWeight: (_momoNetwork.isNotEmpty && isPhoneValid)
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF8FAFC),
                    Color(0xFFF1F5F9),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      size: 18,
                      color: _kOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Direct USSD Push Authorization',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: const Color(0xFF0f172a),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'A PIN authorization prompt will appear on your phone screen automatically once you proceed.',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: const Color(0xFF475569),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Action Buttons
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: !canProceed
                      ? null
                      : () => setState(() => _step = 4),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    _momoNetwork.isNotEmpty
                        ? 'Continue with ${_carrierName(_momoNetwork)}'
                        : 'Select Carrier to Continue',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFcbd5e1),
                    disabledForegroundColor: const Color(0xFF94a3b8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: Builder(
                  builder: (ctx) {
                    final isNoDoc = _isNoDocPaymentReason;
                    return OutlinedButton.icon(
                      onPressed: () => setState(() => _step = isNoDoc ? 1 : 2),
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: Text(
                        isNoDoc
                            ? 'Back to Payment Type'
                            : 'Back to Supporting Documents',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFcbd5e1),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: const Color(0xFF64748b),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_step == 4) {
      final methodLabel = _momoNetwork.isNotEmpty
          ? 'MOMO (${_momoNetwork.toUpperCase()})'
          : 'MOMO';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 35 : 10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kOrange, Color(0xFFea580c)],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'DIGITAL INVOICE SUMMARY',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'VERIFIED INVOICE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 9.5,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hero Amount Card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(6) : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kOrange.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL PAYABLE AMOUNT',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFC2410C),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'GH₵ ${double.tryParse(_amountCtrl.text)?.toStringAsFixed(2) ?? _amountCtrl.text}',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _kOrange,
                          ),
                        ),
                      ),
                      if (_isInstallmentMode) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'PARTIAL INSTALLMENT  •  Remaining Balance: GH₵ ${((_renewalBalanceDue - (double.tryParse(_amountCtrl.text) ?? 0.0)).clamp(0.0, double.infinity)).toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                _buildInvoiceRow(
                  'Payment Category',
                  _reason.toLowerCase().contains('renewal')
                      ? (_renewalScope == 'national'
                          ? 'National Renewal Dues'
                          : (_renewalScope == 'district'
                              ? 'District Clearance Only'
                              : 'Annual Renewal (National & District)'))
                      : _reason,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                _buildInvoiceRow(
                  'Selected Method',
                  methodLabel,
                ),
                if (_momoPhone.isNotEmpty) ...[
                  Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                  _buildInvoiceRow(
                    'MoMo Account',
                    _momoPhone,
                  ),
                ],

                // Itemized Breakdown inside the Digital Invoice Voucher
                if (_renewalFeeBreakdown.isNotEmpty && _reason.toLowerCase().contains('renewal')) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'ITEMIZED CHARGES BREAKDOWN',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(4) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        for (final it in _renewalFeeBreakdown)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _cleanFeeLabel(it['label']?.toString() ?? ''),
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'GH₵ ${double.tryParse(it['amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? it['amount']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = 3),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(50, 50),
                  side: const BorderSide(color: Color(0xFFcbd5e1), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: const Color(0xFF475569),
                ),
                child: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_loading || _submittingPayment) ? null : _submitPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: (_loading || _submittingPayment)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Initiate Mobile Payment',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_step == 5) {
      final remaining = (_pollMax - _pollAttempt) * 5;
      final progressVal = _pollMax > 0 ? _pollAttempt / _pollMax : 0.0;

      return Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primary.withAlpha(140), primary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Awaiting Approval',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A0F0A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A MoMo prompt has been sent to $_momoPhone.\nOpen your phone and enter your PIN to approve.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748b),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          () {
            String noticeTitle = 'MTN MoMo Approval Notice';
            String noticeText =
                'If the prompt does not pop up, dial *170# → Option 6 (My Wallet) → Option 3 (My Approvals) on your phone to approve.';

            if (_momoNetwork == 'Telecel' || _momoNetwork == 'Vodafone') {
              noticeTitle = 'Telecel Cash Approval Notice';
              noticeText =
                  'If the prompt does not pop up, dial *110# → Option 4 (My Account) → Option 5 (Pending Approvals) on your phone to approve.';
            } else if (_momoNetwork == 'AirtelTigo') {
              noticeTitle = 'AT (AirtelTigo) Approval Notice';
              noticeText =
                  'If the prompt does not pop up, dial *110# → Option 5 (My Wallet) → Pending Approvals on your phone to approve.';
            }

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primary.withAlpha(12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withAlpha(30)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: primary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          noticeTitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    noticeText,
                    style: const TextStyle(
                      color: Color(0xFF4D2D20),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }(),

          const SizedBox(height: 24),
          if (_pollAttempt >= _pollMax) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                'Auto-checking timed out. If you have approved the payment on your phone, click "I\'ve Approved — Check Now" below to complete.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 6,
              backgroundColor: primary.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Checking status... (attempt ${_pollAttempt + 1}/$_pollMax)',
                style: const TextStyle(fontSize: 10, color: Color(0xFF94a3b8)),
              ),
              Text(
                '~${remaining}s left',
                style: const TextStyle(fontSize: 10, color: Color(0xFF94a3b8)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _manualChecking ? null : _manualStatusCheck,
              icon: _manualChecking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
              label: Text(
                _manualChecking ? 'Verifying...' : "I've Approved — Check Now",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10b981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _step = 4;
              _pollAttempt = 0;
              _currentTxRef = '';
            }),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF64748b),
            ),
            child: Text(
              'Cancel & Change Method',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      );
    }

    // This block should never execute because all states are handled above.
    return const SizedBox.shrink();
  }

  String _carrierName(String net) {
    if (net == 'MTN') return 'MTN MoMo';
    if (net == 'Telecel' || net == 'Vodafone') return 'Telecel Cash';
    if (net == 'AirtelTigo') return 'AT Money';
    return 'MoMo';
  }

  Widget _buildRenewalScopeTile({
    required String scopeKey,
    required String title,
    required String subtitle,
    required double amount,
    required bool isDark,
    bool isRecommended = false,
  }) {
    final isSelected = _renewalScope == scopeKey;
    return InkWell(
      onTap: () => _setRenewalScope(scopeKey),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? _kOrange.withAlpha(isDark ? 30 : 15)
              : (isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _kOrange
                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? _kOrange : const Color(0xFF94A3B8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          if (isRecommended)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'RECOMMENDED',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'GH₵ ${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? _kOrange : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, {bool isFullWidth = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: isFullWidth ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: isFullWidth ? Alignment.centerLeft : Alignment.center,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentOverviewCard(bool isDark) {
    final totalBilled = (_renewalFeeAmount != null && _renewalFeeAmount! > 0)
        ? _renewalFeeAmount!
        : (_renewalAmountPaid + _renewalBalanceDue);
    final progress = (totalBilled > 0)
        ? (_renewalAmountPaid / totalBilled).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF059669).withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFF059669)),
                  const SizedBox(width: 6),
                  Text(
                    'INSTALLMENT PLAN OVERVIEW',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF059669),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (_isPartiallyPaid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PARTIALLY PAID',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Paid to date reflects the cumulative payments made towards this bill. Remaining balance can be cleared in one or multiple installments.',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: const Color(0xFF065F46),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 340 || MediaQuery.textScalerOf(context).scale(14) > 15;
              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            'TOTAL BILLED',
                            'GH₵ ${totalBilled.toStringAsFixed(2)}',
                            isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            'PAID TO DATE',
                            'GH₵ ${_renewalAmountPaid.toStringAsFixed(2)}',
                            const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildMetricTile(
                      'BALANCE DUE',
                      'GH₵ ${_renewalBalanceDue.toStringAsFixed(2)}',
                      const Color(0xFFD97706),
                      isFullWidth: true,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'TOTAL BILLED',
                      'GH₵ ${totalBilled.toStringAsFixed(2)}',
                      isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildMetricTile(
                      'PAID TO DATE',
                      'GH₵ ${_renewalAmountPaid.toStringAsFixed(2)}',
                      const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildMetricTile(
                      'BALANCE DUE',
                      'GH₵ ${_renewalBalanceDue.toStringAsFixed(2)}',
                      const Color(0xFFD97706),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_isInstallmentMode) ...[
            const Divider(height: 20),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Remaining After This Payment:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  'GH₵ ${((_renewalBalanceDue - (double.tryParse(_amountCtrl.text) ?? 0.0)).clamp(0.0, double.infinity)).toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _kOrange,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInvoiceRow(String label, String value, {bool isHighlight = false, bool isAttachment = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeText = MediaQuery.textScalerOf(context).scale(14) > 16;
          if (isLargeText || constraints.maxWidth < 320) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                isAttachment
                    ? Row(
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 14, color: _kOrange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        value,
                        style: GoogleFonts.inter(
                          fontSize: isHighlight ? 18 : 14.5,
                          fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w700,
                          color: isHighlight ? _kOrange : const Color(0xFF1E293B),
                        ),
                      ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: isAttachment
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 14, color: _kOrange),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        value,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          fontSize: isHighlight ? 18 : 14,
                          fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w700,
                          color: isHighlight ? _kOrange : const Color(0xFF1E293B),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
