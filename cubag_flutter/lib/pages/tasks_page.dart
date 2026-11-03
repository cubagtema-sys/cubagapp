import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../components/app_layout.dart';
import '../components/in_app_document_viewer.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/theme_service.dart';

// Balanced CUBAG Brand Palette & Editorial Tokens
bool get _isDark => ThemeService.instance.isDark;
const _kBrown = Color(0xFF6B3E26);
const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
Color get _kCardBg => _isDark ? const Color(0xFF1E130D) : const Color(0xFFFFFFFF);
Color get _kSurfaceRaised => _isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);
Color get _kBorder => _isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
Color get _kText => _isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
Color get _kMuted => _isDark ? const Color(0xFFC8ADA0) : const Color(0xFF6F625B);

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
        setState(() {
          _docRequirements = reqs;
          _docsTotal = total;
          _docsUploaded = uploaded;
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
              content: Text('Uploaded "$label" successfully', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              backgroundColor: _kGreen,
            ),
          );
        }
        _loadInitialData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.data?['message'] ?? 'Upload failed', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              backgroundColor: _kRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
    final double completionRatio = _docsTotal > 0 ? (_docsUploaded / _docsTotal).clamp(0.0, 1.0) : 0.0;

    return AppLayout(
      title: 'Tasks & Compliance',
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Header Panel ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(_isDark ? 20 : 4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COMPLIANCE & OBLIGATIONS',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _kBrown,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Filings & Tasks',
                                  style: GoogleFonts.outfit(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _kText,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: (completionRatio >= 1.0 ? _kGreen : _kOrange).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _docsTotal > 0
                                    ? '$_docsUploaded OF $_docsTotal FILED'
                                    : 'VERIFYING REQUIREMENTS',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: completionRatio >= 1.0 ? _kGreen : _kOrange,
                                  letterSpacing: 0.5,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: completionRatio,
                            minHeight: 6,
                            backgroundColor: _kSurfaceRaised,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              completionRatio >= 1.0 ? _kGreen : _kOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Segmented Tab Selector ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _activeTab = 'documents'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _activeTab == 'documents' ? _kBrown : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  _docsTotal > 0
                                      ? 'Documents ($_docsUploaded/$_docsTotal)'
                                      : 'Documents',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _activeTab == 'documents' ? Colors.white : _kMuted,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _activeTab = 'tasks'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _activeTab == 'tasks' ? _kBrown : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  'Action Items (${pendingTasks.length})',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _activeTab == 'tasks' ? Colors.white : _kMuted,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 36, color: _kGreen),
              const SizedBox(height: 10),
              Text(
                'No compliance documents required at this time.',
                style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: _kText),
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
      separatorBuilder: (context, index) => const SizedBox(height: 12),
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
        String statusText;
        Color statusTextColor;

        if (isRejected) {
          borderColor = _kRed.withAlpha(80);
          iconBg = _kRed.withAlpha(20);
          iconColor = _kRed;
          statusIcon = Icons.error_outline_rounded;
          statusText = adminNote != null && adminNote.isNotEmpty
              ? 'Rejected by Secretariat: $adminNote • Re-upload required'
              : 'Rejected by Secretariat • Re-upload required';
          statusTextColor = _kRed;
        } else if (isApproved) {
          borderColor = _kGreen.withAlpha(60);
          iconBg = _kGreen.withAlpha(20);
          iconColor = _kGreen;
          statusIcon = Icons.verified_rounded;
          statusText = 'Verified & Approved by Secretariat';
          statusTextColor = _kGreen;
        } else if (isUnderReview) {
          borderColor = _kOrange.withAlpha(45);
          iconBg = _kOrange.withAlpha(20);
          iconColor = _kOrange;
          statusIcon = Icons.hourglass_top_rounded;
          statusText = 'Uploaded • Secretariat Review In Progress';
          statusTextColor = _kOrange;
        } else {
          borderColor = _kBorder;
          iconBg = _kOrange.withAlpha(20);
          iconColor = _kOrange;
          statusIcon = Icons.description_outlined;
          statusText = 'Pending Upload • Required for Good Standing';
          statusTextColor = _kMuted;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 15 : 4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;

              final infoSection = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      statusIcon,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: statusTextColor,
                            fontWeight: (isUploaded || isRejected) ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actionSection = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUploaded && fileUrl != null && fileUrl.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      color: _kBrown,
                      tooltip: 'View Document',
                      onPressed: () {
                        InAppDocumentViewer.show(
                          context,
                          url: fileUrl,
                          title: label,
                          subtitle: 'Official Compliance Document',
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (isUploading)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kSurfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Uploading...',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5, color: _kMuted),
                          ),
                        ],
                      ),
                    )
                  else if (isApproved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _kGreen.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kGreen.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 14, color: _kGreen),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: _kGreen,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isUnderReview)
                    Opacity(
                      opacity: 0.75,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kSurfaceRaised,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 14, color: _kMuted),
                            const SizedBox(width: 4),
                            Text(
                              'Under Review',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: _kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isRejected)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      onPressed: () => _uploadDocument(key, label),
                      icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                      label: Text(
                        'Replace',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      onPressed: () => _uploadDocument(key, label),
                      icon: const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
                      label: Text(
                        'Upload',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    infoSection,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionSection,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: infoSection),
                  const SizedBox(width: 14),
                  actionSection,
                ],
              );
            },
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.assignment_turned_in_outlined, size: 36, color: _kGreen),
              const SizedBox(height: 10),
              Text(
                'No pending action items.',
                style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: _kText),
              ),
              const SizedBox(height: 4),
              Text(
                'You are fully up to date with your compliance deadlines.',
                style: GoogleFonts.inter(fontSize: 12.5, color: _kMuted),
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
      separatorBuilder: (context, index) => const SizedBox(height: 10),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done ? _kGreen.withAlpha(60) : (isOverdue ? _kRed.withAlpha(80) : _kBorder),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isDark ? 15 : 4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;

              final taskInfo = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (done ? _kGreen : (isOverdue ? _kRed : _kOrange)).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      done ? Icons.check_circle_rounded : (isOverdue ? Icons.warning_amber_rounded : Icons.pending_actions_rounded),
                      color: done ? _kGreen : (isOverdue ? _kRed : _kOrange),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            desc,
                            style: GoogleFonts.inter(fontSize: 12.5, color: _kMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (dueDate != null && dueDate.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            isOverdue ? 'Overdue • Due: $dueDate' : 'Due: $dueDate',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: isOverdue ? FontWeight.bold : FontWeight.w500,
                              color: isOverdue ? _kRed : _kMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );

              final actionBtn = (actionUrl != null && actionUrl.isNotEmpty && !done)
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      onPressed: () => context.go(actionUrl),
                      child: Text('Action →', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    )
                  : null;

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    taskInfo,
                    if (actionBtn != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: actionBtn,
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: taskInfo),
                  if (actionBtn != null) ...[
                    const SizedBox(width: 14),
                    actionBtn,
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}
