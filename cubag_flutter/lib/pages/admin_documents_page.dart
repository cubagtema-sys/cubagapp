import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';
import '../components/cubag_ui.dart';
import '../components/doc_preview_stub.dart'
    if (dart.library.html) '../components/doc_preview_web.dart'
    as doc_preview;

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;
const _kAmber = CubagColors.due;
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kSlate = CubagColors.ink;

// ─────────────────────────────────────────────────────────────────────────────
// 1. APPLICATION DOSSIERS DIRECTORY (LIST PAGE)
// ─────────────────────────────────────────────────────────────────────────────
class AdminDocumentsPage extends StatefulWidget {
  const AdminDocumentsPage({super.key});
  @override
  State<AdminDocumentsPage> createState() => _AdminDocumentsPageState();
}

class _AdminDocumentsPageState extends State<AdminDocumentsPage> {
  bool _loading = true;
  List<dynamic> _members = [];
  String _search = '';
  String _filter = 'pending_review'; // open on the work waiting
  final String _selectedCategory = 'corporate';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
    SocketService().on('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().on('member_documents_updated', _onRulesUpdatedSocket);
    SocketService().on('documents_updated', _onRulesUpdatedSocket);
    SocketService().on('member_updated', _onRulesUpdatedSocket);
    SocketService().on('member_approved', _onRulesUpdatedSocket);
    SocketService().on('compliance_updated', _onRulesUpdatedSocket);
  }

