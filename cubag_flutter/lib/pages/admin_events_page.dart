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

const _kOrange = CubagColors.action;
const _kRed = CubagColors.lapsed;

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
    final titleCtrl = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    final locationCtrl = TextEditingController(
      text: existing?['location']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    String rawDate = existing?['date'] != null
        ? existing!['date'].toString().split('T')[0]
        : '';
    String timeVal = existing?['time']?.toString() ?? '';
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final inputBg = isDark
              ? CubagColors.ink
              : const Color(0xFFFAF6F0);
          final borderCol = isDark
              ? const Color(0xFF3D261C)
              : CubagColors.line;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event_note_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Edit Event Details' : 'Create New Event',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Provide event scheduling, venue details, and agenda description.',
                      style: TextStyle(
                        fontSize: 17,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Event Title *',
                        hintText: 'e.g. CUBAG Annual General Meeting 2026',
                        prefixIcon: const Icon(Icons.title_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Venue / Location
                    TextField(
                      controller: locationCtrl,
                      decoration: InputDecoration(
                        labelText: 'Venue / Location *',
                        hintText: 'e.g. Accra International Conference Centre',
                        prefixIcon: const Icon(
                          Icons.location_on_outlined,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Date & Time pickers
                    Row(
                      children: [
                        // Date picker
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: rawDate.isNotEmpty
                                    ? DateTime.tryParse(rawDate) ??
                                          DateTime.now()
                                    : DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setDlgState(() {
                                  rawDate =
                                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderCol),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: _kOrange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      rawDate.isNotEmpty
                                          ? rawDate
                                          : 'Select Date *',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: rawDate.isNotEmpty
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: rawDate.isNotEmpty
                                            ? null
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Time picker
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setDlgState(() {
                                  final hour = picked.hourOfPeriod == 0
                                      ? 12
                                      : picked.hourOfPeriod;
                                  final minute = picked.minute
                                      .toString()
                                      .padLeft(2, '0');
                                  final period = picked.period == DayPeriod.am
                                      ? 'AM'
                                      : 'PM';
                                  timeVal = '$hour:$minute $period';
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderCol),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 18,
                                    color: _kOrange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      timeVal.isNotEmpty
                                          ? timeVal
                                          : 'Select Time *',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: timeVal.isNotEmpty
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: timeVal.isNotEmpty
                                            ? null
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description & Agenda',
                        hintText:
                            'Brief summary of agenda, keynote speakers, or requirements...',
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.description_outlined, size: 20),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final title = titleCtrl.text.trim();
                        final loc = locationCtrl.text.trim();
                        if (title.isEmpty ||
                            loc.isEmpty ||
                            rawDate.isEmpty ||
                            timeVal.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please complete all required fields (Title, Venue, Date, Time)',
                              ),
                            ),
                          );
                          return;
                        }

                        setDlgState(() => submitting = true);
                        try {
                          if (isEdit) {
                            await _api.putData('events/${existing['id']}', {
                              'title': title,
                              'location': loc,
                              'description': descCtrl.text.trim(),
                              'date': rawDate,
                              'time': timeVal,
                            });
                          } else {
                            await _api.postData('events', {
                              'title': title,
                              'location': loc,
                              'description': descCtrl.text.trim(),
                              'date': rawDate,
                              'time': timeVal,
                            });
                          }
                          if (dlgCtx.mounted) {
                            Navigator.pop(dlgCtx);
                            _fetch(refresh: true);
                          }
                        } catch (e) {
                          setDlgState(() => submitting = false);
                          if (dlgCtx.mounted) {
                            ScaffoldMessenger.of(dlgCtx).showSnackBar(
                              SnackBar(
                                content: Text('Failed to save event: $e'),
                              ),
                            );
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save Changes' : 'Publish Event',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Archive this event?'),
        content: Text('Are you sure you want to archive "${event['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
