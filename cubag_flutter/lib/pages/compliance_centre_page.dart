// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

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
    case 'revision_requested':
      return _kAmber;
    case 'under_review':
      return _kPrimary;
    case 'submitted':
      return _kAmber;
    case 'payment_pending':
      return _kAmber;
    case 'payment_confirmed':
      return _kPrimary;
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
    case 'payment_pending':
      return 'Payment Pending';
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
      return s ?? '—';
  }
}

String _fmtDate(String? d) {
  if (d == null || d.isEmpty) return '—';
  try {
    final dt = DateTime.parse(d);
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
        final ext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'pdf';
        final size = file.size;

        uploadTasks.add(() async {
          final signRes = await ApiService().post(
            '/compliance/applications/${widget.appId}/sign-upload',
            data: {
              'requirement': key,
              'label': docReq['label'],
              'ext': ext,
              'size': size,
            },
          );
          if (signRes.statusCode != 200 || signRes.data is! Map) {
            throw Exception(
              signRes.data?['message']?.toString() ?? 'Sign failed',
            );
          }

          final uploadUrl = signRes.data['upload_url']?.toString();
          final publicUrl = signRes.data['public_url']?.toString();
          final supaKey = signRes.data['supabase_key']?.toString() ?? '';

          if (uploadUrl == null || uploadUrl.isEmpty) {
            throw Exception('Upload URL was not provided by server');
          }

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
            '/compliance/applications/${widget.appId}/confirm-upload',
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
      _showSnack('${docReq['label']} uploaded successfully!', color: _kGreen);
      _fetch();
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', color: _kRed);
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
    try {
      // Read the JWT from local storage and append as ?token=... so the
      // browser GET request works without needing an Authorization header.
      final jwt = await SessionStorage.instance.getString('cubag_token') ?? '';
      final url =
          '${ApiService.baseUrl}/api/v1/compliance/applications/${widget.appId}/certificate'
          '${jwt.isNotEmpty ? '?token=${Uri.encodeComponent(jwt)}' : ''}';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnack('Could not open certificate', color: _kRed);
      }
    } catch (e) {
      _showSnack('Error opening certificate: $e', color: _kRed);
    }
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
                              label: 'Download Compliance Certificate',
                              icon: Icons.download_rounded,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Status view for approved/rejected apps
// ─────────────────────────────────────────────────────────────────────────────
class _StatusViewPage extends StatelessWidget {
  final Map<String, dynamic> app;
  final int appId;
  const _StatusViewPage({required this.app, required this.appId});

  Future<void> _downloadCertificate(BuildContext context) async {
    try {
      final jwt = await SessionStorage.instance.getString('cubag_token') ?? '';
      final url =
          '${ApiService.baseUrl}/api/v1/compliance/applications/$appId/certificate'
          '${jwt.isNotEmpty ? '?token=${Uri.encodeComponent(jwt)}' : ''}';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
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
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        'Download Compliance Certificate',
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? _kCardDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: status == 'revision_requested'
                ? _kAmber.withValues(alpha: 0.5)
                : (isDark ? _kBorderDark : const Color(0xFFe2e8f0)),
            width: status == 'revision_requested' ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                type == 'renewal'
                    ? Icons.refresh_rounded
                    : Icons.assignment_outlined,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeLabel,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_fmtDate(app['created_at']?.toString())} • Docs: $uploaded/$total',
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(status),
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
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
        icon = Icons.check_outlined;
        message = 'Documents uploaded. Please proceed to payment.';
        break;
      case 'payment_pending':
        icon = Icons.payment_outlined;
        message = 'Payment is being processed.';
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
              onTap: () async {
                final trimmed = fileUrl?.trim() ?? '';
                if (trimmed.isEmpty) return;
                final resolved =
                    trimmed.startsWith('http://') ||
                        trimmed.startsWith('https://')
                    ? trimmed
                    : (trimmed.startsWith('/')
                          ? '${ApiService.baseUrl}${trimmed.substring(1)}'
                          : '${ApiService.baseUrl}$trimmed');
                final uri = Uri.tryParse(resolved);
                if (uri == null ||
                    !uri.hasScheme ||
                    (uri.scheme != 'http' && uri.scheme != 'https')) {
                  return;
                }
                if (kIsWeb) {
                  final opened = await launchUrl(uri);
                  if (!opened) {
                    // no-op: browser open failed
                  }
                } else {
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched) {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                }
              },
              child: Row(
                children: [
                  const SizedBox(width: 30),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 12,
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
