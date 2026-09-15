import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/in_app_document_viewer.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _isLoading = true;
  List<dynamic> _tasks = [];
  List<dynamic> _docRequirements = [];
  int _docsTotal = 11;
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
        setState(() {
          _docRequirements = ApiService.ensureList(data['requirements']);
          _docsTotal = int.tryParse(data['total']?.toString() ?? '11') ?? 11;
          _docsUploaded = int.tryParse(data['uploaded']?.toString() ?? '0') ?? 0;
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
        'document_key': key,
        'file': mpFile,
        'image': mpFile,
        'photo': mpFile,
      });
      final res = await ApiService().upload('/documents/upload', formData);

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Uploaded "$label" successfully', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)), backgroundColor: _kGreen),
          );
        }
        _loadInitialData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.data?['message'] ?? 'Upload failed', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)), backgroundColor: _kRed),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)), backgroundColor: _kRed),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDocKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final border = isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AppLayout(
      title: 'Tasks & Compliance',
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tasks & Compliance', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textPrimary)),
                    const SizedBox(height: 2),
                    Text('Manage compliance documents & pending actions', style: GoogleFonts.inter(fontSize: 13.5, color: textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Simple Tabs
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 'documents'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 'documents' ? _kOrange.withAlpha(20) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Documents ($_docsUploaded/$_docsTotal)',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 'documents' ? _kOrange : textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 'tasks'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 'tasks' ? _kOrange.withAlpha(20) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Tasks (${_tasks.where((t) => t['done'] != true).length})',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 'tasks' ? _kOrange : textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tab Content
            if (_activeTab == 'documents')
              _buildDocumentsView(cardBg, border, textPrimary, textMuted)
            else
              _buildTasksView(cardBg, border, textPrimary, textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsView(Color cardBg, Color border, Color textPrimary, Color textMuted) {
    if (_isLoadingDocs) {
      return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(color: _kOrange)));
    }

    if (_docRequirements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Center(child: Text('No compliance documents required.', style: GoogleFonts.outfit(fontSize: 14.5, color: textMuted))),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _docRequirements.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final doc = _docRequirements[idx];
        final key = doc['key']?.toString() ?? '';
        final label = doc['label']?.toString() ?? 'Document';
        final isUploaded = doc['uploaded'] == true;
        final fileUrl = doc['file_url']?.toString();
        final isUploading = _uploadingDocKey == key;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isUploaded ? _kGreen.withAlpha(80) : border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isUploaded ? _kGreen : _kOrange).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isUploaded ? Icons.verified_rounded : Icons.folder_open_rounded,
                  color: isUploaded ? _kGreen : _kOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      isUploaded ? 'Uploaded & Verified' : 'Action Required: Upload Document',
                      style: GoogleFonts.inter(fontSize: 12.5, color: isUploaded ? _kGreen : textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isUploaded && fileUrl != null && fileUrl.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, size: 18, color: _kOrange),
                  tooltip: 'View Document',
                  onPressed: () {
                    InAppDocumentViewer.show(
                      context,
                      url: fileUrl,
                      title: label,
                      subtitle: 'Uploaded Statutory Document',
                    );
                  },
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isUploaded ? Colors.grey.shade200 : _kOrange,
                  foregroundColor: isUploaded ? Colors.black87 : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: isUploading ? null : () => _uploadDocument(key, label),
                child: Text(
                  isUploading ? 'Uploading...' : (isUploaded ? 'Replace' : 'Upload'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTasksView(Color cardBg, Color border, Color textPrimary, Color textMuted) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(color: _kOrange)));
    }

    if (_tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Center(child: Text('No pending tasks.', style: GoogleFonts.outfit(fontSize: 14.5, color: textMuted))),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tasks.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final task = _tasks[idx];
        final title = task['title']?.toString() ?? 'Task';
        final desc = task['description']?.toString() ?? '';
        final done = task['done'] == true;
        final actionUrl = task['action_url']?.toString();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: done ? _kGreen.withAlpha(80) : border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (done ? _kGreen : _kOrange).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  done ? Icons.check_circle_rounded : Icons.task_alt_rounded,
                  color: done ? _kGreen : _kOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary)),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(desc, style: GoogleFonts.inter(fontSize: 13, color: textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (actionUrl != null && actionUrl.isNotEmpty && !done) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () => context.go(actionUrl),
                  child: Text('Action', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
