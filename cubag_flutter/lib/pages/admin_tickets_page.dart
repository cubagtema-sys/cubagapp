import '../components/admin_dialog.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

class AdminTicketsPage extends StatefulWidget {
  const AdminTicketsPage({super.key});
  @override
  State<AdminTicketsPage> createState() => _AdminTicketsPageState();
}

class _AdminTicketsPageState extends State<AdminTicketsPage> {
  final _api = ApiService();

  List<dynamic> _tickets = [];
  Map<String, dynamic>? _selectedTicket;

  String _statusFilter = 'inbox'; // 'inbox', 'open', 'pending', 'resolved', 'archived', 'all'
  String _searchQuery = '';
  bool _loading = true;
  bool _sendingReply = false;

  int _page = 1;
  final int _perPage = 15;
  int _total = 0;
  bool _hasMore = false;

  final _replyCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchTickets(page: 1);
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _searchQuery = v.trim());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _replyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _clearCache() async {
    await ApiService.deleteCacheKeysMatching('admin_tickets');
    await ApiService.deleteCacheKeysMatching('tickets');
  }

  Future<void> _fetchTickets({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _page = page;
      if (_tickets.isEmpty) _loading = true;
    });

    final filter = _statusFilter;
    await _api.fetchDataWithCache(
      '/tickets/admin/all?page=$_page&per_page=$_perPage&status=$filter',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (_statusFilter != filter) return;
        if (hasError && _tickets.isEmpty) {
          setState(() => _loading = false);
          return;
        }
        if (data == null) {
          setState(() => _loading = false);
          return;
        }

        final d = data as Map<String, dynamic>;
        var list = ApiService.ensureList(d);
        if (list.isEmpty && d.containsKey('data') && d['data'] is List) {
          list = List<dynamic>.from(d['data'] as List);
        }

        setState(() {
          _loading = false;
          _tickets = list;
          if (d.containsKey('total')) {
            _total = (d['total'] as num?)?.toInt() ?? _tickets.length;
            _hasMore = (_page * _perPage) < _total;
          } else {
            _total = _tickets.length;
            _hasMore = false;
          }

          if (_selectedTicket != null) {
            final found = _tickets.firstWhere(
              (t) => t['id'].toString() == _selectedTicket!['id'].toString(),
              orElse: () => null,
            );
            if (found != null) {
              _selectedTicket = Map<String, dynamic>.from(found as Map);
            }
          }
        });
      },
    );
  }

  Future<void> _updateTicketStatus(String ticketId, String newStatus) async {
    try {
      final res = await _api.put(
        '/tickets/admin/$ticketId/status',
        data: {'status': newStatus},
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _showToast('Status updated to ${newStatus.toUpperCase()}', _kGreen);
        setState(() {
          if (_selectedTicket != null && _selectedTicket!['id'].toString() == ticketId) {
            _selectedTicket!['status'] = newStatus;
          }
          final idx = _tickets.indexWhere((t) => t['id'].toString() == ticketId);
          if (idx != -1) {
            _tickets[idx]['status'] = newStatus;
          }
        });
        await _clearCache();
        await _fetchTickets(page: _page);
      } else {
        _showToast('Failed to update status', _kRed);
      }
    } catch (e, st) {
      AppLogger.error('admin_tickets_page', e, st);
      _showToast('Failed to update status', _kRed);
    }
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    if (msg.isEmpty || _selectedTicket == null) return;

    final ticketId = _selectedTicket!['id'].toString();
    setState(() => _sendingReply = true);
    try {
      final res = await _api.postData('tickets/admin/$ticketId/reply', {
        'message': msg,
      });
      if (res != null) {
        _replyCtrl.clear();
        _showToast('Reply sent successfully!', _kGreen);
        await _clearCache();
        await _fetchTickets(page: _page);
      }
    } catch (e, st) {
      AppLogger.error('admin_tickets_page', e, st);
      _showToast('Failed to send reply', _kRed);
    }
    if (mounted) setState(() => _sendingReply = false);
  }

  Future<void> _confirmArchiveTicket(String ticketId) async {
    final ok = await showAdminConfirm(context, title: 'Archive this ticket?', message: 'Ticket #$ticketId moves to Archived. You can still open it there.', confirmLabel: 'Archive', destructive: true);

    if (ok == true) {
      await _updateTicketStatus(ticketId, 'archived');
      if (_selectedTicket != null && _selectedTicket!['id'].toString() == ticketId) {
        setState(() => _selectedTicket = null);
      }
    }
  }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  List<dynamic> get _filteredTickets {
    var list = _tickets;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        final id = (t['id']?.toString() ?? '').toLowerCase();
        final subject = (t['subject'] as String? ?? '').toLowerCase();
        final message = (t['message'] as String? ?? '').toLowerCase();
        final memberName = (t['member_name'] as String? ?? '').toLowerCase();
        final company = (t['company'] as String? ?? '').toLowerCase();
        final memNo = (t['membership_number'] as String? ?? '').toLowerCase();
        return id.contains(q) ||
            subject.contains(q) ||
            message.contains(q) ||
            memberName.contains(q) ||
            company.contains(q) ||
            memNo.contains(q);
      }).toList();
    }
    return list;
  }

  (String, StatusKind) _statusView(String s) => switch (s.toLowerCase()) {
        'pending' => ('In progress', StatusKind.pending),
        'resolved' => ('Resolved', StatusKind.good),
        'archived' => ('Archived', StatusKind.neutral),
        _ => ('Open', StatusKind.pending),
      };

  void _copyId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ticket #$id copied'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Tickets',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Tickets',
                subtitle: 'Questions and problems members send to the Secretariat. Open one to read it and reply.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _clearCache();
                      _fetchTickets(page: 1);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              if (_selectedTicket != null) _buildConversation() else ..._buildList(),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildList() {
    final tickets = _filteredTickets;
    return [
      FilterTabs(
        tabs: const [
          ('inbox', 'Inbox'),
          ('pending', 'In progress'),
          ('resolved', 'Resolved'),
          ('archived', 'Archived'),
          ('all', 'All'),
        ],
        selected: _statusFilter,
        onSelected: (key) {
          if (_statusFilter != key) {
            setState(() => _statusFilter = key);
            _fetchTickets(page: 1);
          }
        },
      ),
      const SizedBox(height: CubagSpace.sm),
      AdminSearchField(
        hint: 'Search subject, member, company or ticket number',
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
      ),
      const SizedBox(height: CubagSpace.md),
      if (_loading)
        Column(
          children: List.generate(
            4,
            (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
          ),
        )
      else if (tickets.isEmpty)
        EmptyMessage(
          icon: Icons.inbox_rounded,
          title: _searchQuery.isNotEmpty ? 'No tickets match' : 'Nothing here',
          message: _searchQuery.isNotEmpty
              ? 'Try other words, or clear the search.'
              : (_statusFilter == 'inbox'
                  ? 'No open tickets. Questions from members appear here.'
                  : 'No tickets in this list.'),
        )
      else ...[
        AdminRowGroup(
          dividerIndent: 68,
          children: [for (final t in tickets) _ticketRow(Map<String, dynamic>.from(t as Map))],
        ),
        const SizedBox(height: CubagSpace.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Page $_page · ${_tickets.length} shown of $_total',
                style: CubagType.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _page > 1 ? () => _fetchTickets(page: _page - 1) : null,
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _hasMore ? () => _fetchTickets(page: _page + 1) : null,
            ),
          ],
        ),
      ],
    ];
  }

  Widget _ticketRow(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final subject = map['subject'] as String? ?? 'No subject';
    final status = map['status'] as String? ?? 'open';
    final memberName = map['member_name'] as String? ?? 'Member';
    final company = map['company'] as String? ?? '';
    final created = map['created_at']?.toString() ?? '';
    final date = map['date'] as String? ?? (created.length >= 10 ? created.substring(0, 10) : created);
    final replies = (map['replies'] as List?)?.length ?? 0;
    final (label, kind) = _statusView(status);

    return AdminListRow(
      leading: AdminRowMark(initials: adminInitials(memberName)),
      title: subject,
      subtitle: [memberName, if (company.isNotEmpty) company].join(' · '),
      meta: [
        '#$id',
        if (date.isNotEmpty) date,
        if (replies > 0) replies == 1 ? '1 reply' : '$replies replies',
      ].join(' · '),
      status: StatusChip(label, kind: kind),
      onTap: () => setState(() => _selectedTicket = map),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
        onSelected: (action) {
          if (action == 'archive') {
            _confirmArchiveTicket(id);
          } else if (action == 'copy') {
            _copyId(id);
          } else {
            _updateTicketStatus(id, action);
          }
        },
        itemBuilder: (ctx) => [
          if (status != 'open') const PopupMenuItem(value: 'open', child: Text('Mark open')),
          if (status != 'pending') const PopupMenuItem(value: 'pending', child: Text('Mark in progress')),
          if (status != 'resolved') const PopupMenuItem(value: 'resolved', child: Text('Mark resolved')),
          const PopupMenuItem(value: 'copy', child: Text('Copy ticket number')),
          if (status != 'archived') ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'archive',
              child: Text('Archive', style: TextStyle(color: CubagColors.lapsed)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversation() {
    final t = _selectedTicket!;
    final id = t['id']?.toString() ?? '';
    final subject = t['subject'] as String? ?? 'No subject';
    final message = t['message'] as String? ?? '';
    final status = t['status'] as String? ?? 'open';
    final memberName = t['member_name'] as String? ?? 'Member';
    final company = t['company'] as String? ?? '';
    final created = t['created_at']?.toString() ?? '';
    final date = t['date'] as String? ?? (created.length >= 10 ? created.substring(0, 10) : created);
    final replies = (t['replies'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedTicket = null),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('All tickets'),
          ),
        ),
        const SizedBox(height: CubagSpace.xs),
        Container(
          padding: const EdgeInsets.all(CubagSpace.lg),
          decoration: BoxDecoration(
            color: CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: CubagSpace.sm,
                runSpacing: CubagSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(subject, style: CubagType.title),
                        const SizedBox(height: 4),
                        Text(
                          [memberName, if (company.isNotEmpty) company, if (date.isNotEmpty) date].join(' · '),
                          style: CubagType.small,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: () => _copyId(id), child: Text('#$id')),
                      const SizedBox(width: CubagSpace.xs),
                      DropdownMenu<String>(
                        initialSelection: const ['open', 'pending', 'resolved', 'archived'].contains(status) ? status : 'open',
                        label: const Text('Status'),
                        width: 170,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(value: 'open', label: 'Open'),
                          DropdownMenuEntry(value: 'pending', label: 'In progress'),
                          DropdownMenuEntry(value: 'resolved', label: 'Resolved'),
                          DropdownMenuEntry(value: 'archived', label: 'Archived'),
                        ],
                        onSelected: (val) {
                          if (val != null && val != status) _updateTicketStatus(id, val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: CubagSpace.lg),
              const Divider(height: 1, color: CubagColors.line),
              const SizedBox(height: CubagSpace.lg),
              _bubble(sender: memberName, message: message, time: date, isAdmin: false),
              for (final r in replies)
                () {
                  final rMap = Map<String, dynamic>.from(r as Map);
                  final author = rMap['author'] as String? ?? 'Admin';
                  final lower = author.toLowerCase();
                  return _bubble(
                    sender: author,
                    message: rMap['message'] as String? ?? '',
                    time: rMap['date'] as String? ?? '',
                    isAdmin: lower.contains('admin') || lower.contains('secretariat'),
                  );
                }(),
              const SizedBox(height: CubagSpace.md),
              Text('Your reply', style: CubagType.label),
              const SizedBox(height: CubagSpace.xs),
              TextField(
                controller: _replyCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Write to the member. They are notified in the app.'),
              ),
              const SizedBox(height: CubagSpace.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: CubagSpace.xs,
                runSpacing: CubagSpace.xs,
                children: [
                  OutlinedButton(
                    onPressed: _sendingReply
                        ? null
                        : () async {
                            if (_replyCtrl.text.trim().isNotEmpty) {
                              await _sendReply();
                              await _updateTicketStatus(id, 'resolved');
                            }
                          },
                    child: const Text('Send and mark resolved'),
                  ),
                  FilledButton.icon(
                    onPressed: _sendingReply ? null : _sendReply,
                    icon: _sendingReply
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(_sendingReply ? 'Sending' : 'Send reply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble({
    required String sender,
    required String message,
    required String time,
    required bool isAdmin,
  }) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          margin: const EdgeInsets.only(bottom: CubagSpace.sm),
          padding: const EdgeInsets.all(CubagSpace.md),
          decoration: BoxDecoration(
            color: isAdmin ? CubagColors.actionTint : CubagColors.sand,
            borderRadius: BorderRadius.circular(CubagRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [isAdmin ? 'Secretariat' : sender, if (time.isNotEmpty) time].join(' · '),
                style: CubagType.caption,
              ),
              const SizedBox(height: 4),
              SelectableText(message, style: CubagType.body.copyWith(color: CubagColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
