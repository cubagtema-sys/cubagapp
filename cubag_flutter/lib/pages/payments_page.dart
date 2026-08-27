import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart' show Response, Options, Dio;
import '../components/app_layout.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/whitsun_pay_service.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRed = Color(0xFFef4444);
const _kNavy = Color(0xFF1A0F0A);

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
  String _method = 'momo';
  String _momoNetwork = '';
  String _momoPhone = '';
  int? _complianceAppId;
  String? _complianceType;
  List<dynamic> _complianceDocs = [];
  String _complianceStatus = '';
  bool _appLoading = false;
  bool _submittingApplication = false;
  bool _loading = false;
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
  String _regFeeCategoryTitle = '';
  String _upfrontRegFeeStr = '600.00';
  String _packageFeeStr = '1620.00';
  List<Map<String, dynamic>> _renewalFeeBreakdown = [];
  String _renewalFeeCategoryTitle = '';
  double? _renewalFeeAmount;

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
    _loadData();

    // Listen to real-time fee schedule changes from Admin
    SocketService().socket?.on('fees_updated', _onFeesUpdatedSocket);
  }

  void _onFeesUpdatedSocket(dynamic _) {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    SocketService().socket?.off('fees_updated', _onFeesUpdatedSocket);
    SocketService().socket?.off('payment_approved');
    _pulseController.dispose();
    _amountCtrl.dispose();
    super.dispose();
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

  String _detectNetworkFromPhone(String phone) {
    final clean = _normalizeGhanaPhone(phone);
    if (clean.length < 3) return '';
    final prefix = clean.substring(0, 3);

    // MTN: 024, 025, 053, 054, 055, 059
    if (['024', '025', '053', '054', '055', '059'].contains(prefix)) {
      return 'MTN';
    }
    // Telecel (Vodafone): 020, 050
    if (['020', '050'].contains(prefix)) {
      return 'Vodafone';
    }
    // AT (AirtelTigo): 026, 056, 027, 057
    if (['026', '056', '027', '057'].contains(prefix)) {
      return 'AirtelTigo';
    }
    return '';
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loadingData = true);
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
        _regFeeCategoryTitle = docData['fee_category_title']?.toString() ?? '';
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
            _memberInfo =
                (meRes.data['member'] ?? meRes.data) as Map<String, dynamic>;
            final rawRenewalBreakdown = _memberInfo['renewal_fee_breakdown'];
            if (rawRenewalBreakdown is List) {
              _renewalFeeBreakdown = rawRenewalBreakdown
                  .map((x) => Map<String, dynamic>.from(x as Map))
                  .toList();
            }
            _renewalFeeCategoryTitle =
                _memberInfo['renewal_fee_title']?.toString() ?? '';
            final rawRenewalAmt = _memberInfo['renewal_fee_amount'];
            if (rawRenewalAmt != null) {
              _renewalFeeAmount = double.tryParse(rawRenewalAmt.toString());
            }
            _isRegFeePaid = regPaidFromDoc ||
                _memberInfo['registration_fee_paid'] == true ||
                _memberInfo['registration_paid'] == true ||
                _memberInfo['application_fee_paid'] == true;
            _isPackageFeePaid = _memberInfo['package_fee_paid'] == true;
          } else {
            _isRegFeePaid = regPaidFromDoc;
          }
          // Compute license expiry
          final expiryRaw = _memberInfo['license_expiry_date'];
          _licenseExpiry = expiryRaw != null
              ? DateTime.tryParse(expiryRaw.toString())
              : null;
          _isLicenseBlocked = false;

          // Check query parameters for fee pre-selection & redirect return route
          final state = GoRouterState.of(context);
          final redirectUrl = state.uri.queryParameters['redirect'];
          final queryFee = state.uri.queryParameters['fee'];
          
          if (queryFee != null && queryFee.isNotEmpty) {
            final qfLower = queryFee.toLowerCase();
            if (qfLower.contains('registration') || redirectUrl == '/application-documents') {
              _reason = 'Registration Fee';
              _isCategoryLocked = true;
            } else if (qfLower.contains('package') || qfLower.contains('entrance') || qfLower.contains('new member')) {
              _reason = 'New Membership Dues';
              _isCategoryLocked = true;
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
          } else {
            _reason = 'Annual Renewal Dues';
          }

          if (_reason == 'Registration Fee') {
            _amountCtrl.text = _upfrontRegFeeStr;
          } else if (_reason == 'New Membership Dues' || _reason.toLowerCase().contains('package') || _reason.toLowerCase().contains('entrance') || _reason.toLowerCase().contains('new member')) {
            _reason = 'New Membership Dues';
            _amountCtrl.text = _packageFeeStr;
          } else if (_reason.toLowerCase().contains('renewal') &&
              _renewalFeeAmount != null &&
              _renewalFeeAmount! > 0) {
            _amountCtrl.text = _renewalFeeAmount!.toStringAsFixed(2);
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
    if (_loading) return;
    final amt = double.tryParse(_amountCtrl.text) ?? 0;
    if (amt <= 0) {
      setState(() {
        _errorMsg = 'Please enter a valid amount greater than 0.';
        _showError = true;
      });
      return;
    }
    if (_method == 'momo' && _momoPhone.trim().isEmpty) {
      setState(() {
        _errorMsg = 'Please enter your Mobile Money phone number.';
        _showError = true;
      });
      return;
    }
    final effectiveReason = _reason.trim().isEmpty
        ? 'Association Payment'
        : _reason;

    setState(() => _loading = true);

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
      final requestData = {
        'amount': amt,
        'description': effectiveReason,
        'method': _method,
        'network': _momoNetwork,
        'phone': _momoPhone,
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
                              Icons.event_available_rounded,
                              size: 16,
                              color: _kOrange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Renewal opens: $renewalOpens',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
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
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          // ── Completed Payment Guard
        } else if (res.data is Map &&
            res.data['error_code'] == 'PAYMENT_ALREADY_COMPLETED') {
          final msg =
              res.data['message'] ??
              'Payment for this item has already been completed.';
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
          final paymentId = res.data['payment_id'];
          final txRef =
              res.data['transaction_ref'] ?? res.data['whitsun_ref'] ?? '';
          // Update IDs now that we have them from the server, then start polling
          if (mounted) {
            setState(() {
              _currentPaymentId = paymentId;
              _currentTxRef = txRef;
            });
          }
          // Directly dispatch MoMo authorization prompt from mobile device to WhitsunPay (bypasses Cloudflare block)
          WhitsunPayService().dispatchPrompt(
            txRef: txRef.toString(),
            phone: _momoPhone,
            network: _momoNetwork,
            amount: amt,
            description: effectiveReason,
            serverDispatchData: res.data is Map && res.data['gateway_dispatch'] is Map
                ? Map<String, dynamic>.from(res.data['gateway_dispatch'] as Map)
                : null,
          );
          _pollWhitsunPayStatus(paymentId, txRef);
        } else {
          _confirmedAmount = _amountCtrl.text;
          _handlePaymentSuccess();
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
    if (mounted) setState(() => _loading = false);
  }



  bool get _isNoDocPaymentReason {
    final r = _reason.toLowerCase();
    return r.contains('registration') ||
        r.contains('new membership') ||
        r.contains('membership dues') ||
        r.contains('entrance') ||
        r.contains('onboarding');
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
    if (value.contains('renewal')) return 'renewal';
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
          data: {'type': _complianceType},
        );
        final rawId = res.data['application_id'];
        _complianceAppId = rawId is int
            ? rawId
            : int.tryParse(rawId?.toString() ?? '');
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
                style: GoogleFonts.outfit(
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
        final ext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'pdf';
        final size = file.size;

        uploadTasks.add(() async {
          final signRes = await ApiService().post(
            '/compliance/applications/$_complianceAppId/sign-upload',
            data: {
              'requirement': key,
              'label': docReq['label'],
              'ext': ext,
              'size': size,
            },
          );
          if (signRes.statusCode != 200) {
            throw Exception(signRes.data['message'] ?? 'Sign failed');
          }

          final uploadUrl = signRes.data['upload_url'] as String;
          final publicUrl = signRes.data['public_url'] as String;
          final supaKey = signRes.data['supabase_key'] as String;
          late Uint8List bytes;
          if (file.bytes != null) {
            bytes = file.bytes!;
          } else {
            bytes = await file.xFile.readAsBytes();
          }
          final mimeMap = {
            'pdf': 'application/pdf',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
          };
          final mime = mimeMap[ext] ?? 'application/octet-stream';

          await Dio().put(
            uploadUrl,
            data: bytes,
            options: Options(
              headers: {
                'apikey': supaKey,
                'Authorization': 'Bearer $supaKey',
                'Content-Type': mime,
                'Content-Length': bytes.length,
                'x-upsert': 'true',
              },
              contentType: mime,
            ),
          );

          await ApiService().post(
            '/compliance/applications/${_complianceAppId!}/confirm-upload',
            data: {
              'requirement': key,
              'label': docReq['label'],
              'public_url': publicUrl,
              'filename': file.name,
              'size': size,
            },
          );
        }());
      }

      await Future.wait(uploadTasks);

      if (!mounted) return;
      _showSnack('${docReq['label']} uploaded!', color: _kGreen);
      await _loadComplianceApplicationDetails(_complianceAppId!);
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', color: _kRed);
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
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(msg, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
      if (pId == paymentId || pId == null) {
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
          final status = res.data['status']?.toString().toLowerCase() ?? '';
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
                    res.data['message'] ?? 'Payment was declined or cancelled.';
                _showError = true;
                _step = 1;
              });
            }
          }
        }
      } catch (e) {
        // continue
      }

      // Direct client check with WhitsunPay to bypass any Cloudflare backend block
      if (!isComplete && mounted && txRef.isNotEmpty) {
        try {
          final directCheck = await WhitsunPayService().checkStatus(txRef);
          if (directCheck['isPaid'] == true) {
            isComplete = true;
            try {
              await api.post(
                '/payments/verify-code',
                data: {
                  'payment_id': paymentId,
                  'transaction_ref': txRef,
                  'whitsun_ref': txRef,
                  'client_verified': true,
                  'client_tx_id': directCheck['txId'] ?? '',
                },
              );
            } catch (_) {}
            if (mounted) _handlePaymentSuccess();
            break;
          }
        } catch (_) {}
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
      final status = res.data['status']?.toString().toLowerCase() ?? '';
      if (status == 'success' ||
          status == 'successful' ||
          status == 'completed') {
        _handlePaymentSuccess();
        return;
      }

      // Check WhitsunPay directly from device in case backend was blocked by Cloudflare
      final directCheck = await WhitsunPayService().checkStatus(_currentTxRef);
      if (directCheck['isPaid'] == true) {
        try {
          await api.post(
            '/payments/verify-code',
            data: {
              'payment_id': _currentPaymentId,
              'transaction_ref': _currentTxRef,
              'whitsun_ref': _currentTxRef,
              'client_verified': true,
              'client_tx_id': directCheck['txId'] ?? '',
            },
          );
        } catch (_) {}
        if (mounted) {
          _handlePaymentSuccess();
          return;
        }
      }

      if (status == 'failed' ||
          status == 'declined' ||
          status == 'cancelled') {
        setState(() {
          _errorMsg = res.data['message'] ?? 'Payment declined.';
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
                    'Still pending: ${res.data['message'] ?? 'Please check your phone for the MoMo prompt.'}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
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
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
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
              color: isDark ? const Color(0xFF281710) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF4D2D20)
                    : const Color(0xFFe2e8f0),
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
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Stack(
              children: [
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: const Color(0xFFcbd5e1).withAlpha(120),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Stepper indicator
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFf8fafc),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                                border: Border(
                                  bottom: BorderSide(
                                    color: const Color(
                                      0xFFcbd5e1,
                                    ).withAlpha(80),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: Builder(
                                builder: (ctx) {
                                  final isNoDoc = _isNoDocPaymentReason;
                                  final labels = isNoDoc
                                      ? ['Type', 'Method', 'Review', 'Verify']
                                      : ['Type', 'Document', 'Method', 'Review', 'Verify'];
                                  final stepMap = isNoDoc
                                      ? {1: 0, 3: 1, 4: 2, 5: 3}
                                      : {1: 0, 2: 1, 3: 2, 4: 3, 5: 4};
                                  final curIdx = stepMap[_step] ?? 0;
                                  final totalSteps = labels.length;

                                  return Row(
                                    children: List.generate(totalSteps, (i) {
                                      final isCompleted = curIdx > i;
                                      final isActive = curIdx == i;
                                      final n = i + 1;

                                      return Expanded(
                                        child: Column(
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
                                                            style: GoogleFonts.outfit(
                                                              color: isActive
                                                                  ? Colors.white
                                                                  : const Color(0xFF64748b),
                                                              fontWeight: FontWeight.w800,
                                                              fontSize: 11,
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
                                            const SizedBox(height: 6),
                                            Text(
                                              labels[i],
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                color: isActive
                                                    ? _kOrange
                                                    : const Color(0xFF64748b),
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.2,
                                              ),
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
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: const Color(0xFF64748b),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                          style: GoogleFonts.outfit(
                            fontSize: 20,
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
                            fontSize: 13,
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
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    color: const Color(0xFF16a34a),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'GH₵ ${double.tryParse(_confirmedAmount)?.toStringAsFixed(2) ?? _confirmedAmount}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 26,
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
                                      if (returnToApp) {
                                        context.go('/application-documents');
                                      } else {
                                        context.go('/payment-history');
                                      }
                                    },
                                    child: Text(
                                      returnToApp
                                          ? 'Return to Complete Your Application'
                                          : 'View Payment History',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                if (returnToApp) ...[
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
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
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
                            style: GoogleFonts.outfit(
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
                          style: GoogleFonts.outfit(
                            fontSize: 20,
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
                            fontSize: 13,
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
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
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
            style: GoogleFonts.outfit(
              fontSize: 11,
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

              final packageTitle = _regFeeCategoryTitle.isNotEmpty
                  ? 'New Membership Dues ($_regFeeCategoryTitle)'
                  : 'New Membership Dues';
              final packageAmtStr = _packageFeeStr.isNotEmpty ? _packageFeeStr : '1620.00';

              final renewalTitle = _renewalFeeCategoryTitle.isNotEmpty
                  ? 'Annual Renewal Dues ($_renewalFeeCategoryTitle)'
                  : 'Annual Renewal Dues';
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
              dropdownItems.add(
                DropdownItem<String>(
                  value: 'Annual Renewal Dues',
                  label: '$renewalTitle · GH₵ $renewalAmtStr',
                ),
              );

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
                  labelText = '$renewalTitle · GH₵ $renewalAmtStr';
                  dropdownItems.insert(
                    0,
                    DropdownItem<String>(value: _reason, label: labelText),
                  );
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
                      _amountCtrl.text = renewalAmtStr;
                      _complianceAppId = null;
                      _complianceType = null;
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
          const SizedBox(height: 20),
          Text(
            'AMOUNT TO PAY',
            style: GoogleFonts.outfit(
              fontSize: 11,
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
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    onChanged: (v) => setState(() {}),
                    keyboardType: TextInputType.number,
                    readOnly: _reason.isNotEmpty && _reason != 'Other',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A0F0A),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      hintText: '0.00',
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                        style: GoogleFonts.outfit(
                          fontSize: 11,
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
                          style: GoogleFonts.outfit(
                            fontSize: 10,
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
                                  fontSize: 13,
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
                                  fontSize: 11.5,
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
                          style: GoogleFonts.outfit(
                            fontSize: 14,
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
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text.isNotEmpty ? _amountCtrl.text : "600.00"}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
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
                          _regFeeCategoryTitle.isNotEmpty
                              ? 'FEE BREAKDOWN: NEW MEMBERSHIP DUES (${_regFeeCategoryTitle.toUpperCase()})'
                              : 'NEW MEMBERSHIP DUES BREAKDOWN',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item['label']?.toString() ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155),
                            ),
                          ),
                          Text(
                            'GHS ${item['amount']?.toString() ?? ''}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
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
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
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

          // ── Itemized Fee Breakdown Card (For Annual Renewal Dues) ──
          if (_renewalFeeBreakdown.isNotEmpty &&
              _reason.toLowerCase().contains('renewal')) ...[
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
                          _renewalFeeCategoryTitle.isNotEmpty
                              ? 'RENEWAL BREAKDOWN: ${_renewalFeeCategoryTitle.toUpperCase()}'
                              : 'EXISTING MEMBERSHIP RENEWAL',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
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
                  ..._renewalFeeBreakdown.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item['label']?.toString() ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155),
                            ),
                          ),
                          Text(
                            'GHS ${item['amount']?.toString() ?? ''}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
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
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'GHS ${_amountCtrl.text}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
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
                          fontSize: 13,
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

          SizedBox(
            width: double.infinity,
            height: 50,
            child: Builder(
              builder: (ctx) {
                final r = _reason.toLowerCase();
                final isLicenseReason =
                    r.contains('license') ||
                    r.contains('renewal') ||
                    r.contains('dues') ||
                    r.contains('annual fee');
                // Block only if: license is active AND reason is license-related
                final canContinue =
                    _reason.isNotEmpty &&
                    _amountCtrl.text.isNotEmpty &&
                    !(_isLicenseBlocked && isLicenseReason);
                final isNoDoc = _isNoDocPaymentReason;
                return ElevatedButton.icon(
                  onPressed: canContinue
                      ? () {
                          if (isNoDoc) {
                            setState(() => _step = 3);
                          } else {
                            if (_isComplianceReason(_reason)) {
                              _complianceType = _complianceTypeForReason(_reason);
                              _prepareComplianceApplication();
                            }
                            setState(() => _step = 2);
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
                );
              },
            ),
          ),
        ],
      );
    }

    if (_step == 2) {
      final isCompliance = _isComplianceReason(_reason);
      final title = _complianceType == 'renewal'
          ? 'Membership Renewal Application'
          : 'Member ID Application';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCompliance
                      ? Icons.verified_user_outlined
                      : Icons.folder_open_rounded,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCompliance
                          ? 'COMPLIANCE & DOCUMENTS'
                          : 'SUPPORTING DOCUMENTS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: const Color(0xFF64748b),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      isCompliance ? title : 'Supporting Documents',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A0F0A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isCompliance) ...[
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
                          fontSize: 13,
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
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A0F0A),
                                ),
                              ),
                              Text(
                                'Initiate your compliance application to upload required files.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
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
                        fontSize: 13,
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
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
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
                            style: GoogleFonts.outfit(
                              fontSize: 10,
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
                            style: GoogleFonts.outfit(
                              fontSize: 15,
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
                        style: GoogleFonts.outfit(
                          fontSize: 11,
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
                style: GoogleFonts.outfit(
                  fontSize: 11,
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
                    child: Row(
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
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: const Color(0xFF1A0F0A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                uploaded
                                    ? 'Uploaded & Saved'
                                    : 'Required for submission',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: uploaded
                                      ? _kGreen
                                      : const Color(0xFF94a3b8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _uploadComplianceDoc(doc),
                          icon: Icon(
                            uploaded
                                ? Icons.refresh_rounded
                                : Icons.file_upload_outlined,
                            size: 16,
                          ),
                          label: Text(
                            uploaded ? 'Replace' : 'Upload',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ] else if (_reason.toLowerCase().contains('customs') ||
              _reason.toLowerCase().contains('licence') ||
              _reason.toLowerCase().contains('application fee')) ...[
            // Application Fee verified documents card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFf0fdf4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF86efac)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(4),
                    blurRadius: 8,
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
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFdcfce7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: _kGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '11 Application Documents Uploaded',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A0F0A),
                              ),
                            ),
                            Text(
                              'Submitted via Complete Your Application.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Your 11 required application documents have been uploaded and submitted for review. Click Continue below to proceed to payment method.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF4D2D20),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Non-compliance standard payment document upload card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFe2e8f0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(4),
                    blurRadius: 8,
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primary.withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.file_present_rounded,
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
                              'Supporting Attachments',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A0F0A),
                              ),
                            ),
                            Text(
                              'Paperwork or invoice reference',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748b),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'The required documents listed below on the payment page for step 2',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/compliance'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      'Open Compliance Centre',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withAlpha(80)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    if (isCompliance &&
                        (_complianceStatus == 'draft' ||
                            _complianceStatus == 'revision_requested')) {
                      _submitComplianceApplication();
                    }
                    setState(() => _step = 3);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    'Continue to Payment Method',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
                    'Back to Payment Type',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
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
          // Clean Header Label & Auto-filled Carrier Tag
          Row(
            children: [
              Text(
                'MOBILE MONEY NUMBER',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
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
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
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

          // Direct 10-Digit Phone Number Input (NO COUNTRY CODE)
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
                      _momoPhone = clean;
                      final detected = _detectNetworkFromPhone(clean);
                      if (detected.isNotEmpty) {
                        _momoNetwork = detected;
                      } else if (clean.length < 3) {
                        _momoNetwork = '';
                      }
                      setState(() {});
                    },
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: const Color(0xFF1e293b),
                    ),
                    decoration: InputDecoration(
                      hintText: '024XXXXXXX (10 digits)',
                      hintStyle: GoogleFonts.outfit(
                        color: const Color(0xFF94a3b8),
                        fontSize: 15,
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

          // Micro Helper Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _momoPhone.isEmpty
                  ? 'Enter your 10-digit mobile number (MTN, Telecel, or AT).'
                  : (_momoNetwork.isEmpty
                      ? 'Type full 10 digits to auto-fill network carrier.'
                      : '✓ ${_carrierName(_momoNetwork)} (Push prompt ready)'),
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: _momoNetwork.isNotEmpty
                    ? _kOrange
                    : const Color(0xFF64748b),
                fontWeight: _momoNetwork.isNotEmpty
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Instant Push Notification Info Card
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
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: const Color(0xFF0f172a),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'A PIN authorization prompt will appear on your phone screen automatically once you proceed.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
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
                        : 'Review Payment Summary',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
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
          ? 'MOBILE MONEY (${_momoNetwork.toUpperCase()})'
          : 'MOBILE MONEY';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFcbd5e1).withAlpha(120),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
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
                    gradient: LinearGradient(
                      colors: [_kOrange, const Color(0xFFea580c)],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    'DIGITAL INVOICE SUMMARY',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...[
                  {
                    'label': 'Payment Category',
                    'value': _reason,
                    'highlight': false,
                  },
                  {
                    'label': 'Selected Method',
                    'value': methodLabel,
                    'highlight': false,
                  },
                  {
                    'label': 'Total Payable Amount',
                    'value':
                        'GH₵ ${double.tryParse(_amountCtrl.text)?.toStringAsFixed(2) ?? _amountCtrl.text}',
                    'highlight': true,
                  },
                ].map((row) {
                  final isHighlight = row['highlight'] as bool;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFFf1f5f9),
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          row['label']! as String,
                          style: TextStyle(
                            color: isHighlight
                                ? const Color(0xFF475569)
                                : Colors.grey.shade500,
                            fontWeight: isHighlight
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          row['value']! as String,
                          style: GoogleFonts.outfit(
                            fontWeight: isHighlight
                                ? FontWeight.w900
                                : FontWeight.w700,
                            color: isHighlight
                                ? _kOrange
                                : const Color(0xFF281710),
                            fontSize: isHighlight ? 18 : 13.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
                  onPressed: _loading ? null : _submitPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      : Text(
                          _method == 'momo'
                              ? 'Initiate Mobile Payment'
                              : 'Confirm & Submit Payment',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
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
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A0F0A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A Mobile Money prompt has been sent to $_momoPhone.\nOpen your phone and enter your PIN to approve.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748b),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          () {
            String noticeTitle = 'MTN MoMo Approval Notice';
            String noticeText =
                'If the prompt does not pop up, dial *170# → Option 6 (My Wallet) → Option 3 (My Approvals) on your phone to approve.';

            if (_momoNetwork == 'Vodafone') {
              noticeTitle = 'Telecel (Vodafone) Approval Notice';
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
                      Text(
                        noticeTitle,
                        style: GoogleFonts.outfit(
                          color: primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    noticeText,
                    style: const TextStyle(
                      color: Color(0xFF4D2D20),
                      fontSize: 11,
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
                  fontSize: 12,
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
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    // This block should never execute because all states are handled above.
    return const SizedBox.shrink();
  }

  Widget _methodCard(String id, IconData icon, String label, Color primary) {
    final selected = _method == id;
    return GestureDetector(
      onTap: () => setState(() => _method = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? primary : const Color(0xFFe2e8f0),
            width: selected ? 2.5 : 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
          color: selected ? primary.withAlpha(12) : Colors.white,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: primary.withAlpha(15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: selected ? primary : const Color(0xFF94a3b8),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                color: selected ? primary : const Color(0xFF475569),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _carrierName(String net) {
    if (net == 'MTN') return 'MTN MoMo';
    if (net == 'Vodafone') return 'Telecel Cash';
    if (net == 'AirtelTigo') return 'AT Money';
    return 'Mobile Money';
  }
}
