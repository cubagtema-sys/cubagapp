import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kSlate = Color(0xFF64748B);

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
  String _toastMessage = '';
  Color _toastColor = _kGreen;

  int _page = 1;
  int _perPage = 15;
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = v);
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

          // If a ticket was selected, update its reference
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
        _showToast('Ticket status updated to ${newStatus.toUpperCase()}', _kGreen);
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
        final msg = res.data is Map ? res.data['message']?.toString() : null;
        _showToast(msg ?? 'Failed to update ticket status (${res.statusCode})', _kRed);
      }
    } catch (e, st) {
      AppLogger.error('admin_tickets_page', e, st);
      _showToast('Failed to update ticket status', _kRed);
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
        _showToast('Reply dispatched to member successfully!', _kGreen);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kRed.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.archive_outlined, color: _kRed, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Archive Support Ticket', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Move Ticket #$ticketId to the compliance archive? It will be removed from the active support inbox.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Archive Ticket', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _updateTicketStatus(ticketId, 'archived');
      if (_selectedTicket != null && _selectedTicket!['id'].toString() == ticketId) {
        setState(() => _selectedTicket = null);
      }
    }
  }

  void _showToast(String msg, Color color) {
    setState(() {
      _toastMessage = msg;
      _toastColor = color;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toastMessage = '');
    });
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'open':
        return _kOrange;
      case 'pending':
        return _kAmber;
      case 'resolved':
        return _kGreen;
      case 'archived':
        return _kSlate;
      default:
        return _kBlue;
    }
  }

  String _statusLabel(String s) {
    if (s.isEmpty) return 'Open';
    return s[0].toUpperCase() + s.substring(1);
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

  int get _openCount => _tickets.where((t) => (t['status'] ?? 'open') == 'open').length;
  int get _pendingCount => _tickets.where((t) => (t['status'] ?? '') == 'pending').length;
  int get _resolvedCount => _tickets.where((t) => (t['status'] ?? '') == 'resolved').length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white : const Color(0xFF475569);

    return AppLayout(
      title: 'Support Tickets & Helpdesk',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP EXECUTIVE BANNER ─────────────────────────────────────────
            AdminHeader(
              title: 'Support Tickets & Helpdesk Hub',
              subtitle: 'Track, manage, and resolve member inquiries, port clearance issues, platform questions, and regulatory compliance tickets.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(color: border, width: 1.2),
                    backgroundColor: cardBg,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _clearCache();
                    _fetchTickets(page: 1);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 17, color: _kOrange),
                  label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── KPI METRICS STRIP ───────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildMetricCard('Total Tickets', '$_total', 'All logged cases', Icons.confirmation_number_outlined, _kIndigo, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('Open Inbox', '$_openCount', 'Awaiting secretariat review', Icons.mark_email_unread_outlined, _kOrange, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('In Progress', '$_pendingCount', 'Active investigations', Icons.pending_actions_rounded, _kAmber, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('Resolved Cases', '$_resolvedCount', 'Successfully closed', Icons.check_circle_outline_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(width: 220, child: _buildMetricCard('Total Tickets', '$_total', 'All logged cases', Icons.confirmation_number_outlined, _kIndigo, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('Open Inbox', '$_openCount', 'Awaiting review', Icons.mark_email_unread_outlined, _kOrange, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('In Progress', '$_pendingCount', 'Active cases', Icons.pending_actions_rounded, _kAmber, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('Resolved', '$_resolvedCount', 'Closed tickets', Icons.check_circle_outline_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                          ],
                        ),
                      );
              },
            ),
            const SizedBox(height: 14),

            // ── TOAST NOTIFICATION ──────────────────────────────────────────
            if (_toastMessage.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: _toastColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _toastColor.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _toastColor == _kGreen ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _toastColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _toastMessage,
                        style: GoogleFonts.outfit(color: _toastColor, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),

            // ── CONVERSATION PANEL OR TABULAR DATA TABLE ─────────────────────
            if (_selectedTicket != null)
              _buildConversationStudio(isDark, cardBg, border, textPrimary, textMuted)
            else
              _buildTableSection(isDark, cardBg, border, textPrimary, textMuted),
          ],
        ),
      ),
    );
  }

  // ── METRIC CARD ───────────────────────────────────────────────────────────
  Widget _buildMetricCard(
    String label,
    String value,
    String desc,
    IconData icon,
    Color accentColor,
    Color bg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withAlpha(40)),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textCol)),
                const SizedBox(height: 1),
                Text(label, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textCol)),
                Text(desc, style: GoogleFonts.inter(fontSize: 12, color: subCol), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TABULAR VIEW & CONTROLS ───────────────────────────────────────────────
  Widget _buildTableSection(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final tickets = _filteredTickets;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── FILTER & SEARCH TOOLBAR ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Search bar
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          style: GoogleFonts.outfit(fontSize: 15, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search Ticket #ID, subject, member name, company, or membership no...',
                            hintStyle: GoogleFonts.inter(fontSize: 14, color: textMuted),
                            prefixIcon: Icon(Icons.search_rounded, size: 18, color: textMuted),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 11),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Rows per page dropdown
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Text('Show: ', style: GoogleFonts.inter(fontSize: 14, color: textMuted)),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _perPage,
                              dropdownColor: cardBg,
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                              items: const [
                                DropdownMenuItem(value: 10, child: Text('10 rows')),
                                DropdownMenuItem(value: 15, child: Text('15 rows')),
                                DropdownMenuItem(value: 25, child: Text('25 rows')),
                                DropdownMenuItem(value: 50, child: Text('50 rows')),
                              ],
                              onChanged: (val) {
                                if (val != null && val != _perPage) {
                                  setState(() => _perPage = val);
                                  _fetchTickets(page: 1);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusFilterChip('Open Inbox', 'inbox', Icons.inbox_rounded, activeColor: _kOrange),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip('Archived Cases', 'archived', Icons.archive_outlined, activeColor: _kSlate),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip('All Statuses', 'all', Icons.format_list_bulleted_rounded, activeColor: _kIndigo),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── TABULAR DATA TABLE ────────────────────────────────────────────
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(20),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (_, index) => const ShimmerListTile(),
              ),
            )
          else if (tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _kIndigo.withAlpha(20), shape: BoxShape.circle),
                    child: const Icon(Icons.confirmation_number_outlined, size: 36, color: _kIndigo),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusFilter == 'inbox' ? 'No active support tickets found in inbox.' : 'No archived tickets found.',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'When members submit technical inquiries, clearance issues, or compliance questions, they will appear here in tabular view.',
                    style: GoogleFonts.inter(fontSize: 14, color: textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = constraints.maxWidth > 960 ? constraints.maxWidth : 960.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: DataTable(
                  horizontalMargin: 20,
                  columnSpacing: 24,
                  headingRowColor: WidgetStateProperty.all(
                    isDark ? const Color(0xFF4D2D20) : const Color(0xFFF8FAFC),
                  ),
                  headingTextStyle: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textMuted,
                    letterSpacing: 0.5,
                  ),
                  dataTextStyle: GoogleFonts.inter(
                    fontSize: 14.5,
                    color: textPrimary,
                  ),
                  columns: const [
                    DataColumn(label: Text('TICKET REF')),
                    DataColumn(label: Text('MEMBER & COMPANY')),
                    DataColumn(label: Text('SUBJECT & DETAILS')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('DATE LOGGED')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: tickets.map((t) {
                    final map = Map<String, dynamic>.from(t as Map);
                    final id = map['id']?.toString() ?? '';
                    final subject = map['subject'] as String? ?? 'No Subject';
                    final message = map['message'] as String? ?? '';
                    final status = map['status'] as String? ?? 'open';
                    final memberName = map['member_name'] as String? ?? 'Unknown Member';
                    final company = map['company'] as String? ?? '';
                    final memNo = map['membership_number'] as String? ?? '';
                    final date = map['date'] as String? ?? (map['created_at']?.toString().substring(0, 10) ?? '');
                    final replies = (map['replies'] as List?)?.length ?? 0;
                    final statusCol = _statusColor(status);

                    return DataRow(
                      cells: [
                        // TICKET REF
                        DataCell(
                          InkWell(
                            onTap: () => setState(() => _selectedTicket = map),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _kIndigo.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _kIndigo.withAlpha(50)),
                              ),
                              child: Text(
                                id,
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: _kIndigo),
                              ),
                            ),
                          ),
                        ),

                        // MEMBER & COMPANY
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  memberName,
                                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (company.isNotEmpty)
                                  Text(
                                    company,
                                    style: GoogleFonts.inter(fontSize: 13, color: _kOrange, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (memNo.isNotEmpty)
                                  Text(
                                    memNo,
                                    style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // SUBJECT & DETAILS
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        subject,
                                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (replies > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _kBlue.withAlpha(20),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.chat_bubble_outline_rounded, size: 10, color: _kBlue),
                                            const SizedBox(width: 3),
                                            Text('$replies', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: _kBlue)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  message,
                                  style: GoogleFonts.inter(fontSize: 13, color: textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // STATUS
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusCol.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusCol.withAlpha(60)),
                            ),
                            child: Text(
                              _statusLabel(status).toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: statusCol,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),

                        // DATE LOGGED
                        DataCell(
                          Text(
                            date,
                            style: GoogleFonts.inter(fontSize: 13.5, color: textMuted, fontWeight: FontWeight.w500),
                          ),
                        ),

                        // ACTIONS
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => setState(() => _selectedTicket = map),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kOrange,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  minimumSize: Size.zero,
                                ),
                                icon: const Icon(Icons.forum_outlined, size: 13),
                                label: Text('Respond', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert_rounded, size: 18, color: textMuted),
                                tooltip: 'Ticket Actions',
                                color: cardBg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                onSelected: (action) {
                                  if (action == 'archive') {
                                    _confirmArchiveTicket(id);
                                  } else {
                                    _updateTicketStatus(id, action);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (status != 'open')
                                    PopupMenuItem(value: 'open', child: Text('Mark as Open', style: GoogleFonts.outfit(fontSize: 14))),
                                  if (status != 'pending')
                                    PopupMenuItem(value: 'pending', child: Text('Mark as In Progress', style: GoogleFonts.outfit(fontSize: 14))),
                                  if (status != 'resolved')
                                    PopupMenuItem(value: 'resolved', child: Text('Mark as Resolved', style: GoogleFonts.outfit(fontSize: 14, color: _kGreen, fontWeight: FontWeight.bold))),
                                  const PopupMenuDivider(),
                                  if (status != 'archived')
                                    PopupMenuItem(value: 'archive', child: Text('Archive Ticket', style: GoogleFonts.outfit(fontSize: 14, color: _kRed))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),

          // ── PAGINATION FOOTER ─────────────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_tickets.length} of $_total tickets (Page $_page)',
                  style: GoogleFonts.inter(fontSize: 14, color: textMuted, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _page > 1 ? () => _fetchTickets(page: _page - 1) : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.chevron_left_rounded, size: 16),
                      label: Text('Prev', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        'Page $_page',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _hasMore ? () => _fetchTickets(page: _page + 1) : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      label: Text('Next', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                      icon: const Icon(Icons.chevron_right_rounded, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String key, IconData icon, {Color? activeColor}) {
    final isSel = _statusFilter == key;
    final color = activeColor ?? _kOrange;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        if (_statusFilter != key) {
          setState(() => _statusFilter = key);
          _fetchTickets(page: 1);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? color.withAlpha(isDark ? 40 : 25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel ? color : (isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSel ? color : (isDark ? Colors.white60 : const Color(0xFF64748B))),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? color : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CONVERSATION & REPLY STUDIO ───────────────────────────────────────────
  Widget _buildConversationStudio(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final t = _selectedTicket!;
    final id = t['id']?.toString() ?? '';
    final subject = t['subject'] as String? ?? 'No Subject';
    final message = t['message'] as String? ?? '';
    final status = t['status'] as String? ?? 'open';
    final memberName = t['member_name'] as String? ?? 'Member';
    final company = t['company'] as String? ?? '';
    final memNo = t['membership_number'] as String? ?? '';
    final date = t['date'] as String? ?? (t['created_at']?.toString().substring(0, 10) ?? '');
    final replies = (t['replies'] as List?) ?? [];
    final statusCol = _statusColor(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation Header & Status Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _selectedTicket = null),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: border),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: Text('Back to Table', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(width: 14),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kIndigo.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kIndigo.withAlpha(60)),
                ),
                child: Text('TICKET #$id', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: _kIndigo)),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  subject,
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),

              // Status Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: statusCol.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusCol.withAlpha(60)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ['open', 'pending', 'resolved', 'archived'].contains(status) ? status : 'open',
                    dropdownColor: cardBg,
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: statusCol),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('STATUS: OPEN')),
                      DropdownMenuItem(value: 'pending', child: Text('STATUS: IN PROGRESS')),
                      DropdownMenuItem(value: 'resolved', child: Text('STATUS: RESOLVED')),
                      DropdownMenuItem(value: 'archived', child: Text('STATUS: ARCHIVED')),
                    ],
                    onChanged: (val) {
                      if (val != null) _updateTicketStatus(id, val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Member Overview Strip
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _kOrange.withAlpha(20), shape: BoxShape.circle),
                      child: const Icon(Icons.person_outline_rounded, size: 16, color: _kOrange),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DIRECTOR / MEMBER', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: textMuted)),
                          Text(memberName, style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (company.isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _kIndigo.withAlpha(20), shape: BoxShape.circle),
                        child: const Icon(Icons.business_outlined, size: 16, color: _kIndigo),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('COMPANY NAME', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: textMuted)),
                            Text(company, style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (memNo.isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _kGreen.withAlpha(20), shape: BoxShape.circle),
                        child: const Icon(Icons.badge_outlined, size: 16, color: _kGreen),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MEMBERSHIP NO', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: textMuted)),
                            Text(memNo, style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _kBlue.withAlpha(20), shape: BoxShape.circle),
                      child: const Icon(Icons.calendar_today_outlined, size: 16, color: _kBlue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LOGGED DATE', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, color: textMuted)),
                          Text(date, style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Conversation Stream
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 18, color: _kOrange),
                  const SizedBox(width: 8),
                  Text('Communication Thread', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                  const Spacer(),
                  if (status != 'archived')
                    TextButton.icon(
                      onPressed: () => _confirmArchiveTicket(id),
                      icon: const Icon(Icons.archive_outlined, size: 14, color: _kRed),
                      label: Text('Archive Case', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: _kRed)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Original Member Inquiry
              _buildMessageBubble(
                senderName: memberName,
                companyTag: company.isNotEmpty ? company : 'Member',
                message: message,
                timestamp: date,
                isAdmin: false,
                isDark: isDark,
                border: border,
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),

              // Thread Replies
              ...replies.map((r) {
                final rMap = Map<String, dynamic>.from(r as Map);
                final author = rMap['author'] as String? ?? 'Admin';
                final rMsg = rMap['message'] as String? ?? '';
                final rDate = rMap['date'] as String? ?? '';
                final isAdm = author.toLowerCase().contains('admin') || author.toLowerCase().contains('secretariat');

                return _buildMessageBubble(
                  senderName: author,
                  companyTag: isAdm ? 'CUBAG Secretariat' : 'Member',
                  message: rMsg,
                  timestamp: rDate,
                  isAdmin: isAdm,
                  isDark: isDark,
                  border: border,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                );
              }),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Secretariat Reply Composer
              Text('DISPATCH ADMINISTRATIVE REPLY', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _replyCtrl,
                maxLines: 4,
                style: GoogleFonts.inter(fontSize: 15, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type your official administrative reply or clearance instructions to the member...',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: textMuted),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _sendingReply
                        ? null
                        : () async {
                            if (_replyCtrl.text.trim().isNotEmpty) {
                              await _sendReply();
                              await _updateTicketStatus(id, 'resolved');
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kGreen,
                      side: BorderSide(color: _kGreen.withAlpha(80)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: Text('Reply & Mark Resolved', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _sendingReply ? null : _sendReply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _sendingReply
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(_sendingReply ? 'Sending...' : 'Send Reply', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMessageBubble({
    required String senderName,
    required String companyTag,
    required String message,
    required String timestamp,
    required bool isAdmin,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final bubbleBg = isAdmin
        ? (isDark ? const Color(0xFF4D2D20) : const Color(0xFFFFF7ED))
        : (isDark ? const Color(0xFF281710) : const Color(0xFFF1F5F9));
    final bubbleBorder = isAdmin ? _kOrange.withAlpha(80) : border;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isAdmin) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _kIndigo.withAlpha(25), shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.person_rounded, size: 16, color: _kIndigo)),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isAdmin ? 14 : 3),
                  bottomRight: Radius.circular(isAdmin ? 3 : 14),
                ),
                border: Border.all(color: bubbleBorder, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        senderName,
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: isAdmin ? _kOrange : textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (isAdmin ? _kOrange : _kIndigo).withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          companyTag,
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: isAdmin ? _kOrange : _kIndigo),
                        ),
                      ),
                      const Spacer(),
                      Text(timestamp, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: GoogleFonts.inter(fontSize: 15, color: textPrimary, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _kOrange.withAlpha(25), shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.admin_panel_settings_rounded, size: 16, color: _kOrange)),
            ),
          ],
        ],
      ),
    );
  }
}
