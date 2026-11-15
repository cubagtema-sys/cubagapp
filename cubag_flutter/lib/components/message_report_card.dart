import 'package:flutter/material.dart';

import '../design/cubag_design.dart';
import 'admin_list.dart';
import 'cubag_ui.dart';

/// Reasons a member can choose when reporting a chat (backend REPORT_REASONS).
const messageReportReasonLabels = {
  'spam': 'Spam',
  'harassment': 'Harassment',
  'abusive': 'Abusive language',
  'fraud': 'Fraud or scam',
  'inappropriate': 'Inappropriate content',
  'other': 'Other',
};

/// One report in the admin moderation queue (AdminMessageReportsPage).
class MessageReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool busy;
  final ValueChanged<String> onStatus;
  final VoidCallback onOpenMember;

  const MessageReportCard({
    super.key,
    required this.report,
    required this.busy,
    required this.onStatus,
    required this.onOpenMember,
  });

  String _date(Object? raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]} ${d.year}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final status = (report['status'] ?? 'open').toString();
    final reason = messageReportReasonLabels[report['reason']] ?? 'Other';
    final reporter = report['reporter_name']?.toString() ?? 'Unknown member';
    final reported = report['reported_name']?.toString() ?? 'Unknown member';
    final message = report['message_text']?.toString().trim() ?? '';
    final details = report['details']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: CubagSpace.sm),
      padding: const EdgeInsets.all(CubagSpace.lg),
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
              const AdminRowMark(icon: Icons.flag_outlined),
              const SizedBox(width: CubagSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reason, style: CubagType.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      '$reporter reported $reported · ${_date(report['created_at'])}',
                      style: CubagType.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CubagSpace.sm),
              switch (status) {
                'resolved' => const StatusChip('Resolved', kind: StatusKind.good),
                'dismissed' => const StatusChip('Dismissed'),
                _ => const StatusChip('Open', kind: StatusKind.pending),
              },
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: CubagSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CubagSpace.md),
              decoration: BoxDecoration(
                color: CubagColors.sand,
                borderRadius: BorderRadius.circular(CubagRadius.control),
              ),
              child: Text('“$message”', style: CubagType.body.copyWith(color: CubagColors.ink)),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: CubagSpace.sm),
            Text('Reporter\'s note: $details', style: CubagType.small.copyWith(color: CubagColors.inkSoft)),
          ],
          const SizedBox(height: CubagSpace.md),
          Wrap(
            spacing: CubagSpace.xs,
            runSpacing: CubagSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (status == 'open') ...[
                FilledButton(onPressed: () => onStatus('resolved'), child: const Text('Mark resolved')),
                OutlinedButton(onPressed: () => onStatus('dismissed'), child: const Text('Dismiss')),
              ] else
                OutlinedButton(onPressed: () => onStatus('open'), child: const Text('Reopen')),
              TextButton.icon(
                onPressed: onOpenMember,
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: Text('View $reported'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
