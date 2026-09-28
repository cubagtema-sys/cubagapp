import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final String? initialAction;
  const AdminPaymentsPage({super.key, this.initialAction});
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
    if (widget.initialAction == 'counter_payment') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecordCounterPaymentModal();
      });
    }
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

  String _resolveReceiptUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    if (url.startsWith('/')) {
      return '$base$url';
    }
    return '$base/$url';
  }

  Future<void> _markPaid(dynamic id) async {
    setState(() => _actionLoading = true);
    final index = _transactions.indexWhere((t) => (t['tx_id'] ?? t['id']) == id);
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

  Future<void> _rejectPayment(dynamic id, {String? reason}) async {
    setState(() => _actionLoading = true);
    try {
      final res = await ApiService().post('/payments/admin/reject/$id', data: {
        'reason': reason ?? 'Deposit slip rejected or invalid',
      });
      if (res.statusCode == 200) {
        _showToast('Payment marked as rejected.');
        _fetch(refresh: true);
      }
    } catch (e, st) {
      AppLogger.error('admin_payments_reject', e, st);
      _showToast('Network error while rejecting payment.', isError: true);
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  void _showRecordCounterPaymentModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RecordCounterPaymentDialog(
        onSuccess: () {
          _showToast('Counter payment recorded and approved successfully!');
          _fetch(refresh: true);
        },
      ),
    );
  }

  void _showReceiptDialog(
    String receiptUrl,
    String memberName,
    double amount,
    String date, {
    dynamic txId,
    bool isPending = false,
  }) {
    final fullUrl = _resolveReceiptUrl(receiptUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                color: _kOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bank Deposit Receipt Slip',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  Text(
                    '$memberName · GH₵ ${amount.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748b),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'Open in new tab',
              onPressed: () => launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 440),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFcbd5e1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(
                      fullUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 280,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(strokeWidth: 2.5),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 200,
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image_rounded, size: 40, color: Color(0xFF94a3b8)),
                              const SizedBox(height: 10),
                              Text(
                                'Unable to load receipt image directly.\nClick "Open in new tab" above.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748b)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pinch / scroll to zoom into receipt details',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94a3b8)),
              ),
            ],
          ),
        ),
        actions: [
          if (isPending && txId != null) ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _rejectPayment(txId);
              },
              icon: const Icon(Icons.cancel_outlined, size: 16, color: _kRed),
              label: const Text('Reject Slip', style: TextStyle(color: _kRed, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kRed),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _markPaid(txId);
              },
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Confirm & Mark Paid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(
    dynamic txId,
    double amount,
    String memberName, {
    String? receiptUrl,
    String? method,
    String? notes,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);
    final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 480,
          child: Column(
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
                'Confirm & Mark Paid',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mark GHS ${amount.toStringAsFixed(2)} from $memberName as PAID / RECEIVED?\nThis automatically activates member standing and generates their official receipt.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: subTextColor, fontSize: 14.5, height: 1.4),
              ),
              if (hasReceipt) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _showReceiptDialog(receiptUrl, memberName, amount, '', txId: txId, isPending: true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF24140D).withAlpha(12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kOrange.withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_rounded, color: _kOrange, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bank Deposit Slip Attached',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: const Color(0xFF1A0F0A),
                                ),
                              ),
                              Text(
                                'Click to inspect full deposit receipt image',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748b)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.zoom_in_rounded, color: _kOrange, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
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
                        'Approve & Mark Paid',
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

    final paymentMethod = (tx['payment_method'] ?? 'momo').toString();
    final isBank = paymentMethod.toLowerCase() == 'bank' || paymentMethod.toLowerCase() == 'bank_transfer';
    final receiptUrl = tx['receipt_url']?.toString();
    final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';

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
          width: 540,
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
                  'Payment Channel / Method',
                  isBank ? 'Bank Transfer (GCB Bank Limited)' : 'Mobile Money / Instant Pay',
                  inputBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                if (tx['payment_ref'] != null && tx['payment_ref'].toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _detailField(
                    'Reference / Slip No.',
                    tx['payment_ref'].toString(),
                    inputBg,
                    borderColor,
                    textColor,
                    subTextColor,
                  ),
                ],
                if (tx['notes'] != null && tx['notes'].toString().isNotEmpty && tx['notes'] != 'null') ...[
                  const SizedBox(height: 10),
                  _detailField(
                    'Depositor Notes',
                    tx['notes'].toString(),
                    inputBg,
                    borderColor,
                    textColor,
                    subTextColor,
                  ),
                ],
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
                if (hasReceipt) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => _showReceiptDialog(
                      receiptUrl,
                      tx['member_name']?.toString() ?? '',
                      amount,
                      tx['date']?.toString() ?? '',
                      txId: tx['tx_id'] ?? tx['id'],
                      isPending: status == 'pending',
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF24140D).withAlpha(12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kOrange.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attachment_rounded, color: _kOrange, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attached Deposit Slip / Transfer Receipt',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: const Color(0xFF1A0F0A),
                                  ),
                                ),
                                Text(
                                  'Click to preview high-resolution receipt',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748b)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: _kOrange, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
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
                  tx['tx_id'] ?? tx['id'],
                  amount,
                  tx['member_name']?.toString() ?? '',
                  receiptUrl: receiptUrl,
                  method: paymentMethod,
                  notes: tx['notes']?.toString(),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRecordCounterPaymentModal,
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.point_of_sale_rounded, size: 20),
        label: Text(
          '➕ Record Counter / Cash Payment',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
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
                  backgroundColor: _kGreen,
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
                onPressed: _showRecordCounterPaymentModal,
                icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                label: Text(
                  '➕ Record Counter / Cash Payment',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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

          // ── Quick Office Counter Settlement Banner ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF10b981).withAlpha(40), const Color(0xFF065f46).withAlpha(30)]
                    : [const Color(0xFFecfdf5), const Color(0xFFd1fae5).withAlpha(120)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF10b981).withAlpha(80),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10b981).withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.point_of_sale_rounded, color: Color(0xFF10b981), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct Walk-in / Office Counter Settlement',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'Member or customer paying at Secretariat office with Cash, Cheque, or POS Card Swipe?',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showRecordCounterPaymentModal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10b981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: Text(
                    'Record Payment',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
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
                            DataColumn(label: Text('CHANNEL / METHOD')),
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

                            final method = (tx['payment_method'] ?? 'momo').toString().toLowerCase();
                            final isBank = method == 'bank' || method == 'bank_transfer' || method == 'wire';
                            final receiptUrl = tx['receipt_url']?.toString();
                            final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';

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

                                // 3. Channel / Method (with Bank / Receipt Pill)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isBank
                                              ? const Color(0xFF0284c7).withAlpha(20)
                                              : _kOrange.withAlpha(20),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isBank
                                                ? const Color(0xFF0284c7).withAlpha(60)
                                                : _kOrange.withAlpha(60),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isBank
                                                  ? Icons.account_balance_rounded
                                                  : Icons.phone_android_rounded,
                                              size: 13,
                                              color: isBank
                                                  ? const Color(0xFF0284c7)
                                                  : _kOrange,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isBank ? 'BANK' : 'MOMO',
                                              style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: isBank
                                                    ? const Color(0xFF0284c7)
                                                    : _kOrange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasReceipt) ...[
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () => _showReceiptDialog(
                                            receiptUrl,
                                            memberName,
                                            amount,
                                            date,
                                            txId: tx['tx_id'] ?? tx['id'],
                                            isPending: status == 'pending',
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10b981).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFF10b981).withAlpha(80),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.image_outlined,
                                                  size: 13,
                                                  color: _kGreen,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'View Slip',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kGreen,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // 4. Amount
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

                                // 5. Description
                                DataCell(
                                  Container(
                                    constraints: BoxConstraints(
                                      minWidth: 160,
                                      maxWidth: constraints.maxWidth > 900
                                          ? constraints.maxWidth * 0.22
                                          : 220,
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

                                // 6. Date
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

                                // 7. Status Badge
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

                                // 8. Action Buttons
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
                                                  tx['tx_id'] ?? tx['id'],
                                                  amount,
                                                  memberName,
                                                  receiptUrl: receiptUrl,
                                                  method: method,
                                                  notes: tx['notes']?.toString(),
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
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _kRed,
                                            side: const BorderSide(color: _kRed),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: _actionLoading
                                              ? null
                                              : () => _rejectPayment(tx['tx_id'] ?? tx['id']),
                                          child: const Text(
                                            'Reject',
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

// ─────────────────────────────────────────────────────────────────────────────
// RECORD COUNTER / CASH PAYMENT MODAL DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _RecordCounterPaymentDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const _RecordCounterPaymentDialog({required this.onSuccess});

  @override
  State<_RecordCounterPaymentDialog> createState() => _RecordCounterPaymentDialogState();
}

class _RecordCounterPaymentDialogState extends State<_RecordCounterPaymentDialog> {
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _receiptNoController = TextEditingController();
  final _notesController = TextEditingController();

  List<dynamic> _members = [];
  bool _loadingMembers = true;
  Map<String, dynamic>? _selectedMember;

  List<Map<String, dynamic>> _platformFees = [];
  bool _loadingFees = false;
  String _feeSourceNotice = '';

  String _category = 'Annual Renewal Dues';
  String _paymentMethod = 'cash';
  bool _submitting = false;
  String? _errorMessage;
  Timer? _searchDebounce;

  static const List<Map<String, String>> _methods = [
    {'key': 'cash', 'label': 'Cash (Secretariat Counter)'},
    {'key': 'cheque', 'label': 'Cheque'},
    {'key': 'pos', 'label': 'POS Terminal / Debit Card'},
    {'key': 'bank_deposit', 'label': 'Direct Bank Counter Deposit'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _fetchPlatformFees();
  }

  Future<void> _fetchPlatformFees() async {
    if (mounted) setState(() => _loadingFees = true);
    try {
      final res = await ApiService().get('admin/fees');
      if (!mounted) return;
      if (res.statusCode == 200 && res.data != null && res.data is List) {
        setState(() {
          _platformFees = List<Map<String, dynamic>>.from(
            (res.data as List).map((x) => Map<String, dynamic>.from(x as Map))
          );
          _loadingFees = false;
        });
        if (_selectedMember != null) {
          _updateAmountForCategory(_category);
        }
      } else {
        setState(() => _loadingFees = false);
      }
    } catch (e, st) {
      AppLogger.error('record_counter_fees_fetch', e, st);
      if (mounted) setState(() => _loadingFees = false);
    }
  }

  Future<void> _fetchMembers({String query = ''}) async {
    if (mounted) setState(() => _loadingMembers = true);
    try {
      final qParam = query.trim().isNotEmpty ? '?q=${Uri.encodeComponent(query.trim())}' : '';
      final res = await ApiService().get(
        '/payments/admin/members-lookup$qParam',
        options: Options(validateStatus: (status) => status != null && status < 600),
      );
      if (!mounted) return;
      if (res.statusCode == 200 && res.data != null) {
        final list = (res.data['members'] as List<dynamic>?) ?? [];
        setState(() {
          _members = list;
          _loadingMembers = false;
        });
      } else {
        setState(() => _loadingMembers = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  List<String> get _categories {
    final list = <String>[
      'Annual Renewal Dues',
      'Registration Fee',
      'Subscription Fee',
      'Vetting & Dossier Verification Fee',
      'District / Branch Development Levy',
      'New Membership Package Fee',
    ];

    final mType = (_selectedMember?['member_type'] ?? 'corporate').toString().toLowerCase().trim();

    for (final f in _platformFees) {
      final label = f['label']?.toString().trim() ?? '';
      final section = (f['section'] ?? '').toString().toLowerCase().trim();

      final isCategoryMatch = (mType == 'associate' && section == 'associate') ||
          (mType == 'licentiate' && section == 'licentiate') ||
          (mType == 'corporate' && (section == 'new_membership' || section == 'corporate'));

      if (label.isNotEmpty && !list.contains(label) && (isCategoryMatch || section.isEmpty)) {
        list.add(label);
      }
    }

    list.addAll([
      'CTI Training / Course',
      'Statutory Processing / Service Fee',
      'General Dues / Other',
    ]);

    return list;
  }

  void _updateAmountForCategory(String category) {
    if (_selectedMember == null) return;

    final mType = (_selectedMember!['member_type'] ?? 'corporate').toString().toLowerCase().trim();
    final mTypeDisplay = mType == 'associate'
        ? 'Associate'
        : mType == 'licentiate'
            ? 'Licentiate'
            : 'Corporate';

    final appBill = double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ??
        double.tryParse(_selectedMember!['renewal_fee_amount']?.toString() ?? '') ?? 0.0;

    String notice = '';
    double? resolvedAmount;

    if (category == 'Annual Renewal Dues') {
      if (appBill > 0) {
        resolvedAmount = appBill;
        notice = 'Official Issued Renewal Bill: GH₵ ${appBill.toStringAsFixed(2)}';
      } else {
        final renewalItem = _platformFees.firstWhere(
          (f) => f['id'] == 'renewal_base_fee' || f['id'] == 'renewal_fee' || f['section'] == 'renewal',
          orElse: () => {},
        );
        if (renewalItem.isNotEmpty && renewalItem['amount'] != null) {
          resolvedAmount = double.tryParse(renewalItem['amount'].toString());
          notice = 'Platform Tariff (admin/fees): Renewal Fee';
        }
      }
    } else {
      Map<String, dynamic> matchedFee = {};

      for (final f in _platformFees) {
        final sec = (f['section'] ?? '').toString().toLowerCase().trim();
        final lbl = (f['label'] ?? '').toString().toLowerCase().trim();
        final catLower = category.toLowerCase().trim();

        final secMatch = (mType == 'associate' && sec == 'associate') ||
            (mType == 'licentiate' && sec == 'licentiate') ||
            (mType == 'corporate' && (sec == 'new_membership' || sec == 'corporate'));

        if (secMatch && (lbl == catLower || lbl.contains(catLower) || catLower.contains(lbl))) {
          matchedFee = f;
          break;
        }
      }

      if (matchedFee.isEmpty) {
        for (final f in _platformFees) {
          final lbl = (f['label'] ?? '').toString().toLowerCase().trim();
          final catLower = category.toLowerCase().trim();
          if (lbl == catLower || (catLower.length > 3 && lbl.contains(catLower))) {
            matchedFee = f;
            break;
          }
        }
      }

      if (matchedFee.isEmpty) {
        final catLower = category.toLowerCase();
        if (catLower.contains('registration') || catLower.contains('reg form')) {
          matchedFee = _platformFees.firstWhere(
            (f) => mType == 'associate'
                ? f['id'] == 'associate_reg_form_fee'
                : mType == 'licentiate'
                    ? f['id'] == 'licentiate_reg_form_fee'
                    : (f['id'] == 'reg_form_fee' || f['id'] == 'new_reg_fee'),
            orElse: () => {},
          );
        } else if (catLower.contains('subscription')) {
          matchedFee = _platformFees.firstWhere(
            (f) => mType == 'associate'
                ? f['id'] == 'associate_sub_fee'
                : mType == 'licentiate'
                    ? f['id'] == 'licentiate_sub_fee'
                    : f['id'] == 'new_sub_fee',
            orElse: () => {},
          );
        } else if (catLower.contains('vetting')) {
          matchedFee = _platformFees.firstWhere(
            (f) => mType == 'associate'
                ? f['id'] == 'associate_vetting_fee'
                : mType == 'licentiate'
                    ? f['id'] == 'licentiate_vetting_fee'
                    : f['id'] == 'new_vetting_fee',
            orElse: () => {},
          );
        } else if (catLower.contains('district') || catLower.contains('branch')) {
          matchedFee = _platformFees.firstWhere(
            (f) => mType == 'associate'
                ? f['id'] == 'associate_district_fee'
                : mType == 'licentiate'
                    ? f['id'] == 'licentiate_district_fee'
                    : f['id'] == 'new_district_fee',
            orElse: () => {},
          );
        } else if (catLower.contains('package') || catLower.contains('new membership dues')) {
          matchedFee = _platformFees.firstWhere(
            (f) => f['is_summary'] == true &&
                ((mType == 'associate' && f['section'] == 'associate') ||
                 (mType == 'licentiate' && f['section'] == 'licentiate') ||
                 (mType == 'corporate' && f['section'] == 'new_membership')),
            orElse: () => {},
          );
        }
      }

      if (matchedFee.isNotEmpty && matchedFee['amount'] != null) {
        resolvedAmount = double.tryParse(matchedFee['amount'].toString());
        final lbl = matchedFee['label']?.toString() ?? category;
        notice = 'Platform Fee (admin/fees): $lbl [$mTypeDisplay]';
      }
    }

    setState(() {
      if (resolvedAmount != null && resolvedAmount > 0) {
        _amountController.text = resolvedAmount.toStringAsFixed(2);
        _feeSourceNotice = notice;
      } else {
        _feeSourceNotice = 'Manual / Custom Entry [$mTypeDisplay]';
      }
    });
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchMembers(query: val);
    });
  }

  void _selectMember(Map<String, dynamic> member) {
    setState(() {
      _selectedMember = member;
      _errorMessage = null;

      final appBill = double.tryParse(member['app_bill_amount']?.toString() ?? '') ?? 0.0;
      final renewalFee = double.tryParse(member['renewal_fee_amount']?.toString() ?? '') ?? 0.0;
      final bill = appBill > 0 ? appBill : renewalFee;
      final isPkgPaid = member['package_fee_paid'] == true;

      if (bill > 0) {
        _category = 'Annual Renewal Dues';
      } else if (!isPkgPaid) {
        _category = 'Registration Fee';
      } else {
        _category = 'Annual Renewal Dues';
      }

      _updateAmountForCategory(_category);
    });
  }

  Future<void> _submitPayment() async {
    if (_selectedMember == null) {
      setState(() => _errorMessage = 'Please select a member first.');
      return;
    }

    final amountStr = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid payment amount greater than zero.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final payload = {
        'member_id': _selectedMember!['id'],
        'amount': amount,
        'description': _category,
        'payment_method': _paymentMethod,
        'receipt_no': _receiptNoController.text.trim(),
        'notes': _notesController.text.trim(),
        'application_id': _selectedMember!['renewal_app_id'],
      };

      final res = await ApiService().post('/payments/admin/record-counter', data: payload);
      if (!mounted) return;

      if (res.statusCode == 201 || res.statusCode == 200) {
        Navigator.of(context).pop();
        widget.onSuccess();
      } else {
        setState(() {
          _errorMessage = res.data?['message']?.toString() ?? 'Failed to record payment.';
          _submitting = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('record_counter_payment', e, st);
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error recording payment. Please try again.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextColor = isDark ? const Color(0xFF94a3b8) : const Color(0xFF64748b);
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFe2e8f0);
    final inputBg = isDark ? const Color(0xFF1A0F0A).withAlpha(120) : const Color(0xFFf8fafc);

    final appBill = _selectedMember != null
        ? (double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ??
           double.tryParse(_selectedMember!['renewal_fee_amount']?.toString() ?? '') ?? 0.0)
        : 0.0;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kGreen.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: _kGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Record Counter / Office Payment',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Over-the-counter settlement for dues, renewals, or fees',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: subTextColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kRed.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kRed.withAlpha(60)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: _kRed, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.outfit(
                                    color: _kRed,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ── Member Selection Section ─────────────────────────────
                      Text(
                        '1. SELECT MEMBER / CUSTOMER',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (_selectedMember == null) ...[
                        // Search bar
                        TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: GoogleFonts.outfit(fontSize: 14, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Search by member name, company, phone, license...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: subTextColor),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Member list
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: _loadingMembers
                              ? const Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 2))
                              : _members.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No matching members found.',
                                        style: GoogleFonts.inter(fontSize: 13, color: subTextColor),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _members.length,
                                      separatorBuilder: (_, index) => Divider(height: 1, color: borderColor.withAlpha(80)),
                                      itemBuilder: (ctx, idx) {
                                        final m = _members[idx] as Map<String, dynamic>;
                                        final name = m['name']?.toString() ?? 'Unknown Member';
                                        final company = m['company']?.toString() ?? '';
                                        final phone = m['phone']?.toString() ?? '';
                                        final lic = m['license_number']?.toString();
                                        final bill = double.tryParse(m['app_bill_amount']?.toString() ?? '') ??
                                            double.tryParse(m['renewal_fee_amount']?.toString() ?? '') ?? 0.0;
                                        final isPkgPaid = m['package_fee_paid'] == true;

                                        final mTypeRaw = (m['member_type']?.toString() ?? 'corporate').toLowerCase();
                                        final mTypeStr = mTypeRaw == 'associate'
                                            ? 'Associate'
                                            : mTypeRaw == 'licentiate'
                                                ? 'Licentiate'
                                                : 'Corporate';

                                        return ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: _kOrange.withAlpha(30),
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'M',
                                              style: GoogleFonts.outfit(
                                                color: _kOrange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: textColor,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: _kOrange.withAlpha(20),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: _kOrange.withAlpha(60)),
                                                ),
                                                child: Text(
                                                  mTypeStr.toUpperCase(),
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kOrange,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Text(
                                            [
                                              if (company.isNotEmpty) company,
                                              if (phone.isNotEmpty) phone,
                                              if (lic != null && lic.isNotEmpty) lic,
                                            ].join(' · '),
                                            style: GoogleFonts.inter(fontSize: 11, color: subTextColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: bill > 0
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _kAmber.withAlpha(25),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: _kAmber.withAlpha(80)),
                                                  ),
                                                  child: Text(
                                                    'Billed: GH₵ ${bill.toStringAsFixed(0)}',
                                                    style: GoogleFonts.outfit(
                                                      color: _kAmber,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                )
                                              : (!isPkgPaid
                                                  ? Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: _kBlue.withAlpha(25),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'New Member Dues',
                                                        style: GoogleFonts.outfit(
                                                          color: _kBlue,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    )
                                                  : null),
                                          onTap: () => _selectMember(m),
                                        );
                                      },
                                    ),
                        ),
                      ] else ...[
                        // Selected member card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _kGreen.withAlpha(15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _kGreen.withAlpha(60)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _kGreen,
                                child: Text(
                                  (_selectedMember!['name']?.toString() ?? 'M')[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedMember!['name']?.toString() ?? 'Member',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _kOrange.withAlpha(25),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: _kOrange.withAlpha(80)),
                                          ),
                                          child: Text(
                                            ((_selectedMember!['member_type'] ?? 'corporate').toString().toLowerCase() == 'associate'
                                                    ? 'Associate'
                                                    : (_selectedMember!['member_type'] ?? 'corporate').toString().toLowerCase() == 'licentiate'
                                                        ? 'Licentiate'
                                                        : 'Corporate')
                                                .toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _kOrange,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            [
                                              if (_selectedMember!['company'] != null) _selectedMember!['company'],
                                              if (_selectedMember!['phone'] != null) _selectedMember!['phone'],
                                              if (_selectedMember!['license_number'] != null)
                                                'Lic: ${_selectedMember!['license_number']}',
                                            ].join(' · '),
                                            style: GoogleFonts.inter(fontSize: 11.5, color: subTextColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedMember = null;
                                    _amountController.clear();
                                    _feeSourceNotice = '';
                                  });
                                  _fetchMembers();
                                },
                                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                label: const Text('Change'),
                                style: TextButton.styleFrom(
                                  foregroundColor: _kOrange,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // If member has official renewal bill, show quick fill action
                        if (appBill > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kAmber.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _kAmber.withAlpha(60)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.receipt_long_rounded, color: _kAmber, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Official Renewal Bill: GH₵ ${appBill.toStringAsFixed(2)}',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _category = 'Annual Renewal Dues';
                                      _amountController.text = appBill.toStringAsFixed(2);
                                      _feeSourceNotice = 'Official Issued Renewal Bill: GH₵ ${appBill.toStringAsFixed(2)}';
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: _kAmber),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: const Size(0, 28),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  child: Text(
                                    'Fill Full Bill',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _kAmber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 18),

                      // ── Payment Details Section ──────────────────────────────
                      Text(
                        '2. PAYMENT SPECIFICATIONS',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment Category Dropdown
                      DropdownButtonFormField<String>(
                        value: _categories.contains(_category)
                            ? _category
                            : (_categories.isNotEmpty ? _categories.first : 'Annual Renewal Dues'),
                        decoration: InputDecoration(
                          labelText: 'Payment Category / Dues Type',
                          labelStyle: GoogleFonts.outfit(color: subTextColor, fontSize: 13),
                          filled: true,
                          fillColor: inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        dropdownColor: cardBg,
                        items: _categories.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: GoogleFonts.outfit(fontSize: 14, color: textColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _category = v);
                            _updateAmountForCategory(v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Amount & Method Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Amount Paid (GH₵)',
                                    labelStyle: GoogleFonts.outfit(color: subTextColor, fontSize: 13),
                                    prefixText: 'GH₵ ',
                                    prefixStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _kGreen),
                                    filled: true,
                                    fillColor: inputBg,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                  ),
                                ),
                                if (_feeSourceNotice.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _kGreen.withAlpha(18),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _kGreen.withAlpha(50)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.verified_rounded, size: 13, color: _kGreen),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _feeSourceNotice,
                                            style: GoogleFonts.outfit(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: _kGreen,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 6,
                            child: DropdownButtonFormField<String>(
                              initialValue: _paymentMethod,
                              decoration: InputDecoration(
                                labelText: 'Payment Method',
                                labelStyle: GoogleFonts.outfit(color: subTextColor, fontSize: 13),
                                filled: true,
                                fillColor: inputBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                              dropdownColor: cardBg,
                              items: _methods.map((m) {
                                return DropdownMenuItem(
                                  value: m['key']!,
                                  child: Text(
                                    m['label']!,
                                    style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _paymentMethod = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Receipt / Cheque # field
                      TextFormField(
                        controller: _receiptNoController,
                        style: GoogleFonts.outfit(fontSize: 14, color: textColor),
                        decoration: InputDecoration(
                          labelText: 'Physical Receipt Book # / Cheque # (Optional)',
                          labelStyle: GoogleFonts.outfit(color: subTextColor, fontSize: 13),
                          hintText: 'e.g. RCP-2026-0048 or Cheque #4092 Zenith Bank',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: subTextColor.withAlpha(150)),
                          prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                          filled: true,
                          fillColor: inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Internal Notes field
                      TextFormField(
                        controller: _notesController,
                        style: GoogleFonts.outfit(fontSize: 14, color: textColor),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Administrative / Office Notes (Optional)',
                          labelStyle: GoogleFonts.outfit(color: subTextColor, fontSize: 13),
                          hintText: 'e.g. Paid in cash at front desk by company director.',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: subTextColor.withAlpha(150)),
                          filled: true,
                          fillColor: inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Automated Action Notice
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _kGreen.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kGreen.withAlpha(40)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.verified_rounded, color: _kGreen, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Automated Settlement: Upon recording, status will immediately become PAID. Any applicable license will be renewed for 1 year, and an official receipt email + push notification will be sent to the member automatically.',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textColor.withAlpha(200),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: subTextColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _submitting ? null : _submitPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _submitting ? 'Recording Payment...' : 'Confirm & Record Payment',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

