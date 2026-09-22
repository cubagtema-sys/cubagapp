// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/in_app_document_viewer.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRed = Color(0xFFef4444);
const _kDarkBg = Color(0xFF1A0F0A);
const _kCardDark = Color(0xFF281710);
const _kBorderDark = Color(0xFF4D2D20);
const _kTextDark = Color(0xFF2B211D);

Color _statusColor(String? s) {
  switch (s) {
    case 'approved':
      return _kGreen;
    case 'rejected':
      return _kRed;
    case 'awaiting_bill':
      return const Color(0xFF8B5CF6); // Purple/Violet
    case 'awaiting_payment':
    case 'payment_pending':
      return _kAmber;
    case 'payment_submitted':
      return const Color(0xFFE65100); // Warm vibrant amber/orange
    case 'payment_confirmed':
      return _kGreen;
    case 'revision_requested':
      return _kAmber;
    case 'under_review':
      return _kPrimary;
    case 'submitted':
      return _kAmber;
    default:
      return Colors.grey;
  }
}

String _statusLabel(String? s) {
  switch (s) {
    case 'draft':
      return 'Draft';
    case 'submitted':
      return 'Submitted';
    case 'awaiting_bill':
      return 'Awaiting Bill';
    case 'awaiting_payment':
    case 'payment_pending':
      return 'Awaiting Payment';
    case 'payment_submitted':
      return 'Payment Submitted';
    case 'payment_confirmed':
      return 'Payment Confirmed';
    case 'under_review':
      return 'Under Review';
    case 'revision_requested':
      return 'Revision Required';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    default:
      if (s != null && s.isNotEmpty) {
        return s
            .split('_')
            .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
      }
      return '—';
  }
}

String _fmtDate(String? d) {
  if (d == null || d.isEmpty) return '—';
  try {
    final dt = DateTime.tryParse(d);
    if (dt != null) {
      final m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
    }
    // Handle RFC 2822 / HTTP format (e.g., "Mon, 14 Sep 2026 21:01:02 GMT")
    final rfcMatch = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(d);
    if (rfcMatch != null) {
      return '${rfcMatch.group(1)} ${rfcMatch.group(2)} ${rfcMatch.group(3)}';
    }
    return d;
  } catch (_) {
    return d;
  }
}

// Staleness threshold — warn if auto-filled doc is older than this
const _kStaleDays = 365;