  void _onRulesUpdatedSocket(dynamic data) {
    if (!mounted) return;
    if (data is Map && data['member_id'] != null) {
      final mid = data['member_id'].toString();
      final status = data['status']?.toString();
      setState(() {
        for (var m in _members) {
          if (m['id'].toString() == mid) {
            if (status == 'approved' || status == 'active') {
              final total = (m['total_required'] as num?)?.toInt() ?? 0;
              m['docs_approved'] = total > 0 ? total : ((m['docs_approved'] as num?)?.toInt() ?? 0) + 1;
              m['status'] = status;
            }
          }
        }
      });
    }
    ApiService.deleteCacheKeysMatching('documents/admin');
    _fetch(forceRefresh: true);
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _search = v);
      }
    });
  }

  @override
  void dispose() {
    SocketService().off('document_rules_updated', _onRulesUpdatedSocket);
    SocketService().off('member_documents_updated', _onRulesUpdatedSocket);
    SocketService().off('documents_updated', _onRulesUpdatedSocket);
    SocketService().off('member_updated', _onRulesUpdatedSocket);
    SocketService().off('member_approved', _onRulesUpdatedSocket);
    SocketService().off('compliance_updated', _onRulesUpdatedSocket);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await ApiService.deleteCacheKeysMatching('documents/admin');
    }
    if (_members.isEmpty) setState(() => _loading = true);
    try {
      final res = await ApiService().get('/documents/admin/pending?status=all');
      if (mounted && res.statusCode == 200 && res.data is Map) {
        setState(() {
          _members = res.data['members'] ?? [];
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _getAllMembers() {
    return _members
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getMembersForCategory(String category) {
    return _getAllMembers();
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _getMembersForCategory(_selectedCategory);

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) {
        final name = (m['name'] as String? ?? '').toLowerCase();
        final comp = (m['company'] as String? ?? '').toLowerCase();
        final memNo = (m['membership_number'] as String? ?? '').toLowerCase();
        final email = (m['email'] as String? ?? '').toLowerCase();
        return name.contains(q) || comp.contains(q) || memNo.contains(q) || email.contains(q);
      }).toList();
    }

    if (_filter == 'sme') {
      list = list
          .where((m) => (m['member_scale'] as String? ?? '') == 'sme')
          .toList();
    } else if (_filter == 'large_corporate') {
      list = list
          .where((m) => (m['member_scale'] as String? ?? '') == 'large_corporate')
          .toList();
    } else if (_filter == 'incomplete') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return totalReq > 0 && up < totalReq;
      }).toList();
    } else if (_filter == 'pending_review') {
      list = list.where((m) {
        final up = (m['docs_uploaded'] as num?)?.toInt() ?? 0;
        final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return totalReq > 0 && up >= totalReq && ap < totalReq;
      }).toList();
    } else if (_filter == 'fully_approved') {
      list = list.where((m) {
        final ap = (m['docs_approved'] as num?)?.toInt() ?? 0;
        final totalReq = (m['total_required'] as num?)?.toInt() ?? 0;
        return (totalReq > 0 && ap >= totalReq) || totalReq == 0;
      }).toList();
    }

    return list;
  }

  // ── Layout ────────────────────────────────────────────────────────────────
  // Opens on the applicants whose documents are all in and waiting for a
  // decision. Each applicant is one row: who, how far along, what to do.

  int _num(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  /// Label and kind for an applicant's documents.
  (String, StatusKind) _stateOf(Map<String, dynamic> m) {
    final up = _num(m, 'docs_uploaded');
    final ap = _num(m, 'docs_approved');
    final req = _num(m, 'total_required');
    if ((m['status'] as String?) == 'active') return ('Active member', StatusKind.good);
    if (req == 0) return ('No documents needed', StatusKind.good);
    if (ap >= req) return ('Approved', StatusKind.good);
    if (up >= req) return ('To review', StatusKind.pending);
    return ('Incomplete', StatusKind.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final all = _getAllMembers();
    int count(String f) {
      final saved = _filter;
      _filter = f;
      final n = _filtered.length;
      _filter = saved;
      return n;
    }

    final counts = {
      'pending_review': count('pending_review'),
      'incomplete': count('incomplete'),
      'fully_approved': count('fully_approved'),
      'all': all.length,
    };
    final list = _filtered;
    // Side-by-side rows need room beside the admin sidebar.
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return AppLayout(
      title: 'Applications',
      scrollable: true,
      background: CubagColors.sand,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: EdgeInsets.all(wide ? CubagSpace.xl : CubagSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: CubagSpace.md,
                  runSpacing: CubagSpace.md,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: const PageIntro(
                        'Applications',
                        subtitle: 'Check each applicant\'s documents, then approve or ask for changes.',
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: () => _fetch(forceRefresh: true),
                          icon: const Icon(Icons.refresh_rounded, color: CubagColors.inkSoft),
                        ),
                        const SizedBox(width: CubagSpace.xs),
                        OutlinedButton(
                          onPressed: () =>
                              context.push('/admin/document-rules').then((_) => _fetch(forceRefresh: true)),
                          child: const Text('Requirements'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CubagSpace.lg),
                _toolbar(counts, wide),
                const SizedBox(height: CubagSpace.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator(color: CubagColors.action)),
                  )
                else if (list.isEmpty)
                  _empty()
                else
                  Container(
                    decoration: BoxDecoration(
                      color: CubagColors.paper,
                      borderRadius: BorderRadius.circular(CubagRadius.card),
                      border: Border.all(color: CubagColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: CubagColors.line),
                          _row(list[i], wide),
                        ],
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

  Widget _toolbar(Map<String, int> counts, bool wide) {
    const labels = {
      'pending_review': 'To review',
      'incomplete': 'Incomplete',
      'fully_approved': 'Approved',
      'all': 'All',
    };
    final tabs = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final e in labels.entries)
          ButtonSegment(value: e.key, label: Text('${e.value} ${counts[e.key] ?? 0}')),
      ],
      selected: {labels.containsKey(_filter) ? _filter : 'all'},
      onSelectionChanged: (s) => setState(() => _filter = s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? CubagColors.ink : CubagColors.paper,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Colors.white : CubagColors.inkSoft,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: CubagColors.line)),
      ),
    );
    final search = TextField(
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search name, company, TIN or member ID',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        filled: true,
        fillColor: CubagColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubagRadius.control),
          borderSide: const BorderSide(color: CubagColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubagRadius.control),
          borderSide: const BorderSide(color: CubagColors.line),
        ),
      ),
    );
    if (wide) {
      return Row(children: [tabs, const SizedBox(width: CubagSpace.md), Expanded(child: search)]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
        const SizedBox(height: CubagSpace.sm),
        search,
      ],
    );
  }

  Widget _empty() {
    final (title, body) = switch (_filter) {
      'pending_review' => ('Nothing to review', 'Applicants appear here once all their documents are uploaded.'),
      'incomplete' => ('No incomplete applications', 'Everyone has uploaded what they need.'),
      'fully_approved' => ('No approved applications yet', 'Applicants appear here once you approve them.'),
      _ => ('No applicants found', 'Try a different search.'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: CubagSpace.lg),
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.task_alt_rounded, size: 36, color: CubagColors.muted),
          const SizedBox(height: CubagSpace.sm),
          Text(title, style: CubagType.bodyStrong),
          const SizedBox(height: 4),
          Text(body, style: CubagType.small, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> m, bool wide) {
    final name = ((m['name'] as String?) ?? 'Applicant').trim();
    final company = ((m['company'] as String?) ?? '').trim();
    final memNo = ((m['membership_number'] as String?) ?? '').trim();
    final port = ((m['port_of_operation'] as String?) ?? '').trim();
    final scale = (m['member_scale'] as String? ?? 'sme') == 'large_corporate' ? 'Large corporate' : 'SME';
    final up = _num(m, 'docs_uploaded');
    final ap = _num(m, 'docs_approved');
    final req = _num(m, 'total_required');
    final (label, kind) = _stateOf(m);
    final progress = req == 0 ? 1.0 : (up / req).clamp(0.0, 1.0);

    Future<void> open() async {
      await context.push('/admin/documents/${m['id']}');
      _fetch(forceRefresh: true);
    }

    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(company.isEmpty ? name : company, style: CubagType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          [
            if (company.isNotEmpty) name,
            scale,
            if (port.isNotEmpty) port,
            if (memNo.isNotEmpty && !memNo.toUpperCase().contains('PENDING')) memNo,
          ].join(' · '),
          style: CubagType.small,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final docs = SizedBox(
      width: wide ? 180 : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            req == 0 ? 'No documents needed' : '$up of $req uploaded${ap > 0 ? ', $ap approved' : ''}',
            style: CubagType.caption,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: CubagColors.sand,
              color: ap >= req && req > 0 ? CubagColors.valid : CubagColors.cocoa,
            ),
          ),
        ],
      ),
    );

    final action = kind == StatusKind.pending
        ? FilledButton(onPressed: open, child: const Text('Review'))
        : OutlinedButton(onPressed: open, child: const Text('Open'));

    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.all(CubagSpace.md),
        child: wide
            ? Row(
                children: [
                  Expanded(child: who),
                  const SizedBox(width: CubagSpace.md),
                  docs,
                  const SizedBox(width: CubagSpace.lg),
                  SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: StatusChip(label, kind: kind))),
                  action,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: who), const SizedBox(width: CubagSpace.sm), StatusChip(label, kind: kind)],
                  ),
                  const SizedBox(height: CubagSpace.sm),
                  docs,
                  const SizedBox(height: CubagSpace.sm),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REVIEW APPLICANT DOSSIER PAGE (FULL VIEW FOR AN APPLICANT)
