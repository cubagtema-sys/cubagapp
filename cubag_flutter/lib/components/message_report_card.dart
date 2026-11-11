import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.flag_rounded,
                  size: 18,
                  color: AppColors.accentOrangeText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$reporter reported $reported · ${_date(report['created_at'])}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightCream,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '“$message”',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Reporter\'s note: $details',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenMember,
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                  label: Text('View $reported'),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (status == 'open') ...[
                  FilledButton(
                    onPressed: () => onStatus('resolved'),
                    child: const Text('Mark resolved'),
                  ),
                  TextButton(
                    onPressed: () => onStatus('dismissed'),
                    child: const Text('Dismiss'),
                  ),
                ] else
                  TextButton(
                    onPressed: () => onStatus('open'),
                    child: const Text('Reopen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      'resolved' => (
        'Resolved',
        const Color(0xFF166534),
        const Color(0xFFDCFCE7),
      ),
      'dismissed' => (
        'Dismissed',
        const Color(0xFF475569),
        const Color(0xFFF1F5F9),
      ),
      _ => ('Open', const Color(0xFF9A3412), const Color(0xFFFFEDD5)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
