import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../components/home/home_sections.dart';
import '../../design/cubag_design.dart';

/// Top of the admin dashboard: what needs action, four key figures, and two
/// simple charts. Built from GET /admin/dashboard (kpis, queue,
/// revenue_by_month, status_counts); sections without data are left out.
class AdminOverview extends StatelessWidget {
  final Map<String, dynamic> dashboard;
  final String adminName;
  final ValueChanged<String> onOpen;

  const AdminOverview({
    super.key,
    required this.dashboard,
    required this.adminName,
    required this.onOpen,
  });

  Map<String, dynamic> _map(String k) =>
      dashboard[k] is Map ? Map<String, dynamic>.from(dashboard[k] as Map) : {};

  static String money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return 'GH₵ $b';
  }

  @override
  Widget build(BuildContext context) {
    final kpis = _map('kpis');
    final queue = _map('queue');
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final waiting = _WaitingList(queue: queue, onOpen: onOpen);
      final figures = _Figures(kpis: kpis, queue: queue, wide: box.maxWidth >= 700);
      final revenue = _RevenueChart(rows: (dashboard['revenue_by_month'] as List?) ?? const []);
      final members = _MembersByStatus(counts: _map('status_counts'));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$greeting${adminName.isEmpty ? '' : ', $adminName'}', style: CubagType.display),
          const SizedBox(height: CubagSpace.xxs),
          const Text('Here is what needs your attention today.', style: CubagType.body),
          const SizedBox(height: CubagSpace.xl),
          figures,
          const SizedBox(height: CubagSpace.xl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: waiting),
                const SizedBox(width: CubagSpace.xl),
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [revenue, const SizedBox(height: CubagSpace.xl), members],
                  ),
                ),
              ],
            )
          else ...[
            waiting,
            const SizedBox(height: CubagSpace.xl),
            revenue,
            const SizedBox(height: CubagSpace.xl),
            members,
          ],
        ],
      );
    });
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Panel({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
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
          Text(title, style: CubagType.headline),
          if (subtitle != null) Text(subtitle!, style: CubagType.small),
          const SizedBox(height: CubagSpace.md),
          child,
        ],
      ),
    );
  }
}

/// Items that need an admin's action, each opening its page.
class _WaitingList extends StatelessWidget {
  final Map<String, dynamic> queue;
  final ValueChanged<String> onOpen;
  const _WaitingList({required this.queue, required this.onOpen});

