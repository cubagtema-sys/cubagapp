import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../components/app_layout.dart';
import '../components/in_app_document_viewer.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/theme_service.dart';
import '../design/cubag_design.dart';

// Balanced CUBAG Brand Palette & Editorial Tokens
bool get _isDark => ThemeService.instance.isDark;
const _kBrown = Color(0xFF6B3E26);
const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kAmber = CubagColors.due;
const _kRed = CubagColors.lapsed;
Color get _kCardBg => _isDark ? const Color(0xFF1E130D) : const Color(0xFFFFFFFF);
Color get _kSurfaceRaised => _isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);
Color get _kBorder => _isDark ? const Color(0xFF3D261C) : CubagColors.line;
Color get _kText => _isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;
Color get _kMuted => _isDark ? const Color(0xFFC8ADA0) : CubagColors.muted;

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _isLoading = true;
  List<dynamic> _tasks = [];
  List<dynamic> _docRequirements = [];
  int _docsTotal = 0;
  int _docsUploaded = 0;
  int _docsApproved = 0;
  int _docsUnderReview = 0;
  int _docsRejected = 0;
  bool _isLoadingDocs = true;
  String _activeTab = 'documents'; // 'documents' or 'tasks'
  String? _uploadingDocKey;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    SocketService().on('fees_updated', _onDataUpdatedSocket);
    SocketService().on('tasks_updated', _onDataUpdatedSocket);
    SocketService().on('documents_updated', _onDataUpdatedSocket);
  }

  void _onDataUpdatedSocket(dynamic _) {
    if (mounted) _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_fetchTasks(), _fetchRequirements()]);
  }

  @override
  void dispose() {
    SocketService().off('fees_updated', _onDataUpdatedSocket);
    SocketService().off('tasks_updated', _onDataUpdatedSocket);
    SocketService().off('documents_updated', _onDataUpdatedSocket);
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    if (!_isLoading && mounted) setState(() => _isLoading = true);
    await ApiService().fetchDataWithCache('/tasks', (data, isCached, {bool hasError = false}) {
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _tasks = ApiService.ensureList(data);
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _fetchRequirements() async {
    if (mounted) setState(() => _isLoadingDocs = true);
    await ApiService().fetchDataWithCache('/documents/requirements', (data, isCached, {bool hasError = false}) {
      if (!mounted) return;
      if (data != null && data is Map) {
        final reqs = ApiService.ensureList(data['requirements']);
        final total = int.tryParse(data['total']?.toString() ?? '') ?? reqs.length;
        final uploaded = int.tryParse(data['uploaded']?.toString() ?? '') ??
            reqs.where((d) => d is Map && d['uploaded'] == true).length;
        final approved = int.tryParse(data['approved']?.toString() ?? '') ??
            reqs.where((d) => d is Map && (d['status'] == 'approved' || d['status'] == 'verified')).length;
        final underReview = int.tryParse(data['under_review']?.toString() ?? '') ??
            reqs.where((d) => d is Map && d['uploaded'] == true && d['status'] != 'approved' && d['status'] != 'verified' && d['status'] != 'rejected').length;
        final rejected = int.tryParse(data['rejected']?.toString() ?? '') ??
            reqs.where((d) => d is Map && d['status'] == 'rejected').length;

        setState(() {
          _docRequirements = reqs;
          _docsTotal = total;
          _docsUploaded = uploaded;
          _docsApproved = approved;
          _docsUnderReview = underReview;
          _docsRejected = rejected;
          _isLoadingDocs = false;
        });
      }
    });
  }

  Future<void> _uploadDocument(String key, String label) async {
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    setState(() => _uploadingDocKey = key);
    try {
      late dynamic mpFile;
      if (file.bytes != null) {
        final exactBytes = Uint8List.fromList(file.bytes!);
        mpFile = MultipartFile.fromBytes(exactBytes, filename: file.name);
      } else if (file.path != null) {
        mpFile = await MultipartFile.fromFile(file.path!, filename: file.name);
      } else {
        return;
      }

      final formData = FormData.fromMap({
        'requirement': key,
        'document_key': key,
        'label': label,
        'file': mpFile,
      });
      final res = await ApiService().upload('/documents/upload', formData);

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded "$label" successfully', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: _kGreen,
            ),
          );
        }
        _loadInitialData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.data?['message'] ?? 'Upload failed', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: _kRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: _kRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDocKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final pendingTasks = _tasks.where((t) => t['done'] != true).toList();

    // Accurate calculation based on verification & review status
    final bool isAllApproved = _docsTotal > 0 && _docsApproved == _docsTotal;
    final bool hasUnderReview = _docsUnderReview > 0;
    final bool hasRejected = _docsRejected > 0;

    String statusBadgeText;
    Color statusBadgeColor;
    double progressValue;

    if (_docsTotal == 0) {
      statusBadgeText = 'VERIFYING REQUIREMENTS';
      statusBadgeColor = _kMuted;
      progressValue = 0.0;
    } else if (isAllApproved) {
      statusBadgeText = 'ALL $_docsTotal REQUIREMENTS VERIFIED';
      statusBadgeColor = _kGreen;
      progressValue = 1.0;
    } else if (hasUnderReview) {
      if (_docsUploaded >= _docsTotal) {
        statusBadgeText = '$_docsUploaded of $_docsTotal uploaded · $_docsUnderReview in review';
      } else {
        statusBadgeText = '$_docsApproved of $_docsTotal approved · $_docsUnderReview in review';
      }
      statusBadgeColor = _kAmber;
      progressValue = ((_docsApproved + (_docsUnderReview * 0.5)) / _docsTotal).clamp(0.08, 0.95);
    } else if (hasRejected) {
      statusBadgeText = '$_docsRejected REVISION REQUIRED';
      statusBadgeColor = _kRed;
      progressValue = (_docsApproved / _docsTotal).clamp(0.0, 1.0);
    } else {
      statusBadgeText = '$_docsUploaded of $_docsTotal uploaded';
      statusBadgeColor = _docsUploaded > 0 ? _kOrange : _kMuted;
      progressValue = (_docsUploaded / _docsTotal).clamp(0.0, 1.0);
    }

    return AppLayout(
      title: 'Tasks',
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Header Panel ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorder, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(_isDark ? 30 : 6),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
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
                                color: statusBadgeColor.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isAllApproved
                                    ? Icons.verified_user_rounded
                                    : (hasUnderReview
                                        ? Icons.hourglass_top_rounded
                                        : Icons.assignment_outlined),
                                color: statusBadgeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your documents and tasks',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _kBrown,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tasks',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: _kText,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Status badge chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusBadgeColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusBadgeColor.withAlpha(50), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: statusBadgeColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  statusBadgeText,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: statusBadgeColor,
                                    letterSpacing: 0.3,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 8,
                            backgroundColor: _kSurfaceRaised,
                            valueColor: AlwaysStoppedAnimation<Color>(statusBadgeColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Segmented Tab Selector ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _kSurfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _activeTab = 'documents'),
                            borderRadius: BorderRadius.circular(9),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _activeTab == 'documents' ? _kBrown : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 16,
                                      color: _activeTab == 'documents' ? Colors.white : _kMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _docsTotal > 0
                                          ? 'Documents ($_docsUploaded/$_docsTotal)'
                                          : 'Documents',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _activeTab == 'documents' ? Colors.white : _kMuted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _activeTab = 'tasks'),
                            borderRadius: BorderRadius.circular(9),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _activeTab == 'tasks' ? _kBrown : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.task_alt_rounded,
                                      size: 16,
                                      color: _activeTab == 'tasks' ? Colors.white : _kMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Tasks (${pendingTasks.length})',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _activeTab == 'tasks' ? Colors.white : _kMuted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Tab Body Content ──────────────────────────────────
                  if (_activeTab == 'documents')
                    _buildDocumentsView()
                  else
                    _buildTasksView(pendingTasks),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentsView() {
    if (_isLoadingDocs && _docRequirements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    if (_docRequirements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 40, color: _kGreen),
              const SizedBox(height: 12),
              Text(
                'No compliance documents required at this time.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kText),
              ),
              const SizedBox(height: 4),
              Text(
                'Your account status and documents are currently in good order.',
                style: TextStyle(fontSize: 13, color: _kMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _docRequirements.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, idx) {
        final doc = _docRequirements[idx];
        final key = doc['key']?.toString() ?? '';
        final label = doc['label']?.toString() ?? 'Document';
        final isUploaded = doc['uploaded'] == true;
        final fileUrl = doc['file_url']?.toString();
        final isUploading = _uploadingDocKey == key;

        final rawStatus = (doc['status']?.toString() ?? '').toLowerCase().trim();
        final docStatus = rawStatus.isNotEmpty ? rawStatus : (isUploaded ? 'pending' : 'not_uploaded');
        final isApproved = docStatus == 'approved' || docStatus == 'verified';
        final isRejected = docStatus == 'rejected';
        final isUnderReview = isUploaded && !isApproved && !isRejected;
        final adminNote = doc['admin_note']?.toString();

        Color borderColor;
        Color iconBg;
        Color iconColor;
        IconData statusIcon;
        String statusPillText;
        Color statusPillBg;
        Color statusPillTextColor;
        String statusSubtext;

        if (isRejected) {
          borderColor = _kRed.withAlpha(90);
          iconBg = _kRed.withAlpha(20);
          iconColor = _kRed;
          statusIcon = Icons.error_outline_rounded;
          statusPillText = 'Revision Required';
          statusPillBg = _kRed.withAlpha(20);
          statusPillTextColor = _kRed;
          statusSubtext = 'Document flagged by Secretariat. Please re-upload.';
        } else if (isApproved) {
          borderColor = _kGreen.withAlpha(70);
          iconBg = _kGreen.withAlpha(20);
          iconColor = _kGreen;
          statusIcon = Icons.verified_rounded;
          statusPillText = 'Verified & Approved';
          statusPillBg = _kGreen.withAlpha(20);
          statusPillTextColor = _kGreen;
          statusSubtext = 'Officially vetted and confirmed in good standing.';
        } else if (isUnderReview) {
          borderColor = _kAmber.withAlpha(60);
          iconBg = _kAmber.withAlpha(20);
          iconColor = _kAmber;
          statusIcon = Icons.hourglass_top_rounded;
          statusPillText = 'Under Review';
          statusPillBg = _kAmber.withAlpha(25);
          statusPillTextColor = CubagColors.due;
          statusSubtext = 'Uploaded successfully. Secretariat vetting in progress.';
        } else {
          borderColor = _kBorder;
          iconBg = _kOrange.withAlpha(20);
          iconColor = _kOrange;
          statusIcon = Icons.description_outlined;
          statusPillText = 'Not uploaded';
          statusPillBg = _kSurfaceRaised;
          statusPillTextColor = _kMuted;
          statusSubtext = 'Required for your licence.';
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 20 : 5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Icon + Document Title + Status Pill
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(statusIcon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusPillBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusPillText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusPillTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                statusSubtext,
                style: TextStyle(
                  fontSize: 12.5,
                  color: _kMuted,
                  height: 1.35,
                ),
              ),

              // Secretariat Admin Note if rejected/revision required
              if (isRejected && adminNote != null && adminNote.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kRed.withAlpha(12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kRed.withAlpha(40)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: _kRed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secretariat Note: $adminNote',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              // Action buttons row: Full mobile-friendly touch targets
              Row(
                children: [
                  if (isUploaded && fileUrl != null && fileUrl.isNotEmpty) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrown,
                        side: BorderSide(color: _kBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        InAppDocumentViewer.show(
                          context,
                          url: fileUrl,
                          title: label,
                          subtitle: 'Official Compliance Filing',
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(
                        'Preview',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: isUploading
                        ? Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _kSurfaceRaised,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Uploading file...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: _kMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : isApproved
                            ? Container(
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _kGreen.withAlpha(15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _kGreen.withAlpha(50)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, size: 16, color: _kGreen),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Completed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: _kGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : isUnderReview
                                ? Container(
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _kSurfaceRaised,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _kBorder),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock_clock_rounded, size: 16, color: _kMuted),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Review',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5,
                                            color: _kMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isRejected ? _kRed : _kOrange,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 40),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _uploadDocument(key, label),
                                    icon: Icon(
                                      isRejected ? Icons.refresh_rounded : Icons.upload_file_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      isRejected ? 'Upload again' : 'Upload',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTasksView(List<dynamic> pendingTasks) {
    if (_isLoading && _tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.assignment_turned_in_outlined, size: 40, color: _kGreen),
              const SizedBox(height: 12),
              Text(
                'No pending action items.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kText),
              ),
              const SizedBox(height: 4),
              Text(
                'You are fully up to date with your compliance deadlines.',
                style: TextStyle(fontSize: 13, color: _kMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, idx) {
        final task = _tasks[idx];
        final title = task['title']?.toString() ?? 'Action Item';
        final desc = task['description']?.toString() ?? '';
        final done = task['done'] == true;
        final actionUrl = task['action_url']?.toString();
        final dueDate = task['due_date']?.toString();
        final bool isOverdue = dueDate != null &&
            DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true &&
            !done;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: done ? _kGreen.withAlpha(60) : (isOverdue ? _kRed.withAlpha(80) : _kBorder),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 20 : 5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
                      color: (done ? _kGreen : (isOverdue ? _kRed : _kOrange)).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      done
                          ? Icons.check_circle_rounded
                          : (isOverdue ? Icons.warning_amber_rounded : Icons.pending_actions_rounded),
                      color: done ? _kGreen : (isOverdue ? _kRed : _kOrange),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 13,
                              color: _kMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (dueDate != null || actionUrl != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (dueDate != null)
                      Text(
                        isOverdue ? 'Overdue: $dueDate' : 'Due: $dueDate',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isOverdue ? _kRed : _kMuted,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (!done && actionUrl != null && actionUrl.isNotEmpty)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: () => context.go(actionUrl),
                        child: Text(
                          'Complete Task',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
