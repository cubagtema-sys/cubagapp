import 'package:flutter/material.dart';

import '../design/cubag_design.dart';
import '../services/api_service.dart';
import 'admin_list.dart';
import 'filter_tabs.dart';

/// What WhitsunPay should pay into each CUBAG account for a period, by
/// payment code (server: GET /payments/admin/settlement-report). Finance
/// checks this against WhitsunPay's settlement statements.
class SettlementReport extends StatefulWidget {
  /// Saves a CSV file (the Revenue page's download helper).
  final Future<void> Function(String title, String csv) onExport;
  const SettlementReport({super.key, required this.onExport});

  @override
  State<SettlementReport> createState() => _SettlementReportState();
}

class _SettlementReportState extends State<SettlementReport> {
  String _period = 'week';
  DateTimeRange? _custom;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _d(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'today' => DateTimeRange(start: today, end: today),
      'month' => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
      'custom' => _custom ?? DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      _ => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = _range;
    try {
      final res = await ApiService().get('/payments/admin/settlement-report?from=${_iso(r.start)}&to=${_iso(r.end)}');
      if (!mounted) return;
      if (res.statusCode == 200 && res.data is Map) {
        setState(() {
          _data = Map<String, dynamic>.from(res.data as Map);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = res.statusCode == 403
              ? 'You need access to Payments to see the settlement report.'
              : 'Could not load the settlement report.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the settlement report. Check the connection.';
        });
      }
    }
  }

  String _money(num v) {
    final parts = v.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'GH₵ $whole.${parts[1]}';
  }

  void _export() {
    final d = _data;
    if (d == null) return;
    final rows = <String>['Date,Payment code,Bank,Account number,Amount (GHS),Payments'];
    for (final x in (d['days'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(x as Map);
      rows.add('${m['date']},${m['code']},"${m['bank_name']}",${m['account_number']},'
          '${(m['total'] as num).toStringAsFixed(2)},${m['count']}');
    }
    rows.add('');
    rows.add('Total via WhitsunPay,,,,${(d['whitsun_total'] as num? ?? 0).toStringAsFixed(2)},${d['whitsun_count'] ?? 0}');
    rows.add('Paid straight to bank or office (not for WhitsunPay),,,,'
        '${(d['direct_total'] as num? ?? 0).toStringAsFixed(2)},${d['direct_count'] ?? 0}');
    widget.onExport('CUBAG_settlement_${d['from']}_to_${d['to']}', rows.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    final d = _data;
    final banks = (d?['banks'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Every MoMo payment lands in the WhitsunPay account with a payment code. WhitsunPay pays each code '
          'into its CUBAG bank account. Use this to check their settlements.',
          style: CubagType.small,
        ),
        const SizedBox(height: CubagSpace.md),
        Row(
          children: [
            Expanded(
              child: FilterTabs(
                tabs: const [('today', 'Today'), ('week', 'Last 7 days'), ('month', 'This month'), ('custom', 'Choose dates')],
                selected: _period,
                onSelected: (p) async {
                  if (p == 'custom') {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 1, now.month, now.day),
                      lastDate: now,
                      initialDateRange: _range,
                    );
                    if (picked == null) return;
                    _custom = picked;
                  }
                  setState(() => _period = p);
                  _load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.sm),
        Row(
          children: [
            Expanded(child: Text('${_d(r.start)} to ${_d(r.end)}', style: CubagType.label)),
            OutlinedButton.icon(
              onPressed: d == null || _loading ? null : _export,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download CSV'),
            ),
          ],
        ),
        const SizedBox(height: CubagSpace.md),
        if (_loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          EmptyMessage(
            icon: Icons.cloud_off_rounded,
            title: _error!,
            action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
          )
        else ...[
          AdminFigureStrip(figures: [
            AdminFigure('Via WhitsunPay', _money(d?['whitsun_total'] as num? ?? 0), color: CubagColors.valid),
            AdminFigure('Payments', '${d?['whitsun_count'] ?? 0}'),
            AdminFigure('Straight to bank or office', _money(d?['direct_total'] as num? ?? 0)),
          ]),
          const SizedBox(height: CubagSpace.lg),
          if (banks.isEmpty)
            const EmptyMessage(
              icon: Icons.account_balance_outlined,
              title: 'No WhitsunPay payments in this period',
              message: 'Paid MoMo payments appear here with their codes.',
            )
          else
            for (final b in banks) ...[
              AdminRowGroup(
                children: [
                  AdminListRow(
                    leading: const AdminRowMark(icon: Icons.account_balance_outlined),
                    title: b['bank_name']?.toString() ?? '',
                    subtitle: 'Account ${b['account_number']}',
                    meta: '${b['count']} ${b['count'] == 1 ? 'payment' : 'payments'}',
                    status: Text(
                      _money(b['total'] as num),
                      style: CubagType.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    trailing: const SizedBox(width: CubagSpace.xs),
                  ),
                  for (final c in (b['codes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(68, 10, CubagSpace.md, 10),
                      child: Row(
                        children: [
                          SizedBox(width: 80, child: Text(c['code'].toString(), style: CubagType.label)),
                          Expanded(
                            child: Text(
                              c['label']?.toString() ?? '',
                              style: CubagType.small,
                            ),
                          ),
                          Text(
                            _money(c['total'] as num),
                            style: CubagType.small.copyWith(
                              color: CubagColors.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: CubagSpace.md),
            ],
        ],
      ],
    );
  }
}
