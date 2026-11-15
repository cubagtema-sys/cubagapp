import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

class AdminEventAttendeesPage extends StatefulWidget {
  final int eventId;
  final String title;

  const AdminEventAttendeesPage({
    super.key,
    required this.eventId,
    required this.title,
  });

  @override
  State<AdminEventAttendeesPage> createState() =>
      _AdminEventAttendeesPageState();
}

class _AdminEventAttendeesPageState extends State<AdminEventAttendeesPage> {
  bool _loading = true;
  List<dynamic> _allMembers = [];
  String _filter = 'all'; // 'all', 'attended', 'absent'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiService().get('/events/${widget.eventId}/attendees');
      if (mounted && res.statusCode == 200) {
        setState(() {
          _allMembers = res.data['attendees'] ?? [];
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load attendees: ${res.data}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        try {
          final dynamic dioErr = e;
          if (dioErr.response != null && dioErr.response.data != null) {
            msg =
                dioErr.response.data['message'] ??
                dioErr.response.data.toString();
          }
        } catch (e, st) {
          AppLogger.error('admin_event_attendees_page', e, st);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendees: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allMembers.where((m) {
      final attended = m['checked_in_at'] != null;
      if (_filter == 'attended' && !attended) return false;
      if (_filter == 'absent' && attended) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final company = (m['company'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !company.contains(q)) return false;
      }
      return true;
    }).toList();
    final attendedCount = _allMembers.where((m) => m['checked_in_at'] != null).length;
    final absentCount = _allMembers.length - attendedCount;
    AdminFigure fig(String label, String key, int n, {Color? color}) => AdminFigure(
          label,
          '$n',
          color: n > 0 ? color : null,
          selected: _filter == key,
          onTap: () => setState(() => _filter = key),
        );

    return AppLayout(
      title: 'Attendees',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: CubagType.title),
              const SizedBox(height: CubagSpace.xxs),
              Text('Members who signed up, and who was checked in at the door.', style: CubagType.small),
              const SizedBox(height: CubagSpace.md),
              AdminFigureStrip(figures: [
                fig('Signed up', 'all', _allMembers.length),
                fig('Checked in', 'attended', attendedCount, color: CubagColors.valid),
                fig('Not checked in', 'absent', absentCount),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search name or company',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (filtered.isEmpty)
                EmptyMessage(
                  icon: Icons.groups_outlined,
                  title: _searchQuery.isNotEmpty
                      ? 'No one matches'
                      : (_allMembers.isEmpty ? 'No one has signed up yet' : 'No one in this list'),
                  message: _searchQuery.isNotEmpty ? 'Try another name, or clear the search.' : null,
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [
                    for (final a in filtered)
                      AdminListRow(
                        leading: AdminRowMark(
                          initials: adminInitials(a['name']?.toString() ?? ''),
                          color: a['checked_in_at'] != null ? CubagColors.valid : CubagColors.cocoa,
                          background: a['checked_in_at'] != null ? CubagColors.validTint : CubagColors.sand,
                        ),
                        title: a['name']?.toString() ?? 'Member',
                        subtitle: [
                          if ((a['company'] ?? '').toString().isNotEmpty) a['company'].toString(),
                          if ((a['email'] ?? '').toString().isNotEmpty) a['email'].toString(),
                        ].join(' · '),
                        status: a['checked_in_at'] != null
                            ? const StatusChip('Checked in', kind: StatusKind.good)
                            : const StatusChip('Not checked in'),
                      ),
                  ],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