// ─────────────────────────────────────────────────────────────────────────────
class ReviewApplicantPage extends StatefulWidget {
  final int memberId;
  const ReviewApplicantPage({super.key, required this.memberId});

  @override
  State<ReviewApplicantPage> createState() => _ReviewApplicantPageState();
}

class _ReviewApplicantPageState extends State<ReviewApplicantPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _hasError = false;
  Map<String, dynamic> _member = {};
  List<dynamic> _docs = [];
  late TabController _tab;
  final Map<int, bool> _actionLoading = {};
  final Map<String, TextEditingController> _noteCtrl = {};
  bool _approvingAll = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _fetch();
    SocketService().socket?.on('member_documents_updated', _onMemberDocsUpdatedSocket);
  }

  void _onMemberDocsUpdatedSocket(dynamic data) {
    if (mounted) {
      if (data is Map && data['member_id'] != null) {
        if (data['member_id'].toString() == widget.memberId.toString()) {
          _fetch(forceRefresh: true);
        }
      } else {
        _fetch(forceRefresh: true);
      }
    }
  }

  @override
  void dispose() {
    SocketService().socket?.off('member_documents_updated', _onMemberDocsUpdatedSocket);
    for (final c in _noteCtrl.values) {
      c.dispose();
    }
    _tab.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      if (forceRefresh) {
        await ApiService.deleteCacheKeysMatching('documents/admin/member/${widget.memberId}');
      }
      final res = await ApiService().get('/documents/admin/member/${widget.memberId}');
      if (mounted && res.statusCode == 200 && res.data != null) {
        final d = res.data is Map ? res.data : {};
        setState(() {
          _member = Map<String, dynamic>.from(d['member'] as Map? ?? {});
          _docs = d['documents'] is List ? d['documents'] : [];
          _loading = false;
          _hasError = false;
        });
        return;
      }
    } catch (e, st) {
      AppLogger.error('admin_documents_page', e, st);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (_docs.isEmpty) _hasError = true;
      });
    }
  }

  Future<void> _setStatus(int docId, String status, String reqKey) async {
    final note = _noteCtrl[reqKey]?.text.trim() ?? '';
    final prevDocs = _docs.map((d) => Map<String, dynamic>.from(d as Map)).toList();

    // Instant optimistic update
    setState(() {
      _actionLoading[docId] = true;
      for (var d in _docs) {
        if (d is Map && d['id'] == docId) {
          d['status'] = status;
          if (note.isNotEmpty) d['admin_note'] = note;
        }
      }
    });

    try {
      final res = await ApiService().post(
        '/documents/admin/review/$docId',
        data: {'status': status, 'admin_note': note},
      );
      if (mounted) {
        _snack(
          status == 'approved'
              ? 'Certificate approved successfully'
              : 'Certificate marked as rejected with feedback',
          status == 'approved' ? _kGreen : _kRed,
        );
        if (res.statusCode == 200) {
          await ApiService.deleteCacheKeysMatching('documents/admin');
          _fetch(forceRefresh: true);
        } else {
          // Revert if server failed
          setState(() => _docs = prevDocs);
        }
      }
    } catch (_) {
      if (mounted) {
        _snack('Network error updating document status', _kRed);
        setState(() => _docs = prevDocs);
      }
    }
    if (mounted) setState(() => _actionLoading[docId] = false);
  }

  Future<void> _showDocPreviewModal(
    BuildContext context,
    String title,
    String fileUrl,
  ) async {
    final cleanUrl = await ApiService.signedDocumentUrl(ApiService.resolveImageUrl(fileUrl));
    if (!context.mounted) return;
    final isImage =
        cleanUrl.toLowerCase().contains('.png') ||
        cleanUrl.toLowerCase().contains('.jpg') ||
        cleanUrl.toLowerCase().contains('.jpeg') ||
        cleanUrl.toLowerCase().contains('.webp') ||
        cleanUrl.toLowerCase().contains('.gif');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 900,
          height: 680,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () async {
                      final uri = Uri.tryParse(cleanUrl);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    tooltip: 'Open in new tab',
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: isImage
                    ? InteractiveViewer(
                        child: CorsImageWidget(
                          url: cleanUrl,
                          fit: BoxFit.contain,
                          placeholder: const Center(
                            child: CircularProgressIndicator(color: _kOrange),
                          ),
                          errorWidget: const Center(
                            child: Text('Failed to load image preview.'),
                          ),
                        ),
                      )
                    : doc_preview.buildDocPreview(
                        cleanUrl,
                        'modal_${title.hashCode}_${cleanUrl.hashCode}',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: _kGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verify & Approve Documents',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'This will approve all uploaded documents and verify the applicant for membership. Continue?',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve Documents'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final prevDocs = _docs.map((d) => Map<String, dynamic>.from(d as Map)).toList();
    final prevStatus = _member['status'];

    // Instant optimistic update
    setState(() {
      _approvingAll = true;
      for (var d in _docs) {
        if (d is Map) {
          d['status'] = 'approved';
        }
      }
      _member['status'] = 'approved';
    });

    try {
      final res = await ApiService().post(
        '/documents/admin/member/${widget.memberId}/approve-all',
      );
      if (mounted) {
        if (res.statusCode == 200) {
          _snack('All application documents approved and verified!', _kGreen);
          await ApiService.deleteCacheKeysMatching('documents/admin');
          _fetch(forceRefresh: true);
        } else {
          _snack('Failed to approve documents. Try again.', _kRed);
          setState(() {
            _docs = prevDocs;
            _member['status'] = prevStatus;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        _snack('Network error while approving documents', _kRed);
        setState(() {
          _docs = prevDocs;
          _member['status'] = prevStatus;
        });
      }
    }
    if (mounted) setState(() => _approvingAll = false);
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Map<String, dynamic>> _safeDocs(List<dynamic> list) =>
      list.map((d) => Map<String, dynamic>.from(d as Map)).toList();

  List<Map<String, dynamic>> get _pendingReview => _safeDocs(
    _docs,
  ).where((d) => d['uploaded'] == true && d['status'] == 'pending').toList();
  List<Map<String, dynamic>> get _approved =>
      _safeDocs(_docs).where((d) => d['status'] == 'approved').toList();
  List<Map<String, dynamic>> get _rejectedOrMissing => _safeDocs(
    _docs,
  ).where((d) => d['uploaded'] != true || d['status'] == 'rejected').toList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F1612);
    final textMuted = isDark
        ? const Color(0xFFB0A298)
        : const Color(0xFF6B5E55);

    final name = ((_member['name'] as String?) ?? 'Applicant').trim();
    final company = ((_member['company'] as String?) ?? 'Company / Enterprise')
        .trim();
    final phone = (_member['phone'] as String?) ?? '';
    final tin = (_member['tin'] as String?) ?? '';
    final port = (_member['port_of_operation'] as String?) ?? 'Tema Port';
    final memberType = ((_member['member_type'] as String?) ?? 'Corporate').trim();
    final isCorporate = memberType.toLowerCase().contains('corporate');
    Color headerTypeColor = _kOrange;
    if (isCorporate) {
      headerTypeColor = _kIndigo;
    } else if (memberType.toLowerCase().contains('associate')) {
      headerTypeColor = _kGreen;
    }
    final scale = (_member['member_scale'] as String? ?? 'sme').toLowerCase();
    final hasPaid = _member['registration_fee_paid'] == true;
    final regFeeRaw = _member['registration_fee_amount'];
    final regFeeAmt = regFeeRaw != null ? (double.tryParse(regFeeRaw.toString()) ?? 0.0) : 0.0;
    final lastPaymentRaw = _member['last_payment_amount'];
    final lastPaymentAmt = lastPaymentRaw != null ? (double.tryParse(lastPaymentRaw.toString()) ?? 0.0) : null;

    final safeList = _safeDocs(_docs);
    final uploaded = safeList.where((d) => d['uploaded'] == true).length;
    final approved = safeList.where((d) => d['status'] == 'approved').length;
    final pending = safeList
        .where((d) => d['uploaded'] == true && d['status'] == 'pending')
        .length;
    final total = safeList.length;

    final isApproved =
        (_member['status'] as String?) == 'active' ||
        (_member['status'] as String?) == 'approved' ||
        (total > 0 && approved == total);

    return AppLayout(
      title: 'Review Applicant — $company',
      scrollable: false,
      child: Container(
        color: bg,
        child: _loading
            ? ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: 6,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (_, index) => const ShimmerListTile(),
              )
            : _hasError && _docs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
                          const SizedBox(height: 14),
                          Text(
                            'Unable to load applicant documents.',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retry Loading'),
                            onPressed: () => _fetch(forceRefresh: true),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                children: [
                  // ── APPLICANT HEADER CARD ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Semantics(button: true, label: 'Back', child: InkWell(
                                onTap: () {
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/admin/documents');
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF4D2D20)
                                        : CubagColors.sand,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 15,
                                    color: textPrimary,
                                  ),
                                ),
                              )),
                              const SizedBox(width: 12),

                              CircleAvatar(
                                radius: 22,
                                backgroundColor: headerTypeColor,
                                child: Text(
                                  company.isNotEmpty
                                      ? company[0].toUpperCase()
                                      : 'C',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            company,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: headerTypeColor.withAlpha(25),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: headerTypeColor.withAlpha(60),
                                            ),
                                          ),
                                          child: Text(
                                            memberType.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: headerTypeColor,
                                            ),
                                          ),
                                        ),
                                        if (isCorporate) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (scale == 'sme' ? _kOrange : _kIndigo).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              scale == 'sme' ? "SME" : "LARGE CORP",
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: scale == 'sme' ? _kOrange : _kIndigo,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textMuted)),
                                          ],
                                        ),
                                        if (phone.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.phone_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text(phone, style: TextStyle(fontSize: 12.5, color: textMuted)),
                                            ],
                                          ),
                                        if (tin.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.tag_rounded, size: 13, color: textMuted),
                                              const SizedBox(width: 4),
                                              Text('TIN: $tin', style: TextStyle(fontSize: 12.5, color: textMuted)),
                                            ],
                                          ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.anchor_rounded, size: 13, color: textMuted),
                                            const SizedBox(width: 4),
                                            Text(port, style: TextStyle(fontSize: 12.5, color: textMuted)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasPaid ? _kGreen.withAlpha(20) : _kAmber.withAlpha(20),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: (hasPaid ? _kGreen : _kAmber).withAlpha(50)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fee status',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: hasPaid ? _kGreen : _kAmber,
                                      ),
                                    ),
                                    Text(
                                      hasPaid
                                          ? (lastPaymentAmt != null && lastPaymentAmt > 0
                                                ? 'PAID (GH₵ ${lastPaymentAmt.toStringAsFixed(0)})'
                                                : 'PAID')
                                          : (regFeeAmt > 0
                                                ? 'UNPAID (GH₵ ${regFeeAmt.toStringAsFixed(0)})'
                                                : 'UNPAID'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: hasPaid ? _kGreen : _kAmber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              ElevatedButton.icon(
                                onPressed: (isApproved || _approvingAll)
                                    ? null
                                    : _approveAll,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isApproved
                                      ? Colors.grey.shade700
                                      : _kGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: isApproved
                                    ? const Icon(Icons.check_circle_rounded, size: 16)
                                    : (_approvingAll
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.verified_rounded, size: 16)),
                                label: Text(
                                  isApproved
                                      ? 'Documents Verified'
                                      : (_approvingAll
                                            ? 'Verifying...'
                                            : (total > 0
                                                  ? 'Approve All ($total/$total)'
                                                  : 'Approve Application')),
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              _buildMiniPill('Required', '$total', _kSlate, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Uploaded', '$uploaded', _kBlue, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Awaiting Review', '$pending', _kAmber, border, isDark),
                              const SizedBox(width: 8),
                              _buildMiniPill('Approved', '$approved', _kGreen, border, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── TABS ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: border)),
                      ),
                      child: TabBar(
                        controller: _tab,
                        indicatorColor: _kOrange,
                        labelColor: _kOrange,
                        unselectedLabelColor: textMuted,
                        labelStyle: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                        tabs: [
                          Tab(text: 'Awaiting Action (${_pendingReview.length})'),
                          Tab(text: 'Approved Files (${_approved.length})'),
                          Tab(text: 'Incomplete / Rejected (${_rejectedOrMissing.length})'),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _buildDocList(_pendingReview, isDark, cardBg, border, textPrimary, textMuted),
                        _buildDocList(_approved, isDark, cardBg, border, textPrimary, textMuted),
                        _buildDocList(_rejectedOrMissing, isDark, cardBg, border, textPrimary, textMuted),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMiniPill(
    String label,
    String value,
    Color accent,
    Color border,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF4D2D20) : CubagColors.sand,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : CubagColors.muted,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : CubagColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocList(
    List<Map<String, dynamic>> items,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 40, color: textMuted.withAlpha(100)),
            const SizedBox(height: 10),
            Text(
              'No statutory documents in this section.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final d = items[i];
        final id = d['id'] as int?;
        final label = (d['label'] as String?) ?? 'Certificate Document';
        final key = (d['key'] as String?) ?? 'doc';
        final status = (d['status'] as String?) ?? 'not_uploaded';
        final fileUrl = d['file_url'] as String?;
        final fileName = (d['file_name'] as String?) ?? 'Document.pdf';
        final uploadedAt = d['uploaded_at'] as String?;
        final isUploaded = d['uploaded'] == true && fileUrl != null;

        _noteCtrl.putIfAbsent(key, () => TextEditingController(text: d['admin_note'] as String? ?? ''));

        Color pillColor = _kRed;
        String pillLabel = 'Not Uploaded';
        if (status == 'approved') {
          pillColor = _kGreen;
          pillLabel = 'Approved';
        } else if (status == 'rejected') {
          pillColor = _kRed;
          pillLabel = 'Rejected';
        } else if (isUploaded) {
          pillColor = _kAmber;
          pillLabel = 'Awaiting Vetting';
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: pillColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isUploaded ? Icons.description_rounded : Icons.warning_amber_rounded,
                  color: pillColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: pillColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: pillColor.withAlpha(50)),
                          ),
                          child: Text(
                            pillLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: pillColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUploaded
                          ? 'File: $fileName • Uploaded: ${uploadedAt ?? "Recently"}'
                          : 'Applicant has not uploaded this statutory certificate yet.',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    if (isUploaded) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _showDocPreviewModal(context, label, fileUrl),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.remove_red_eye_rounded, size: 13, color: _kOrange),
                                  const SizedBox(width: 4),
                                  Text('Preview', style: TextStyle(fontSize: 12, color: AppColors.accentOrangeText, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () async => launchUrl(
                              Uri.parse(await ApiService.signedDocumentUrl(ApiService.resolveImageUrl(fileUrl))),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 13, color: textMuted),
                                  const SizedBox(width: 4),
                                  Text('Open in Tab', style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),

              if (id != null && isUploaded)
                if (status == 'approved')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded, size: 14, color: _kGreen),
                        const SizedBox(width: 5),
                        Text('Approved', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kGreen)),
                      ],
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          elevation: 0,
                        ),
                        onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'approved', key),
                        icon: const Icon(Icons.check_rounded, size: 13),
                        label: Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: const BorderSide(color: _kRed),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _actionLoading[id] == true ? null : () => _setStatus(id, 'rejected', key),
                        icon: const Icon(Icons.close_rounded, size: 13),
                        label: Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
            ],
          ),
        );
      },
    );
  }
}

class AdminMemberDocumentsPage extends StatelessWidget {
  final String memberId;
  const AdminMemberDocumentsPage({super.key, required this.memberId});

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(memberId) ?? 0;
    return ReviewApplicantPage(memberId: id);
  }
}
