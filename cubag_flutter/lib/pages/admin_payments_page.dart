import '../components/admin_list.dart';
import '../components/admin_dialog.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';
import '../components/cubag_ui.dart';

const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

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

  void _showIssueBillModal([Map<String, dynamic>? member]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IssueBillDialog(
        initialMember: member,
        onSuccess: () {
          _showToast('Official bill issued and dispatched successfully!');
          _fetch(refresh: true);
        },
      ),
    );
  }

  Future<void> _showReceiptDialog(
    String receiptUrl,
    String memberName,
    double amount,
    String date, {
    dynamic txId,
    bool isPending = false,
  }) async {
    final fullUrl = _resolveReceiptUrl(receiptUrl);
    // SEC-04: receipts live in private storage; view through a signed link.
    final signedUrl = await ApiService.signedDocumentUrl(fullUrl);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: 'Bank slip',
        subtitle: '$memberName · GH₵ ${amount.toStringAsFixed(2)}${date.isEmpty ? '' : ' · $date'}',
        maxWidth: 720,
        actions: [
          TextButton.icon(
            onPressed: () async => launchUrl(
              Uri.parse(await ApiService.signedDocumentUrl(fullUrl)),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open in a new tab'),
          ),
          if (isPending && txId != null) ...[
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmReject(txId, memberName);
              },
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _markPaid(txId);
              },
              child: const Text('Confirm payment'),
            ),
          ] else
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 480),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: CubagColors.sand,
              borderRadius: BorderRadius.circular(CubagRadius.card),
            ),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                signedUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, p) =>
                    p == null ? child : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (context, e, s) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Could not show the slip here. Use Open in a new tab.', textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CubagSpace.xs),
          Text('Pinch or scroll to zoom. Check the amount and reference against the bank statement.', style: CubagType.caption),
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
    final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';
    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: 'Confirm this payment?',
        subtitle: 'Only confirm after you have seen the money in CUBAG\'s account.',
        maxWidth: 480,
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: _actionLoading
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    _markPaid(txId);
                  },
            child: const Text('Confirm payment'),
          ),
        ],
        children: [
          AdminDetailRow('From', memberName),
          AdminDetailRow('Amount', 'GH₵ ${amount.toStringAsFixed(2)}'),
          if ((method ?? '').isNotEmpty) AdminDetailRow('Paid by', _methodLabel(method)),
          if ((notes ?? '').isNotEmpty && notes != 'null') AdminDetailRow('Member\'s note', notes!),
          const SizedBox(height: CubagSpace.sm),
          Text(
            'The payment is marked as paid, the member\'s standing updates and their receipt is issued.',
            style: CubagType.small,
          ),
          if (hasReceipt) ...[
            const SizedBox(height: CubagSpace.md),
            OutlinedButton.icon(
              onPressed: () => _showReceiptDialog(receiptUrl, memberName, amount, '', txId: txId, isPending: true),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Look at the bank slip first'),
            ),
          ],
        ],
      ),
    );
  }

  String _methodLabel(String? m) => switch ((m ?? '').toLowerCase()) {
        'bank' || 'bank_transfer' => 'Bank deposit or transfer',
        'momo' || 'mobile_money' => 'Mobile Money',
        'cash' => 'Cash at the office',
        'cheque' => 'Cheque',
        _ => (m ?? '').isEmpty ? '—' : m!,
      };

  void _showDetailModal(Map<String, dynamic> tx) {
    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
    final status = (tx['status']?.toString() ?? '').toLowerCase();
    final paymentMethod = (tx['payment_method'] ?? 'momo').toString();
    final receiptUrl = tx['receipt_url']?.toString();
    final hasReceipt = receiptUrl != null && receiptUrl.isNotEmpty && receiptUrl != 'null';
    final member = tx['member_name']?.toString() ?? '';
    String v(String k) {
      final x = tx[k]?.toString() ?? '';
      return x == 'null' ? '' : x;
    }

    final (label, kind) = switch (status) {
      'paid' || 'completed' || 'success' || 'successful' => ('Paid', StatusKind.good),
      'failed' || 'rejected' || 'cancelled' => ('Not paid', StatusKind.bad),
      _ => ('Waiting to verify', StatusKind.pending),
    };

    showDialog(
      context: context,
      builder: (ctx) => AdminDialog(
        title: 'GH₵ ${amount.toStringAsFixed(2)}',
        subtitle: [member, v('description')].where((s) => s.isNotEmpty).join(' · '),
        actions: [
          if (status == 'pending') ...[
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmReject(tx['tx_id'] ?? tx['id'], member);
              },
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showConfirmDialog(
                  tx['tx_id'] ?? tx['id'],
                  amount,
                  member,
                  receiptUrl: receiptUrl,
                  method: paymentMethod,
                  notes: tx['notes']?.toString(),
                );
              },
              child: const Text('Confirm payment'),
            ),
          ] else
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
        children: [
          Align(alignment: Alignment.centerLeft, child: StatusChip(label, kind: kind)),
          const SizedBox(height: CubagSpace.md),
          AdminDetailRow('Member', member),
          AdminDetailRow('For', v('description')),
          AdminDetailRow('Paid by', _methodLabel(paymentMethod)),
          if (v('payment_ref').isNotEmpty) AdminDetailRow('Reference', v('payment_ref')),
          if (v('tx_id').isNotEmpty) AdminDetailRow('Transaction', v('tx_id')),
          if (v('notes').isNotEmpty) AdminDetailRow('Member\'s note', v('notes')),
          AdminDetailRow('Date', v('date').isNotEmpty ? v('date') : v('created_at')),
          if (hasReceipt) ...[
            const SizedBox(height: CubagSpace.md),
            OutlinedButton.icon(
              onPressed: () => _showReceiptDialog(receiptUrl, member, amount, v('date'),
                  txId: tx['tx_id'] ?? tx['id'], isPending: status == 'pending'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Look at the bank slip'),
            ),
          ],
        ],
      ),
    );
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
                        OutlinedButton.icon(
                          onPressed: () => _showIssueBillModal(),
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: const Text('Issue bill'),
                        ),
                        const SizedBox(width: CubagSpace.xs),
                        FilledButton.icon(
                          onPressed: _showRecordCounterPaymentModal,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Record office payment'),
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
      builder: (ctx) => AdminDialog(
        title: 'Reject this payment?',
        subtitle: member.isEmpty ? null : 'From $member. They are told it was not accepted and why.',
        maxWidth: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CubagColors.lapsed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject payment'),
          ),
        ],
        children: [
          AdminField(
            label: 'Reason (the member sees it)',
            child: TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'For example: The amount on the slip does not match'),
            ),
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

  static const _methodLabels = {
    'cash': 'Cash at the office',
    'momo': 'Mobile Money',
    'cheque': 'Cheque',
    'pos': 'Card (POS)',
    'bank_deposit': 'Bank deposit',
  };

  @override
  Widget build(BuildContext context) {
    final m = _selectedMember;
    final appBill = m != null
        ? (double.tryParse(m['app_bill_amount']?.toString() ?? '') ??
            double.tryParse(m['renewal_fee_amount']?.toString() ?? '') ??
            0.0)
        : 0.0;
    final alreadyPaid = m != null && _isCategoryAlreadyPaid(_category);

    return AdminDialog(
      title: 'Record an office payment',
      subtitle: 'For money received at the office: cash, cheque, card, bank deposit or Mobile Money paid in person.',
      maxWidth: 620,
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_submitting || m == null || alreadyPaid) ? null : _submitPayment,
          child: Text(_submitting ? 'Recording…' : (alreadyPaid ? 'Already paid' : 'Record payment')),
        ),
      ],
      children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(CubagSpace.sm),
            decoration: BoxDecoration(color: CubagColors.lapsedTint, borderRadius: BorderRadius.circular(CubagRadius.control)),
            child: Text(_errorMessage!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
          ),
          const SizedBox(height: CubagSpace.md),
        ],
        Text('1. Who paid', style: CubagType.headline),
        const SizedBox(height: CubagSpace.sm),
        if (m == null) ...[
          AdminSearchField(
            hint: 'Search name, company, phone or licence number',
            controller: _searchController,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: CubagSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: _loadingMembers
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                : _members.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(CubagSpace.lg),
                        child: Text('No member matches.', style: CubagType.small, textAlign: TextAlign.center),
                      )
                    : SingleChildScrollView(
                        child: AdminRowGroup(
                          dividerIndent: 68,
                          children: [
                            for (final raw in _members)
                              () {
                                final x = Map<String, dynamic>.from(raw as Map);
                                final name = x['name']?.toString() ?? 'Member';
                                final bill = double.tryParse(x['app_bill_amount']?.toString() ?? '') ??
                                    double.tryParse(x['renewal_fee_amount']?.toString() ?? '') ??
                                    0.0;
                                return AdminListRow(
                                  leading: AdminRowMark(initials: adminInitials(name)),
                                  title: name,
                                  subtitle: [
                                    if ((x['company'] ?? '').toString().isNotEmpty) x['company'].toString(),
                                    if ((x['phone'] ?? '').toString().isNotEmpty) x['phone'].toString(),
                                  ].join(' · '),
                                  meta: (x['license_number'] ?? '').toString().isEmpty ? null : 'Licence ${x['license_number']}',
                                  status: bill > 0
                                      ? StatusChip('Bill GH₵ ${bill.toStringAsFixed(0)}', kind: StatusKind.pending)
                                      : (x['package_fee_paid'] == true ? null : const StatusChip('New member', kind: StatusKind.pending)),
                                  onTap: () => _selectMember(x),
                                );
                              }(),
                          ],
                        ),
                      ),
          ),
        ] else ...[
          AdminRowGroup(
            children: [
              AdminListRow(
                leading: AdminRowMark(initials: adminInitials(m['name']?.toString() ?? '')),
                title: m['name']?.toString() ?? 'Member',
                subtitle: [
                  if (m['company'] != null) m['company'].toString(),
                  if (m['phone'] != null) m['phone'].toString(),
                ].join(' · '),
                meta: m['license_number'] == null ? null : 'Licence ${m['license_number']}',
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedMember = null;
                      _amountController.clear();
                      _feeSourceNotice = '';
                    });
                    _fetchMembers();
                  },
                  child: const Text('Change'),
                ),
              ),
            ],
          ),
          const SizedBox(height: CubagSpace.sm),
          _buildMemberStandingSummary(false, CubagColors.ink, CubagColors.muted),
          if (appBill > 0)
            Builder(builder: (ctx) {
              final appPaid = double.tryParse(m['app_amount_paid']?.toString() ?? '') ?? 0.0;
              final remaining = (appBill - appPaid).clamp(0.0, appBill);
              return Padding(
                padding: const EdgeInsets.only(top: CubagSpace.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        remaining <= 0
                            ? 'Renewal bill GH₵ ${appBill.toStringAsFixed(2)}: fully paid'
                            : 'Renewal bill GH₵ ${appBill.toStringAsFixed(2)}: GH₵ ${remaining.toStringAsFixed(2)} still to pay',
                        style: CubagType.small.copyWith(color: CubagColors.ink),
                      ),
                    ),
                    if (remaining > 0)
                      TextButton(
                        onPressed: () => setState(() {
                          _category = 'Annual Renewal Dues';
                          _amountController.text = remaining.toStringAsFixed(2);
                          _feeSourceNotice = 'The rest of the renewal bill.';
                        }),
                        child: const Text('Use this amount'),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: CubagSpace.xl),
          Text('2. What they paid', style: CubagType.headline),
          const SizedBox(height: CubagSpace.sm),
          AdminField(
            label: 'For',
            child: DropdownMenu<String>(
              key: ValueKey('cat-${m['id']}'),
              initialSelection: _categories.contains(_category)
                  ? _category
                  : (_categories.isNotEmpty ? _categories.first : 'Annual Renewal Dues'),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final c in _categories)
                  DropdownMenuEntry(value: c, label: _isCategoryAlreadyPaid(c) ? '$c (already paid)' : c),
              ],
              onSelected: (v) {
                if (v != null) {
                  setState(() => _category = v);
                  _updateAmountForCategory(v);
                }
              },
            ),
          ),
          if (alreadyPaid)
            Padding(
              padding: const EdgeInsets.only(bottom: CubagSpace.md),
              child: Text(
                'This member has already paid for "$_category", so it cannot be recorded twice.',
                style: CubagType.small.copyWith(color: CubagColors.lapsed),
              ),
            ),
          AdminFieldPair(
            AdminField(
              label: 'Amount',
              help: _feeSourceNotice.isEmpty ? null : _feeSourceNotice.replaceAll('⚠️ ', ''),
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: 'GH₵ '),
              ),
            ),
            AdminField(
              label: 'Paid by',
              child: DropdownMenu<String>(
                initialSelection: _paymentMethod,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final x in _methods)
                    DropdownMenuEntry(value: x['key']!, label: _methodLabels[x['key']] ?? x['label']!),
                ],
                onSelected: (v) {
                  if (v != null) setState(() => _paymentMethod = v);
                },
              ),
            ),
          ),
          AdminSwitchRow(
            title: 'Part payment',
            subtitle: 'Records part of a bill. The rest stays due.',
            value: _isInstallment,
            onChanged: (val) => setState(() {
              _isInstallment = val;
              if (_isInstallment && (_errorMessage ?? '').contains('already paid')) _errorMessage = null;
            }),
          ),
          if (_isInstallment)
            AdminField(
              label: 'Which part is this?',
              child: TextField(
                controller: _installmentNumberCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(prefixText: 'Part '),
              ),
            ),
          AdminField(
            label: 'Receipt book or cheque number (optional)',
            child: TextField(
              controller: _receiptNoController,
              decoration: const InputDecoration(hintText: 'For example: RCP-2026-0048'),
            ),
          ),
          AdminField(
            label: 'Office note (optional)',
            child: TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'For example: Paid in cash by the company director'),
            ),
          ),
          Text(
            'When you record it, the payment is marked as paid straight away and the member\'s standing updates.',
            style: CubagType.small,
          ),
        ],
      ],
    );
  }

  Widget _buildMemberStandingSummary(bool isDark, Color textColor, Color subTextColor) {
    final m = _selectedMember;
    if (m == null) return const SizedBox.shrink();
    final isRegPaid = m['package_fee_paid'] == true || m['registration_fee_paid'] == true;
    final appBill = double.tryParse(m['app_bill_amount']?.toString() ?? '') ?? 0.0;
    final appPaid = double.tryParse(m['app_amount_paid']?.toString() ?? '') ?? 0.0;
    final isRenewalPaid = (appBill > 0 && appPaid >= appBill) ||
        m['renewal_paid_this_year'] == true ||
        m['renewal_approved_this_year'] == true;
    return Wrap(
      spacing: CubagSpace.xs,
      runSpacing: CubagSpace.xs,
      children: [
        StatusChip(isRegPaid ? 'Registration paid' : 'Registration not paid', kind: isRegPaid ? StatusKind.good : StatusKind.pending),
        StatusChip(isRenewalPaid ? 'Renewal paid' : 'Renewal not paid', kind: isRenewalPaid ? StatusKind.good : StatusKind.pending),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ISSUE OFFICIAL AD-HOC MEMBER BILL DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class IssueBillDialog extends StatefulWidget {
  final Map<String, dynamic>? initialMember;
  final VoidCallback onSuccess;

  const IssueBillDialog({super.key, this.initialMember, required this.onSuccess});

  @override
  State<IssueBillDialog> createState() => _IssueBillDialogState();
}

class _BillLineEntry {
  final TextEditingController labelCtrl;
  final TextEditingController amountCtrl;
  String paymentCode;
  String bankName;
  String accountNumber;

  _BillLineEntry({
    String label = '',
    String amount = '',
    this.paymentCode = 'ADM',
    this.bankName = 'GCB',
    this.accountNumber = '107113005326',
  })  : labelCtrl = TextEditingController(text: label),
        amountCtrl = TextEditingController(text: amount);

  void dispose() {
    labelCtrl.dispose();
    amountCtrl.dispose();
  }
}

class _IssueBillDialogState extends State<IssueBillDialog> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController(text: 'Association Cloth');
  final _notesController = TextEditingController();

  List<dynamic> _members = [];
  bool _loadingMembers = false;
  Map<String, dynamic>? _selectedMember;

  final List<_BillLineEntry> _lineItems = [];
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  bool _submitting = false;
  String? _errorMessage;
  Timer? _searchDebounce;

  static const List<Map<String, String>> _codeAccounts = [
    {'code': 'ADM', 'bank': 'GCB', 'account': '107113005326', 'label': 'ADM · GCB (Operations/Admin)'},
    {'code': 'REG', 'bank': 'GCB', 'account': '107113005326', 'label': 'REG · GCB (Registration/Vetting/Cloth)'},
    {'code': 'SUB', 'bank': 'Zenith Bank', 'account': '6010309212', 'label': 'SUB · Zenith (Subscription/Levy)'},
    {'code': 'DST', 'bank': 'Ecobank', 'account': '1441002452360', 'label': 'DST · Ecobank (District Dues)'},
    {'code': 'CTI', 'bank': 'NIB', 'account': '1110045585101', 'label': 'CTI · NIB (Courses/Training)'},
    {'code': 'CPD', 'bank': 'NIB', 'account': '1110045585101', 'label': 'CPD · NIB (CPD Refresher)'},
    {'code': 'OTH', 'bank': 'GCB', 'account': '107113005326', 'label': 'OTH · GCB (Other Services)'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialMember != null) {
      _selectedMember = widget.initialMember;
    } else {
      _fetchMembers();
    }
    _lineItems.add(_BillLineEntry(
      label: 'Association Cloth',
      amount: '180.00',
      paymentCode: 'ADM',
      bankName: 'GCB',
      accountNumber: '107113005326',
    ));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    for (final it in _lineItems) {
      it.dispose();
    }
    super.dispose();
  }

  double get _totalAmount => _lineItems.fold(
        0.0,
        (sum, it) => sum + (double.tryParse(it.amountCtrl.text.replaceAll(',', '')) ?? 0.0),
      );

  Future<void> _fetchMembers([String search = '']) async {
    setState(() => _loadingMembers = true);
    try {
      final res = await ApiService().get('/payments/admin/members-lookup?search=${Uri.encodeComponent(search)}');
      if (mounted && res.statusCode == 200 && res.data is Map) {
        final d = res.data as Map<String, dynamic>;
        setState(() {
          _members = d['members'] as List<dynamic>? ?? [];
          _loadingMembers = false;
        });
      } else {
        if (mounted) setState(() => _loadingMembers = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _fetchMembers(v.trim()));
  }

  void _applyPreset(String title, String label, String amount, String code, String bank, String account) {
    setState(() {
      _titleController.text = title;
      for (final it in _lineItems) {
        it.dispose();
      }
      _lineItems.clear();
      _lineItems.add(_BillLineEntry(
        label: label,
        amount: amount,
        paymentCode: code,
        bankName: bank,
        accountNumber: account,
      ));
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _submit() async {
    final m = _selectedMember;
    if (m == null) {
      setState(() => _errorMessage = 'Please select a member to bill.');
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Please enter a bill title.');
      return;
    }
    if (_lineItems.isEmpty) {
      setState(() => _errorMessage = 'Add at least one line item to the bill.');
      return;
    }
    final total = _totalAmount;
    if (total <= 0) {
      setState(() => _errorMessage = 'Total bill amount must be greater than zero.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final itemsPayload = _lineItems.map((it) {
      final amt = double.tryParse(it.amountCtrl.text.replaceAll(',', '')) ?? 0.0;
      return {
        'label': it.labelCtrl.text.trim().isEmpty ? title : it.labelCtrl.text.trim(),
        'amount': amt,
        'payment_code': it.paymentCode,
        'bank_name': it.bankName,
        'account_number': it.accountNumber,
      };
    }).toList();

    try {
      final dueDateStr = '${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}';
      final res = await ApiService().post('/payments/admin/issue-bill', data: {
        'member_id': m['id'],
        'title': title,
        'items': itemsPayload,
        'total_amount': total,
        'due_date': dueDateStr,
        'notes': _notesController.text.trim(),
      });

      if (!mounted) return;
      if (res.statusCode == 201 || res.statusCode == 200) {
        Navigator.of(context).pop();
        widget.onSuccess();
      } else {
        setState(() {
          _submitting = false;
          _errorMessage = res.data?['message']?.toString() ?? 'Failed to issue bill. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = 'Network error while issuing bill: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _selectedMember;
    final total = _totalAmount;

    return AdminDialog(
      title: 'Issue official member bill',
      subtitle: m == null
          ? 'Select a member, define bill line items, and set payment deadline.'
          : 'Bill for ${m['name']} · Licence ${m['license_number'] ?? m['id']}',
      maxWidth: 680,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_submitting ? 'Issuing…' : 'Issue bill (GH₵ ${total.toStringAsFixed(2)})'),
        ),
      ],
      children: [
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: CubagSpace.md),
            padding: const EdgeInsets.all(CubagSpace.sm),
            decoration: BoxDecoration(
              color: CubagColors.lapsedTint,
              borderRadius: BorderRadius.circular(CubagRadius.card),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: CubagColors.lapsed, size: 18),
                const SizedBox(width: CubagSpace.xs),
                Expanded(child: Text(_errorMessage!, style: CubagType.small.copyWith(color: CubagColors.lapsed))),
              ],
            ),
          ),

        // 1. MEMBER SELECTION
        Text('1. Member to bill', style: CubagType.headline),
        const SizedBox(height: CubagSpace.xs),
        if (m == null) ...[
          AdminSearchField(
            hint: 'Search name, company, phone or licence number',
            controller: _searchController,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: CubagSpace.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _loadingMembers
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : _members.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(CubagSpace.md),
                        child: Text('No members found.', style: CubagType.small, textAlign: TextAlign.center),
                      )
                    : SingleChildScrollView(
                        child: AdminRowGroup(
                          dividerIndent: 68,
                          children: [
                            for (final raw in _members)
                              () {
                                final x = Map<String, dynamic>.from(raw as Map);
                                final name = x['name']?.toString() ?? 'Member';
                                return AdminListRow(
                                  leading: AdminRowMark(initials: adminInitials(name)),
                                  title: name,
                                  subtitle: [
                                    if ((x['company'] ?? '').toString().isNotEmpty) x['company'].toString(),
                                    if ((x['phone'] ?? '').toString().isNotEmpty) x['phone'].toString(),
                                  ].join(' · '),
                                  meta: (x['license_number'] ?? '').toString().isEmpty ? null : 'Licence ${x['license_number']}',
                                  onTap: () => setState(() => _selectedMember = x),
                                );
                              }(),
                          ],
                        ),
                      ),
          ),
        ] else ...[
          AdminRowGroup(
            children: [
              AdminListRow(
                leading: AdminRowMark(initials: adminInitials(m['name']?.toString() ?? '')),
                title: m['name']?.toString() ?? 'Member',
                subtitle: [
                  if (m['company'] != null) m['company'].toString(),
                  if (m['phone'] != null) m['phone'].toString(),
                ].join(' · '),
                meta: m['license_number'] == null ? null : 'Licence ${m['license_number']}',
                trailing: TextButton(
                  onPressed: () => setState(() => _selectedMember = null),
                  child: const Text('Change member'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: CubagSpace.lg),

        // 2. QUICK BILL PRESETS
        Text('2. Quick presets', style: CubagType.headline),
        const SizedBox(height: CubagSpace.xs),
        Wrap(
          spacing: CubagSpace.xs,
          runSpacing: CubagSpace.xs,
          children: [
            ActionChip(
              label: const Text('Association Cloth (GH₵ 180)'),
              avatar: const Icon(Icons.checkroom_rounded, size: 16),
              onPressed: () => _applyPreset('Association Cloth', 'Association Cloth', '180.00', 'ADM', 'GCB', '107113005326'),
            ),
            ActionChip(
              label: const Text('ID Card Replacement (GH₵ 45)'),
              avatar: const Icon(Icons.badge_rounded, size: 16),
              onPressed: () => _applyPreset('ID Card Replacement', 'Staff ID Card Replacement', '45.00', 'ADM', 'GCB', '107113005326'),
            ),
            ActionChip(
              label: const Text('Vetting Fee (GH₵ 750)'),
              avatar: const Icon(Icons.fact_check_rounded, size: 16),
              onPressed: () => _applyPreset('Vetting Fee', 'Vetting & Inspection Fee', '750.00', 'REG', 'GCB', '107113005326'),
            ),
            ActionChip(
              label: const Text('District Registration (GH₵ 250)'),
              avatar: const Icon(Icons.domain_rounded, size: 16),
              onPressed: () => _applyPreset('District Registration', 'Tema District Registration', '250.00', 'DST', 'Ecobank', '1441002452360'),
            ),
            ActionChip(
              label: const Text('Administrative Fine (GH₵ 500)'),
              avatar: const Icon(Icons.gavel_rounded, size: 16),
              onPressed: () => _applyPreset('Administrative Fine', 'Penalty / Non-compliance Fine', '500.00', 'ADM', 'GCB', '107113005326'),
            ),
            ActionChip(
              label: const Text('Subscription Dues (GH₵ 120)'),
              avatar: const Icon(Icons.card_membership_rounded, size: 16),
              onPressed: () => _applyPreset('Annual Subscription Dues', 'Annual Subscription Dues', '120.00', 'SUB', 'Zenith Bank', '6010309212'),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.lg),

        // 3. BILL TITLE & LINE ITEMS
        Text('3. Bill details & line items', style: CubagType.headline),
        const SizedBox(height: CubagSpace.xs),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Bill title',
            hintText: 'e.g. Association Cloth, Inspection Fee, Special Assessment',
          ),
        ),
        const SizedBox(height: CubagSpace.md),

        // Dynamic Line Items List
        for (int i = 0; i < _lineItems.length; i++) ...[
          Container(
            padding: const EdgeInsets.all(CubagSpace.sm),
            margin: const EdgeInsets.only(bottom: CubagSpace.sm),
            decoration: BoxDecoration(
              color: CubagColors.paper,
              borderRadius: BorderRadius.circular(CubagRadius.card),
              border: Border.all(color: CubagColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _lineItems[i].labelCtrl,
                        decoration: InputDecoration(
                          labelText: 'Item ${i + 1} description',
                          hintText: 'e.g. Association Cloth',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: CubagSpace.xs),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _lineItems[i].amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount (GHS)',
                          prefixText: 'GH₵ ',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_lineItems.length > 1) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: CubagColors.lapsed, size: 20),
                        tooltip: 'Remove line item',
                        onPressed: () {
                          setState(() {
                            final removed = _lineItems.removeAt(i);
                            removed.dispose();
                          });
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: CubagSpace.xs),
                DropdownButtonFormField<String>(
                  initialValue: _lineItems[i].paymentCode,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Settlement bank & payment code',
                    isDense: true,
                  ),
                  items: _codeAccounts.map((ca) => DropdownMenuItem(
                    value: ca['code'],
                    child: Text(
                      ca['label']!,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final match = _codeAccounts.firstWhere((ca) => ca['code'] == val, orElse: () => _codeAccounts.first);
                      setState(() {
                        _lineItems[i].paymentCode = val;
                        _lineItems[i].bankName = match['bank']!;
                        _lineItems[i].accountNumber = match['account']!;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _lineItems.add(_BillLineEntry(
                  label: '',
                  amount: '0.00',
                  paymentCode: 'ADM',
                  bankName: 'GCB',
                  accountNumber: '107113005326',
                ));
              });
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add another item'),
          ),
        ),
        const SizedBox(height: CubagSpace.md),

        // TOTAL SUMMARY CARD
        Container(
          padding: const EdgeInsets.all(CubagSpace.md),
          decoration: BoxDecoration(
            color: CubagColors.action.withAlpha(15),
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.action.withAlpha(40)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total bill amount:', style: CubagType.headline.copyWith(color: CubagColors.action)),
              Text(
                'GH₵ ${total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: CubagColors.action),
              ),
            ],
          ),
        ),
        const SizedBox(height: CubagSpace.lg),

        // 4. DEADLINE & NOTES
        Text('4. Payment deadline & instructions', style: CubagType.headline),
        const SizedBox(height: CubagSpace.xs),
        InkWell(
          onTap: _pickDueDate,
          borderRadius: BorderRadius.circular(CubagRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: CubagSpace.sm),
            decoration: BoxDecoration(
              border: Border.all(color: CubagColors.line),
              borderRadius: BorderRadius.circular(CubagRadius.card),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: CubagColors.action),
                const SizedBox(width: CubagSpace.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment deadline', style: CubagType.caption),
                    Text(
                      '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const Spacer(),
                TextButton(onPressed: _pickDueDate, child: const Text('Change date')),
              ],
            ),
          ),
        ),
        const SizedBox(height: CubagSpace.sm),
        TextField(
          controller: _notesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes / remarks for member (optional)',
            hintText: 'e.g. Please collect your cloth from the Secretariat after payment.',
          ),
        ),
        const SizedBox(height: CubagSpace.xs),
        Text(
          'Issuing this bill immediately creates a pending task on the member\'s dashboard, dispatches a push notification and email, and enables them to pay online via MoMo or Card.',
          style: CubagType.small,
        ),
      ],
    );
  }
}
