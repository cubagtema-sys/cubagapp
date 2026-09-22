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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Archive Support Ticket', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Are you sure you want to archive Ticket #$ticketId?',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _kSlate)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Archive', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AppLayout(
      title: 'Support Tickets',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          AdminHeader(
            title: 'Support Tickets & Helpdesk',
            subtitle: 'Track, manage, and respond to member inquiries and compliance issues.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                  side: BorderSide(color: border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  _clearCache();
                  _fetchTickets(page: 1);
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Streamlined KPI Row
          _buildKPIRow(isDark, cardBg, border, textPrimary, textMuted),
          const SizedBox(height: 16),

          // Active view: Conversation studio or Ticket table
          if (_selectedTicket != null)
            _buildConversationStudio(isDark, cardBg, border, textPrimary, textMuted)
          else
            _buildTableSection(isDark, cardBg, border, textPrimary, textMuted),
        ],
      ),
    );
  }

  Widget _buildKPIRow(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final cards = [
          _buildCompactMetric('Total Cases', '$_total', Icons.confirmation_number_outlined, _kIndigo, 'all', cardBg, border, textPrimary, textMuted),
          _buildCompactMetric('Open Inbox', '$_openCount', Icons.mark_email_unread_outlined, _kOrange, 'inbox', cardBg, border, textPrimary, textMuted),
          _buildCompactMetric('In Progress', '$_pendingCount', Icons.pending_actions_rounded, _kAmber, 'pending', cardBg, border, textPrimary, textMuted),
          _buildCompactMetric('Resolved', '$_resolvedCount', Icons.check_circle_outline_rounded, _kGreen, 'resolved', cardBg, border, textPrimary, textMuted),
        ];

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((c) => Container(width: 160, margin: const EdgeInsets.only(right: 8), child: c)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCompactMetric(
    String label,
    String value,
    IconData icon,
    Color color,
    String filterKey,
    Color bg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final isSel = _statusFilter == filterKey;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() => _statusFilter = filterKey);
        _fetchTickets(page: 1);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: isDark ? 0.2 : 0.08) : bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? color : border,
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? color : textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter & Search Toolbar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.outfit(fontSize: 13.5, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by ID, subject, member name, company...',
                        hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                        prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 14),
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
                const SizedBox(width: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusFilterChip('Inbox', 'inbox', activeColor: _kOrange),
                      const SizedBox(width: 6),
                      _buildStatusFilterChip('Archived', 'archived', activeColor: _kSlate),
                      const SizedBox(width: 6),
                      _buildStatusFilterChip('All', 'all', activeColor: _kIndigo),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table Content
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: List.generate(4, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
              ),
            )
          else if (tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _kIndigo.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.inbox_rounded, size: 28, color: _kIndigo),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No tickets found in this view',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Member inquiries and helpdesk tickets will appear here.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const minWidth = 880.0;
                final tableWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: DataTable(
                      horizontalMargin: 16,
                      columnSpacing: 18,
                      headingRowHeight: 40,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 56,
                      headingRowColor: WidgetStateProperty.all(
                        isDark ? const Color(0xFF381F15) : const Color(0xFFF8FAFC),
                      ),
                      headingTextStyle: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                      dataTextStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: textPrimary,
                      ),
                      columns: const [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('MEMBER & COMPANY')),
                        DataColumn(label: Text('SUBJECT & PREVIEW')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('DATE')),
                        DataColumn(label: Text('ACTION')),
                      ],
                      rows: tickets.map((t) {
                        final map = Map<String, dynamic>.from(t as Map);
                        final id = map['id']?.toString() ?? '';
                        final subject = map['subject'] as String? ?? 'No Subject';
                        final message = map['message'] as String? ?? '';
                        final status = map['status'] as String? ?? 'open';
                        final memberName = map['member_name'] as String? ?? 'Member';
                        final company = map['company'] as String? ?? '';
                        final date = map['date'] as String? ?? (map['created_at']?.toString().substring(0, 10) ?? '');
                        final replies = (map['replies'] as List?)?.length ?? 0;
                        final statusCol = _statusColor(status);

                        return DataRow(
                          cells: [
                            // ID
                            DataCell(
                              InkWell(
                                onTap: () => setState(() => _selectedTicket = map),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _kIndigo.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#$id',
                                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: _kIndigo),
                                  ),
                                ),
                              ),
                            ),
                            // Member
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      memberName,
                                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (company.isNotEmpty)
                                      Text(
                                        company,
                                        style: GoogleFonts.inter(fontSize: 11.5, color: _kOrange, fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // Subject
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 280),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subject,
                                            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (replies > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: _kBlue.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text('$replies', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: _kBlue)),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      message,
                                      style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Status
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusCol.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusCol.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  _statusLabel(status).toUpperCase(),
                                  style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusCol),
                                ),
                              ),
                            ),
                            // Date
                            DataCell(
                              Text(date, style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                            ),
                            // Actions
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    onPressed: () => setState(() => _selectedTicket = map),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kOrange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      elevation: 0,
                                    ),
                                    child: Text('Respond', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert_rounded, size: 16, color: textMuted),
                                    color: cardBg,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    onSelected: (action) {
                                      if (action == 'archive') {
                                        _confirmArchiveTicket(id);
                                      } else {
                                        _updateTicketStatus(id, action);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      if (status != 'open')
                                        PopupMenuItem(value: 'open', child: Text('Mark Open', style: GoogleFonts.outfit(fontSize: 13))),
                                      if (status != 'pending')
                                        PopupMenuItem(value: 'pending', child: Text('Mark In Progress', style: GoogleFonts.outfit(fontSize: 13))),
                                      if (status != 'resolved')
                                        PopupMenuItem(value: 'resolved', child: Text('Mark Resolved', style: GoogleFonts.outfit(fontSize: 13, color: _kGreen, fontWeight: FontWeight.bold))),
                                      const PopupMenuDivider(),
                                      if (status != 'archived')
                                        PopupMenuItem(value: 'archive', child: Text('Archive', style: GoogleFonts.outfit(fontSize: 13, color: _kRed))),
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

          // Pagination Footer
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_tickets.length} of $_total (Page $_page)',
                  style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      onPressed: _page > 1 ? () => _fetchTickets(page: _page - 1) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$_page', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      onPressed: _hasMore ? () => _fetchTickets(page: _page + 1) : null,
                      visualDensity: VisualDensity.compact,
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

  Widget _buildStatusFilterChip(String label, String key, {Color? activeColor}) {
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
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: isDark ? 0.25 : 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel ? color : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? color : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

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
    final date = t['date'] as String? ?? (t['created_at']?.toString().substring(0, 10) ?? '');
    final replies = (t['replies'] as List?) ?? [];
    final statusCol = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Studio Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedTicket = null),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 14),
                  label: Text('Back', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kIndigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('#$id', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _kIndigo)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subject,
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Status selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: statusCol.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusCol.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: ['open', 'pending', 'resolved', 'archived'].contains(status) ? status : 'open',
                      dropdownColor: cardBg,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: statusCol),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('OPEN')),
                        DropdownMenuItem(value: 'pending', child: Text('IN PROGRESS')),
                        DropdownMenuItem(value: 'resolved', child: Text('RESOLVED')),
                        DropdownMenuItem(value: 'archived', child: Text('ARCHIVED')),
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
          const Divider(height: 1),

          // Member Info Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: isDark ? const Color(0xFF1A0F0A).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Text('From: ', style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                Text(memberName, style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold, color: textPrimary)),
                if (company.isNotEmpty) ...[
                  Text(' • ', style: GoogleFonts.inter(fontSize: 12, color: textMuted)),
                  Text(company, style: GoogleFonts.inter(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600)),
                ],
                const Spacer(),
                Text(date, style: GoogleFonts.inter(fontSize: 11.5, color: textMuted)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Conversation Thread
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Original message bubble
                _buildSimpleBubble(
                  sender: memberName,
                  tag: company.isNotEmpty ? company : 'Member',
                  message: message,
                  time: date,
                  isAdmin: false,
                  isDark: isDark,
                  border: border,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),

                // Replies
                ...replies.map((r) {
                  final rMap = Map<String, dynamic>.from(r as Map);
                  final author = rMap['author'] as String? ?? 'Admin';
                  final rMsg = rMap['message'] as String? ?? '';
                  final rDate = rMap['date'] as String? ?? '';
                  final isAdm = author.toLowerCase().contains('admin') || author.toLowerCase().contains('secretariat');

                  return _buildSimpleBubble(
                    sender: author,
                    tag: isAdm ? 'Secretariat' : 'Member',
                    message: rMsg,
                    time: rDate,
                    isAdmin: isAdm,
                    isDark: isDark,
                    border: border,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  );
                }),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Reply Composer
                Text(
                  'REPLY TO MEMBER',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _replyCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 13.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Type administrative response or instructions...',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textMuted),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
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
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kGreen,
                        side: BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text('Reply & Resolve', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _sendingReply ? null : _sendReply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      icon: _sendingReply
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 14),
                      label: Text(_sendingReply ? 'Sending...' : 'Send Reply', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
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

  Widget _buildSimpleBubble({
    required String sender,
    required String tag,
    required String message,
    required String time,
    required bool isAdmin,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final bubbleBg = isAdmin
        ? (isDark ? const Color(0xFF4D2D20) : const Color(0xFFFFF7ED))
        : (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC));
    final bubbleBorder = isAdmin ? _kOrange.withValues(alpha: 0.4) : border;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sender,
                style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold, color: isAdmin ? _kOrange : textPrimary),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: (isAdmin ? _kOrange : _kIndigo).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: isAdmin ? _kOrange : _kIndigo),
                ),
              ),
              const Spacer(),
              Text(time, style: GoogleFonts.inter(fontSize: 11, color: textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary, height: 1.4),
          ),
        ],
      ),
    );
  }
}
