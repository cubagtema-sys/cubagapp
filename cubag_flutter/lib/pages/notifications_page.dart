import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  String _filter = 'all';
  List<Map<String, dynamic>> _notifications = [];
  final TextEditingController _searchCtrl = TextEditingController();

  final Map<String, Map<String, dynamic>> _categories = {
    'payment': {
      'icon': Icons.payments_outlined,
      'color': const Color(0xFF10b981),
      'label': 'Payment',
    },
    'meeting': {
      'icon': Icons.event_outlined,
      'color': const Color(0xFF3b82f6),
      'label': 'Meeting',
    },
    'compliance': {
      'icon': Icons.task_alt_outlined,
      'color': const Color(0xFFf59e0b),
      'label': 'Compliance',
    },
    'system': {
      'icon': Icons.info_outline,
      'color': _kOrange,
      'label': 'System',
    },
    'announcement': {
      'icon': Icons.campaign_outlined,
      'color': const Color(0xFF8b5cf6),
      'label': 'Announcement',
    },
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/notifications');
      dynamic rawItems;
      if (res.statusCode == 200 && res.data != null) {
        rawItems = (res.data is Map && res.data.containsKey('items'))
            ? res.data['items']
            : res.data;
      } else {
        final cachedData = await CacheService().fetchCachedMap(
          '/notifications',
        );
        rawItems = cachedData.containsKey('items')
            ? cachedData['items']
            : cachedData;
      }
      final data = ApiService.ensureList(rawItems);
      final list = data.map((a) {
        final Map<String, dynamic> item = (a is Map)
            ? Map<String, dynamic>.from(a)
            : {};
        return {
          'id': item['id'],
          'type': item['category']?.toString().toLowerCase() ?? 'announcement',
          'title': item['title']?.toString() ?? '',
          'message':
              item['body']?.toString() ?? item['content']?.toString() ?? '',
          'created_at': item['created_at']?.toString() ?? '',
          'time': item['created_at'] != null
              ? _formatDate(item['created_at'].toString())
              : '',
          'read':
              item['read_at'] != null ||
              item['is_read'] == true ||
              item['read'] == true,
        };
      }).toList();

      if (!mounted) return;
      setState(() => _notifications = List<Map<String, dynamic>>.from(list));

      final service = Provider.of<NotificationService>(context, listen: false);
      service.syncFromNotifications(data);
      await service.fetchUnreadCount(force: true);
    } catch (e, st) {
      AppLogger.error('notifications_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService().post('/notifications/mark-read', data: {});
      if (!mounted) return;
      final updated = _notifications.map((n) => {...n, 'read': true}).toList();
      setState(() => _notifications = updated);
      final service = Provider.of<NotificationService>(context, listen: false);
      service.syncFromNotifications(
        updated.map((n) => {'id': n['id'], 'is_read': true}).toList(),
      );
      await service.fetchUnreadCount(force: true);
    } catch (e, st) {
      AppLogger.error('notifications_page', e, st);
    }
  }

  Future<void> _markRead(dynamic id) async {
    final notification = _notifications.firstWhere(
      (n) => n['id'] == id,
      orElse: () => {},
    );
    if (notification.isNotEmpty && notification['read'] != true) {
      try {
        await ApiService().post(
          '/notifications/mark-read',
          data: {'notification_id': id},
        );
        if (!mounted) return;
        final updated = _notifications
            .map((n) => n['id'] == id ? {...n, 'read': true} : n)
            .toList();
        setState(() => _notifications = updated);
        final service = Provider.of<NotificationService>(
          context,
          listen: false,
        );
        service.syncFromNotifications(
          updated.map((n) => {'id': n['id'], 'is_read': n['read']}).toList(),
        );
        await service.fetchUnreadCount(force: true);
      } catch (e, st) {
        AppLogger.error('notifications_page', e, st);
      }
    }
  }

  // F-36 fix: delete from server first, then remove locally
  Future<void> _delete(dynamic id) async {
    try {
      await ApiService().delete('/notifications/$id');
    } catch (_) {
      // If server call fails, still remove locally (graceful degradation)
    }
    if (mounted) {
      final updated = _notifications.where((n) => n['id'] != id).toList();
      setState(() => _notifications = updated);
      final service = Provider.of<NotificationService>(context, listen: false);
      service.syncFromNotifications(
        updated.map((n) => {'id': n['id'], 'is_read': n['read']}).toList(),
      );
      await service.fetchUnreadCount(force: true);
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      }

      final months = [
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
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kOrange : const Color(0xFFf1f5f9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _kOrange : const Color(0xFFe2e8f0),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kOrange.withAlpha(30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF475569),
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFf8fafc),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: Color(0xFFcbd5e1),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Notifications',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery.isNotEmpty
                  ? 'Try refining your keywords or clearing the search query.'
                  : 'You are all caught up! No active notifications found.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF94a3b8),
                height: 1.4,
              ),
            ),
            if (searchQuery.isNotEmpty || _filter != 'all') ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _filter = 'all';
                }),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFcbd5e1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reset Filters',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showNotificationDetail(Map<String, dynamic> n) {
    if (n['read'] != true) {
      _markRead(n['id']);
    }
    final cat = _categories[n['type']] ?? _categories['system']!;
    final color = cat['color'] as Color;
    final dateStr = _formatDate(
      n['created_at']?.toString() ?? n['time']?.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Align(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFcbd5e1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                (cat['icon'] as IconData?) ??
                                    Icons.notifications_rounded,
                                color: color,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (cat['label']?.toString() ?? 'SYSTEM')
                                          .toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: const Color(0xFF94a3b8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          n['title']?.toString() ?? '',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFf8fafc),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                          ),
                          child: SelectableText(
                            n['message']?.toString() ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF4D2D20),
                              height: 1.55,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _delete(n['id']);
                              },
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                              label: Text(
                                'Delete',
                                style: GoogleFonts.inter(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A0F0A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Close',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cat = _categories[n['type']] ?? _categories['system']!;
    final color = cat['color'] as Color;
    final isRead = n['read'] == true || n['read_at'] != null;
    final dateStr = _formatDate(
      n['created_at']?.toString() ?? n['time']?.toString(),
    );

    final cardBg = isDark
        ? (isRead ? const Color(0xFF1A0F0A) : color.withAlpha(25))
        : (isRead ? Colors.white : color.withAlpha(12));
    final borderColor = isDark
        ? (isRead ? const Color(0xFF281710) : color.withAlpha(120))
        : (isRead ? const Color(0xFFE2E8F0) : color.withAlpha(90));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isRead ? 1.0 : 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showNotificationDetail(n),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Category Icon Avatar (matching skeleton tile size)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 40 : 20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(cat['icon'] as IconData, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                // Compact Title & Subtitle Stack
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        n['message']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          color: isDark ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white60 : Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unread = _notifications.where((n) => n['read'] != true && n['read_at'] == null).length;
    final searchQuery = _searchCtrl.text.toLowerCase().trim();

    final filtered = _notifications.where((n) {
      bool filterMatch = true;
      if (_filter == 'unread') {
        filterMatch = n['read'] != true && n['read_at'] == null;
      } else if (_filter != 'all') {
        filterMatch = n['type'] == _filter;
      }
      if (!filterMatch) return false;

      if (searchQuery.isEmpty) return true;
      final title = (n['title'] ?? '').toString().toLowerCase();
      final message = (n['message'] ?? '').toString().toLowerCase();
      return title.contains(searchQuery) || message.contains(searchQuery);
    }).toList();

    return AppLayout(
      title: 'Notifications',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: _kOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Title
                    Text(
                      'Activity Feed',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Latest system alerts and personal notifications.',
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white70 : const Color(0xFF64748b),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Search input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFf1f5f9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextFormField(
                        controller: _searchCtrl,
                        onChanged: (val) => setState(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Search notifications by title or keyword...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94a3b8),
                            fontSize: 16,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF94a3b8),
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    color: Color(0xFF94a3b8),
                                  ),
                                  onPressed: () => setState(() {
                                    _searchCtrl.clear();
                                  }),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All Notifications'),
                          _buildFilterChip('unread', 'Unread Only'),
                          _buildFilterChip('payment', 'Payment'),
                          _buildFilterChip('meeting', 'Meeting'),
                          _buildFilterChip('compliance', 'Compliance'),
                          _buildFilterChip('system', 'System'),
                          _buildFilterChip('announcement', 'Announcement'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          searchQuery.isNotEmpty
                              ? 'SEARCH RESULTS (${filtered.length})'
                              : 'LATEST UPDATES (${filtered.length})',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: const Color(0xFF64748b),
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (unread > 0)
                          TextButton.icon(
                            onPressed: _markAllRead,
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: const Text(
                              'Mark All Read',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: _kOrange,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Feed Items
                    if (_loading)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 5,
                        separatorBuilder: (ctx, i) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) => const ShimmerListTile(),
                      )
                    else if (filtered.isEmpty)
                      _buildEmptyState(searchQuery)
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (ctx, i) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final n = filtered[i];
                          return _buildNotificationCard(n);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
