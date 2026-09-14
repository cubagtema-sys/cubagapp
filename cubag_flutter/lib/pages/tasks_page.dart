// dart:io removed — not needed on web; file handling uses PlatformFile.bytes instead
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _tasks = [];

  // Compliance Documents State
  List<dynamic> _docRequirements = [];
  int _docsTotal = 11;
  int _docsUploaded = 0;
  bool _isLoadingDocs = true;
  String _activeTab = 'documents'; // 'documents' or 'tasks'
  String? _uploadingDocKey;

  // Modal State
  Map<String, dynamic>? _selectedTask;
  final TextEditingController _noteController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isSubmitting = false;
  bool _submitDone = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    SocketService().on('fees_updated', _onDataUpdatedSocket);
    SocketService().on('tasks_updated', _onDataUpdatedSocket);
    SocketService().on('documents_updated', _onDataUpdatedSocket);
    SocketService().on('member_documents_updated', _onDataUpdatedSocket);
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
    SocketService().off('member_documents_updated', _onDataUpdatedSocket);
    _noteController.dispose(); // BUG-F14 fix
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    if (!_isLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    await ApiService().fetchDataWithCache('/tasks', (
      data,
      isCached, {
      bool hasError = false,
    }) {
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

    await ApiService().fetchDataWithCache('/documents/requirements', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data != null && data is Map) {
        setState(() {
          _docRequirements = ApiService.ensureList(data['requirements']);
          _docsTotal = int.tryParse(data['total']?.toString() ?? '11') ?? 11;
          _docsUploaded =
              int.tryParse(data['uploaded']?.toString() ?? '0') ?? 0;
          _isLoadingDocs = false;
        });
      }
    });
  }

  Future<void> _onRefreshAll() async {
    await Future.wait([_fetchTasks(), _fetchRequirements()]);
  }

  Future<void> _openDocumentFile(String? fileUrl, {String? label}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (fileUrl == null || fileUrl.trim().isEmpty) {
      if (mounted && messenger != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No file link is available for this document.'),
          ),
        );
      }
      return;
    }

    final trimmed = fileUrl.trim();
    final resolved =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : (trimmed.startsWith('/')
              ? '${ApiService.baseUrl}${trimmed.startsWith('/') ? trimmed.substring(1) : trimmed}'
              : '${ApiService.baseUrl}$trimmed');

    final uri = Uri.tryParse(resolved);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open ${label ?? 'document'} right now.'),
          ),
        );
      }
      return;
    }

    try {
      if (kIsWeb) {
        final opened = await launchUrl(uri);
        if (!opened && mounted && messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Unable to open ${label ?? 'document'} in the browser.',
              ),
            ),
          );
        }
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        final fallback = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!fallback && mounted && messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Unable to open ${label ?? 'document'} in the app.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && messenger != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open ${label ?? 'document'}: $e')),
        );
      }
    }
  }

  Future<void> _uploadDocumentRequirement(Map<String, dynamic> docReq) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final docKey = docReq['key']?.toString() ?? '';

    setState(() => _uploadingDocKey = docKey);

    if (mounted && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Uploading ${result.files.length} document(s)...',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1A0F0A),
        ),
      );
    }

    try {
      final List<Future<void>> uploadTasks = [];

      for (final pickedFile in result.files) {
        uploadTasks.add(() async {
          late Uint8List bytes;
          if (pickedFile.bytes != null) {
            bytes = pickedFile.bytes!;
          } else {
            bytes = await pickedFile.xFile.readAsBytes();
          }

          final formData = FormData.fromMap({
            'requirement': docReq['key'],
            'label': docReq['label'],
            'file': MultipartFile.fromBytes(bytes, filename: pickedFile.name),
          });

          await ApiService().post('/documents/upload', data: formData);
        }());
      }

      await Future.wait(uploadTasks);
      if (!mounted) return;

      if (mounted && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${docReq['label']} submitted successfully!',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10b981),
          ),
        );
      }
      _fetchRequirements();
    } catch (e) {
      if (mounted && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error uploading document: $e'),
            backgroundColor: const Color(0xFFef4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDocKey = null);
    }
  }

  void _openSubmitModal(Map<String, dynamic> task) {
    setState(() {
      _selectedTask = task;
      _noteController.clear();
      _selectedFile = null;
      _submitDone = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildSubmitModal(),
    );
  }

  Future<void> _pickFile(StateSetter setModalState) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result != null) {
      setModalState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Future<void> _handleSubmit(StateSetter setModalState) async {
    setModalState(() => _isSubmitting = true);
    setState(() => _isSubmitting = true);
    try {
      final apiService = ApiService();
      final formData = FormData.fromMap({
        'task_id': _selectedTask?['id'],
        'notes': _noteController.text,
        if (_selectedFile != null)
          'file': kIsWeb || _selectedFile!.bytes != null
              ? MultipartFile.fromBytes(
                  _selectedFile!.bytes!,
                  filename: _selectedFile!.name,
                )
              : await MultipartFile.fromFile(
                  _selectedFile!.path!,
                  filename: _selectedFile!.name,
                ),
      });
      final response = await apiService.post('/tasks/submit', data: formData);
      if (!mounted) return;
      // BUG-F13 fix: only mark done on success, show error on failure
      if (response.statusCode == 200 || response.statusCode == 201) {
        setModalState(() {
          _submitDone = true;
        });
        setState(() {
          _submitDone = true;
        });
        _fetchTasks();
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        });
      } else {
        final msg =
            (response.data is Map ? response.data['message'] : null) ??
            'Submission failed';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setModalState(() => _isSubmitting = false);
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildSubmitModal() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(32),
            child: _submitDone
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const _PulsingRing(color: Color(0xFF10b981)),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10b981),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Evidence Submitted!',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF1A0F0A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your evidence has been sent for admin review.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF6b6375),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Submit Evidence',
                                  style: GoogleFonts.outfit(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF1A0F0A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedTask?['title'] ?? 'Task Requirement',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: const Color(0xFF6b6375),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 24),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.3),
                              padding: const EdgeInsets.all(8),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Completion Notes',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF1A0F0A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteController,
                        maxLines: 4,
                        style: GoogleFonts.inter(fontSize: 16),
                        decoration: InputDecoration(
                          hintText:
                              'Describe what you did to complete this task...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 15,
                            color: const Color(0xFF64748b),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).primaryColor,
                              width: 2.0,
                            ),
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1A0F0A)
                              : Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Attachments (images, PDF, Word, video)',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF1A0F0A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CustomPaint(
                        painter: DashedBorderPainter(
                          color: _selectedFile != null
                              ? Theme.of(context).primaryColor
                              : Theme.of(context).dividerColor,
                          borderRadius: 12,
                        ),
                        child: InkWell(
                          onTap: () => _pickFile(setModalState),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 28,
                              horizontal: 16,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _selectedFile != null
                                        ? Theme.of(
                                            context,
                                          ).primaryColor.withValues(alpha: 0.1)
                                        : Theme.of(
                                            context,
                                          ).dividerColor.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _selectedFile != null
                                        ? Icons.file_present_rounded
                                        : Icons.cloud_upload_outlined,
                                    size: 32,
                                    color: _selectedFile != null
                                        ? Theme.of(context).primaryColor
                                        : const Color(0xFF64748b),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedFile != null
                                      ? _selectedFile!.name
                                      : 'Click to attach files',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: _selectedFile != null
                                        ? Theme.of(context).primaryColor
                                        : const Color(0xFF64748b),
                                    fontWeight: _selectedFile != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  _handleSubmit(setModalState);
                                },
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Submit for Admin Review',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int pendingCount = _tasks.where((t) => t['done'] != true).length;

    return AppLayout(
      title: 'Tasks & Compliance',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _onRefreshAll,
        color: Theme.of(context).primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 24.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors:
                              Theme.of(context).brightness == Brightness.dark
                              ? [
                                  const Color(0xFF1A0F0A),
                                  const Color(0xFF1A0F0A),
                                ]
                              : [
                                  const Color(0xFFFF5000),
                                  const Color(0xFFe66c19),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF4D2D20)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Icon with pulsing circle
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              if (!_isLoading &&
                                  (pendingCount > 0 ||
                                      _docsUploaded < _docsTotal))
                                _PulsingRing(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).primaryColor
                                      : Colors.white,
                                ),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(
                                          context,
                                        ).primaryColor.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isLoading
                                      ? Icons.sync
                                      : (pendingCount > 0 ||
                                                _docsUploaded < _docsTotal
                                            ? Icons.assignment_late_rounded
                                            : Icons.verified_user_rounded),
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).primaryColor
                                      : Colors.white,
                                  size: 26,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Compliance Status',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (!_isLoading &&
                                        (pendingCount > 0 ||
                                            _docsUploaded < _docsTotal)) ...[
                                      const _BlinkingDot(
                                        color: Colors.redAccent,
                                        size: 8,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        _isLoading
                                            ? 'Checking records...'
                                            : '$_docsUploaded/$_docsTotal Docs Uploaded · $pendingCount Action Items',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? const Color(0xFF9ca3af)
                                              : Colors.white.withValues(
                                                  alpha: 0.95,
                                                ),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
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
                    ),
                    const SizedBox(height: 24),

                    // Tab Segment Switcher
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF281710)
                            : const Color(0xFFf1f5f9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF4D2D20)
                              : const Color(0xFFe2e8f0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _activeTab = 'documents'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _activeTab == 'documents'
                                      ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF4D2D20)
                                            : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _activeTab == 'documents'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.folder_shared_rounded,
                                      size: 16,
                                      color: _activeTab == 'documents'
                                          ? const Color(0xFFFF5000)
                                          : Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Registration Docs',
                                          maxLines: 1,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: _activeTab == 'documents'
                                                ? (Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.white
                                                      : const Color(0xFF1A0F0A))
                                                : Colors.grey.shade500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _activeTab = 'tasks'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _activeTab == 'tasks'
                                      ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF4D2D20)
                                            : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _activeTab == 'tasks'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.task_alt_rounded,
                                      size: 16,
                                      color: _activeTab == 'tasks'
                                          ? const Color(0xFFFF5000)
                                          : Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Checklist & Dues',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: _activeTab == 'tasks'
                                            ? (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : const Color(0xFF1A0F0A))
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_activeTab == 'documents')
                      _buildDocumentsSection()
                    else
                      _buildTasksChecklistSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTasksChecklistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 16.0),
          child: Text(
            'Compliance Requirements',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF1A0F0A),
            ),
          ),
        ),

        if (_isLoading && _tasks.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            decoration: BoxDecoration(
              color: const Color(0xFFef4444).withValues(alpha: 0.05),
              border: Border.all(
                color: const Color(0xFFef4444).withValues(alpha: 0.2),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFef4444).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFFef4444),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Connection Failed',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A0F0A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6b6375),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 140,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFef4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _fetchTasks,
                    child: Text(
                      'Retry',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (_tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF4D2D20)
                    : const Color(0xFFE8DED6),
                width: 1.0,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.task_alt_rounded,
                    color: Theme.of(context).primaryColor,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'All Caught Up!',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A0F0A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You have no pending tasks or dues to clear.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6b6375),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _tasks.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final task = _tasks[index];
              final bool done = task['done'] == true;
              final bool submitted = task['submitted'] == true;
              final bool verified = task['admin_verified'] == true;
              final bool urgent = task['urgent'] == true;

              // Status determination
              Color badgeBgColor;
              Color badgeTextColor;
              String statusText;
              IconData statusIcon;

              if (verified) {
                badgeBgColor = const Color(0xFF10b981).withValues(alpha: 0.1);
                badgeTextColor = const Color(0xFF10b981);
                statusText = 'Verified';
                statusIcon = Icons.verified_rounded;
              } else if (submitted) {
                badgeBgColor = const Color(0xFF3b82f6).withValues(alpha: 0.1);
                badgeTextColor = const Color(0xFF3b82f6);
                statusText = 'Reviewing';
                statusIcon = Icons.hourglass_empty_rounded;
              } else if (urgent) {
                badgeBgColor = const Color(0xFFef4444).withValues(alpha: 0.1);
                badgeTextColor = const Color(0xFFef4444);
                statusText = 'Urgent';
                statusIcon = Icons.warning_amber_rounded;
              } else {
                badgeBgColor = Theme.of(
                  context,
                ).primaryColor.withValues(alpha: 0.1);
                badgeTextColor = Theme.of(context).primaryColor;
                statusText = 'Pending';
                statusIcon = Icons.assignment_outlined;
              }

              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4D2D20)
                        : const Color(0xFFE8DED6),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Icon + Title & Status Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: badgeBgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              statusIcon,
                              color: badgeTextColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['title'] ?? 'Task',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF1A0F0A),
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeBgColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: badgeTextColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (task['description'] != null &&
                          task['description'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          task['description'],
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            color: const Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ],

                      if (task['admin_notes'] != null &&
                          task['admin_notes'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFef4444,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFFef4444,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Color(0xFFef4444),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Admin Note: ${task['admin_notes']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: const Color(0xFFef4444),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (task['due_date'] != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Due: ${task['due_date']}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: urgent
                                ? const Color(0xFFef4444)
                                : const Color(0xFF6b6375),
                            fontWeight: urgent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],

                      // Action Button Section
                      if (task['action_url'] != null) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: urgent
                                  ? const Color(0xFFef4444)
                                  : Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final actionUrl = task['action_url'].toString();
                              if (actionUrl == '/tasks') {
                                setState(() => _activeTab = 'documents');
                              } else {
                                context.go(actionUrl);
                              }
                            },
                            child: Text(
                              task['action_label']?.toString() ?? 'Take Action',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ] else if (!submitted) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () => _openSubmitModal(task),
                            child: Text(
                              'Submit Required Documents',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDocumentsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final cardBg = Theme.of(context).cardColor;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE8DED6);
    final progress = _docsTotal > 0 ? (_docsUploaded / _docsTotal) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress Summary Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Clearance Documents Progress',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _docsUploaded == _docsTotal
                          ? const Color(0xFF10b981).withValues(alpha: 0.1)
                          : const Color(0xFFFF5000).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_docsUploaded / $_docsTotal Uploaded',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _docsUploaded == _docsTotal
                            ? const Color(0xFF10b981)
                            : const Color(0xFFFF5000),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? const Color(0xFF4D2D20)
                      : const Color(0xFFf1f5f9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _docsUploaded == _docsTotal
                        ? const Color(0xFF10b981)
                        : const Color(0xFFFF5000),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload and maintain your mandatory onboarding clearances. Administrators review and approve these documents to verify your membership.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (_isLoadingDocs && _docRequirements.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _docRequirements.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final doc = _docRequirements[i];
              final String key = doc['key'] ?? '';
              final String label = doc['label'] ?? key;
              final bool uploaded = doc['uploaded'] == true;
              final String status = (doc['status'] ?? 'not_uploaded')
                  .toString()
                  .toLowerCase();
              final String? fileUrl = doc['file_url'];
              final String? fileName = doc['file_name'];
              final String? adminNote = doc['admin_note'];
              final bool isUploadingThis = _uploadingDocKey == key;

              Color statusBg;
              Color statusColor;
              String statusLabel;
              IconData statusIcon;

              if (status == 'approved') {
                statusBg = const Color(0xFF10b981).withValues(alpha: 0.1);
                statusColor = const Color(0xFF10b981);
                statusLabel = 'Approved';
                statusIcon = Icons.check_circle_rounded;
              } else if (status == 'pending') {
                statusBg = const Color(0xFFf59e0b).withValues(alpha: 0.1);
                statusColor = const Color(0xFFf59e0b);
                statusLabel = 'Pending Review';
                statusIcon = Icons.hourglass_top_rounded;
              } else if (status == 'rejected') {
                statusBg = const Color(0xFFef4444).withValues(alpha: 0.1);
                statusColor = const Color(0xFFef4444);
                statusLabel = 'Needs Update';
                statusIcon = Icons.error_outline_rounded;
              } else {
                statusBg = Colors.grey.withValues(alpha: 0.1);
                statusColor = Colors.grey.shade600;
                statusLabel = 'Not Uploaded';
                statusIcon = Icons.upload_file_rounded;
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: status == 'rejected'
                        ? const Color(0xFFef4444).withValues(alpha: 0.4)
                        : borderColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(statusIcon, color: statusColor, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A0F0A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  if (fileName != null) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        fileName,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (adminNote != null && adminNote.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFef4444,
                          ).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFef4444,
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Color(0xFFef4444),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Admin note: $adminNote',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: const Color(0xFFef4444),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (uploaded &&
                            fileUrl != null &&
                            fileUrl.isNotEmpty) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              side: BorderSide(
                                color: primary.withValues(alpha: 0.4),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () =>
                                _openDocumentFile(fileUrl, label: label),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 14,
                            ),
                            label: Text(
                              'View File',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: uploaded
                                ? const Color(0xFF1A0F0A)
                                : primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            elevation: 0,
                          ),
                          onPressed: isUploadingThis
                              ? null
                              : () => _uploadDocumentRequirement(doc),
                          icon: isUploadingThis
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  uploaded
                                      ? Icons.refresh_rounded
                                      : Icons.upload_file_rounded,
                                  size: 14,
                                ),
                          label: Text(
                            uploaded ? 'Update File' : 'Upload File',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

// Stateful widgets and Custom Painters for premium visual indicators

class _BlinkingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _BlinkingDot({required this.color, this.size = 8.0});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animationController,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Color color;
  const _PulsingRing({required this.color});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 52 + (24 * _controller.value),
          height: 52 + (24 * _controller.value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: 1.0 - _controller.value),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dashLength;
  final double borderRadius;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.gap = 4.0,
    this.dashLength = 6.0,
    this.borderRadius = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(borderRadius),
        ),
      );

    final dashPath = Path();
    double distance = 0.0;

    for (final pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        final len = dashLength;
        final nextDistance = distance + len;
        if (nextDistance < pathMetric.length) {
          dashPath.addPath(
            pathMetric.extractPath(distance, nextDistance),
            Offset.zero,
          );
        } else {
          dashPath.addPath(
            pathMetric.extractPath(distance, pathMetric.length),
            Offset.zero,
          );
        }
        distance = nextDistance + gap;
      }
      distance = 0.0;
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.borderRadius != borderRadius;
  }
}