  static const _rows = [
    ('documents', 'Applications to check', 'Members with documents waiting for review', '/admin/documents', Icons.folder_shared_rounded),
    ('payments', 'Payments to verify', 'Bank slips waiting for confirmation', '/admin/payments', Icons.account_balance_wallet_rounded),
    ('compliance', 'Compliance applications', 'Renewals and licence applications in review', '/admin/compliance', Icons.verified_user_rounded),
    ('reported_messages', 'Reported messages', 'Member reports to review', '/admin/message-reports', Icons.flag_rounded),
    ('complaints', 'Open complaints', 'Public complaints not yet resolved', '/admin/complaints', Icons.gavel_rounded),
    ('tickets', 'Support tickets', 'Open member support requests', '/admin/tickets', Icons.support_agent_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final shown = _rows.where((r) => queue.containsKey(r.$1)).toList();
    final total = shown.fold<int>(0, (a, r) => a + ((queue[r.$1] as num?)?.toInt() ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Waiting for you', style: CubagType.headline)),
            if (shown.isNotEmpty)
              Text(total == 0 ? 'All clear' : '$total in total', style: CubagType.small),
          ],
        ),
        const SizedBox(height: CubagSpace.xs),
        if (shown.isEmpty)
          const HomeGroup(children: [
            QuietRow(icon: Icons.check_circle_rounded, text: 'Nothing is waiting for you.'),
          ])
        else
          HomeGroup(
            children: [
              for (final r in shown) _row(r, (queue[r.$1] as num?)?.toInt() ?? 0),
            ],
          ),
      ],
    );
  }

  Widget _row((String, String, String, String, IconData) r, int count) {
    final has = count > 0;
    return InkWell(
      onTap: () => onOpen(r.$4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: 14),
        child: Row(
          children: [
            Icon(r.$5, color: has ? CubagColors.action : CubagColors.muted, size: 22),
            const SizedBox(width: CubagSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$2, style: CubagType.bodyStrong),
                  Text(r.$3, style: CubagType.small),
                ],
              ),
            ),
            const SizedBox(width: CubagSpace.sm),
            has
                ? Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CubagColors.action,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        textAlign: TextAlign.center,
                        style: CubagType.label.copyWith(color: Colors.white)),
                  )
                : const Text('None', style: CubagType.small),
            const SizedBox(width: CubagSpace.xs),
            const Icon(Icons.chevron_right_rounded, color: CubagColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Four figures that describe the association at a glance.
class _Figures extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final Map<String, dynamic> queue;
  final bool wide;
  const _Figures({required this.kpis, required this.queue, required this.wide});

  num _n(String k) => num.tryParse(kpis[k]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Active members', '${_n('active_members')}', 'of ${_n('total_members')} registered'),
      ('Pending applications', '${_n('pending_members')}', 'awaiting approval'),
      ('Revenue received', AdminOverview.money(_n('revenue')), 'confirmed payments'),
      ('Awaiting verification', AdminOverview.money(_n('pending_revenue')), 'payments not yet confirmed'),
    ];
    final tiles = [
      for (final i in items)
        Container(
          padding: const EdgeInsets.all(CubagSpace.md),
          decoration: BoxDecoration(
            color: CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.$1, style: CubagType.small),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(i.$2, style: CubagType.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Text(i.$3, style: CubagType.caption),
            ],
          ),
        ),
    ];
    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: CubagSpace.md),
            Expanded(child: tiles[i]),
          ],
        ],
      );
    }
    // Two per row, each as tall as its content.
    return Column(
      children: [
        for (var r = 0; r < tiles.length; r += 2) ...[
          if (r > 0) const SizedBox(height: CubagSpace.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[r]),
                const SizedBox(width: CubagSpace.sm),
                Expanded(child: tiles[r + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Confirmed revenue for the last six months, one bar per month.
class _RevenueChart extends StatelessWidget {
  final List rows;
  const _RevenueChart({required this.rows});

  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    // Always show the last six calendar months, zero where nothing was paid.
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    final byKey = {
      for (final r in rows)
        if (r is Map) r['month']?.toString(): (num.tryParse(r['total']?.toString() ?? '') ?? 0).toDouble(),
    };
    final values = [
      for (final m in months)
        byKey['${m.year}-${m.month.toString().padLeft(2, '0')}'] ?? 0.0,
    ];
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    final total = values.fold<double>(0, (a, b) => a + b);

    return _Panel(
      title: 'Revenue',
      subtitle: 'Confirmed payments, last 6 months: ${AdminOverview.money(total)}',
      child: SizedBox(
        height: 200,
        child: maxV == 0
            ? const Center(child: Text('No confirmed payments in the last 6 months.', style: CubagType.small))
            : BarChart(
                BarChartData(
                  maxY: maxV * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(color: CubagColors.line, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_m[months[v.toInt()].month - 1], style: CubagType.caption),
                        ),
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => CubagColors.ink,
                      getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                        AdminOverview.money(rod.toY),
                        CubagType.label.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < values.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: values[i],
                          width: 28,
                          color: i == values.length - 1 ? CubagColors.action : CubagColors.cocoa,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Members by status as labelled horizontal bars (easier to read than a pie).
class _MembersByStatus extends StatelessWidget {
  final Map<String, dynamic> counts;
  const _MembersByStatus({required this.counts});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('active', 'Active', CubagColors.valid),
      ('pending', 'Pending', CubagColors.due),
      ('suspended', 'Suspended', CubagColors.lapsed),
      ('inactive', 'Inactive', CubagColors.muted),
    ];
    final values = {for (final r in rows) r.$1: (num.tryParse(counts[r.$1]?.toString() ?? '') ?? 0).toInt()};
    final total = values.values.fold<int>(0, (a, b) => a + b);
    return _Panel(
      title: 'Members by status',
      subtitle: '$total members',
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: CubagSpace.sm),
              child: Row(
                children: [
                  SizedBox(width: 90, child: Text(r.$2, style: CubagType.label)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : values[r.$1]! / total,
                        minHeight: 10,
                        color: r.$3,
                        backgroundColor: CubagColors.sand,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${values[r.$1]}',
                        textAlign: TextAlign.right, style: CubagType.figure.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
