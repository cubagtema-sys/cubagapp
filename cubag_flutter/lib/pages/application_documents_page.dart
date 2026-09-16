import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

// ── Colour constants ─────────────────────────────────────────────────────────
const _kGreen = Color(0xFF10b981);
const _kOrange = Color(0xFFFF5000);
const _kRed = Color(0xFFef4444);
const _kGrey = Color(0xFF6b6375);

class ApplicationDocumentsPage extends StatefulWidget {
  const ApplicationDocumentsPage({super.key});
  @override
  State<ApplicationDocumentsPage> createState() =>
      _ApplicationDocumentsPageState();
}

class _ApplicationDocumentsPageState extends State<ApplicationDocumentsPage> with WidgetsBindingObserver {
  bool _loading = true;
  bool _submitting = false;
  List<dynamic> _requirements = [];
  int _totalDocs = 0;
  int _uploadedCount = 0;
  String _memberStatus = 'pending';
  final Map<String, bool> _uploading = {};

  bool _registrationFeePaid = false;
  String _registrationFeeAmount = '';
  String _packageFeeAmount = '';
  bool _allRequiredApproved = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registrationFeeAmount =
        SessionStorage.instance.getStringSync('cubag_reg_fee_amount') ?? '';
    _packageFeeAmount =
        SessionStorage.instance.getStringSync('cubag_package_fee_amount') ?? '';
    _fetchRequirements();

    // Attach real-time event listeners
    SocketService().dataUpdateNotifier.addListener(_onGlobalDataUpdate);
    SocketService().on('documents_updated', _onDocumentsUpdated);
    SocketService().on('member_documents_updated', _onDocumentsUpdated);
    SocketService().on('member_updated', _onDocumentsUpdated);
    SocketService().on('fees_updated', _onDocumentsUpdated);

