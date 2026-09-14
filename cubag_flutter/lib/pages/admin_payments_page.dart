import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRed = Color(0xFFef4444);
const _kBlue = Color(0xFF3b82f6);
const _kCardBg = Color(0xFF281710);

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});
  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  bool _loading = true;
  bool _hasError = false;
  Map<String, dynamic> _kpis = {'revenue': 0, 'pending': 0, 'failed': 0};
  List<dynamic> _transactions = [];
  String _search = '';
  String _filterStatus = 'all';
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _actionLoading = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool refresh = false, int? page}) async {
    if (!mounted) return;
    if (page != null) {
      _page = page;
    } else if (refresh) {
      _page = 1;
    }

    if (refresh || page != null) {
      setState(() {
        _loading = true;
        _hasError = false;
        _transactions = [];
      });
    } else if (_transactions.isEmpty) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    await ApiService().fetchDataWithCache(
      '/payments/admin/all?page=$_page&limit=25&search=$_search&status=$_filterStatus',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;

        if (isCached && _transactions.isNotEmpty && !refresh && page == null) {
          setState(() => _loading = false);
          return;
        }

        if (hasError && _transactions.isEmpty) {
          setState(() {
            _loading = false;
            _hasError = true;
          });
          return;
        }
        if (data == null) {
          setState(() => _loading = false);
          return;
        }

        final d = data as Map<String, dynamic>;
        setState(() {
          _loading = false;
          _hasError = false;
          _kpis = d['kpis'] ?? _kpis;

          final incoming = ApiService.ensureList(d);
          _transactions = incoming;

          if (d.containsKey('total')) {
            _total = d['total'] ?? 0;
            _hasMore = (_page * 25) < _total;
          } else {
            _hasMore = false;
          }
        });
      },
    );
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _search = v);
        _fetch(refresh: true);
      }
    });
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError ? _kRed : _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _markPaid(dynamic id) async {
    setState(() => _actionLoading = true);
    final index = _transactions.indexWhere((t) => t['tx_id'] == id);
    if (index != -1) {
      setState(() {
        _transactions[index]['status'] = 'paid';
      });
    }

    try {
      final res = await ApiService().post('/payments/admin/mark-paid/$id');
      if (res.statusCode == 200) {
        _showToast('Payment confirmed and recorded successfully.');
        _fetch(refresh: true);
      }
    } catch (e, st) {
      AppLogger.error('admin_payments_mark_paid', e, st);
      if (index != -1) {
        setState(() => _transactions[index]['status'] = 'pending');
      }
      _showToast('Network error while approving payment.', isError: true);
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  void _showConfirmDialog(dynamic txId, double amount, String memberName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: _kGreen,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Confirm Payment',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mark GHS ${amount.toStringAsFixed(2)} from $memberName as PAID / RECEIVED?\nThis updates the member standing to good standing.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: subTextColor, fontSize: 15),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _actionLoading
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _markPaid(txId);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      elevation: 0,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Approve',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailModal(Map<String, dynamic> tx) {
    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
    final status = tx['status']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);
    final inputBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(120)
        : const Color(0xFFf8fafc);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: _kOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Payment Invoice Details',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: textColor,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _statusColor(status).withAlpha(50),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AMOUNT CHARGED',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: subTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'GHS ${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _detailField(
                  'Transaction ID',
                  tx['tx_id']?.toString() ?? '—',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                const SizedBox(height: 10),
                _detailField(
                  'Member / Company Name',
                  tx['member_name']?.toString() ?? '—',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                const SizedBox(height: 10),
                _detailField(
                  'Payment Reference / Channel',
                  tx['payment_ref']?.toString() ??
                      'Mobile Money / Instant Pay',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                const SizedBox(height: 10),
                _detailField(
                  'Description / Fee Type',
                  tx['description']?.toString() ?? 'Annual Membership Dues',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                const SizedBox(height: 10),
                _detailField(
                  'Date Created',
                  tx['date']?.toString() ?? tx['created_at']?.toString() ?? '—',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (status == 'pending')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showConfirmDialog(
                  tx['tx_id'],
                  amount,
                  tx['member_name']?.toString() ?? '',
                );
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: const Text('Approve Payment'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailField(
    String label,
    String value,
    Color inputBg,
    Color borderCol,
    Color textCol,
    Color subTextCol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: subTextCol,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol),
          ),
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textCol,
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'completed':
      case 'success':
        return _kGreen;
      case 'pending':
        return _kAmber;
      case 'failed':
      case 'overdue':
        return _kRed;
      default:
        return _kBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final headerBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(150)
        : const Color(0xFFf8fafc);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);

    final revenue = double.tryParse(_kpis['revenue']?.toString() ?? '0') ?? 0;
    final pendingCount = _kpis['pending']?.toString() ?? '0';
    final failedCount = _kpis['failed']?.toString() ?? '0';

    return AppLayout(
      title: 'Financial Center',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Financial Center & Transactions',
            subtitle:
                'Review member dues, subscription invoices, bank transfers, and payment approvals.',
            actions: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _fetch(refresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  'Refresh',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Metric Summary Cards ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Collected Revenue',
                  value: 'GHS ${revenue.toStringAsFixed(2)}',
                  icon: Icons.account_balance_wallet_outlined,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Pending Approvals',
                  value: pendingCount,
                  icon: Icons.hourglass_top_rounded,
                  color: kAdminAmber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Failed / Overdue',
                  value: failedCount,
                  icon: Icons.cancel_outlined,
                  color: kAdminRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Filter & Search Toolbar ──────────────────────────────────────────
          AdminToolbar(
            searchHint:
                'Search transactions by member, reference, or description...',
            onSearchChanged: _onSearchChanged,
            filters: [
              _filterChip('All Transactions', 'all'),
              _filterChip('Paid', 'paid'),
              _filterChip('Pending', 'pending'),
              _filterChip('Overdue', 'overdue'),
            ],
          ),
          const SizedBox(height: 16),

          // ── Tabular Payments DataTable ───────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (_hasError && _transactions.isEmpty)
            FetchErrorView(onRetry: () => _fetch(refresh: true))
          else if (_transactions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  Icon(Icons.payments_outlined, size: 48, color: subTextColor),
                  const SizedBox(height: 12),
                  Text(
                    'No payment records found.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try clearing your search query or selecting a different status filter.',
                    style: GoogleFonts.inter(fontSize: 15, color: subTextColor),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(headerBg),
                          headingTextStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: subTextColor,
                            letterSpacing: 0.5,
                          ),
                          dataTextStyle: GoogleFonts.outfit(
                            fontSize: 15,
                            color: textColor,
                          ),
                          columnSpacing: 24,
                          horizontalMargin: 24,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('TRANSACTION REF')),
                            DataColumn(label: Text('MEMBER / COMPANY')),
                            DataColumn(label: Text('AMOUNT (GHS)')),
                            DataColumn(label: Text('DESCRIPTION / PURPOSE')),
                            DataColumn(label: Text('DATE')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: _transactions.map((tx) {
                            final status =
                                tx['status']?.toString() ?? 'pending';
                            final color = _statusColor(status);
                            final amount =
                                double.tryParse(
                                  tx['amount']?.toString() ?? '0',
                                ) ??
                                0;
                            final memberName =
                                tx['member_name']?.toString() ?? 'Member';
                            final momoTxId = tx['momo_tx_id']?.toString().trim();
                            final rawRef = tx['payment_ref']?.toString().trim();
                            final refCode = tx['ref_code']?.toString().trim();
                            final txId = (momoTxId != null && momoTxId.isNotEmpty && momoTxId != 'null' && momoTxId != 'None')
                                ? momoTxId
                                : (refCode != null && refCode.isNotEmpty && refCode != 'null' && refCode != 'None')
                                    ? refCode
                                    : (rawRef != null && rawRef.isNotEmpty && rawRef != 'null' && rawRef != 'None')
                                        ? rawRef
                                        : 'TXN-${(tx['tx_id'] ?? tx['id'] ?? '1').toString().padLeft(6, '0')}';
                            final desc =
                                tx['description']?.toString() ??
                                'Membership Dues';
                            final date =
                                tx['date']?.toString() ??
                                tx['created_at']?.toString() ??
                                '—';

                            return DataRow(
                              cells: [
                                // 1. Transaction Ref (Sleek Orange Badge)
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _kOrange.withAlpha(isDark ? 30 : 15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _kOrange.withAlpha(60),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      txId,
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _kOrange,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),

                                // 2. Member / Company
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: _kOrange.withAlpha(35),
                                        child: Text(
                                          memberName.isNotEmpty
                                              ? memberName[0].toUpperCase()
                                              : 'M',
                                          style: GoogleFonts.outfit(
                                            color: _kOrange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 180,
                                        ),
                                        child: Text(
                                          memberName,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 3. Amount
                                DataCell(
                                  Text(
                                    'GHS ${amount.toStringAsFixed(2)}',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: textColor,
                                    ),
                                  ),
                                ),

                                // 4. Description
                                DataCell(
                                  Container(
                                    constraints: BoxConstraints(
                                      minWidth: 160,
                                      maxWidth: constraints.maxWidth > 900
                                          ? constraints.maxWidth * 0.25
                                          : 240,
                                    ),
                                    child: Text(
                                      desc,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: subTextColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),

                                // 5. Date
                                DataCell(
                                  Text(
                                    date.split('T').first,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: subTextColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),

                                // 6. Status Badge
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: color.withAlpha(50),
                                      ),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),

                                // 7. Action Buttons
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (status == 'pending') ...[
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _kGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: _actionLoading
                                              ? null
                                              : () => _showConfirmDialog(
                                                  tx['tx_id'],
                                                  amount,
                                                  memberName,
                                                ),
                                          child: const Text(
                                            'Approve',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      IconButton(
                                        icon: const Icon(
                                          Icons.receipt_long_rounded,
                                          size: 18,
                                          color: _kOrange,
                                        ),
                                        tooltip: 'View Invoice Details',
                                        onPressed: () => _showDetailModal(
                                          Map<String, dynamic>.from(tx),
                                        ),
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
              ),
            ),

          const SizedBox(height: 16),

          // ── Pagination Bar ───────────────────────────────────────────────────
          if (_total > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${((_page - 1) * 25) + 1}–${(_page * 25).clamp(0, _total)} of $_total transactions',
                  style: GoogleFonts.inter(color: subTextColor, fontSize: 15),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _page > 1
                          ? () => _fetch(page: _page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      label: const Text('Previous'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _hasMore
                          ? () => _fetch(page: _page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.outfit(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: 14,
          color: isSelected ? _kOrange : null,
        ),
      ),
      selected: isSelected,
      selectedColor: _kOrange.withAlpha(30),
      checkmarkColor: _kOrange,
      onSelected: (_) {
        setState(() {
          _filterStatus = value;
          _page = 1;
        });
        _fetch(refresh: true);
      },
    );
  }
}
