import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/calendar_service.dart';
import '../components/shimmer_loader.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  List<dynamic> _events = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'upcoming'; // 'upcoming' or 'past'

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(_onScroll);
    _searchCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchCtrl.text.trim().toLowerCase();
        });
      }
    });
    SocketService().on('events_updated', _onRealtimeEventsUpdate);
  }

  void _onRealtimeEventsUpdate(dynamic _) {
    if (mounted) {
      _fetch(refresh: true);
    }
  }

  @override
  void dispose() {
    SocketService().off('events_updated', _onRealtimeEventsUpdate);
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && _hasMore) {
        _fetchMore();
      }
    }
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _loading = true;
        _events = [];
      });
    } else {
      if (!_loading && _events.isEmpty) setState(() => _loading = true);
    }

    final isPast = _selectedFilter == 'past';
    final endpoint =
        '/events?page=$_page&limit=20&status=${isPast ? 'past' : 'upcoming'}&include_past=$isPast';
    await ApiService().fetchDataWithCache(endpoint, (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      if (data != null) {
        final items = ApiService.ensureList(data);
        // If cached data is empty while network is still fetching, maintain loading shimmer
        if (isCached && items.isEmpty) {
          return;
        }
        setState(() {
          _loading = false;
          _events = items;
          if (data is Map && data.containsKey('total')) {
            _total = data['total'];
            _hasMore = _events.length < _total;
          } else {
            _hasMore = false;
          }
        });
      } else if (!isCached || hasError) {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    });
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final includePast = _selectedFilter == 'past';
      final data = await ApiService().fetchData(
        '/events?page=$_page&limit=20&include_past=$includePast',
      );
      if (mounted) {
        final newItems = ApiService.ensureList(data);
        setState(() {
          _events.addAll(newItems);
          if (data is Map && data.containsKey('total')) {
            _hasMore = _events.length < data['total'];
          } else {
            _hasMore = newItems.isNotEmpty;
          }
        });
      }
    } catch (_) {
      _page--;
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  Widget _buildFilterChip(String label, String value, Color primary) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      labelStyle: CubagType.label.copyWith(
        color: isSelected ? CubagColors.onCocoa : CubagColors.inkSoft,
      ),
      selectedColor: CubagColors.cocoa,
      backgroundColor: CubagColors.paper,
      side: BorderSide(color: isSelected ? CubagColors.cocoa : CubagColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) {
        if (_selectedFilter != value) {
          setState(() => _selectedFilter = value);
          _fetch(refresh: true);
        }
      },
    );
  }

  Widget _buildHeaderControls(Color primary, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search events',
            prefixIcon: const Icon(Icons.search_rounded, color: CubagColors.muted),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, color: CubagColors.muted),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: CubagSpace.sm),
        Row(
          children: [
            _buildFilterChip('Upcoming', 'upcoming', primary),
            const SizedBox(width: CubagSpace.xs),
            _buildFilterChip('Past', 'past', primary),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarBadge(DateTime? date, Color primary, bool isDark) {
    final badgeBorder = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final badgeBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final dayTextColor = isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;

    if (date == null) {
      return Container(
        width: 50,
        height: 54,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: badgeBorder, width: 1.0),
        ),
        child: Icon(Icons.calendar_month_rounded, color: primary, size: 22),
      );
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final monthStr = months[date.month - 1].toUpperCase();
    final dayStr = '${date.day}';

    return Container(
      width: 50,
      height: 54,
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: badgeBorder,
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          // Top red/orange bar with month
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: const BoxDecoration(
              color: CubagColors.cocoa,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(7),
              ),
            ),
            child: Text(
              monthStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          // Bottom section with day number
          Expanded(
            child: Center(
              child: Text(
                dayStr,
                style: TextStyle(
                  color: dayTextColor,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(
    String label,
    Color color, {
    bool isBlinking = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBlinking) ...[
            _BlinkingDot(color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: CubagType.caption.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color primary,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primary.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF5F6B7E),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: const Color(0xFF4D2D20),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEventDetails(
    BuildContext context,
    Map<String, dynamic> e,
    DateTime? date,
    Color primary,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Sheet handle and close button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Event details',
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: CubagColors.muted,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: CubagColors.sand),
              // Scrollable Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      e['title']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: const Color(0xFF281710),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Date & Time block
                    _buildDetailRow(
                      Icons.calendar_today_rounded,
                      'Date & Time',
                      '${e['date']?.toString() ?? ''}${e['time'] != null ? ' at ${e['time']}' : ''}',
                      primary,
                    ),
                    if (e['location'] != null &&
                        e['location'].toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.location_on_rounded,
                        'Location',
                        e['location'].toString(),
                        primary,
                      ),
                    ],
                    if (e['capacity'] != null &&
                        e['capacity'].toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.people_alt_rounded,
                        'Attendee Limit',
                        'Maximum ${e['capacity']} participants',
                        primary,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'About Event',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: const Color(0xFF281710),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CubagColors.sand,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: CubagColors.lineStrong.withAlpha(80),
                        ),
                      ),
                      child: Text(
                        e['description']?.toString() ??
                            'No description provided.',
                        style: TextStyle(
                          fontSize: 15,
                          color: CubagColors.inkSoft,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Add to Calendar action button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          final title = e['title']?.toString() ?? 'CUBAG Event';
                          final description =
                              e['description']?.toString() ?? '';
                          final location = e['location']?.toString() ?? 'Ghana';
                          final rawDate = e['date']?.toString();
                          DateTime startDate = DateTime.now().add(
                            const Duration(days: 1),
                          );
                          if (rawDate != null) {
                            startDate =
                                (DateTime.tryParse(rawDate) ?? startDate)
                                    .toLocal();
                          }

                          Navigator.pop(ctx);
                          await Future.delayed(const Duration(milliseconds: 250));

                          await CalendarService.addEventToCalendar(
                            title: title,
                            description: description,
                            location: location,
                            startDate: startDate,
                          );

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Event "$title" added to your calendar!',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: CubagColors.valid,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.event_available_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Add to Phone Calendar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListContent(Color primary) {
    if (_loading) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (ctx, i) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => const ShimmerListTile(),
      );
    }

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final filteredList = _events.where((e) {
      final title = (e['title']?.toString() ?? '').toLowerCase();
      final desc = (e['description']?.toString() ?? '').toLowerCase();
      final loc = (e['location']?.toString() ?? '').toLowerCase();
      final matchesSearch =
          title.contains(_searchQuery) ||
          desc.contains(_searchQuery) ||
          loc.contains(_searchQuery);
      if (!matchesSearch) return false;

      DateTime? date;
      try {
        date = DateTime.parse(e['date'].toString());
      } catch (e, st) {
        AppLogger.error('events_page', e, st);
      }
      if (date == null) return true;
      final eventDay = DateTime(date.year, date.month, date.day);

      if (_selectedFilter == 'past') {
        return eventDay.isBefore(todayDate);
      } else {
        return eventDay.isAfter(todayDate) || eventDay == todayDate;
      }
    }).toList();

    if (filteredList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CubagSpace.xxxl, horizontal: CubagSpace.lg),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: CubagColors.paper, shape: BoxShape.circle),
              child: const Icon(Icons.event_outlined, size: 30, color: CubagColors.cocoa),
            ),
            const SizedBox(height: CubagSpace.md),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No events match your search'
                  : (_selectedFilter == 'upcoming' ? 'No events scheduled yet' : 'No past events'),
              style: CubagType.headline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CubagSpace.xxs),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try other words, or clear the search.'
                  : (_selectedFilter == 'upcoming'
                      ? 'Meetings, seminars and CTI sessions will appear here. You can add them to your calendar.'
                      : 'Events you could attend will be listed here after they happen.'),
              textAlign: TextAlign.center,
              style: CubagType.small,
            ),
            if (_selectedFilter == 'upcoming' && _searchQuery.isEmpty) ...[
              const SizedBox(height: CubagSpace.md),
              TextButton(
                onPressed: () {
                  setState(() => _selectedFilter = 'past');
                  _fetch(refresh: true);
                },
                child: const Text('See past events'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: filteredList.map((e) {
        DateTime? date;
        try {
          date = DateTime.parse(e['date'].toString());
        } catch (e, st) {
          AppLogger.error('events_page', e, st);
        }

        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        final eventDay = date != null
            ? DateTime(date.year, date.month, date.day)
            : null;

        Widget? statusPill;
        if (eventDay != null) {
          if (eventDay == todayDate) {
            statusPill = _buildStatusPill(
              'Today',
              CubagColors.valid,
              isBlinking: true,
            );
          } else if (eventDay.isAfter(todayDate)) {
            statusPill = null;
          } else {
            statusPill = _buildStatusPill('Past', CubagColors.muted);
          }
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
        final textColor = isDark ? const Color(0xFFFFF8F3) : const Color(0xFF281710);
        final mutedColor = isDark ? const Color(0xFFC8ADA0) : CubagColors.muted;
        final borderColor = isDark ? const Color(0xFF3D261C) : CubagColors.line;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: borderColor),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(CubagRadius.card),
              onTap: () => _showEventDetails(context, e, date, primary),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Tear-off calendar badge
                    _buildCalendarBadge(date, primary, isDark),
                    const SizedBox(width: 16),
                    // Middle Column: Event info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  e['title']?.toString() ?? '',
                                  style: CubagType.bodyStrong.copyWith(color: textColor),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (statusPill != null) ...[
                                const SizedBox(width: 8),
                                statusPill,
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            e['description']?.toString() ?? '',
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          // Metadata Info Row
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              if (e['time'] != null &&
                                  e['time'].toString().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.access_time_rounded,
                                      size: 13,
                                      color: Color(0xFF5F6B7E),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      e['time'].toString(),
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: CubagColors.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (e['location'] != null &&
                                  e['location'].toString().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.location_on_rounded,
                                      size: 13,
                                      color: Color(0xFF5F6B7E),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        e['location'].toString(),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: CubagColors.muted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (e['capacity'] != null &&
                                  e['capacity'].toString().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.people_outline_rounded,
                                      size: 13,
                                      color: Color(0xFF5F6B7E),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Limit: ${e['capacity']}',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: CubagColors.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF5F6B7E),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppLayout(
      title: 'Events',
      scrollable: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.lg, CubagSpace.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderControls(primary, isDark),
                const SizedBox(height: 16),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _fetch(refresh: true),
                    color: primary,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildListContent(primary),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  final Color color;
  const _BlinkingDot({required this.color});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
