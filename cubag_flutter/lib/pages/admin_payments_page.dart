import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';
import '../components/cubag_ui.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kAmber = CubagColors.due;
const _kRed = CubagColors.lapsed;
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
  String _filterStatus = 'pending'; // open on the work waiting
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
          style: TextStyle(fontWeight: FontWeight.w600),
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
    final textColor = isDark ? CubagColors.sand : CubagColors.ink;

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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  Text(
                    '$memberName · GH₵ ${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: CubagColors.muted,
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
                  border: Border.all(color: CubagColors.lineStrong),
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
                              const Icon(Icons.broken_image_rounded, size: 40, color: Color(0xFF5F6B7E)),
                              const SizedBox(height: 10),
                              Text(
                                'Unable to load receipt image directly.\nClick "Open in new tab" above.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: CubagColors.muted),
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
                style: TextStyle(fontSize: 12, color: const Color(0xFF5F6B7E)),
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
        ? CubagColors.sand
        : CubagColors.ink;
    final subTextColor = isDark
        ? const Color(0xFF5F6B7E)
        : CubagColors.inkSoft;
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mark GHS ${amount.toStringAsFixed(2)} from $memberName as PAID / RECEIVED?\nThis automatically activates member standing and generates their official receipt.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subTextColor, fontSize: 14.5, height: 1.4),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: CubagColors.ink,
                                ),
                              ),
                              Text(
                                'Click to inspect full deposit receipt image',
                                style: TextStyle(fontSize: 12, color: CubagColors.muted),
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
                        style: TextStyle(
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
                        style: TextStyle(
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
        ? CubagColors.sand
        : CubagColors.ink;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.line;
    final subTextColor = isDark
        ? const Color(0xFF5F6B7E)
        : CubagColors.muted;
    final inputBg = isDark
        ? CubagColors.ink.withAlpha(120)
        : CubagColors.sand;

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
              style: TextStyle(
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
                            'Amount charged',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: subTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'GHS ${amount.toStringAsFixed(2)}',
                            style: TextStyle(
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
                          style: TextStyle(
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
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: CubagColors.ink,
                                  ),
                                ),
                                Text(
                                  'Click to preview high-resolution receipt',
                                  style: TextStyle(fontSize: 12, color: CubagColors.muted),
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
          style: TextStyle(
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
            style: TextStyle(
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

  // ── Layout ────────────────────────────────────────────────────────────────
  // Action first: the list opens on payments waiting to be verified. Each row
  // reads like a sentence (who, what for, how much, how) and carries its own
  // actions, so it works on a phone, a tablet and a laptop alike.

  static const _filters = [
    ('pending', 'To verify'),
    ('paid', 'Paid'),
    ('failed', 'Rejected'),
    ('all', 'All'),
  ];

  String _money(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'GH₵ $whole.${parts[1]}';
  }

  String _shortDate(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  (String, StatusKind) _statusOf(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'success':
      case 'successful':
      case 'completed':
        return ('Paid', StatusKind.good);
      case 'pending':
      case 'processing':
      case 'submitted':
        return ('To verify', StatusKind.pending);
      case 'rejected':
        return ('Rejected', StatusKind.bad);
      case 'failed':
      case 'cancelled':
        return ('Failed', StatusKind.bad);
      case 'overdue':
        return ('Overdue', StatusKind.bad);
      default:
        return (status.isEmpty ? 'Unknown' : status, StatusKind.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final revenue = double.tryParse(_kpis['revenue']?.toString() ?? '0') ?? 0;
    // The server reports these as money totals (GH₵), not counts.
    final pending = double.tryParse(_kpis['pending']?.toString() ?? '0') ?? 0;
    final failed = double.tryParse(_kpis['failed']?.toString() ?? '0') ?? 0;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return AppLayout(
      title: 'Payments',
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
                  runSpacing: CubagSpace.md,
                  spacing: CubagSpace.md,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: const PageIntro(
                        'Payments',
                        subtitle: 'Check each slip against your bank or MoMo statement, then confirm or reject it.',
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: () => _fetch(refresh: true),
                          icon: const Icon(Icons.refresh_rounded, color: CubagColors.inkSoft),
                        ),
                        const SizedBox(width: CubagSpace.xs),
                        FilledButton.icon(
                          onPressed: _showRecordCounterPaymentModal,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Record counter payment'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CubagSpace.lg),
                _summary(revenue, pending, failed, wide),
                const SizedBox(height: CubagSpace.lg),
                _toolbar(wide),
                const SizedBox(height: CubagSpace.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator(color: CubagColors.action)),
                  )
                else if (_hasError && _transactions.isEmpty)
                  FetchErrorView(onRetry: () => _fetch(refresh: true))
                else if (_transactions.isEmpty)
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
                        for (var i = 0; i < _transactions.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: CubagColors.line),
                          _row(Map<String, dynamic>.from(_transactions[i] as Map), wide),
                        ],
                      ],
                    ),
                  ),
                if (!_loading && (_page > 1 || _hasMore)) ...[
                  const SizedBox(height: CubagSpace.md),
                  Row(
                    children: [
                      Text(
                        _total > 0 ? 'Page $_page of ${(_total / 25).ceil()} · $_total payments' : 'Page $_page',
                        style: CubagType.small,
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _page > 1 ? () => _fetch(page: _page - 1) : null,
                        child: const Text('Previous'),
                      ),
                      const SizedBox(width: CubagSpace.sm),
                      OutlinedButton(
                        onPressed: _hasMore ? () => _fetch(page: _page + 1) : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(double revenue, double pending, double failed, bool wide) {
    Widget figure(String label, String value, {Color color = CubagColors.ink, VoidCallback? onTap}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: CubagSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CubagType.small),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: CubagType.title.copyWith(color: color)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            figure('Received', _money(revenue)),
            const VerticalDivider(width: 1, color: CubagColors.line),
            figure(
              'Waiting to verify',
              _money(pending),
              color: pending > 0 ? CubagColors.due : CubagColors.ink,
              onTap: () => _setFilter('pending'),
            ),
            const VerticalDivider(width: 1, color: CubagColors.line),
            figure('Rejected or failed', _money(failed), onTap: () => _setFilter('failed')),
          ],
        ),
      ),
    );
  }

  void _setFilter(String value) {
    if (_filterStatus == value) return;
    setState(() {
      _filterStatus = value;
      _page = 1;
    });
    _fetch(refresh: true);
  }

  Widget _toolbar(bool wide) {
    final tabs = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [for (final f in _filters) ButtonSegment(value: f.$1, label: Text(f.$2))],
      selected: {_filterStatus == 'overdue' ? 'failed' : _filterStatus},
      onSelectionChanged: (s) => _setFilter(s.first),
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
        hintText: 'Search by name, reference or purpose',
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
    final (title, body) = switch (_filterStatus) {
      'pending' => ('Nothing to verify', 'New bank and MoMo slips from members will appear here.'),
      'paid' => ('No confirmed payments yet', 'Payments appear here once you confirm them.'),
      'failed' => ('No rejected payments', 'Payments you reject, or that fail, appear here.'),
      _ => ('No payments found', 'Try a different search.'),
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
          const Icon(Icons.check_circle_outline_rounded, size: 36, color: CubagColors.muted),
          const SizedBox(height: CubagSpace.sm),
          Text(title, style: CubagType.bodyStrong),
          const SizedBox(height: 4),
          Text(body, style: CubagType.small, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> tx, bool wide) {
    final id = tx['tx_id'] ?? tx['id'];
    final rawStatus = tx['status']?.toString() ?? 'pending';
    final (statusLabel, statusKind) = _statusOf(rawStatus);
    final isPending = statusKind == StatusKind.pending;
    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
    final member = tx['member_name']?.toString() ?? 'Member';
    final purpose = (tx['description']?.toString() ?? '').trim();
    final date = _shortDate(tx['date']?.toString() ?? tx['created_at']?.toString() ?? '');
    final method = (tx['payment_method'] ?? 'momo').toString().toLowerCase();
    final methodLabel = switch (method) {
      'bank' || 'bank_transfer' || 'wire' => 'Bank transfer',
      'cash' || 'counter' => 'Counter',
      'card' => 'Card',
      _ => 'MoMo',
    };
    final ref = [tx['momo_tx_id'], tx['payment_ref'], tx['ref_code']]
        .map((v) => v?.toString().trim() ?? '')
        .firstWhere((v) => v.isNotEmpty && v != 'null', orElse: () => '');
    final receiptUrl = tx['receipt_url']?.toString();
    final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(member, style: CubagType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          purpose.isEmpty ? 'Payment' : purpose,
          style: CubagType.body.copyWith(color: CubagColors.inkSoft),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          [methodLabel, date, if (ref.isNotEmpty) 'Ref $ref'].join(' · '),
          style: CubagType.small,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final amountBlock = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(_money(amount), style: CubagType.bodyStrong.copyWith(fontSize: 16)),
        const SizedBox(height: 4),
        StatusChip(statusLabel, kind: statusKind),
      ],
    );

    final actions = Wrap(
      spacing: CubagSpace.sm,
      runSpacing: CubagSpace.xs,
      alignment: WrapAlignment.end,
      children: [
        if (hasReceipt)
          TextButton.icon(
            onPressed: () => _showReceiptDialog(receiptUrl, member, amount, date, txId: id, isPending: isPending),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('View slip'),
          ),
        if (isPending) ...[
          OutlinedButton(
            onPressed: _actionLoading ? null : () => _confirmReject(id, member),
            style: OutlinedButton.styleFrom(foregroundColor: CubagColors.lapsed),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: _actionLoading
                ? null
                : () => _showConfirmDialog(
                      id,
                      amount,
                      member,
                      receiptUrl: receiptUrl,
                      method: method,
                      notes: tx['notes']?.toString(),
                    ),
            child: const Text('Confirm'),
          ),
        ] else
          TextButton(onPressed: () => _showDetailModal(tx), child: const Text('Details')),
      ],
    );

    return InkWell(
      onTap: () => _showDetailModal(tx),
      child: Padding(
        padding: const EdgeInsets.all(CubagSpace.md),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: CubagSpace.md),
                  amountBlock,
                  const SizedBox(width: CubagSpace.lg),
                  ConstrainedBox(constraints: const BoxConstraints(minWidth: 220), child: actions),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: CubagSpace.sm),
                      amountBlock,
                    ],
                  ),
                  const SizedBox(height: CubagSpace.sm),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmReject(dynamic id, String member) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$member will be told the payment was not accepted.', style: CubagType.body),
            const SizedBox(height: CubagSpace.md),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (shown to the member)',
                hintText: 'e.g. Amount on slip does not match',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CubagColors.lapsed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject payment'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok == true) await _rejectPayment(id, reason: text.isEmpty ? null : text);
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
  String _feeSourceNotice = '';

  String _category = 'Annual Renewal Dues';
  String _paymentMethod = 'cash';
  bool _submitting = false;
  String? _errorMessage;
  Timer? _searchDebounce;

  static const List<Map<String, String>> _methods = [
    {'key': 'cash', 'label': 'Cash (Secretariat Counter)'},
    {'key': 'momo', 'label': 'Mobile Money (MTN / Telecel / AT MoMo)'},
    {'key': 'cheque', 'label': 'Cheque'},
    {'key': 'pos', 'label': 'POS Terminal / Debit Card'},
    {'key': 'bank_deposit', 'label': 'Direct Bank Counter Deposit'},
  ];

  bool _isInstallment = false;
  final _installmentNumberCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _fetchPlatformFees();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _amountController.dispose();
    _receiptNoController.dispose();
    _notesController.dispose();
    _installmentNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPlatformFees() async {
    try {
      final res = await ApiService().get('admin/fees');
      if (!mounted) return;
      if (res.statusCode == 200 && res.data != null && res.data is List) {
        setState(() {
          _platformFees = List<Map<String, dynamic>>.from(
            (res.data as List).map((x) => Map<String, dynamic>.from(x as Map))
          );
        });
        if (_selectedMember != null) {
          _updateAmountForCategory(_category);
        }
      }
    } catch (e, st) {
      AppLogger.error('record_counter_fees_fetch', e, st);
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
      'Vetting & Document Verification Fee',
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

  bool _isCategoryAlreadyPaid(String category) {
    if (_isInstallment) return false;
    if (_selectedMember == null) return false;
    final catLower = category.toLowerCase().trim();

    // 1. Registration / Package
    if (catLower.contains('registration') || catLower.contains('entrance') || catLower.contains('package')) {
      if (_selectedMember!['package_fee_paid'] == true || _selectedMember!['registration_fee_paid'] == true) {
        return true;
      }
    }

    // 2. Annual Renewal
    if (catLower.contains('renewal') || catLower.contains('annual dues')) {
      final appBill = double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ?? 0.0;
      final appPaid = double.tryParse(_selectedMember!['app_amount_paid']?.toString() ?? '') ?? 0.0;
      if (appBill > 0 && appPaid >= appBill) {
        return true;
      }
      if (_selectedMember!['renewal_paid_this_year'] == true || _selectedMember!['renewal_approved_this_year'] == true) {
        return true;
      }
    }

    // 3. Paid descriptions from DB
    final paidDescs = (_selectedMember!['paid_descriptions'] as List<dynamic>?) ?? [];
    for (final d in paidDescs) {
      final dLower = d.toString().toLowerCase().trim();
      if (dLower == catLower || (catLower.length > 5 && dLower.contains(catLower))) {
        return true;
      }
    }

    return false;
  }

  void _updateAmountForCategory(String category) {
    if (_selectedMember == null) return;

    if (_isCategoryAlreadyPaid(category)) {
      setState(() {
        _amountController.clear();
        _feeSourceNotice = '⚠️ ALREADY SETTLED: Member has already paid for "$category".';
      });
      return;
    }

    final mType = (_selectedMember!['member_type'] ?? 'corporate').toString().toLowerCase().trim();
    final mTypeDisplay = 'Corporate';

    final appBill = double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ??
        double.tryParse(_selectedMember!['renewal_fee_amount']?.toString() ?? '') ?? 0.0;
    final appPaid = double.tryParse(_selectedMember!['app_amount_paid']?.toString() ?? '') ?? 0.0;
    final remainingBill = appBill > 0 ? (appBill - appPaid).clamp(0.0, appBill) : 0.0;

    String notice = '';
    double? resolvedAmount;

    if (category == 'Annual Renewal Dues') {
      if (remainingBill > 0) {
        resolvedAmount = remainingBill;
        notice = 'Outstanding Renewal Bill Balance: GH₵ ${remainingBill.toStringAsFixed(2)}';
      } else if (appBill > 0 && remainingBill <= 0) {
        resolvedAmount = 0.0;
        notice = 'Official Renewal Bill (GH₵ ${appBill.toStringAsFixed(2)}) is ALREADY FULLY PAID ✓';
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

      final isRegPaid = member['package_fee_paid'] == true || member['registration_fee_paid'] == true;
      final appBill = double.tryParse(member['app_bill_amount']?.toString() ?? '') ?? 0.0;
      final appPaid = double.tryParse(member['app_amount_paid']?.toString() ?? '') ?? 0.0;
      final isRenewalPaid = (appBill > 0 && appPaid >= appBill) ||
          member['renewal_paid_this_year'] == true ||
          member['renewal_approved_this_year'] == true;

      final remainingBill = appBill - appPaid;

      if (remainingBill > 0 && !isRenewalPaid) {
        _category = 'Annual Renewal Dues';
      } else if (!isRegPaid) {
        _category = 'Registration Fee';
      } else if (!isRenewalPaid) {
        _category = 'Annual Renewal Dues';
      } else {
        _category = 'Statutory Processing / Service Fee';
      }

      _updateAmountForCategory(_category);
    });
  }

  Future<void> _submitPayment() async {
    if (_selectedMember == null) {
      setState(() => _errorMessage = 'Please select a member first.');
      return;
    }

    if (_isCategoryAlreadyPaid(_category)) {
      setState(() {
        _errorMessage = "Member '${_selectedMember!['name']}' has already paid for '$_category'. Duplicate payment is not allowed.";
      });
      return;
    }

    final amountStr = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid payment amount greater than zero.');
      return;
    }

    final appBill = double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ?? 0.0;
    final appPaid = double.tryParse(_selectedMember!['app_amount_paid']?.toString() ?? '') ?? 0.0;
    if (_category == 'Annual Renewal Dues' && appBill > 0) {
      final remaining = (appBill - appPaid).clamp(0.0, appBill);
      if (amount > (remaining + 0.01)) {
        setState(() => _errorMessage = 'Payment amount of GH₵ ${amount.toStringAsFixed(2)} exceeds the remaining bill balance of GH₵ ${remaining.toStringAsFixed(2)}.');
        return;
      }
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
        'is_installment': _isInstallment,
        'installment_number': int.tryParse(_installmentNumberCtrl.text.trim()) ?? 1,
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
    final textColor = isDark ? CubagColors.sand : CubagColors.ink;
    final subTextColor = isDark ? const Color(0xFF5F6B7E) : CubagColors.muted;
    final borderColor = isDark ? const Color(0xFF4D2D20) : CubagColors.line;
    final inputBg = isDark ? CubagColors.ink.withAlpha(120) : CubagColors.sand;

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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Over-the-counter settlement for dues, renewals, or fees',
                          style: TextStyle(
                            fontSize: 12,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
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
                                  style: TextStyle(
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
                        '1. Select member / customer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (_selectedMember == null) ...[
                        // Search bar
                        TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: TextStyle(fontSize: 14, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Search by member name, company, phone, license...',
                            hintStyle: TextStyle(fontSize: 13, color: subTextColor),
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
                                        style: TextStyle(fontSize: 13, color: subTextColor),
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

                                        const mTypeStr = 'Corporate';

                                        return ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: _kOrange.withAlpha(30),
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'M',
                                              style: TextStyle(
                                                color: AppColors.accentOrangeText,
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
                                                  style: TextStyle(
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
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.accentOrangeText,
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
                                            style: TextStyle(fontSize: 11, color: subTextColor),
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
                                                    style: TextStyle(
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
                                                        style: TextStyle(
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
                                  style: TextStyle(
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
                                      style: TextStyle(
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
                                            'Corporate',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.accentOrangeText,
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
                                            style: TextStyle(fontSize: 11.5, color: subTextColor),
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

                        // Member Settlement Status Summary
                        if (_selectedMember != null) ...[
                          const SizedBox(height: 8),
                          _buildMemberStandingSummary(isDark, textColor, subTextColor),
                        ],

                        // If member has official renewal bill, show quick fill action (only if remaining > 0)
                        if (appBill > 0) ...[
                          const SizedBox(height: 8),
                          Builder(builder: (ctx) {
                            final appPaid = double.tryParse(_selectedMember!['app_amount_paid']?.toString() ?? '') ?? 0.0;
                            final remaining = (appBill - appPaid).clamp(0.0, appBill);
                            final isFullyPaid = remaining <= 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: (isFullyPaid ? _kGreen : _kAmber).withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: (isFullyPaid ? _kGreen : _kAmber).withAlpha(60)),
                              ),
                              child: Row(
                                children: [
                                  Icon(isFullyPaid ? Icons.check_circle_rounded : Icons.receipt_long_rounded,
                                      color: isFullyPaid ? _kGreen : _kAmber, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isFullyPaid
                                          ? 'Official Renewal Bill: GH₵ ${appBill.toStringAsFixed(2)} (Fully Settled ✓)'
                                          : 'Renewal Bill: GH₵ ${appBill.toStringAsFixed(2)} (Remaining: GH₵ ${remaining.toStringAsFixed(2)})',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  if (!isFullyPaid)
                                    OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _category = 'Annual Renewal Dues';
                                          _amountController.text = remaining.toStringAsFixed(2);
                                          _feeSourceNotice = 'Outstanding Renewal Bill: GH₵ ${remaining.toStringAsFixed(2)}';
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: _kAmber),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: const Size(0, 28),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      child: Text(
                                        'Fill Remaining',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _kAmber,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],

                      const SizedBox(height: 18),

                      // ── Payment Details Section ──────────────────────────────
                      Text(
                        '2. Payment specifications',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment Category Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _categories.contains(_category)
                            ? _category
                            : (_categories.isNotEmpty ? _categories.first : 'Annual Renewal Dues'),
                        decoration: InputDecoration(
                          labelText: 'Payment Category / Dues Type',
                          labelStyle: TextStyle(color: subTextColor, fontSize: 13),
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
                          final isPaid = _isCategoryAlreadyPaid(c);
                          return DropdownMenuItem(
                            value: c,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isPaid ? (isDark ? Colors.white38 : Colors.grey.shade500) : textColor,
                                      fontWeight: isPaid ? FontWeight.normal : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isPaid) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _kGreen.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _kGreen.withAlpha(80)),
                                    ),
                                    child: Text(
                                      'Paid ✓',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: _kGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
                      if (_isCategoryAlreadyPaid(_category)) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _kRed.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kRed.withAlpha(50)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: _kRed, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This member has already paid for "$_category". Duplicate payment is blocked.',
                                  style: TextStyle(color: _kRed, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Amount Paid (GH₵)',
                                    labelStyle: TextStyle(color: subTextColor, fontSize: 13),
                                    prefixText: 'GH₵ ',
                                    prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: _kGreen),
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
                                            style: TextStyle(
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
                                labelStyle: TextStyle(color: subTextColor, fontSize: 13),
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
                                    style: TextStyle(fontSize: 13, color: textColor),
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

                      // Installment / Part Payment toggle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isInstallment ? _kOrange.withAlpha(20) : inputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isInstallment ? _kOrange : borderColor,
                            width: _isInstallment ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _isInstallment,
                              activeColor: _kOrange,
                              onChanged: (val) {
                                setState(() {
                                  _isInstallment = val ?? false;
                                  if (_isInstallment && _errorMessage != null && _errorMessage!.contains('already paid')) {
                                    _errorMessage = null;
                                  }
                                });
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Record as Installment / Part Payment',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    'Allows recording partial amounts towards dues or license fees',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: subTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isInstallment) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 85,
                                child: TextFormField(
                                  controller: _installmentNumberCtrl,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                  decoration: InputDecoration(
                                    labelText: 'Part #',
                                    labelStyle: TextStyle(fontSize: 11, color: subTextColor),
                                    prefixText: '#',
                                    prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentOrangeText),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    filled: true,
                                    fillColor: cardBg,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Receipt / Cheque # field
                      TextFormField(
                        controller: _receiptNoController,
                        style: TextStyle(fontSize: 14, color: textColor),
                        decoration: InputDecoration(
                          labelText: 'Physical Receipt Book # / Cheque # (Optional)',
                          labelStyle: TextStyle(color: subTextColor, fontSize: 13),
                          hintText: 'e.g. RCP-2026-0048 or Cheque #4092 Zenith Bank',
                          hintStyle: TextStyle(fontSize: 12, color: subTextColor.withAlpha(150)),
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
                        style: TextStyle(fontSize: 14, color: textColor),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Administrative / Office Notes (Optional)',
                          labelStyle: TextStyle(color: subTextColor, fontSize: 13),
                          hintText: 'e.g. Paid in cash at front desk by company director.',
                          hintStyle: TextStyle(fontSize: 12, color: subTextColor.withAlpha(150)),
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
                                style: TextStyle(
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
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_submitting || _isCategoryAlreadyPaid(_category)) ? null : _submitPayment,
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
                      _submitting
                          ? 'Recording Payment...'
                          : (_isCategoryAlreadyPaid(_category) ? 'Category Already Paid' : 'Confirm & Record Payment'),
                      style: TextStyle(
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

  Widget _buildMemberStandingSummary(bool isDark, Color textColor, Color subTextColor) {
    if (_selectedMember == null) return const SizedBox.shrink();

    final isRegPaid = _selectedMember!['package_fee_paid'] == true || _selectedMember!['registration_fee_paid'] == true;
    final appBill = double.tryParse(_selectedMember!['app_bill_amount']?.toString() ?? '') ?? 0.0;
    final appPaid = double.tryParse(_selectedMember!['app_amount_paid']?.toString() ?? '') ?? 0.0;
    final isRenewalPaid = (appBill > 0 && appPaid >= appBill) ||
        _selectedMember!['renewal_paid_this_year'] == true ||
        _selectedMember!['renewal_approved_this_year'] == true;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E140E) : const Color(0xFFF8F5F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF3D261C) : CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: subTextColor),
              const SizedBox(width: 6),
              Text(
                'Member settlement status',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: subTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildMiniStatusChip('Registration / Package', isRegPaid),
              _buildMiniStatusChip('Annual Renewal Dues', isRenewalPaid),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusChip(String label, bool isPaid) {
    final color = isPaid ? _kGreen : _kOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPaid ? Icons.check_circle_rounded : Icons.pending_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ${isPaid ? "Paid ✓" : "Outstanding"}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

