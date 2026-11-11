import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';
import '../design/cubag_design.dart';
import '../components/cubag_ui.dart';
import '../components/home/home_sections.dart';

const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

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

      if (mounted) {
        _showSnack('$label uploaded successfully', _kGreen);
        _fetchRequirements();
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) _showSnack('Upload error: $msg', _kRed);
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
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  /// Never show a zero or missing fee as an amount.
  String get _regFeeLabel {
    final v = double.tryParse(_registrationFeeAmount.replaceAll(',', ''));
    return (v != null && v > 0) ? 'GH₵ ${v.toStringAsFixed(2)}' : 'the registration fee';
  }

  void _pay(String fee) =>
      context.go('/payments?fee=${Uri.encodeComponent(fee)}&redirect=/application-documents');

  /// The onboarding sequence, with the one action that moves it forward.
  /// Same rules as before the redesign; only the presentation changed.
  List<ChecklistStep> _steps() {
    final noDocs = _totalDocs == 0;
    final submitted = _memberStatus == 'pending_review' || _memberStatus == 'active';
    final allUploaded = noDocs || _uploadedCount >= _totalDocs;
    final approved = _allRequiredApproved || _memberStatus == 'approved';

    Widget button(String label, VoidCallback? onPressed) => Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        );

    final steps = <ChecklistStep>[];
    if (!noDocs) {
      steps.add(ChecklistStep(
        'Upload your documents',
        detail: '$_uploadedCount of $_totalDocs uploaded',
        state: allUploaded ? ChecklistState.done : ChecklistState.current,
      ));
      steps.add(ChecklistStep(
        'Submit for review',
        detail: submitted ? 'Submitted to the Secretariat' : 'Send your documents to the Secretariat',
        state: submitted ? ChecklistState.done : (allUploaded ? ChecklistState.current : ChecklistState.upcoming),
        action: button(
          _submitting ? 'Submitting…' : 'Submit application',
          _submitting ? null : _submitApplication,
        ),
      ));
    }
    final feeState = _registrationFeePaid
        ? ChecklistState.done
        : ((noDocs || submitted) ? ChecklistState.current : ChecklistState.upcoming);
    final payPackage = submitted && approved && !_registrationFeePaid;
    steps.add(ChecklistStep(
      payPackage ? 'Pay the membership package' : 'Pay the registration fee',
      detail: _registrationFeePaid
          ? 'Paid'
          : (payPackage
              ? 'Your documents are approved'
              : 'Paid once, $_regFeeLabel'),
      state: feeState,
      action: button(
        'Pay now',
        () => _pay(payPackage ? 'Membership Entrance Package' : 'Registration Fee'),
      ),
    ));
    steps.add(ChecklistStep(
      'Secretariat approval',
      detail: 'We\'ll notify you when your membership is active',
      state: (_registrationFeePaid && (noDocs || submitted)) ? ChecklistState.current : ChecklistState.upcoming,
    ));
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _requirements.isEmpty) {
      return const AppLayout(
        title: 'Your application',
        background: CubagColors.paper,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AppLayout(
      title: 'Your application',
      scrollable: false,
      background: CubagColors.paper,
      child: PageBody(
        onRefresh: _fetchRequirements,
        children: [
          const PageIntro(
            'Complete your application',
            subtitle: 'Your account is ready. Finish these steps and the Secretariat will activate your membership.',
          ),
          const SizedBox(height: CubagSpace.xl),
          StepChecklist(steps: _steps()),
          if (_totalDocs > 0 && _requirements.isNotEmpty) ...[
            const SizedBox(height: CubagSpace.xxl),
            const Text('Documents', style: CubagType.headline),
            const SizedBox(height: CubagSpace.xxs),
            const Text('PDF or photo, up to 15 MB each.', style: CubagType.small),
            const SizedBox(height: CubagSpace.sm),
            HomeGroup(children: [for (final r in _requirements) _docRow(Map<String, dynamic>.from(r as Map))]),
          ],
        ],
      ),
    );
  }

  Widget _docRow(Map<String, dynamic> req) {
    final key = req['key']?.toString() ?? '';
    final status = req['status']?.toString() ?? 'not_uploaded';
    final uploaded = req['uploaded'] == true;
    final isUploading = _uploading[key] == true;
    final fileName = req['file_name']?.toString();
    final note = req['admin_note']?.toString().trim() ?? '';

    final (chipLabel, chipKind) = switch (status) {
      'approved' => ('Approved', StatusKind.good),
      'rejected' => ('Rejected', StatusKind.bad),
      'pending' => ('Under review', StatusKind.pending),
      _ => (uploaded ? 'Under review' : 'Not uploaded', uploaded ? StatusKind.pending : StatusKind.neutral),
    };
    final canUpload = !uploaded || status == 'rejected';

    return Padding(
      padding: const EdgeInsets.all(CubagSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(req['label']?.toString() ?? 'Document', style: CubagType.bodyStrong)),
              const SizedBox(width: CubagSpace.xs),
              StatusChip(chipLabel, kind: chipKind),
            ],
          ),
          if (uploaded && fileName != null && fileName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 16, color: CubagColors.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(fileName, style: CubagType.small, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ],
          if (status == 'rejected' && note.isNotEmpty) ...[
            const SizedBox(height: CubagSpace.xs),
            Text('Secretariat note: $note', style: CubagType.small.copyWith(color: CubagColors.lapsed)),
          ],
          if (canUpload) ...[
            const SizedBox(height: CubagSpace.sm),
            OutlinedButton.icon(
              onPressed: isUploading ? null : () => _pickAndUpload(req),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: isUploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_rounded, size: 20),
              label: Text(isUploading ? 'Uploading…' : (status == 'rejected' ? 'Upload again' : 'Upload')),
            ),
          ],
        ],
      ),
    );
  }
}
