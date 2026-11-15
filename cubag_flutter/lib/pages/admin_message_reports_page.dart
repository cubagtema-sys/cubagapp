import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/app_layout.dart';
import '../components/fetch_error_view.dart';
import '../components/message_report_card.dart';
import '../services/api_service.dart';
import '../components/admin_components.dart';
import '../components/filter_tabs.dart';
import '../design/cubag_design.dart';
import '../utils/app_logger.dart';

/// Moderation queue for member-to-member messaging (store UGC rules:
/// Apple 1.2, Google Play user-generated content). Members report a chat from
/// the conversation header; reports land here for the Secretariat.
///
/// Backend: `GET /messages/admin/reports?status=`, `PUT /messages/admin/reports/{id}`
/// (sub-admin permission `messaging`).
class AdminMessageReportsPage extends StatefulWidget {
  const AdminMessageReportsPage({super.key});

  @override
  State<AdminMessageReportsPage> createState() =>
      _AdminMessageReportsPageState();
}

const _statuses = [
  ('open', 'Open'),
  ('resolved', 'Resolved'),
  ('dismissed', 'Dismissed'),
  ('all', 'All'),
];

class _AdminMessageReportsPageState extends State<AdminMessageReportsPage> {
  final _api = ApiService();
  String _status = 'open';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Set<int> _busy = {};

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
    try {
      final res = await _api.get('/messages/admin/reports?status=$_status');
      if (!mounted) return;
      final data = res.data;
      if (res.statusCode == 200 && data is Map && data['items'] is List) {
        setState(() {
          _items = (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _loading = false;
          _error = 'You need the Messaging permission to review reports.';
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Could not load reports.';
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_message_reports', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load reports. Check your connection.';
        });
      }
    }
  }

  Future<void> _setStatus(Map<String, dynamic> report, String status) async {
    final id = report['id'] as int;
    setState(() => _busy.add(id));
    String? failure;
    try {
      final res = await _api.put(
        '/messages/admin/reports/$id',
        data: {'status': status},
      );
      if (res.statusCode != 200) failure = 'Could not update the report.';
    } catch (e, st) {
      AppLogger.error('admin_message_reports_update', e, st);
      failure = 'Could not update the report. Check your connection.';
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    final messenger = ScaffoldMessenger.of(context);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (status) {
          'resolved' => 'Report marked as resolved.',
          'dismissed' => 'Report dismissed.',
          _ => 'Report reopened.',
        }),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Reported messages',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminHeader(
                title: 'Reported messages',
                subtitle: 'Members can report a chat from the conversation screen, which also blocks the other member for them. '
                    'Read each report, then resolve or dismiss it. To act on a member, open their profile.',
              ),
              FilterTabs(
                tabs: _statuses,
                selected: _status,
                onSelected: (value) {
                  if (_status == value) return;
                  setState(() => _status = value);
                  _load();
                },
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                FetchErrorView(onRetry: _load, message: _error)
              else if (_items.isEmpty)
                EmptyMessage(
                  icon: Icons.verified_user_outlined,
                  title: _status == 'open' ? 'No open reports' : 'No reports here',
                  message: _status == 'open' ? 'Reports from members appear here.' : null,
                )
              else
                for (final r in _items)
                  MessageReportCard(
                    report: r,
                    busy: _busy.contains(r['id']),
                    onStatus: (s) => _setStatus(r, s),
                    onOpenMember: () => context.push('/member-detail/${r['reported_member_id']}'),
                  ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
