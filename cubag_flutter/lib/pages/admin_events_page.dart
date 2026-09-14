import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import 'admin_qr_scanner_page.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kBlue = Color(0xFF3b82f6);
const _kRed = Color(0xFFef4444);
const _kCardBg = Color(0xFF281710);

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
              ? const Color(0xFF1A0F0A).withAlpha(120)
              : const Color(0xFFf8fafc);
          final borderCol = isDark
              ? const Color(0xFF4D2D20)
              : const Color(0xFFe2e8f0);

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
                  style: GoogleFonts.outfit(
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
                      style: GoogleFonts.inter(
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
                                      style: GoogleFonts.inter(
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
                                      style: GoogleFonts.inter(
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
        title: const Text('Archive Event?'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final headerBg = isDark
        ? const Color(0xFF1A0F0A).withAlpha(150)
        : const Color(0xFFf8fafc);
    final textCol = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextCol = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);

    final now = DateTime.now();
    final total = _events.length;
    final upcomingCount = _events.where((ev) {
      final dStr = ev['date']?.toString().split('T')[0] ?? '';
      final parsed = DateTime.tryParse(dStr);
      return parsed != null &&
          !parsed.isBefore(DateTime(now.year, now.month, now.day));
    }).length;
    final pastCount = total - upcomingCount;

    return AppLayout(
      title: 'Events & Meetings',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Events & Executive Meetings',
            subtitle:
                'Schedule meetings, track attendee check-in registrations, and manage event rosters.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminOrange,
                  side: const BorderSide(color: kAdminOrange, width: 1.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminQrScannerPage(
                        onScan: (memberId) {
                          context.push('/verify-member/$memberId');
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: Text(
                  'Scan Check-in QR',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _showEventDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Create Event',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Metric Stats Cards ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Events',
                  value: '$total',
                  icon: Icons.event_note_outlined,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Upcoming Events',
                  value: '$upcomingCount',
                  icon: Icons.upcoming_outlined,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Past Events',
                  value: '$pastCount',
                  icon: Icons.history_rounded,
                  color: kAdminOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search Bar & Filter Tabs ─────────────────────────────────────────
          AdminToolbar(
            searchHint: 'Search events by title, venue, or description...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            filters: [
              _filterChip('All Events', 'all'),
              _filterChip('Upcoming', 'upcoming'),
              _filterChip('Past', 'past'),
            ],
          ),
          const SizedBox(height: 16),

          // ── Tabular Events Table ─────────────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (_hasError)
            FetchErrorView(onRetry: () => _fetch(refresh: true))
          else if (_filteredEvents.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                children: [
                  Icon(Icons.event_busy_outlined, size: 48, color: subTextCol),
                  const SizedBox(height: 12),
                  Text(
                    'No events match your current filter.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: textCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Create a new event or adjust your search filter.',
                    style: GoogleFonts.inter(fontSize: 17, color: subTextCol),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(headerBg),
                          headingTextStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: subTextCol,
                            letterSpacing: 0.5,
                          ),
                          dataTextStyle: GoogleFonts.outfit(
                            fontSize: 17,
                            color: textCol,
                          ),
                          columnSpacing: 24,
                          horizontalMargin: 24,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('EVENT / TITLE')),
                            DataColumn(label: Text('DATE & TIME')),
                            DataColumn(label: Text('VENUE / LOCATION')),
                            DataColumn(label: Text('ATTENDEES')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: _filteredEvents.map((ev) {
                            final title =
                                ev['title']?.toString() ?? 'Untitled Event';
                            final desc = ev['description']?.toString() ?? '';
                            final location =
                                ev['location']?.toString() ?? 'TBD';
                            final rawDate =
                                ev['date']?.toString().split('T')[0] ?? '';
                            final time = ev['time']?.toString() ?? '';
                            final attendeeCount =
                                ev['attendees_count'] ??
                                ev['attendee_count'] ??
                                0;

                            final parsed = DateTime.tryParse(rawDate);
                            final isPast =
                                parsed != null &&
                                parsed.isBefore(
                                  DateTime(now.year, now.month, now.day),
                                );

                            return DataRow(
                              cells: [
                                // 1. Title & Description Excerpt
                                DataCell(
                                  Container(
                                    constraints: BoxConstraints(
                                      minWidth: 200,
                                      maxWidth: constraints.maxWidth > 900
                                          ? constraints.maxWidth * 0.28
                                          : 280,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: textCol,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            desc,
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              color: subTextCol,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),

                                // 2. Date & Time
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _kOrange.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today_rounded,
                                              size: 13,
                                              color: _kOrange,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              rawDate.isNotEmpty
                                                  ? rawDate
                                                  : 'No Date',
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: _kOrange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (time.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          time,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: subTextCol,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // 3. Venue
                                DataCell(
                                  Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 200,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 16,
                                          color: subTextCol,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            location,
                                            style: GoogleFonts.inter(
                                              fontSize: 17,
                                              color: textCol,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // 4. Attendees Button
                                DataCell(
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      context.push(
                                        '/admin/events/${ev['id']}/attendees',
                                        extra: ev,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kBlue.withAlpha(25),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _kBlue.withAlpha(50),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.people_alt_outlined,
                                            size: 14,
                                            color: _kBlue,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '$attendeeCount Attendees',
                                            style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: _kBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 10,
                                            color: _kBlue,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // 5. Status
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPast
                                          ? Colors.grey.withAlpha(25)
                                          : _kGreen.withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isPast ? 'Past Event' : 'Upcoming',
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isPast ? Colors.grey : _kGreen,
                                      ),
                                    ),
                                  ),
                                ),

                                // 6. Action Buttons
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.people_outline_rounded,
                                          size: 18,
                                          color: _kBlue,
                                        ),
                                        tooltip: 'View Registered Attendees',
                                        onPressed: () {
                                          context.push(
                                            '/admin/events/${ev['id']}/attendees',
                                            extra: ev,
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: _kOrange,
                                        ),
                                        tooltip: 'Edit Event',
                                        onPressed: () => _showEventDialog(ev),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: _kRed,
                                        ),
                                        tooltip: 'Archive Event',
                                        onPressed: () => _deleteEvent(ev),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.outfit(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: 16,
          color: isSelected ? _kOrange : null,
        ),
      ),
      selected: isSelected,
      selectedColor: _kOrange.withAlpha(30),
      checkmarkColor: _kOrange,
      onSelected: (_) => setState(() => _filterStatus = value),
    );
  }
}