bool _isStale(String? uploadedAt) {
  if (uploadedAt == null) return false;
  try {
    final dt = DateTime.parse(uploadedAt);
    return DateTime.now().difference(dt).inDays > _kStaleDays;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root page: type selector + existing applications list
// ─────────────────────────────────────────────────────────────────────────────
class ComplianceCentrePage extends StatefulWidget {
  const ComplianceCentrePage({super.key});
  @override
  State<ComplianceCentrePage> createState() => _ComplianceCentrePageState();
}

class _ComplianceCentrePageState extends State<ComplianceCentrePage> {
  bool _loading = true;
  List<dynamic> _applications = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
    SocketService().on('compliance_updated', _onRealtimeComplianceUpdate);
  }

  void _onRealtimeComplianceUpdate(dynamic _) {
    if (mounted) {
      _fetch();
    }
  }

  @override
  void dispose() {
    SocketService().off('compliance_updated', _onRealtimeComplianceUpdate);
    super.dispose();
  }

  Future<void> _fetch() async {
    // Show skeleton only on first load (no cached data yet)
    if (_applications.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await ApiService().fetchDataWithCache('/compliance/my-applications', (
        data,
        isCached, {
        bool hasError = false,
      }) {
        if (!mounted) return;
        if (hasError) {
          if (!isCached) {
            setState(() {
              _loading = false;
              _error =
                  'Failed to load compliance applications. Pull down to retry.';
            });
          }
          return;
        }
        if (data != null && data is Map) {
          final apps = ApiService.ensureList(data['applications']);
          setState(() {
            _loading = false;
            _error = null;
            _applications = apps;
          });
        }
      });
    } catch (e, st) {
      AppLogger.error('compliance_centre_page', e, st);
      if (mounted) {
        final message = e.toString();
        final friendly =
            message.contains('Failed host lookup') ||
                message.contains('Connection refused') ||
                message.contains('SocketException')
            ? 'The backend server is currently unreachable. Please check your internet connection and try again.'
            : message;
        setState(() {
          _loading = false;
          _error = friendly;
        });
      }
    }
  }

  Future<void> _openExisting(dynamic app) async {
    final appId = app['id'] as int?;
    if (appId == null) return;
    final status = app['status']?.toString() ?? '';
    if (status == 'approved') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _StatusViewPage(app: app, appId: appId),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ApplicationDetailPage(appId: appId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Count applications that need member attention (revision)
    final revisionCount = _applications
        .where((a) => a['status'] == 'revision_requested')
        .length;

    return AppLayout(
      title: 'Compliance Centre',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: _kPrimary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  _SectionHeader(isDark: isDark),
                  const SizedBox(height: 28),

                  // ── Revision Alert ──────────────────────────────────────
                  if (revisionCount > 0) ...[
                    _AlertBanner(
                      icon: Icons.edit_note_rounded,
                      message:
                          '$revisionCount application${revisionCount > 1 ? 's require' : ' requires'} your attention. Please review admin notes and resubmit.',
                      color: _kAmber,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Type Selector ───────────────────────────────────────
                  Text(
                    'Compliance Application Tracking',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? _kDarkBg : const Color(0xFFf8fafc),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? _kBorderDark
                            : const Color(0xFFcbd5e1).withAlpha(120),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'Start new compliance applications from the Payments page. The Compliance Centre now helps you monitor submitted applications, review admin notes, and reupload documents for revisions or rejected files.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF475569),
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Applications List ───────────────────────────────────
                  Text(
                    'My Applications',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          SkeletonLoader(
                            width: double.infinity,
                            height: 24,
                            borderRadius: 12,
                          ),
                          SizedBox(height: 16),
                          SkeletonLoader(
                            width: double.infinity,
                            height: 18,
                            borderRadius: 10,
                          ),
                          SizedBox(height: 16),
                          SkeletonLoader(
                            width: double.infinity,
                            height: 18,
                            borderRadius: 10,
                          ),
                          SizedBox(height: 16),
                          SkeletonLoader(
                            width: double.infinity,
                            height: 140,
                            borderRadius: 16,
                          ),
                          SizedBox(height: 16),
                          SkeletonLoader(
                            width: double.infinity,
                            height: 18,
                            borderRadius: 10,
                          ),
                          SizedBox(height: 12),
                          SkeletonLoader(
                            width: double.infinity,
                            height: 18,
                            borderRadius: 10,
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: _kRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if (_applications.isEmpty)
                    _EmptyState()
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _applications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ApplicationCard(
                        app: _applications[i],
                        onTap: () => _openExisting(_applications[i]),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Application detail: upload docs → submit → pay (poll) → track
// ─────────────────────────────────────────────────────────────────────────────
class _ApplicationDetailPage extends StatefulWidget {
  final int appId;
  const _ApplicationDetailPage({required this.appId});
  @override
  State<_ApplicationDetailPage> createState() => _ApplicationDetailPageState();
}

class _ApplicationDetailPageState extends State<_ApplicationDetailPage> {
  bool _loading = true;
  Map<String, dynamic> _app = {};
  List<dynamic> _docs = [];
  String? _uploadingKey;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get(
        '/compliance/applications/${widget.appId}',
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _app = Map<String, dynamic>.from(res.data['application'] ?? {});
          _docs = ApiService.ensureList(res.data['documents']);
        });
      }
    } catch (e, st) {
      AppLogger.error('compliance_detail', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────
  Future<void> _uploadDoc(Map<String, dynamic> docReq) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final key = docReq['key']?.toString() ?? '';
    setState(() => _uploadingKey = key);
    _showSnack(
      'Uploading ${result.files.length} document(s)…',
      color: _kDarkBg,
      showProgress: true,
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
            '/compliance/applications/${widget.appId}/upload',
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
      _showSnack('${docReq['label']} uploaded successfully!', color: _kGreen);
      _fetch();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) _showSnack('Upload failed: $msg', color: _kRed);
    } finally {
      if (mounted) setState(() => _uploadingKey = null);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
        '/compliance/applications/${widget.appId}/submit',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _showSnack(res.data['message'] ?? 'Submitted', color: _kGreen);
        await _fetch();
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Certificate download (FIX #6) — pass JWT as query param ────────────

  Widget _buildStepper() {
    final status = _app['status']?.toString() ?? 'draft';
    final completed = status != 'draft' && status != 'revision_requested';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Progress',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 40,
                child: Container(height: 2, color: const Color(0xFFe2e8f0)),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: completed ? _kPrimary : _kAmber,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: completed ? _kPrimary : _kAmber,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        completed
                            ? Icons.check_rounded
                            : Icons.description_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Documents',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: completed
                            ? _kPrimary
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : _kTextDark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completed
                          ? 'Application uploaded and under review'
                          : 'Upload or replace required documents',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadCertificate() async {
    final url =
        ApiService.resolveImageUrl('api/v1/compliance/applications/${widget.appId}/certificate');
    await InAppDocumentViewer.show(
      context,
      url: url,
      title: 'Annual Certificate of Compliance',
      subtitle: 'Official CUBAG Certificate',
    );
  }

  void _showSnack(
    String msg, {
    Color color = _kDarkBg,
    bool showProgress = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (showProgress) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _app['status']?.toString() ?? 'draft';
    final appType = _app['type']?.toString() ?? '';
    final typeLabel = appType == 'renewal'
        ? 'Membership Renewal'
        : 'Member ID Application';

    final hasRejectedDocs = _docs.any((d) => d['status'] == 'rejected');
    final isEditable =
        status == 'draft' ||
        status == 'revision_requested' ||
        status == 'rejected' ||
        hasRejectedDocs;
    final isRevision =
        status == 'revision_requested' ||
        status == 'rejected' ||
        hasRejectedDocs;
    final isSubmitted = status == 'submitted';
    final isUnderReview =
        [
          'under_review',
          'payment_pending',
          'payment_confirmed',
        ].contains(status) &&
        !hasRejectedDocs;
    final isApproved = status == 'approved';

    final uploadedCount = _docs.where((d) => d['uploaded'] == true).length;
    final totalCount = _docs.length;
    final allUploaded = uploadedCount == totalCount && totalCount > 0;

    return Scaffold(
      backgroundColor: isDark ? _kDarkBg : const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: isRevision
            ? (status == 'rejected' ? _kRed : _kAmber)
            : _kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          typeLabel,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        elevation: 0,
      ),
      body: _loading
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SkeletonLoader(
                    width: double.infinity,
                    height: 56,
                    borderRadius: 14,
                  ),
                  const SizedBox(height: 16),
                  const SkeletonLoader(
                    width: double.infinity,
                    height: 90,
                    borderRadius: 14,
                  ),
                  const SizedBox(height: 16),
                  const SkeletonLoader(
                    width: double.infinity,
                    height: 18,
                    borderRadius: 10,
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    5,
                    (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: SkeletonLoader(
                        width: double.infinity,
                        height: 72,
                        borderRadius: 14,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetch,
              color: _kPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatusBanner(
                          status: status,
                          adminNote: _app['admin_note']?.toString(),
                        ),
                        if (!isApproved && (status == 'payment_pending' || (_app['payment_amount'] != null && (double.tryParse(_app['payment_amount'].toString()) ?? 0) > 0))) ...[
                          const SizedBox(height: 16),
                          _buildRenewalBillCard(isDark),
                        ],
                        const SizedBox(height: 20),
                        _buildStepper(),
                        const SizedBox(height: 24),

                        // ── Stale auto-fill warning ──────────────────────
                        if (_docs.any(
                          (d) =>
                              d['auto_filled'] == true &&
                              _isStale(d['source_uploaded_at']?.toString()),
                        )) ...[
                          _AlertBanner(
                            icon: Icons.warning_amber_rounded,
                            message:
                                'Some auto-filled documents were uploaded over a year ago. Please verify they are still current and replace if needed.',
                            color: _kAmber,
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (!isApproved) ...[
                          _ProgressCard(
                            uploaded: uploadedCount,
                            total: totalCount,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 24),
                        ],

                        Text(
                          'Documents',
                          style: GoogleFonts.outfit(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._docs.map((doc) {
                          final canEditDoc =
                              isEditable || doc['status'] == 'rejected';
                          return _DocRow(
                            doc: doc,
                            isEditable: canEditDoc,
                            isUploading:
                                _uploadingKey == doc['key']?.toString(),
                            onUpload: canEditDoc ? () => _uploadDoc(doc) : null,
                          );
                        }),
                        const SizedBox(height: 28),
                        if (isEditable && allUploaded) ...[
                          _ActionButton(
                            label: isRevision
                                ? 'Resubmit for Review'
                                : 'Submit Application',
                            icon: Icons.send_rounded,
                            color: status == 'rejected'
                                ? _kRed
                                : (isRevision ? _kAmber : _kPrimary),
                            loading: _submitting,
                            onTap: _submit,
                          ),
                          if (isRevision) ...[
                            const SizedBox(height: 10),
                            Text(
                              'No additional payment required — your previous payment is still valid.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],

                        if (isSubmitted || isUnderReview || isApproved) ...[
                          _InfoBox(
                            icon: isApproved
                                ? Icons.verified_rounded
                                : Icons.hourglass_top_rounded,
                            color: isApproved ? _kGreen : _kPrimary,
                            message: isApproved
                                ? 'Your application is approved. Download your compliance certificate below.'
                                : 'Your application is under review. You may still replace documents if a revision is requested.',
                          ),
                          const SizedBox(height: 16),
                          if (isApproved)
                            _ActionButton(
                              label: 'View Compliance Certificate',
                              icon: Icons.workspace_premium_rounded,
                              color: _kGreen,
                              loading: false,
                              onTap: _downloadCertificate,
                            ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildRenewalBillCard(bool isDark) {
    final status = _app['status']?.toString() ?? '';
    final amount = double.tryParse(_app['payment_amount']?.toString() ?? '0') ?? 0.0;
    final deadline = _app['payment_deadline']?.toString() ?? 'Not specified';
    List<dynamic> breakdown = [];
    try {
      if (_app['fee_breakdown'] != null) {
        breakdown = _app['fee_breakdown'] is String 
            ? jsonDecode(_app['fee_breakdown']) 
            : _app['fee_breakdown'];
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPrimary.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: _kPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Official Renewal Bill Issued',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark),
                    ),
                    Text(
                      'Payment Deadline: $deadline',
                      style: GoogleFonts.inter(fontSize: 13.5, color: _kAmber, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          if (breakdown.isNotEmpty) ...[
            ...breakdown.map((item) {
              final label = item['label']?.toString() ?? 'Fee';
              final amt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: GoogleFonts.inter(fontSize: 14, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                    Text('GHS ${amt.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white : _kTextDark)),
                  ],
                ),
              );
            }),
            Divider(color: isDark ? _kBorderDark : const Color(0xFFE2E8F0)),
            const SizedBox(height: 8),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Amount Due:', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark)),
              Text('GHS ${amount.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: _kPrimary)),
            ],
          ),
          const SizedBox(height: 20),

          if (status == 'payment_submitted')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hourglass_top_rounded, color: Color(0xFFE65100), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Payment Submitted',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Verification in progress by Secretariat',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFFFB74D) : const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            )
          else if (status == 'payment_confirmed' || status == 'under_review' || status == 'approved')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Payment Confirmed ✓',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  context.go('/payments?fee=Annual%20Renewal%20Dues&amount=${amount.toStringAsFixed(2)}');
                },
                icon: const Icon(Icons.payment_rounded, size: 18),
                label: Text('Proceed to Payment (GHS ${amount.toStringAsFixed(2)})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status view for approved/rejected apps
// ─────────────────────────────────────────────────────────────────────────────
class _StatusViewPage extends StatelessWidget {
  final Map<String, dynamic> app;
  final int appId;
  const _StatusViewPage({required this.app, required this.appId});

  Future<void> _downloadCertificate(BuildContext context) async {
    final url =
        ApiService.resolveImageUrl('api/v1/compliance/applications/$appId/certificate');
    await InAppDocumentViewer.show(
      context,
      url: url,
      title: 'Annual Certificate of Compliance',
      subtitle: 'Official CUBAG Certificate',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = app['status']?.toString() ?? '';
    final appType = app['type']?.toString() ?? '';
    final typeLabel = appType == 'renewal'
        ? 'Membership Renewal'
        : 'Member ID Application';
    final note = app['admin_note']?.toString();
    final color = _statusColor(status);

    return Scaffold(
      backgroundColor: isDark ? _kDarkBg : const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: color,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          typeLabel,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'approved'
                      ? Icons.verified_rounded
                      : Icons.cancel_rounded,
                  size: 80,
                  color: color,
                ),
                const SizedBox(height: 20),
                Text(
                  _statusLabel(status),
                  style: GoogleFonts.outfit(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  status == 'approved'
                      ? 'Your $typeLabel has been approved.'
                      : 'Your $typeLabel was rejected.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),

                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Note',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          note,
                          style: GoogleFonts.outfit(
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (status == 'approved') ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: Text(
                        'View Compliance Certificate',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _downloadCertificate(context),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(
                    'Back to Compliance Centre',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final bool isDark;
  const _SectionHeader({required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFF5000), Color(0xFFd96e1c)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: _kPrimary.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compliance Centre',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your membership renewal & Member ID applications',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  const _AlertBanner({
    required this.icon,
    required this.message,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ApplicationCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final VoidCallback onTap;
  const _ApplicationCard({required this.app, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = app['status']?.toString() ?? '';
    final type = app['type']?.toString() ?? '';
    final typeLabel = type == 'renewal'
        ? 'Membership Renewal'
        : 'Member ID Application';
    final color = _statusColor(status);
    final uploaded = (app['docs_uploaded'] as num?)?.toInt() ?? 0;
    final total = (app['docs_total'] as num?)?.toInt() ?? 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? _kCardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: status == 'revision_requested'
                ? _kAmber.withValues(alpha: 0.5)
                : (isDark ? _kBorderDark : const Color(0xFFe2e8f0)),
            width: status == 'revision_requested' ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                type == 'renewal'
                    ? Icons.autorenew_rounded
                    : Icons.badge_outlined,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          typeLabel,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 16.5,
                            color: isDark ? Colors.white : _kTextDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_fmtDate(app['created_at']?.toString())} • Docs: $uploaded/$total',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.28), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              status == 'approved'
                                  ? Icons.check_circle_rounded
                                  : status == 'payment_submitted'
                                      ? Icons.hourglass_top_rounded
                                      : status == 'payment_confirmed'
                                          ? Icons.verified_rounded
                                          : status == 'revision_requested'
                                              ? Icons.edit_note_rounded
                                              : status == 'rejected'
                                                  ? Icons.cancel_rounded
                                                  : Icons.circle,
                              size: status == 'payment_submitted' ? 12 : 8,
                              color: color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _statusLabel(status),
                              style: GoogleFonts.outfit(
                                color: color,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  final String? adminNote;
  const _StatusBanner({required this.status, this.adminNote});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    IconData icon;
    String message;
    switch (status) {
      case 'draft':
        icon = Icons.edit_outlined;
        message = 'Upload all required documents, then submit.';
        break;
      case 'submitted':
        icon = Icons.check_circle_outline_rounded;
        message = 'Application submitted. A bill will be generated by the Secretariat for your payment.';
        break;
      case 'payment_pending':
        icon = Icons.payment_outlined;
        message = 'Payment is being processed.';
        break;
      case 'payment_submitted':
        icon = Icons.receipt_long_rounded;
        message =
            adminNote ??
            'Payment receipt submitted successfully. Awaiting Secretariat verification.';
        break;
      case 'payment_confirmed':
        icon = Icons.verified_outlined;
        message = 'Payment confirmed. Admin review in progress.';
        break;
      case 'under_review':
        icon = Icons.hourglass_top;
        message = 'Under review by the CUBAG Secretariat.';
        break;
      case 'revision_requested':
        icon = Icons.edit_note_rounded;
        message =
            adminNote ??
            'Admin has requested changes. Please update the flagged documents and resubmit. No repayment needed.';
        break;
      case 'approved':
        icon = Icons.verified;
        message = 'Approved! Download your compliance certificate below.';
        break;
      case 'rejected':
        icon = Icons.cancel_outlined;
        message =
            adminNote ??
            'Application or document(s) rejected. Please re-upload corrected documents below and resubmit.';
        break;
      default:
        icon = Icons.info_outline;
        message = 'Status: $status';
        break;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(status),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int uploaded, total;
  final bool isDark;
  const _ProgressCard({
    required this.uploaded,
    required this.total,
    required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? uploaded / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? _kBorderDark : const Color(0xFFe2e8f0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Document Progress',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _kTextDark,
                ),
              ),
              Text(
                '$uploaded / $total',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: _kPrimary,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: isDark
                  ? const Color(0xFF3E2418)
                  : const Color(0xFFe2e8f0),
              valueColor: AlwaysStoppedAnimation<Color>(
                uploaded == total ? _kGreen : _kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            uploaded == total
                ? 'All documents uploaded! You may now submit.'
                : '${total - uploaded} document(s) remaining',
            style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  final bool isEditable, isUploading;
  final VoidCallback? onUpload;
  const _DocRow({
    required this.doc,
    required this.isEditable,
    required this.isUploading,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uploaded = doc['uploaded'] == true;
    final autoFilled = doc['auto_filled'] == true;
    final docStatus = doc['status']?.toString() ?? 'not_uploaded';
    final label = doc['label']?.toString() ?? '';
    final fileUrl = doc['file_url']?.toString();
    final adminNote = doc['admin_note']?.toString();
    final srcDate = doc['source_uploaded_at']?.toString();
    final isStaleDoc = autoFilled && _isStale(srcDate);
    final needsAction = docStatus == 'rejected';

    Color sColor;
    IconData sIcon;
    if (!uploaded) {
      sColor = Colors.grey;
      sIcon = Icons.upload_file_rounded;
    } else if (needsAction) {
      sColor = _kRed;
      sIcon = Icons.error_outline_rounded;
    } else if (docStatus == 'approved') {
      sColor = _kGreen;
      sIcon = Icons.check_circle_rounded;
    } else if (isStaleDoc) {
      sColor = _kAmber;
      sIcon = Icons.warning_amber_rounded;
    } else if (autoFilled) {
      sColor = _kAmber;
      sIcon = Icons.auto_fix_high_rounded;
    } else {
      sColor = _kAmber;
      sIcon = Icons.hourglass_empty_rounded;
    }

    final borderColor = needsAction
        ? _kRed.withValues(alpha: 0.4)
        : isStaleDoc
        ? _kAmber.withValues(alpha: 0.4)
        : (isDark ? _kBorderDark : const Color(0xFFe2e8f0));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: uploaded ? sColor.withValues(alpha: 0.3) : borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sIcon, color: sColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    color: isDark ? Colors.white : _kTextDark,
                  ),
                ),
              ),
              if (isUploading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimary,
                  ),
                )
              else if (isEditable)
                InkWell(
                  onTap: onUpload,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (needsAction
                                  ? _kRed
                                  : (uploaded ? _kPrimary : _kGreen))
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            (needsAction
                                    ? _kRed
                                    : (uploaded ? _kPrimary : _kGreen))
                                .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      needsAction
                          ? 'Re-upload'
                          : (uploaded ? 'Replace' : 'Upload'),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: needsAction
                            ? _kRed
                            : (uploaded ? _kPrimary : _kGreen),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // FIX #2: Staleness warning with source upload date
          if (autoFilled && srcDate != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 30),
                Icon(
                  isStaleDoc
                      ? Icons.warning_amber_rounded
                      : Icons.auto_fix_high_rounded,
                  size: 12,
                  color: isStaleDoc ? _kRed : _kAmber,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    isStaleDoc
                        ? 'Auto-filled ${_fmtDate(srcDate)} — document may be outdated, please replace.'
                        : 'Auto-filled from registration (uploaded ${_fmtDate(srcDate)})',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: isStaleDoc ? _kRed : _kAmber,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if ((fileUrl?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                final trimmed = fileUrl?.trim() ?? '';
                if (trimmed.isEmpty) return;
                InAppDocumentViewer.show(
                  context,
                  url: trimmed,
                  title: doc['file_name']?.toString() ?? 'Compliance Document',
                  subtitle: doc['category']?.toString() ?? 'Uploaded Requirement',
                );
              },
              child: Row(
                children: [
                  const SizedBox(width: 30),
                  const Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: _kPrimary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      doc['file_name']?.toString() ?? 'View document',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: _kPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(left: 28),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Admin note: $adminNote',
                style: GoogleFonts.outfit(fontSize: 13.5, color: _kRed),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _InfoBox({
    required this.icon,
    required this.color,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      onPressed: loading ? null : onTap,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 60,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 14),
          Text(
            'No applications yet',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start a new application above',
            style: GoogleFonts.outfit(fontSize: 15, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}
