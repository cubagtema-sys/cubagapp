import '../components/admin_dialog.dart';
import '../components/admin_components.dart';
// ignore_for_file: use_build_context_synchronously
import '../components/filter_tabs.dart';
import '../components/admin_list.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../components/doc_preview_stub.dart'
    if (dart.library.html) '../components/doc_preview_web.dart'
    as doc_preview;
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';
import '../components/cubag_ui.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const _kPrimary = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kAmber = CubagColors.due;
const _kRed = CubagColors.lapsed;
const _kDarkBg = CubagColors.ink;
const _kCardDark = Color(0xFF22140E);
const _kBorderDark = Color(0xFF3D261C);
const _kTextDark = Color(0xFF1F1612);

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
    case 'payment_submitted':
      return _kAmber;
    case 'partially_paid':
      return CubagColors.due;
    case 'under_review':
      return _kPrimary;
    case 'submitted':
      return _kAmber;
    case 'payment_confirmed':
      return _kGreen;
    case 'revision_requested':
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
      return 'Awaiting bill';
    case 'awaiting_payment':
    case 'payment_pending':
      return 'Awaiting payment';
    case 'partially_paid':
      return 'Partially paid';
    case 'payment_submitted':
      return 'Payment submitted';
    case 'payment_confirmed':
      return 'Payment confirmed';
    case 'under_review':
      return 'Under review';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    case 'revision_requested':
      return 'Revision requested';
    default:
      return s ?? '—';
  }
}

