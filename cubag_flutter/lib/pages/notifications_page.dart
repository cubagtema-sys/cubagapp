import 'package:flutter/material.dart';
import '../components/cubag_ui.dart';
import 'package:provider/provider.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;

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
      'color': CubagColors.valid,
      'label': 'Payment',
    },
    'meeting': {
      'icon': Icons.event_outlined,
      'color': const Color(0xFF3b82f6),
      'label': 'Meeting',
    },
    'compliance': {
      'icon': Icons.task_alt_outlined,
      'color': CubagColors.due,
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
    return Padding(
      padding: const EdgeInsets.only(right: CubagSpace.xs),
      child: ChoiceChip(
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
        onSelected: (_) => setState(() => _filter = value),
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
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: CubagColors.paper, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_none_rounded, size: 30, color: CubagColors.cocoa),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty || _filter != 'all' ? 'Nothing here' : 'You are all caught up',
              style: CubagType.headline,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery.isNotEmpty
                  ? 'Try other words, or clear the search.'
                  : (_filter != 'all'
                      ? 'No notifications in this list.'
                      : 'Payment, renewal and event updates will appear here.'),
              textAlign: TextAlign.center,
              style: CubagType.small,
            ),
            if (searchQuery.isNotEmpty || _filter != 'all') ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _filter = 'all';
                }),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CubagColors.lineStrong),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reset Filters',
                  style: TextStyle(
                    color: CubagColors.inkSoft,
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
                        color: CubagColors.lineStrong,
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
                                      cat['label']?.toString() ?? 'System',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: const Color(0xFF5F6B7E),
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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: CubagColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: CubagColors.sand,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CubagColors.line),
                          ),
                          child: SelectableText(
                            n['message']?.toString() ?? '',
                            style: TextStyle(
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
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: CubagColors.ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Close',
                                style: TextStyle(
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
    final cat = _categories[n['type']] ?? _categories['system']!;
    final isRead = n['read'] == true || n['read_at'] != null;
    final dateStr = _formatDate(n['created_at']?.toString() ?? n['time']?.toString());
    final label = (cat['label'] ?? 'System').toString();

    return Dismissible(
      key: ValueKey('notif_${n['id']}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(n['id']),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: CubagColors.lapsed,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(width: 6),
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
      child: Material(
        color: isRead ? CubagColors.paper : CubagColors.actionTint.withAlpha(140),
        child: InkWell(
          onTap: () => _showNotificationDetail(n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(CubagSpace.md, 14, CubagSpace.md, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isRead ? CubagColors.sand : CubagColors.paper,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(cat['icon'] as IconData, color: CubagColors.cocoa, size: 18),
                ),
                const SizedBox(width: CubagSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n['title']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: isRead
                                  ? CubagType.body.copyWith(color: CubagColors.ink)
                                  : CubagType.bodyStrong,
                            ),
                          ),
                          if (!isRead)
                            Semantics(
                              label: 'Unread',
                              child: Container(
                                margin: const EdgeInsets.only(left: 8, top: 8),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: CubagColors.action, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                      if ((n['message']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          n['message'].toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CubagType.small.copyWith(color: CubagColors.inkSoft),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        dateStr.isEmpty ? label : '$label · $dateStr',
                        style: CubagType.caption,
                      ),
                    ],
                  ),
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
                padding: const EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.lg, CubagSpace.lg, CubagSpace.xxxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header: title, unread count and the one bulk action.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: PageIntro(
                            'Notifications',
                            subtitle: unread > 0
                                ? 'You have $unread unread notification${unread == 1 ? '' : 's'}.'
                                : 'You are up to date.',
                          ),
                        ),
                        if (unread > 0)
                          TextButton(
                            onPressed: _markAllRead,
                            child: const Text('Mark all as read'),
                          ),
                      ],
                    ),
                    const SizedBox(height: CubagSpace.lg),

                    // Search input
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search notifications',
                        prefixIcon: const Icon(Icons.search_rounded, color: CubagColors.muted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, color: CubagColors.muted),
                                onPressed: () => setState(() => _searchCtrl.clear()),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: CubagSpace.sm),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All'),
                          _buildFilterChip(
                            'unread',
                            unread > 0 ? 'Unread ($unread)' : 'Unread',
                          ),
                          _buildFilterChip('payment', 'Payments'),
                          _buildFilterChip('meeting', 'Meetings'),
                          _buildFilterChip('compliance', 'Compliance'),
                          _buildFilterChip('system', 'System'),
                          _buildFilterChip('announcement', 'Announcements'),
                        ],
                      ),
                    ),
                    const SizedBox(height: CubagSpace.md),

                    if (_filter != 'all' || searchQuery.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _filter = 'all';
                          }),
                          child: const Text('Show all'),
                        ),
                      ),
                    const SizedBox(height: CubagSpace.xs),

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
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: CubagColors.paper,
                          borderRadius: BorderRadius.circular(CubagRadius.card),
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(CubagRadius.card),
                          border: Border.all(color: CubagColors.line),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < filtered.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: CubagColors.line),
                              _buildNotificationCard(filtered[i]),
                            ],
                          ],
                        ),
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
