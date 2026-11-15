import '../components/admin_dialog.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import 'admin_qr_scanner_page.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';


class AdminEventsPage extends StatefulWidget {
  const AdminEventsPage({super.key});

  @override
  State<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<AdminEventsPage> {
  final ApiService _api = ApiService();
  List<dynamic> _events = [];
  bool _loading = true;
  bool _hasError = false;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'upcoming', 'past'

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) {
      setState(() {
        _loading = true;
        _events = [];
      });
    } else {
      if (_events.isEmpty) setState(() => _loading = true);
    }

    try {
      final res = await _api.get('/events/admin/all?per_page=100&status=all');
      if (mounted) {
        final items = ApiService.ensureList(res.data);
        setState(() {
          _events = items;
          _loading = false;
          _hasError = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_events', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _showEventDialog([Map<String, dynamic>? existing]) async {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?['title']?.toString() ?? '');
    final locationCtrl = TextEditingController(text: existing?['location']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    String rawDate = existing?['date'] != null ? existing!['date'].toString().split('T')[0] : '';
    String timeVal = existing?['time']?.toString() ?? '';
    bool submitting = false;
    String? error;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          Future<void> submit() async {
            final title = titleCtrl.text.trim();
            final loc = locationCtrl.text.trim();
            if (title.isEmpty || loc.isEmpty || rawDate.isEmpty || timeVal.isEmpty) {
              setDlgState(() => error = 'Add a title, a venue, a date and a time.');
              return;
            }
            setDlgState(() {
              submitting = true;
              error = null;
            });
            final data = {
              'title': title,
              'location': loc,
              'description': descCtrl.text.trim(),
              'date': rawDate,
              'time': timeVal,
            };
            try {
              if (isEdit) {
                await _api.putData('events/${existing['id']}', data);
              } else {
                await _api.postData('events', data);
              }
              if (dlgCtx.mounted) {
                Navigator.pop(dlgCtx);
                _fetch(refresh: true);
              }
            } catch (e) {
              setDlgState(() {
                submitting = false;
                error = 'Could not save the event. Try again.';
              });
            }
          }

          return AdminDialog(
            title: isEdit ? 'Edit event' : 'New event',
            subtitle: 'Members see it in the app and can add it to their calendar.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(submitting ? 'Saving…' : (isEdit ? 'Save changes' : 'Publish event')),
              ),
            ],
            children: [
              AdminField(
                label: 'Title',
                child: TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'For example: Annual general meeting 2026'),
                ),
              ),
              AdminField(
                label: 'Venue',
                child: TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(hintText: 'For example: CUBAG office, Tema'),
                ),
              ),
              AdminFieldPair(
                AdminField(
                  label: 'Date',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(rawDate) ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDlgState(() => rawDate =
                            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(rawDate.isEmpty ? 'Pick a date' : rawDate),
                  ),
                ),
                AdminField(
                  label: 'Time',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (picked != null) {
                        setDlgState(() {
                          final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
                          final minute = picked.minute.toString().padLeft(2, '0');
                          timeVal = '$hour:$minute ${picked.period == DayPeriod.am ? 'AM' : 'PM'}';
                        });
                      }
                    },
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                    label: Text(timeVal.isEmpty ? 'Pick a time' : timeVal),
                  ),
                ),
              ),
              AdminField(
                label: 'Details (optional)',
                child: TextField(
                  controller: descCtrl,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Agenda, speakers, what to bring'),
                ),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
    titleCtrl.dispose();
    locationCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _deleteEvent(dynamic event) async {
    final confirm = await showAdminConfirm(context, title: 'Archive this event?', message: 'Members will no longer see "${event['title']}".', confirmLabel: 'Archive', destructive: true);
    if (confirm != true) return;

    try {
      await _api.deleteData('events/${event['id']}');
      _fetch(refresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error archiving event: $e')));
      }
    }
  }

  List<dynamic> get _filteredEvents {
    final now = DateTime.now();
    return _events.where((ev) {
      final title = (ev['title']?.toString() ?? '').toLowerCase();
      final loc = (ev['location']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          query.isEmpty || title.contains(query) || loc.contains(query);

      if (!matchesSearch) return false;

      // Status filter
      final dStr = ev['date']?.toString().split('T')[0] ?? '';
      final parsedDate = DateTime.tryParse(dStr);
      final isPast =
          parsedDate != null &&
          parsedDate.isBefore(DateTime(now.year, now.month, now.day));

      if (_filterStatus == 'upcoming' && isPast) return false;
      if (_filterStatus == 'past' && !isPast) return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final total = _events.length;
    final upcomingCount = _events.where((ev) {
      final parsed = DateTime.tryParse(ev['date']?.toString().split('T')[0] ?? '');
      return parsed != null && !parsed.isBefore(today);
    }).length;
    final pastCount = total - upcomingCount;
    AdminFigure fig(String label, String key, int n) => AdminFigure(
          label,
          '$n',
          selected: _filterStatus == key,
          onTap: () => setState(() => _filterStatus = key),
        );

    return AppLayout(
      title: 'Events',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Events',
                subtitle: 'Meetings and events members can see and sign up for. Open one for its attendee list; scan tickets at the door.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminQrScannerPage(
                            onScan: (memberId) => context.push('/verify-member/$memberId'),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan tickets'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showEventDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New event'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                fig('All', 'all', total),
                fig('Upcoming', 'upcoming', upcomingCount),
                fig('Past', 'past', pastCount),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search title or venue',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_hasError)
                FetchErrorView(onRetry: () => _fetch(refresh: true))
              else if (_filteredEvents.isEmpty)
                EmptyMessage(
                  icon: Icons.event_outlined,
                  title: _events.isEmpty ? 'No events yet' : 'No events match',
                  message: _events.isEmpty
                      ? 'Add a meeting, seminar or CTI session. Members see it in the app and can add it to their calendar.'
                      : 'Try another filter, or clear the search.',
                  action: _events.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _showEventDialog(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New event'),
                        )
                      : null,
                )
              else
                AdminRowGroup(
                  dividerIndent: 76,
                  children: [for (final ev in _filteredEvents) _eventRow(ev, today)],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Widget _eventRow(dynamic ev, DateTime today) {
    final title = ev['title']?.toString() ?? 'Untitled event';
    final location = ev['location']?.toString() ?? '';
    final time = ev['time']?.toString() ?? '';
    final count = int.tryParse('${ev['attendees_count'] ?? ev['attendee_count'] ?? 0}') ?? 0;
    final parsed = DateTime.tryParse(ev['date']?.toString().split('T')[0] ?? '');
    final isPast = parsed != null && parsed.isBefore(today);

    final badge = Container(
      width: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: isPast ? CubagColors.muted : CubagColors.cocoa,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              parsed == null ? '—' : _months[parsed.month - 1],
              textAlign: TextAlign.center,
              style: CubagType.caption.copyWith(color: CubagColors.onCocoa, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(parsed == null ? '?' : '${parsed.day}', style: CubagType.headline),
          ),
        ],
      ),
    );

    void openAttendees() => context.push('/admin/events/${ev['id']}/attendees');

    return AdminListRow(
      leading: badge,
      title: title,
      subtitle: [if (time.isNotEmpty) time, if (location.isNotEmpty) location].join(' · '),
      meta: count == 1 ? '1 attending' : '$count attending',
      status: isPast ? const StatusChip('Past') : const StatusChip('Upcoming', kind: StatusKind.good),
      onTap: openAttendees,
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
        onSelected: (v) {
          if (v == 'attendees') openAttendees();
          if (v == 'edit') _showEventDialog(ev);
          if (v == 'delete') _deleteEvent(ev);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'attendees', child: Text('Attendees')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: CubagColors.lapsed))),
        ],
      ),
    );
  }
}