String _fmt(String? d) {
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

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN LIST PAGE
// ─────────────────────────────────────────────────────────────────────────────
class AdminCompliancePage extends StatefulWidget {
  const AdminCompliancePage({super.key});
  @override
  State<AdminCompliancePage> createState() => _AdminCompliancePageState();
}

class _AdminCompliancePageState extends State<AdminCompliancePage> {
  final Map<String, List<dynamic>> _data = {'renewal': []};
  final Map<String, bool> _loading = {'renewal': true};
  final Map<String, int> _totals = {'renewal': 0};
  final Map<String, int> _page = {'renewal': 1};
  final Map<String, int> _perPage = {'renewal': 50};
  final Map<String, String> _statusFilters = {'renewal': ''};
  final String _selectedCategory = 'corporate';
  String _renewalSearch = '';

  @override
  void initState() {
    super.initState();
    _fetch('renewal');
    SocketService().on('compliance_updated', _onComplianceLiveUpdate);
    SocketService().on('member_updated', _onComplianceLiveUpdate);
    SocketService().on('member_approved', _onComplianceLiveUpdate);
    SocketService().on('tasks_updated', _onComplianceLiveUpdate);
  }

  void _onComplianceLiveUpdate(dynamic data) {
    if (!mounted) return;
    if (data is Map && data['application_id'] != null) {
      final appId = data['application_id'].toString();
      final newStatus = data['status']?.toString();
      if (newStatus != null) {
        setState(() {
          for (var list in _data.values) {
            for (var a in list) {
              if (a is Map && a['id']?.toString() == appId) {
                a['status'] = newStatus;
              }
            }
          }
        });
      }
    }
    ApiService.deleteCacheKeysMatching('compliance');
    _fetch('renewal');
  }

  @override
  void dispose() {
    SocketService().off('compliance_updated', _onComplianceLiveUpdate);
    SocketService().off('member_updated', _onComplianceLiveUpdate);
    SocketService().off('member_approved', _onComplianceLiveUpdate);
    SocketService().off('tasks_updated', _onComplianceLiveUpdate);
    super.dispose();
  }

  Future<void> _fetch(String type) async {
    setState(() => _loading[type] = true);
    try {
      final page = _page[type] ?? 1;
      final perPage = _perPage[type] ?? 50;
      final status = _statusFilters[type] ?? '';
      final params =
          'type=$type&page=$page&per_page=$perPage${status.isNotEmpty ? '&status=$status' : ''}';
      await ApiService().fetchDataWithCache(
        '/compliance/admin/applications?$params',
        (data, isCached, {bool hasError = false}) {
          if (!mounted) return;
          if (hasError) {
            if (!isCached) setState(() => _loading[type] = false);
            return;
          }
          if (data != null && data is Map) {
            final map = Map<String, dynamic>.from(data);
            final apps = ApiService.ensureList(map['applications']);
            final total = (map['total'] as num?)?.toInt() ?? apps.length;
            setState(() {
              _data[type] = apps;
              _totals[type] = total;
              _loading[type] = false;
            });
          }
        },
      );
    } catch (e, st) {
      AppLogger.error('admin_compliance_page', e, st);
    }
    if (mounted) setState(() => _loading[type] = false);
  }

  List<Map<String, dynamic>> _getAllApps() {
    return (_data['renewal'] ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getAppsForCategory(String category) {
    final all = _getAllApps();
    return all.where((a) {
      final mType = (a['member_type']?.toString().toLowerCase() ?? 'corporate');
      if (category == 'corporate') {
        return mType == 'corporate' || mType.isEmpty;
      }
      return mType == category;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredForCurrentCategory() {
    final list = _getAppsForCategory(_selectedCategory);
    final q = _renewalSearch.toLowerCase().trim();
    final status = (_statusFilters['renewal'] ?? '').toLowerCase();

    return list.where((a) {
      if (status.isNotEmpty) {
        final aStatus = (a['status']?.toString() ?? '').toLowerCase();
        if (aStatus != status) return false;
      }
      if (q.isNotEmpty) {
        final name = (a['member_name'] as String? ?? '').toLowerCase();
        final comp = (a['member_company'] as String? ?? '').toLowerCase();
        final email = (a['member_email'] as String? ?? '').toLowerCase();
        final id = a['id']?.toString() ?? '';
        return name.contains(q) || comp.contains(q) || email.contains(q) || id.contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = _getAppsForCategory(_selectedCategory);
    int count(String s) => all.where((a) => (a['status']?.toString() ?? '').toLowerCase() == s).length;
    final list = _filteredForCurrentCategory();
    final filter = _statusFilters['renewal'] ?? '';
    final loading = _loading['renewal'] == true;
    AdminFigure fig(String label, String value, int n, {Color? color}) => AdminFigure(
          label,
          '$n',
          color: n > 0 ? color : null,
          selected: filter == value,
          onTap: () => setState(() => _statusFilters['renewal'] = value),
        );

    return AppLayout(
      title: 'Compliance',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Compliance',
                subtitle: 'Renewal and licence applications. Open one to check the documents, issue the bill, then approve.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _fetch('renewal'),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                fig('New', 'submitted', count('submitted'), color: CubagColors.due),
                fig('In review', 'under_review', count('under_review'), color: CubagColors.due),
                fig('Changes', 'revision_requested', count('revision_requested'), color: CubagColors.due),
                fig('Approved', 'approved', count('approved'), color: CubagColors.valid),
                fig('Rejected', 'rejected', count('rejected'), color: CubagColors.lapsed),
                fig('All', '', all.length),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search name, company or ID',
                onChanged: (v) => setState(() => _renewalSearch = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (list.isEmpty)
                EmptyMessage(
                  icon: Icons.fact_check_outlined,
                  title: _renewalSearch.isNotEmpty ? 'No applications match' : _renewalFilterLabelEmpty(),
                  message: _renewalSearch.isNotEmpty
                      ? 'Try other words, or clear the search.'
                      : 'Applications appear here when members submit them.',
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [for (final app in list) _applicationRow(app)],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  String _renewalFilterLabelEmpty() => switch (_statusFilters['renewal'] ?? '') {
        'submitted' => 'No new applications',
        'under_review' => 'Nothing in review',
        'revision_requested' => 'No applications waiting for changes',
        'approved' => 'No approved applications yet',
        'rejected' => 'No rejected applications',
        _ => 'No applications yet',
      };

  Widget _applicationRow(Map<String, dynamic> app) {
    final uploaded = (app['docs_uploaded'] as num?)?.toInt() ?? 0;
    final totalDocs = (app['docs_total'] as num?)?.toInt() ?? 0;
    final paymentRef = app['payment_ref']?.toString();
    final paymentAmount = app['payment_amount'];
    final status = app['status']?.toString().toLowerCase() ?? '';
    final isPaid = app['payment_confirmed_at'] != null || status == 'payment_confirmed' || status == 'approved';
    final paySent = !isPaid && ((paymentRef != null && paymentRef.isNotEmpty) || status == 'payment_submitted');
    final payment = isPaid
        ? (paymentAmount != null ? 'Paid GH₵ $paymentAmount' : 'Paid')
        : (paySent ? (paymentAmount != null ? 'Payment sent GH₵ $paymentAmount' : 'Payment sent') : 'Not paid yet');
    final name = app['member_name']?.toString() ?? 'Applicant';
    final company = app['member_company']?.toString() ?? '';
    final id = app['id'];
    final ref = id is int ? '#COMP-${id.toString().padLeft(5, '0')}' : '';
    final type = app['type']?.toString() ?? '';
    final typeLabel = type == 'renewal_district'
        ? 'District clearance'
        : (type == 'renewal_national' ? 'National renewal' : (type.contains('renewal') ? 'Renewal' : 'Licence application'));
    final kind = switch (status) {
      'approved' || 'payment_confirmed' => StatusKind.good,
      'rejected' => StatusKind.bad,
      'draft' => StatusKind.neutral,
      _ => StatusKind.pending,
    };

    return AdminListRow(
      leading: AdminRowMark(initials: adminInitials(name)),
      title: name,
      subtitle: [if (company.isNotEmpty) company, typeLabel].join(' · '),
      meta: [
        if (ref.isNotEmpty) ref,
        if (totalDocs > 0) '$uploaded of $totalDocs documents',
        payment,
      ].join(' · '),
      status: StatusChip(_statusLabel(status), kind: kind),
      background: status == 'submitted' || status == 'payment_submitted' ? CubagColors.dueTint.withAlpha(90) : null,
      onTap: () => _openDetail(app),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> app) async {
    final id = app['id'];
    if (id != null) {
      await context.push('/admin/compliance/$id');
      if (mounted) {
        await ApiService.deleteCacheKeysMatching('compliance');
        _fetch('renewal');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DETAIL PAGE (SIMPLIFIED & INTEGRATED IN APP LAYOUT / SIDEBAR SHELL)
// ─────────────────────────────────────────────────────────────────────────────
class AdminComplianceDetailPage extends StatefulWidget {
  final int appId;
  const AdminComplianceDetailPage({super.key, required this.appId});
  @override
  State<AdminComplianceDetailPage> createState() =>
      _AdminComplianceDetailPageState();
}

class _BillItemController {
  final TextEditingController labelCtrl;
  final TextEditingController amountCtrl;

  _BillItemController({String label = '', dynamic amount = ''})
      : labelCtrl = TextEditingController(text: label),
        amountCtrl = TextEditingController(
          text: (amount != null && amount != '' && amount != '0' && amount != 0 && amount != '0.0')
              ? amount.toString()
              : (amount == 0 || amount == '0' || amount == '' ? '' : amount.toString()),
        );

  void dispose() {
    labelCtrl.dispose();
    amountCtrl.dispose();
  }

  String get label => labelCtrl.text.trim();
  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0.0;
}

class _AdminComplianceDetailPageState extends State<AdminComplianceDetailPage> {
  bool _loading = true;
  Map<String, dynamic> _app = {};
  Map<String, dynamic>? _payment;
  bool _confirmingPayment = false;
  List<dynamic> _docs = [];
  bool _approving = false;
  bool _rejecting = false;
  bool _requestingRevision = false;
  final _noteCtrl = TextEditingController();
  final _billTitleCtrl = TextEditingController(text: 'Annual renewal dues');

  final List<_BillItemController> _billItemControllers = [];
  DateTime? _paymentDeadline = DateTime.now().add(const Duration(days: 14));
  bool _savingBill = false;
  bool _allowInstallments = true;
  final _minInstallmentCtrl = TextEditingController(text: '0.00');
  List<dynamic> _installments = [];

  double get _calculatedTotal {
    double sum = 0;
    for (var item in _billItemControllers) {
      sum += item.amount;
    }
    return sum;
  }

  @override
  void initState() {
    super.initState();
    _billItemControllers.add(_BillItemController(label: 'Base renewal fee', amount: 500.0));
    _fetch();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _billTitleCtrl.dispose();
    _minInstallmentCtrl.dispose();
    for (final c in _billItemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get(
        '/compliance/admin/applications/${widget.appId}',
      );
      if (mounted && res.statusCode == 200) {
        setState(() {
          _loading = false;
          _app = Map<String, dynamic>.from(res.data['application'] ?? {});
          _docs = ApiService.ensureList(res.data['documents']);
          _payment = res.data['payment'] != null ? Map<String, dynamic>.from(res.data['payment']) : null;
          _installments = ApiService.ensureList(res.data['installments'] ?? _app['installments']);

          if (_app['allow_installments'] != null) {
            _allowInstallments = _app['allow_installments'] == true || _app['allow_installments'].toString().toLowerCase() == 'true';
          }
          if (_app['min_installment_amount'] != null) {
            final minAmt = double.tryParse(_app['min_installment_amount'].toString()) ?? 0.0;
            _minInstallmentCtrl.text = minAmt > 0 ? minAmt.toStringAsFixed(2) : '0.00';
          }

          if (_app['fee_breakdown'] != null) {
            try {
              final rawBreakdown = _app['fee_breakdown'] is String
                  ? jsonDecode(_app['fee_breakdown'])
                  : _app['fee_breakdown'];
              if (rawBreakdown is List && rawBreakdown.isNotEmpty) {
                for (final c in _billItemControllers) {
                  c.dispose();
                }
                _billItemControllers.clear();
                for (final e in rawBreakdown) {
                  if (e is Map) {
                    _billItemControllers.add(_BillItemController(
                      label: e['label']?.toString() ?? '',
                      amount: e['amount'],
                    ));
                  }
                }
              }
            } catch (_) {}
          }
          if (_app['bill_title'] != null && _app['bill_title'].toString().trim().isNotEmpty) {
            _billTitleCtrl.text = _app['bill_title'].toString().trim();
          }
          if (_app['payment_deadline'] != null) {
            _paymentDeadline = DateTime.tryParse(_app['payment_deadline'].toString()) ?? _paymentDeadline;
          }
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_compliance_detail', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAndIssueBill() async {
    final validItems = _billItemControllers
        .map((c) => {'label': c.label.isEmpty ? 'Renewal fee' : c.label, 'amount': c.amount})
        .where((c) => (c['amount'] as double) > 0 || (c['label'] as String).isNotEmpty)
        .toList();

    if (validItems.isEmpty) {
      _showSnack('Please add at least one fee item with an amount.', color: _kRed);
      return;
    }
    if (_paymentDeadline == null) {
      _showSnack('Please select a payment deadline.', color: _kRed);
      return;
    }

    setState(() => _savingBill = true);
    try {
      final deadlineStr = "${_paymentDeadline!.year}-${_paymentDeadline!.month.toString().padLeft(2, '0')}-${_paymentDeadline!.day.toString().padLeft(2, '0')}";
      final billTitle = _billTitleCtrl.text.trim().isEmpty ? 'Annual renewal dues' : _billTitleCtrl.text.trim();
      final minAmt = double.tryParse(_minInstallmentCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      final res = await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/set-bill',
        data: {
          'bill_title': billTitle,
          'fee_breakdown': validItems,
          'payment_deadline': deadlineStr,
          'allow_installments': _allowInstallments,
          'min_installment_amount': minAmt,
        },
      );
      if (res.statusCode == 200) {
        _showSnack('Bill issued successfully!', color: _kGreen);
        _fetch();
      } else {
        _showSnack(res.data?['message'] ?? 'Failed to issue bill', color: _kRed);
      }
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _savingBill = false);
    }
  }

  Future<void> _updateDocStatus(Map<String, dynamic> doc, String status) async {
    final isBankSlip = doc['key'] == 'bank_deposit_slip' || doc['is_payment_receipt'] == true;
    final paymentId = doc['payment_id'] ?? _payment?['id'] ?? (doc['id'] is String ? int.tryParse((doc['id'] as String).replaceFirst('pay_', '')) : null);
    final rawDocId = doc['id'];
    final docId = rawDocId is int ? rawDocId : (rawDocId is num ? rawDocId.toInt() : null);

    if (docId == null && paymentId == null) return;

    String? note;
    if (status == 'rejected') {
      note = await _promptNote(context, 'Rejection note for "${doc['label']}"');
      if (note == null) return;
    }

    final prevDocStatus = doc['status'];
    final prevPayStatus = _payment?['status'];

    // Instant optimistic update
    setState(() {
      doc['status'] = status;
      if (isBankSlip && _payment != null) {
        _payment!['status'] = status == 'approved' ? 'paid' : 'rejected';
      }
    });

    try {
      if (isBankSlip && paymentId != null) {
        if (status == 'approved') {
          await ApiService().post('/payments/admin/mark-paid/$paymentId');
        } else {
          await ApiService().post('/payments/admin/reject/$paymentId', data: {'reason': note ?? ''});
        }
      }

      if (docId != null) {
        await ApiService().put(
          '/compliance/admin/applications/${widget.appId}/doc/$docId/status',
          data: {'status': status, 'note': note ?? ''},
        );
      }

      await ApiService.deleteCacheKeysMatching('compliance');
      _showSnack(
        status == 'approved'
            ? (isBankSlip ? 'Bank deposit payment approved & verified' : 'Document approved')
            : (isBankSlip ? 'Bank deposit payment rejected' : 'Document marked as rejected'),
        color: status == 'approved' ? _kGreen : _kRed,
      );
      _fetch();
    } catch (e) {
      // Revert if error
      setState(() {
        doc['status'] = prevDocStatus;
        if (isBankSlip && _payment != null) {
          _payment!['status'] = prevPayStatus;
        }
      });
      _showSnack('Error: $e', color: _kRed);
    }
  }

  Future<void> _approveAll() async {
    final isRenewal = _app['type']?.toString().toLowerCase() == 'renewal';
    final actionName = isRenewal ? 'Renewal' : 'Application';
    final note = await _promptNote(context, '$actionName approval note (optional)');
    if (!mounted) return;

    final prevStatus = _app['status'];
    final prevDocs = _docs.map((d) => Map<String, dynamic>.from(d as Map)).toList();

    // Instant optimistic update
    setState(() {
      _approving = true;
      _app['status'] = 'approved';
      for (var d in _docs) {
        if (d is Map) d['status'] = 'approved';
      }
    });

    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/approve',
        data: {'note': note ?? ''},
      );
      await ApiService.deleteCacheKeysMatching('compliance');
      await ApiService.deleteCacheKeysMatching('members');
      _showSnack('$actionName approved successfully!', color: _kGreen);
      _fetch();
    } catch (e) {
      setState(() {
        _app['status'] = prevStatus;
        _docs = prevDocs;
      });
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _rejectAll() async {
    final note = await _promptNote(context, 'Rejection reason (required)');
    if (note == null || note.isEmpty) return;
    if (!mounted) return;

    final prevStatus = _app['status'];
    setState(() {
      _rejecting = true;
      _app['status'] = 'rejected';
    });

    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/reject',
        data: {'note': note},
      );
      await ApiService.deleteCacheKeysMatching('compliance');
      _showSnack('Application rejected', color: _kRed);
      _fetch();
    } catch (e) {
      setState(() => _app['status'] = prevStatus);
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<void> _requestRevision() async {
    final note = await _promptNote(
      context,
      'Describe what the member needs to fix (required)',
    );
    if (note == null || note.isEmpty) return;
    if (!mounted) return;
    setState(() => _requestingRevision = true);
    try {
      await ApiService().post(
        '/compliance/admin/applications/${widget.appId}/request-revision',
        data: {'note': note},
      );
      _showSnack(
        'Revision requested. Member has been notified.',
        color: _kAmber,
      );
      _fetch();
    } catch (e) {
      _showSnack('Error: $e', color: _kRed);
    } finally {
      if (mounted) setState(() => _requestingRevision = false);
    }
  }

  Future<String?> _promptNote(BuildContext context, String hint) async {
    _noteCtrl.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AdminDialog(
        title: 'Add a note for the member',
        subtitle: 'They see it with your decision.',
        maxWidth: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, _noteCtrl.text.trim()), child: const Text('Continue')),
        ],
        children: [
          TextField(
            controller: _noteCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {Color color = _kDarkBg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showDocPreviewModal(BuildContext context, String title, String fileUrl) {
    final isImage =
        fileUrl.toLowerCase().contains('.png') ||
        fileUrl.toLowerCase().contains('.jpg') ||
        fileUrl.toLowerCase().contains('.jpeg') ||
        fileUrl.toLowerCase().contains('.webp') ||
        fileUrl.toLowerCase().contains('.gif');

    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: title,
        maxWidth: 900,
        actions: [
          TextButton.icon(
            onPressed: () async {
              final resolved = await ApiService.signedDocumentUrl(ApiService.resolveImageUrl(fileUrl));
              final uri = Uri.parse(resolved);
              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open in a new tab'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
        children: [
          Container(
            height: MediaQuery.sizeOf(ctx).height * 0.6,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: CubagColors.sand, borderRadius: BorderRadius.circular(CubagRadius.card)),
            child: isImage
                ? InteractiveViewer(
                    child: CorsImageWidget(
                      url: fileUrl,
                      fit: BoxFit.contain,
                      placeholder: const Center(child: CircularProgressIndicator()),
                      errorWidget: const Center(child: Text('Could not show this file. Use Open in a new tab.')),
                    ),
                  )
                : doc_preview.buildDocPreview(fileUrl, 'modal_${title.hashCode}'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeaderBar(bool isDark, String typeLabel, String status) {
    final name = _app['member_name']?.toString() ?? 'Applicant';
    final company = _app['member_company']?.toString() ?? '';
    final kind = switch (status) {
      'approved' || 'payment_confirmed' => StatusKind.good,
      'rejected' => StatusKind.bad,
      'draft' => StatusKind.neutral,
      _ => StatusKind.pending,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/admin/compliance');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('All applications'),
        ),
        const SizedBox(height: CubagSpace.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(company.isNotEmpty ? company : name, style: CubagType.display.copyWith(fontSize: 28)),
                  const SizedBox(height: CubagSpace.xxs),
                  Wrap(
                    spacing: CubagSpace.xs,
                    runSpacing: CubagSpace.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(_statusLabel(status), kind: kind),
                      Text(
                        [
                          typeLabel,
                          if (company.isNotEmpty) name,
                          '#COMP-${widget.appId.toString().padLeft(5, '0')}',
                        ].join(' · '),
                        style: CubagType.small,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _fetch,
            ),
          ],
        ),
      ],
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  Future<void> _confirmBankPayment(dynamic paymentId) async {
    final confirmed = await showAdminConfirm(context, title: 'Confirm this bank payment?', message: 'Only confirm after you have seen the money in the bank account. The payment is then marked as paid for this member.', confirmLabel: 'Confirm payment');

    if (confirmed != true) return;

    setState(() => _confirmingPayment = true);
    try {
      final res = await ApiService().post('/payments/admin/mark-paid/$paymentId');
      if (res.statusCode == 200) {
        _showSnack('Payment confirmed.', color: _kGreen);
        setState(() {
          if (_payment != null) {
            _payment!['status'] = 'paid';
          }
          for (var doc in _docs) {
            if (doc is Map<String, dynamic> &&
                (doc['key'] == 'bank_deposit_slip' || doc['is_payment_receipt'] == true)) {
              doc['status'] = 'approved';
            }
          }
        });
        await _fetch();
      } else {
        _showSnack(res.data?['message']?.toString() ?? 'Failed to confirm payment.', color: _kRed);
      }
    } catch (e, st) {
      AppLogger.error('admin_compliance_confirm_payment', e, st);
      _showSnack('Could not confirm the payment. Try again.', color: _kRed);
    } finally {
      if (mounted) setState(() => _confirmingPayment = false);
    }
  }

  Widget _buildPaymentProofSection(bool isDark) {
    final pay = _payment;
    final payRef = pay?['payment_ref']?.toString() ?? _app['payment_ref']?.toString() ?? '';
    final rawReceiptUrl = pay?['receipt_url']?.toString() ?? '';
    final hasReceipt = rawReceiptUrl.trim().isNotEmpty;
    final receiptUrl = hasReceipt ? _resolveUrl(rawReceiptUrl) : '';
    final amount = double.tryParse(pay?['amount']?.toString() ?? _app['payment_amount']?.toString() ?? '0') ?? 0.0;
    final bankName = pay?['bank_name']?.toString() ?? 'GCB Bank Limited';
    final accountNum = pay?['account_number']?.toString() ?? '';
    final notes = pay?['notes']?.toString();
    final paymentId = pay?['id'] ?? pay?['tx_id'];
    final payStatus = pay?['status']?.toString().toLowerCase() ?? (_app['status'] == 'payment_confirmed' ? 'paid' : 'pending');
    final isPaid = payStatus == 'paid' || payStatus == 'success' || payStatus == 'completed';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(
          color: isDark ? _kBorderDark : CubagColors.line,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPaid ? CubagColors.validTint : CubagColors.sand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: isPaid ? _kGreen : _kPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank slip and payment proof',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _kTextDark,
                      ),
                    ),
                    Text(
                      'Direct bank wire / branch deposit submitted by applicant',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : CubagColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPaid ? _kGreen : _kAmber).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isPaid ? _kGreen : _kAmber).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                      size: 13,
                      color: isPaid ? _kGreen : _kAmber,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPaid ? 'Payment confirmed' : 'Waiting for you to confirm',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isPaid ? _kGreen : _kAmber,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Content body: receipt thumbnail + details
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Receipt Slip Preview
                  if (hasReceipt) ...[
                    GestureDetector(
                      onTap: () => _showDocPreviewModal(
                        context,
                        'Bank slip · $payRef',
                        receiptUrl,
                      ),
                      child: Container(
                        width: isNarrow ? double.infinity : 170,
                        height: isNarrow ? 200 : 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? _kBorderDark : CubagColors.line,
                            width: 1.5,
                          ),
                          color: isDark ? CubagColors.ink : CubagColors.sand,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CorsImageWidget(
                              url: receiptUrl,
                              fit: BoxFit.cover,
                              placeholder: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                              ),
                              errorWidget: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.broken_image_rounded, color: CubagColors.muted, size: 28),
                                    const SizedBox(height: 4),
                                    Text('Receipt file', style: TextStyle(fontSize: 11, color: CubagColors.muted)),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Click to View',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 16 : 0),
                  ],

                  // Details
                  Expanded(
                    flex: isNarrow ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Amount deposited',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? Colors.white60 : CubagColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'GH₵ ${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isPaid ? _kGreen : _kPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildPaymentDetailRow('Payment reference', payRef, isDark),
                        _buildPaymentDetailRow('Paid into', bankName, isDark),
                        if (accountNum.isNotEmpty)
                          _buildPaymentDetailRow('Account number', accountNum, isDark),
                        if (notes != null && notes.isNotEmpty)
                          _buildPaymentDetailRow('Note from the member', notes, isDark),
                        if (pay?['date'] != null || _app['created_at'] != null)
                          _buildPaymentDetailRow('Sent on', _fmt(pay?['date']?.toString() ?? _app['created_at']?.toString()), isDark),

                        const SizedBox(height: 14),

                        // Admin Action Buttons
                        if (!isPaid && paymentId != null)
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _confirmingPayment ? null : () => _confirmBankPayment(paymentId),
                                icon: _confirmingPayment
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_circle_rounded, size: 18),
                                label: Text(
                                  _confirmingPayment ? 'Confirming...' : 'Verify & Confirm Payment',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                              if (hasReceipt)
                                OutlinedButton.icon(
                                  onPressed: () => _showDocPreviewModal(
                                    context,
                                    'Bank slip · $payRef',
                                    receiptUrl,
                                  ),
                                  icon: const Icon(Icons.visibility_rounded, size: 16),
                                  label: Text(
                                    'View slip',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                            ],
                          )
                        else if (isPaid)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded, color: _kGreen, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Payment confirmed and recorded',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _kGreen,
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : CubagColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : _kTextDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection(bool isDark, bool isResolved) {
    final uploadedCount = _docs.where((d) => d['uploaded'] == true).length;
    final totalCount = _docs.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_shared_rounded, color: CubagColors.cocoa, size: 20),
              const SizedBox(width: 8),
              Text(
                'Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _kTextDark,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? CubagColors.ink : CubagColors.sand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$uploadedCount of $totalCount uploaded',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : CubagColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (_docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No statutory documents required for this profile.',
                  style: TextStyle(color: CubagColors.muted, fontSize: 13.5),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final d = _docs[i] as Map<String, dynamic>;
                return _AdminDocRow(
                  doc: d,
                  isDark: isDark,
                  isResolved: isResolved,
                  onApprove: () => _updateDocStatus(d, 'approved'),
                  onReject: () => _updateDocStatus(d, 'rejected'),
                  onPreview: (title, url) => _showDocPreviewModal(context, title, url),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBillGenerationSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: CubagColors.cocoa, size: 20),
              const SizedBox(width: 8),
              Text(
                'Renewal bill',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _kTextDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Configure the fee breakdown and payment deadline for this member renewal.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : CubagColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _billTitleCtrl,
            decoration: InputDecoration(
              labelText: 'Bill title',
              hintText: 'e.g. Annual Renewal Dues',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),

          ..._billItemControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: item.labelCtrl,
                      decoration: InputDecoration(
                        labelText: 'Fee',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Amount (GHS)',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                  if (_billItemControllers.length > 1)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 18),
                      onPressed: () => setState(() {
                        final removed = _billItemControllers.removeAt(idx);
                        removed.dispose();
                      }),
                    ),
                ],
              ),
            );
          }),

          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _billItemControllers.add(_BillItemController(label: '', amount: ''))),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add a fee'),
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Deadline: ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : CubagColors.inkSoft,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _paymentDeadline ?? DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _paymentDeadline = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 14, color: _kPrimary),
                          const SizedBox(width: 4),
                          Text(
                            _paymentDeadline != null
                                ? "${_paymentDeadline!.year}-${_paymentDeadline!.month.toString().padLeft(2, '0')}-${_paymentDeadline!.day.toString().padLeft(2, '0')}"
                                : 'Pick a date',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Part-Payment / Installment Option ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? CubagColors.ink : CubagColors.sand,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: _allowInstallments ? _kGreen : CubagColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Allow payment in parts',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : _kTextDark,
                            ),
                          ),
                          Text(
                            'Allow member to pay bill in installments with balance tracking',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white60 : CubagColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _allowInstallments,
                      activeThumbColor: _kGreen,
                      onChanged: (val) => setState(() => _allowInstallments = val),
                    ),
                  ],
                ),
                if (_allowInstallments) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _minInstallmentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Smallest first payment (GH₵)',
                      hintText: '0.00 for no minimum',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.money_rounded, size: 16),
                    ),
                    style: TextStyle(fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: GH₵ ${_calculatedTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kPrimary),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _savingBill ? null : _saveAndIssueBill,
                icon: _savingBill
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 15),
                label: Text(
                  _savingBill ? 'Saving...' : 'Save & Issue Bill',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentsLedgerSection(bool isDark) {
    final double totalBilled = double.tryParse(_app['payment_amount']?.toString() ?? '0') ?? 0.0;
    final double totalPaid = double.tryParse(_app['amount_paid']?.toString() ?? '0') ?? 0.0;
    final double balanceDue = totalBilled > totalPaid ? (totalBilled - totalPaid) : 0.0;
    final double progress = totalBilled > 0 ? (totalPaid / totalBilled).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CubagColors.sand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: CubagColors.cocoa, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payments received',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _kTextDark,
                      ),
                    ),
                    Text(
                      'Summary of bill settlement and received installments',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : CubagColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (balanceDue <= 0.01 && totalBilled > 0 ? _kGreen : CubagColors.due).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  balanceDue <= 0.01 && totalBilled > 0 ? 'SETTLED' : 'GHS ${balanceDue.toStringAsFixed(2)} DUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: balanceDue <= 0.01 && totalBilled > 0 ? _kGreen : CubagColors.due,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Financial Highlights ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? CubagColors.ink : CubagColors.sand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total billed', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: CubagColors.muted)),
                      const SizedBox(height: 2),
                      Text('GHS ${totalBilled.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total paid', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _kGreen)),
                      const SizedBox(height: 2),
                      Text('GHS ${totalPaid.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kGreen)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (balanceDue > 0 ? CubagColors.due : _kGreen).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Balance due', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: balanceDue > 0 ? CubagColors.due : _kGreen)),
                      const SizedBox(height: 2),
                      Text('GHS ${balanceDue.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: balanceDue > 0 ? CubagColors.due : _kGreen)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Progress Bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? CubagColors.inkSoft : CubagColors.line,
              valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? _kGreen : _kPrimary),
            ),
          ),
          const SizedBox(height: 16),

          // ── Installments Transaction List ──
          if (_installments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'No payments recorded yet for this bill.',
                  style: TextStyle(fontSize: 13, color: CubagColors.muted),
                ),
              ),
            )
          else ...[
            Text(
              'Payments recorded (${_installments.length})',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark),
            ),
            const SizedBox(height: 8),
            ..._installments.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final p = Map<String, dynamic>.from(entry.value is Map ? entry.value : {});
              final pAmt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
              final pStatus = p['status']?.toString().toLowerCase() ?? 'pending';
              final isPConfirmed = pStatus == 'paid' || pStatus == 'completed' || pStatus == 'success';
              final pMethod = (p['payment_method']?.toString() ?? 'momo').toUpperCase();
              final pDate = p['date']?.toString().split('T').first ?? p['created_at']?.toString().split('T').first ?? '';
              final pRef = p['payment_ref']?.toString() ?? p['ref_code']?.toString() ?? '—';
              final rawReceipt = p['receipt_url']?.toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? CubagColors.ink : CubagColors.sand,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: (isPConfirmed ? _kGreen : _kAmber).withValues(alpha: 0.15),
                      child: Text(
                        '#$idx',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isPConfirmed ? _kGreen : _kAmber),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'GHS ${pAmt.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _kTextDark),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isPConfirmed ? _kGreen : _kAmber).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isPConfirmed ? 'CONFIRMED' : 'PENDING',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: isPConfirmed ? _kGreen : _kAmber),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$pMethod • $pDate • Ref: $pRef',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : CubagColors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (rawReceipt != null && rawReceipt.trim().isNotEmpty)
                      IconButton(
                        tooltip: 'View receipt',
                        icon: const Icon(Icons.receipt_rounded, size: 20, color: _kPrimary),
                        onPressed: () async {
                          final resolved = await ApiService.signedDocumentUrl(ApiService.resolveImageUrl(rawReceipt));
                          final uri = Uri.parse(resolved);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDecisionSection(bool isDark, bool isResolved) {
    final bool isRenewal = _app['type']?.toString().toLowerCase() == 'renewal';
    final bool allDocsApproved = _docs.isNotEmpty && _docs.every((d) => d['status'] == 'approved');
    final String approveBtnLabel = allDocsApproved
        ? (isRenewal ? 'Approve renewal' : 'Approve application')
        : (isRenewal ? 'Approve documents and renewal' : 'Approve all documents');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _kCardDark : Colors.white,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: isDark ? _kBorderDark : CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decision',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : _kTextDark,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                icon: _requestingRevision
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Ask for changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAmber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _requestingRevision ? null : _requestRevision,
              ),
              ElevatedButton.icon(
                icon: _approving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_rounded, size: 16),
                label: Text(approveBtnLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (_approving || isResolved) ? null : _approveAll,
              ),
              OutlinedButton.icon(
                icon: _rejecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))
                    : const Icon(Icons.cancel_rounded, size: 16),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kRed,
                  side: const BorderSide(color: _kRed),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (_rejecting || isResolved) ? null : _rejectAll,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _app['status']?.toString() ?? '';
    final memberName = _app['member_name']?.toString() ?? 'Applicant';
    final memberCompany = _app['member_company']?.toString() ?? '';
    final appType = _app['type']?.toString() ?? '';
    final typeLabel = appType == 'renewal' ? 'Membership renewal' : 'Member ID application';
    final isResolved = status == 'approved' || status == 'rejected';
    final hasPayment = _payment != null || (_app['payment_ref'] != null && _app['payment_ref'].toString().isNotEmpty);
    final showLedger = _app['type'] == 'renewal' &&
        (_installments.isNotEmpty || _app['amount_paid'] != null || status == 'partially_paid');
    final canDecide = !isResolved &&
        const [
          'under_review',
          'payment_confirmed',
          'submitted',
          'revision_requested',
          'awaiting_bill',
          'awaiting_payment',
          'partially_paid',
        ].contains(status);
    final note = _app['admin_note']?.toString().trim() ?? '';

    const gap = SizedBox(height: CubagSpace.lg);
    // Work (documents, bill) on the left; who, money and the decision on the right.
    final work = <Widget>[
      _buildDocumentsSection(isDark, isResolved),
      gap,
      _buildBillGenerationSection(isDark),
      if (showLedger) ...[gap, _buildInstallmentsLedgerSection(isDark)],
    ];
    final side = <Widget>[
      _MemberInfoCard(app: _app, isDark: isDark, showPayment: !hasPayment),
      if (note.isNotEmpty) ...[gap, _AdminStatusBanner(status: status, note: note)],
      if (hasPayment) ...[gap, _buildPaymentProofSection(isDark)],
      if (canDecide) ...[gap, _buildDecisionSection(isDark, isResolved)],
    ];

    return AppLayout(
      title: memberCompany.isNotEmpty ? memberCompany : memberName,
      scrollable: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: _loading
              ? Column(
                  children: List.generate(
                    4,
                    (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerListTile()),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopHeaderBar(isDark, typeLabel, status),
                    const SizedBox(height: CubagSpace.lg),
                    LayoutBuilder(
                      builder: (context, c) {
                        if (c.maxWidth < 980) {
                          // One column: decide last, after the work is checked.
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MemberInfoCard(app: _app, isDark: isDark, showPayment: !hasPayment),
                              if (note.isNotEmpty) ...[gap, _AdminStatusBanner(status: status, note: note)],
                              if (hasPayment) ...[gap, _buildPaymentProofSection(isDark)],
                              gap,
                              ...work,
                              if (canDecide) ...[gap, _buildDecisionSection(isDark, isResolved)],
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: work)),
                            const SizedBox(width: CubagSpace.lg),
                            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: CubagSpace.xxl),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MemberInfoCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final bool isDark;
  final bool showPayment;
  const _MemberInfoCard({required this.app, required this.isDark, this.showPayment = true});

  @override
  Widget build(BuildContext context) {
    String v(String k) => app[k]?.toString() ?? '';
    final name = v('member_name').isEmpty ? 'Applicant' : v('member_name');
    final company = v('member_company');
    final c = v('category');
    final category = c.isEmpty ? '' : '${c[0].toUpperCase()}${c.substring(1).toLowerCase()} member';
    final status = v('status').toLowerCase();
    final isPaid = app['payment_confirmed_at'] != null || status == 'payment_confirmed' || status == 'approved';
    final sent = !isPaid && (v('payment_ref').isNotEmpty || status == 'payment_submitted');
    final amount = v('payment_amount');
    final payment = isPaid
        ? (amount.isEmpty ? 'Paid' : 'Paid, GH₵ $amount')
        : (sent ? (amount.isEmpty ? 'Sent, waiting for you to confirm' : 'GH₵ $amount sent, waiting for you to confirm') : 'Not paid yet');

    return Container(
      padding: const EdgeInsets.all(CubagSpace.lg),
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AdminRowMark(initials: adminInitials(company.isNotEmpty ? company : name)),
              const SizedBox(width: CubagSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: CubagType.bodyStrong),
                    if (category.isNotEmpty) Text(category, style: CubagType.small),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CubagSpace.sm),
          const Divider(height: 1, color: CubagColors.line),
          const SizedBox(height: CubagSpace.xs),
          AdminDetailRow('Email', v('member_email')),
          AdminDetailRow('Phone', v('member_phone')),
          AdminDetailRow('Sent in', _fmt(v('created_at'))),
          if (showPayment) ...[
            AdminDetailRow('Payment', payment),
            if (v('payment_ref').isNotEmpty) AdminDetailRow('Payment reference', v('payment_ref')),
          ],
        ],
      ),
    );
  }
}

class _AdminStatusBanner extends StatelessWidget {
  final String status;
  final String? note;
  const _AdminStatusBanner({required this.status, this.note});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Status: ${_statusLabel(status)}${note != null && note!.isNotEmpty ? ' — $note' : ''}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDocRow extends StatefulWidget {
  final Map<String, dynamic> doc;
  final bool isDark, isResolved;
  final VoidCallback onApprove, onReject;
  final Function(String title, String url) onPreview;

  const _AdminDocRow({
    required this.doc,
    required this.isDark,
    required this.isResolved,
    required this.onApprove,
    required this.onReject,
    required this.onPreview,
  });

  @override
  State<_AdminDocRow> createState() => _AdminDocRowState();
}

class _AdminDocRowState extends State<_AdminDocRow> {
  bool _showInlinePreview = false;

  @override
  Widget build(BuildContext context) {
    final uploaded = widget.doc['uploaded'] == true;
    final autoFilled = widget.doc['auto_filled'] == true;
    final status = widget.doc['status']?.toString() ?? 'not_uploaded';
    final label = widget.doc['label']?.toString() ?? 'Document';
    final fileUrl = widget.doc['file_url']?.toString();
    final fileName = widget.doc['file_name']?.toString() ?? 'Document.pdf';
    final adminNote = widget.doc['admin_note']?.toString();

    final isImage =
        fileUrl != null &&
        (fileUrl.toLowerCase().contains('.png') ||
            fileUrl.toLowerCase().contains('.jpg') ||
            fileUrl.toLowerCase().contains('.jpeg') ||
            fileUrl.toLowerCase().contains('.webp') ||
            fileUrl.toLowerCase().contains('.gif'));

    Color sColor = CubagColors.muted;
    IconData sIcon = Icons.radio_button_unchecked;
    if (!uploaded) {
      sColor = CubagColors.muted;
      sIcon = Icons.radio_button_unchecked;
    } else if (status == 'approved') {
      sColor = _kGreen;
      sIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      sColor = _kRed;
      sIcon = Icons.cancel_rounded;
    } else if (autoFilled) {
      sColor = _kAmber;
      sIcon = Icons.auto_fix_high_rounded;
    } else {
      sColor = _kAmber;
      sIcon = Icons.hourglass_empty_rounded;
    }

    final docKey = 'compliance_doc_${widget.doc['id'] ?? label.hashCode}';
    final isBankReceipt = widget.doc['is_payment_receipt'] == true || widget.doc['key'] == 'bank_deposit_slip';
    final paymentRef = widget.doc['payment_ref']?.toString();
    final paymentAmount = widget.doc['amount'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1410) : CubagColors.sand,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: uploaded
              ? sColor.withValues(alpha: 0.25)
              : (widget.isDark ? _kBorderDark : CubagColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isBankReceipt ? Icons.account_balance_rounded : sIcon, color: isBankReceipt ? CubagColors.cocoa : sColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: widget.isDark ? Colors.white : _kTextDark,
                  ),
                ),
              ),
              if (isBankReceipt)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: CubagColors.cocoa.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CubagColors.cocoa.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 11, color: CubagColors.cocoa),
                      const SizedBox(width: 4),
                      Text(
                        'Payment Slip',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: CubagColors.cocoa,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (autoFilled)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Auto-filled',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          if (isBankReceipt && (paymentRef != null || paymentAmount != null)) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF132321) : const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: CubagColors.cocoa.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (paymentRef != null)
                    Text(
                      'Ref: $paymentRef',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: CubagColors.cocoa),
                    ),
                  if (paymentRef != null && paymentAmount != null)
                    Text('  •  ', style: TextStyle(fontSize: 11.5, color: CubagColors.muted)),
                  if (paymentAmount != null)
                    Text(
                      'GHS ${(paymentAmount as num).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kGreen),
                    ),
                ],
              ),
            ),
          ],

          if (fileUrl != null && fileUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'File: $fileName',
                    style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white60 : CubagColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showInlinePreview = !_showInlinePreview),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(_showInlinePreview ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 13, color: _kPrimary),
                        const SizedBox(width: 4),
                        Text(
                          _showInlinePreview ? 'Hide' : 'Preview',
                          style: TextStyle(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => widget.onPreview(label, fileUrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.fullscreen_rounded, size: 13, color: CubagColors.muted),
                        const SizedBox(width: 4),
                        Text(
                          'Full View',
                          style: TextStyle(fontSize: 12, color: CubagColors.muted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(button: true, label: 'Open document', child: InkWell(
                  onTap: () async {
                    final resolved = await ApiService.signedDocumentUrl(ApiService.resolveImageUrl(fileUrl));
                    final uri = Uri.parse(resolved);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.open_in_new_rounded, size: 13, color: CubagColors.muted),
                  ),
                )),
              ],
            ),

            if (_showInlinePreview) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: isImage ? 280 : 380,
                decoration: BoxDecoration(
                  color: widget.isDark ? _kDarkBg : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.isDark ? _kBorderDark : CubagColors.lineStrong),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: isImage
                      ? InteractiveViewer(
                          child: CorsImageWidget(
                            url: fileUrl,
                            fit: BoxFit.contain,
                            placeholder: const Center(
                              child: CircularProgressIndicator(color: _kPrimary),
                            ),
                            errorWidget: const Center(
                              child: Text('Could not show this file. Use Open in a new tab.'),
                            ),
                          ),
                        )
                      : doc_preview.buildDocPreview(fileUrl, docKey),
                ),
              ),
            ],
          ],

          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Note: $adminNote',
                style: TextStyle(fontSize: 11.5, color: _kRed),
              ),
            ),
          ],

          if (uploaded && !widget.isResolved) ...[
            const SizedBox(height: 8),
            if (status == 'approved')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded, size: 13, color: _kGreen),
                    const SizedBox(width: 4),
                    Text('Approved', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kGreen)),
                  ],
                ),
              )
            else
              Row(
                children: [
                  _DocAction(
                    label: 'Approve',
                    color: _kGreen,
                    icon: Icons.check_rounded,
                    onTap: widget.onApprove,
                  ),
                  const SizedBox(width: 8),
                  if (status != 'rejected')
                    _DocAction(
                      label: 'Reject',
                      color: _kRed,
                      icon: Icons.close_rounded,
                      onTap: widget.onReject,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _DocAction extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _DocAction({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}