    // Silent background auto-sync polling every 15 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _fetchRequirements();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) _fetchRequirements();
    }
  }

  void _onGlobalDataUpdate() {
    final event = SocketService().dataUpdateNotifier.value;
    if (!mounted || event == null) return;
    if (event.contains('document') ||
        event.contains('member') ||
        event.contains('requirement') ||
        event.contains('fee')) {
      _fetchRequirements();
    }
  }

  void _onDocumentsUpdated(dynamic _) {
    if (mounted) _fetchRequirements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SocketService().dataUpdateNotifier.removeListener(_onGlobalDataUpdate);
    SocketService().off('documents_updated', _onDocumentsUpdated);
    SocketService().off('member_documents_updated', _onDocumentsUpdated);
    SocketService().off('member_updated', _onDocumentsUpdated);
    SocketService().off('fees_updated', _onDocumentsUpdated);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequirements() async {
    if (!mounted) return;
    if (_requirements.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final res = await ApiService().get('/documents/requirements');
      if (mounted && res.statusCode == 200 && res.data is Map) {
        final reqList = res.data['requirements'] as List<dynamic>? ?? [];
        final status = res.data['member_status']?.toString() ?? 'pending';
        final feePaid =
            (res.data['registration_fee_paid'] == true) ||
            (res.data['application_fee_paid'] == true);
        final regAmount =
            res.data['registration_fee_amount']?.toString() ??
            (_registrationFeeAmount.isNotEmpty ? _registrationFeeAmount : '600.00');
        final packageAmount =
            res.data['package_fee_amount']?.toString() ??
            res.data['registration_package_amount']?.toString() ??
            (_packageFeeAmount.isNotEmpty ? _packageFeeAmount : '1620.00');
        final allRequiredApproved =
            reqList.isNotEmpty &&
            reqList.every(
              (item) => item is Map && item['status'] == 'approved',
            );
        final bool isApproved = status == 'active' || status == 'approved' || allRequiredApproved;

        await SessionStorage.instance.setString('cubag_member_status', isApproved ? 'active' : status);
        await SessionStorage.instance.setString('cubag_status', isApproved ? 'active' : status);
        await SessionStorage.instance.setString('cubag_registration_fee_paid', (feePaid || isApproved).toString());
        await SessionStorage.instance.setString('cubag_reg_fee_amount', regAmount);
        await SessionStorage.instance.setString('cubag_package_fee_amount', packageAmount);

        setState(() {
          _requirements = reqList;
          _totalDocs = res.data['total'] ?? reqList.length;
          _uploadedCount = res.data['uploaded'] ?? 0;
          _allRequiredApproved = allRequiredApproved;
          _memberStatus = status;
          _registrationFeePaid = feePaid || isApproved;
          _registrationFeeAmount = regAmount;
          _packageFeeAmount = packageAmount;
          _loading = false;
        });

        final bool canAccessDashboard = isApproved || (status == 'active' && feePaid);
        if (canAccessDashboard && mounted) {
          context.go('/dashboard');
        }
      }
    } catch (e, st) {
      AppLogger.error('application_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAndUpload(Map<String, dynamic> req) async {
    final key = req['key']?.toString() ?? '';
    final label = req['label']?.toString() ?? '';
    if (key.isEmpty) return;
    setState(() => _uploading[key] = true);
    try {
      // Pick file
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _uploading[key] = false);
        return;
      }

      final List<Future<void>> uploadTasks = [];

      for (final file in result.files) {
        uploadTasks.add(() async {
          final api = ApiService();
          late Uint8List fileBytes;
          if (file.bytes != null) {
            fileBytes = file.bytes!;
          } else {
            fileBytes = await file.xFile.readAsBytes();
          }

          final formData = FormData.fromMap({
            'requirement': key,
            'label': label,
            'file': MultipartFile.fromBytes(fileBytes, filename: file.name),
          });
          final res = await api.upload('/documents/upload', formData);
          if (res.statusCode != 200) {
            throw Exception(res.data?['message']?.toString() ?? 'Upload failed');
          }
        }());
      }

      await Future.wait(uploadTasks);

      if (mounted) {
        _showSnack('$label uploaded successfully', _kGreen);
        _fetchRequirements();
      }
    } catch (e) {
      if (mounted) _showSnack('Upload error. Please try again.', _kRed);
    }
    if (mounted) setState(() => _uploading[key] = false);
  }

  Future<void> _submitApplication() async {
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post('/documents/submit-application');
      if (mounted) {
        if (res.statusCode == 200) {
          _memberStatus = 'pending_review';
          context.go(
            '/payments?fee=Registration%20Fee&redirect=/application-documents',
          );
        } else {
          _showSnack(res.data['message'] ?? 'Submission failed', _kRed);
        }
      }
    } catch (_) {
      if (mounted) _showSnack('Network error. Please try again.', _kRed);
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _requirements.isEmpty) {
      return const AppLayout(
        title: 'Complete Your Application',
        child: Center(
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _totalDocs > 0 ? _uploadedCount / _totalDocs : 0.0;

    return AppLayout(
      title: 'Complete Your Application',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _fetchRequirements,
        color: _kOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header card ──
                    _buildHeaderCard(isDark, progress),
                    const SizedBox(height: 16),

                    // ── Primary Action / Payment Card (PLACED AT TOP BEFORE DOCUMENTS LIST) ──
                    _buildActionCard(isDark),
                    const SizedBox(height: 24),

                    // ── Requirements list ──
                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(color: _kOrange),
                      )
                    else if (_totalDocs > 0 && _requirements.isNotEmpty) ...[
                      Text(
                        'Required Documents (${_requirements.length})',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A0F0A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload each document as a PDF or image (max 15MB each).',
                        style: GoogleFonts.inter(fontSize: 15, color: _kGrey),
                      ),
                      const SizedBox(height: 16),
                      ..._requirements
                          .asMap()
                          .map(
                            (i, req) =>
                                MapEntry(i, _buildDocCard(req, i + 1, isDark)),
                          )
                          .values,
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark, double progress) {
    final hasDocs = _totalDocs > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6B3E26), Color(0xFF3E2418)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3E2418).withAlpha(45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasDocs ? Icons.folder_open_rounded : Icons.verified_user_rounded, color: _kOrange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CUBAG Membership Application',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hasDocs
                ? 'Your account has been created. To complete your CUBAG membership, please upload all required documents below. The secretariat will review and activate your account.'
                : 'Your account has been created. To complete your CUBAG membership, please pay your Registration Fee below to activate your account.',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
          if (hasDocs) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_uploadedCount of $_totalDocs documents uploaded',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _kOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withAlpha(50),
                valueColor: const AlwaysStoppedAnimation<Color>(_kOrange),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocCard(Map<String, dynamic> req, int index, bool isDark) {
    final key = req['key']?.toString() ?? '';
    final status = req['status']?.toString() ?? 'not_uploaded';
    final uploaded = req['uploaded'] == true;
    final isUploading = _uploading[key] == true;
    final fileName = req['file_name']?.toString();
    final adminNote = req['admin_note']?.toString();

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'approved':
        statusColor = _kGreen;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = _kRed;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Rejected';
        break;
      case 'pending':
        statusColor = _kOrange;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'Pending Review';
        break;
      default:
        statusColor = _kGrey;
        statusIcon = Icons.upload_file_rounded;
        statusLabel = 'Not Uploaded';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF281710) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: uploaded
              ? statusColor.withAlpha(100)
              : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFE8DED6)),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Index + status icon
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: uploaded
                      ? Icon(statusIcon, color: statusColor, size: 18)
                      : Text(
                          '$index',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _kGrey,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req['label']?.toString() ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                  ),
                ),
                if (uploaded && fileName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        size: 13,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          fileName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: statusColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (adminNote != null && adminNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Admin note: $adminNote',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _kRed,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    key: ValueKey('upload_btn_${req['id']}_$isDark'),
                    onPressed: isUploading ? null : () => _pickAndUpload(req),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status == 'rejected'
                          ? _kRed
                          : (uploaded ? Colors.grey.shade100 : _kOrange),
                      foregroundColor: status == 'rejected'
                          ? Colors.white
                          : (uploaded ? const Color(0xFF374151) : Colors.white),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: isUploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            status == 'rejected'
                                ? Icons.error_outline_rounded
                                : (uploaded
                                      ? Icons.refresh_rounded
                                      : Icons.upload_rounded),
                            size: 16,
                          ),
                    label: Text(
                      isUploading
                          ? 'Uploading...'
                          : (status == 'rejected'
                                ? 'Re-upload'
                                : (uploaded ? 'Replace' : 'Upload')),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(bool isDark) {
    final alreadySubmitted =
        _memberStatus == 'pending_review' || _memberStatus == 'active';
    final allUploaded = _uploadedCount >= _totalDocs && _totalDocs > 0;
    final canSubmit = allUploaded && !_submitting && !alreadySubmitted;

    Color cardBg = isDark ? const Color(0xFF281710) : const Color(0xFFf8fafc);
    Color borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE8DED6);
    String titleText = 'Application Steps';
    String descText = '';
    String btnText = '';
    IconData btnIcon = Icons.send_rounded;
    Color btnBg = _kGreen;
    VoidCallback? onBtnPressed;

    final displayRegFee = _registrationFeeAmount.isNotEmpty
        ? 'GHS $_registrationFeeAmount'
        : (_loading ? '...' : 'GHS 1.00');

    if (_totalDocs == 0) {
      if (_registrationFeePaid) {
        cardBg = isDark ? const Color(0xFF062e1e) : const Color(0xFFf0fdf4);
        borderColor = const Color(0xFF86efac);
        titleText = '✅ Registration Fee Paid & Confirmed';
        descText =
            'Your Registration Fee has been successfully received. Your membership application is complete and being processed for activation.';
        btnText = 'Registration Fee Paid (Confirmed)';
        btnIcon = Icons.check_circle_rounded;
        btnBg = Colors.grey.shade400;
        onBtnPressed = null;
      } else {
        cardBg = isDark ? const Color(0xFF062e1e) : const Color(0xFFf0fdf4);
        borderColor = const Color(0xFF86efac);
        titleText = 'Pay Fee to Complete Membership';
        descText =
            'No document uploads are required for your membership category. Please pay your fee to complete your membership activation.';
        btnText = 'Pay Fee';
        btnIcon = Icons.payment_rounded;
        btnBg = const Color(0xFFea580c);
        onBtnPressed = () {
          context.go(
            '/payments?fee=Registration%20Fee&redirect=/application-documents',
          );
        };
      }
    } else if (alreadySubmitted) {
      if (_registrationFeePaid) {
        cardBg = isDark ? const Color(0xFF062e1e) : const Color(0xFFf0fdf4);
        borderColor = const Color(0xFF86efac);
        titleText = 'Registration Fee Paid';
        descText =
            'Your Registration Fee has been successfully paid and confirmed. Your application documents are currently being reviewed by the Secretariat for final membership activation.';
        btnText = 'Registration Fee Paid (Confirmed)';
        btnIcon = Icons.check_circle_rounded;
        btnBg = Colors.grey.shade400;
        onBtnPressed = null;
      } else if (_allRequiredApproved || _memberStatus == 'approved') {
        cardBg = isDark ? const Color(0xFF062e1e) : const Color(0xFFf0fdf4);
        borderColor = const Color(0xFF86efac);
        titleText = '✅ Documents Approved! Pay Fee';
        descText =
            'Great news! Your $_totalDocs application documents have been reviewed and approved by the CUBAG Secretariat. Please pay your fee to complete your membership activation.';
        btnText = 'Pay Fee';
        btnIcon = Icons.payment_rounded;
        btnBg = const Color(0xFFea580c);
        onBtnPressed = () {
          context.go(
            '/payments?fee=Membership%20Entrance%20Package&redirect=/application-documents',
          );
        };
      } else {
        cardBg = isDark ? const Color(0xFF2e1000) : const Color(0xFFfff7ed);
        borderColor = const Color(0xFFfdba74);
        titleText = 'Application Submitted & Under Secretariat Review';
        descText =
            'Your $_totalDocs documents have been uploaded and submitted. The Secretariat is currently reviewing your dossier. Please pay your fee if you have not already done so.';
        btnText = 'Pay Fee';
        btnIcon = Icons.payment_rounded;
        btnBg = const Color(0xFFea580c);
        onBtnPressed = () {
          context.go(
            '/payments?fee=Registration%20Fee&redirect=/application-documents',
          );
        };
      }
    } else if (allUploaded) {
      cardBg = isDark ? const Color(0xFF062e1e) : const Color(0xFFf0fdf4);
      borderColor = const Color(0xFF86efac);
      titleText = 'All $_totalDocs Documents Uploaded!';
      descText =
          'Great job! All required documents have been uploaded. Click below to submit your application dossier for Secretariat vetting.';
      btnText = _submitting ? 'Submitting...' : 'Upload To Submit & Pay';
      btnIcon = Icons.send_rounded;
      btnBg = _kGreen;
      onBtnPressed = canSubmit ? _submitApplication : null;
    } else {
      cardBg = isDark ? const Color(0xFF281710) : const Color(0xFFf8fafc);
      borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFcbd5e1);
      titleText = 'Upload All Documents to Unlock Payment';
      descText =
          'You must upload all $_totalDocs required statutory documents before you can submit your application dossier and unlock fee payment. ($_uploadedCount of $_totalDocs uploaded so far)';
      btnText = 'Pay Fee';
      btnIcon = Icons.payment_rounded;
      btnBg = isDark ? Colors.white24 : Colors.grey.shade400;
      onBtnPressed = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
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
              Icon(
                alreadySubmitted
                    ? Icons.verified_rounded
                    : (allUploaded
                          ? Icons.check_circle_rounded
                          : Icons.pending_actions_rounded),
                color: alreadySubmitted
                    ? const Color(0xFFea580c)
                    : (allUploaded ? _kGreen : _kOrange),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titleText,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            descText,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              height: 1.5,
            ),
          ),
          if (!_registrationFeePaid) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REGISTRATION FEE',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Paid separately upon registration before the statutory documents are vetted.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    displayRegFee,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0f172a),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: ValueKey('action_btn_${_registrationFeePaid}_$isDark'),
              onPressed: onBtnPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: btnBg,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark
                    ? const Color(0xFF281710)
                    : Colors.grey.shade300,
                disabledForegroundColor: isDark
                    ? Colors.white38
                    : Colors.grey.shade600,
                elevation: onBtnPressed != null ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(btnIcon, size: 20),
              label: Text(
                btnText,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
