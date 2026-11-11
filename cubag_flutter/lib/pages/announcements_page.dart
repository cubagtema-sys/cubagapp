import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});
  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  List<dynamic> _alerts = [];
  final Set<dynamic> _expanded = {};
  String _filter = 'All';
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(_onScroll);
    SocketService().on('announcements_updated', _onRealtimeUpdate);
  }

  void _onRealtimeUpdate(dynamic _) {
    if (mounted) {
      _fetch(refresh: true);
    }
  }

  @override
  void dispose() {
    SocketService().off('announcements_updated', _onRealtimeUpdate);
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

  void _sortAlerts(List<dynamic> items) {
    items.sort((a, b) {
      if (a is! Map || b is! Map) return 0;
      final da = DateTime.tryParse(a['created_at']?.toString() ?? a['date']?.toString() ?? '');
      final db = DateTime.tryParse(b['created_at']?.toString() ?? b['date']?.toString() ?? '');
      if (da != null && db != null) {
        return db.compareTo(da);
      }
      final idA = int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return idB.compareTo(idA);
    });
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _loading = true;
        _alerts = [];
      });
    } else {
      if (!_loading) setState(() => _loading = true);
    }
    await ApiService().fetchDataWithCache(
      '/announcements?page=$_page&limit=20',
      (data, isCached, {bool hasError = false}) {
        if (mounted && data != null) {
          setState(() {
            _loading = false;
            final items = ApiService.ensureList(data);
            _sortAlerts(items);
            _alerts = items;
            if (data is Map && data.containsKey('total')) {
              _total = data['total'];
              _hasMore = _alerts.length < _total;
            } else {
              _hasMore = false;
            }
          });
        }
      },
    );
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final data = await ApiService().fetchData(
        '/announcements?page=$_page&limit=20',
      );
      if (mounted) {
        final newItems = ApiService.ensureList(data);
        setState(() {
          _alerts.addAll(newItems);
          _sortAlerts(_alerts);
          if (data is Map && data.containsKey('total')) {
            _hasMore = _alerts.length < data['total'];
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

  Future<void> _markAllRead() async {
    try {
      await ApiService().post('/announcements/mark-read', data: {});
      setState(
        () => _alerts = _alerts.map((a) => {...a, 'is_read': true}).toList(),
      );
    } catch (e, st) {
      AppLogger.error('announcements_page', e, st);
    }
  }

  Future<void> _toggleExpand(dynamic id, bool isRead) async {
    if (!isRead) {
      try {
        await ApiService().post(
          '/announcements/mark-read',
          data: {'announcement_id': id},
        );
        setState(
          () => _alerts = _alerts
              .map((a) => a['id'] == id ? {...a, 'is_read': true} : a)
              .toList(),
        );
      } catch (e, st) {
        AppLogger.error('announcements_page', e, st);
      }
    }
    setState(
      () => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id),
    );
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

  Widget _categoryBadge(String category) {
    final cat = category.toUpperCase();
    Color bg = CubagColors.sand;
    Color fg = CubagColors.inkSoft;

    if (cat == 'OPERATIONS' || cat == 'PORT') {
      bg = const Color(0xFFe0f2fe);
      fg = const Color(0xFF0369a1);
    } else if (cat == 'BILLING' || cat == 'FINANCE') {
      bg = CubagColors.validTint;
      fg = const Color(0xFF15803d);
    } else if (cat == 'REGULATORY' || cat == 'LEGAL') {
      bg = const Color(0xFFf3e8ff);
      fg = const Color(0xFF7e22ce);
    } else if (cat == 'GENERAL') {
      bg = CubagColors.dueTint;
      fg = const Color(0xFFb45309);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        cat,
        style: TextStyle(
          fontSize: 14,
          color: fg,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    final cat = category.toUpperCase();
    if (cat == 'OPERATIONS' || cat == 'PORT') {
      return Icons.anchor_outlined;
    } else if (cat == 'BILLING' || cat == 'FINANCE') {
      return Icons.account_balance_wallet_outlined;
    } else if (cat == 'REGULATORY' || cat == 'LEGAL') {
      return Icons.gavel_outlined;
    }
    return Icons.campaign_outlined;
  }

  Widget _buildFilterChip(String category) {
    final isSelected = _filter == category;
    final displayName = category == 'All'
        ? 'All Updates'
        : category.toUpperCase();
    return GestureDetector(
      onTap: () => setState(() => _filter = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kOrange : CubagColors.sand,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _kOrange : CubagColors.line,
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
          displayName,
          style: TextStyle(
            color: isSelected ? Colors.white : CubagColors.inkSoft,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      ..._alerts
          .map((a) => a['category'] ?? a['type'] ?? 'GENERAL')
          .toSet()
          .cast<String>(),
    ];

    final searchQuery = _searchCtrl.text.toLowerCase().trim();
    final filtered = _alerts.where((a) {
      final categoryMatch =
          _filter == 'All' || (a['category'] ?? a['type']) == _filter;
      if (!categoryMatch) return false;

      if (searchQuery.isEmpty) return true;
      final title = (a['title'] ?? '').toString().toLowerCase();
      final body = (a['body'] ?? a['content'] ?? '').toString().toLowerCase();
      return title.contains(searchQuery) || body.contains(searchQuery);
    }).toList();

    final unread = _alerts.where((a) => a['is_read'] != true).length;

    return AppLayout(
      title: 'Announcements',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: () => _fetch(refresh: true),
        color: _kOrange,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Input Box
                    Container(
                      decoration: BoxDecoration(
                        color: CubagColors.sand,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextFormField(
                        controller: _searchCtrl,
                        onChanged: (val) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search circulars by title or keyword...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF5F6B7E),
                            fontSize: 18,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF5F6B7E),
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    color: Color(0xFF5F6B7E),
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

                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: categories
                            .map((c) => _buildFilterChip(c))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          searchQuery.isNotEmpty
                              ? 'SEARCH RESULTS (${filtered.length})'
                              : 'LATEST CIRCULARS (${filtered.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: CubagColors.muted,
                          ),
                        ),
                        if (unread > 0)
                          TextButton.icon(
                            onPressed: _markAllRead,
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: const Text(
                              'Mark All Read',
                              style: TextStyle(
                                fontSize: 16,
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

                    // Announcements List
                    if (_loading)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 8,
                        separatorBuilder: (ctx, i) =>
                            const SizedBox(height: 16),
                        itemBuilder: (ctx, i) => const ShimmerListTile(),
                      )
                    else if (filtered.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 60,
                            horizontal: 24,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                  color: CubagColors.sand,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.campaign_outlined,
                                  size: 48,
                                  color: CubagColors.lineStrong,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Circulars Found',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: CubagColors.inkSoft,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                searchQuery.isNotEmpty
                                    ? 'Try refining your keywords or clearing the search query.'
                                    : 'There are no active circulars posted in this category.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  color: Color(0xFF5F6B7E),
                                  height: 1.4,
                                ),
                              ),
                              if (searchQuery.isNotEmpty ||
                                  _filter != 'All') ...[
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    _searchCtrl.clear();
                                    _filter = 'All';
                                  }),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: CubagColors.lineStrong,
                                    ),
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
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 16),
                        itemBuilder: (context, i) {
                          return _buildAnnouncementCard(filtered[i]);
                        },
                      ),

                    if (_loadingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(color: _kOrange),
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

  void _showAnnouncementDetail(Map<String, dynamic> a) {
    final isRead = a['is_read'] == true;
    if (!isRead) {
      _toggleExpand(a['id'], false);
    }
    final category = (a['category'] ?? a['type'] ?? 'General').toString();
    final dateStr = _formatDate(a['created_at']);
    final iconData = _categoryIcon(category);

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
                                color: _kOrange.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(iconData, color: _kOrange, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _categoryBadge(category),
                                      const Spacer(),
                                      Text(
                                        'Ref: CIRC-${a['id'] ?? '001'}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: const Color(0xFF5F6B7E),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: const Color(0xFF5F6B7E),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          a['title'] ?? '',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: CubagColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          a['body'] ?? a['content'] ?? '',
                          style: TextStyle(
                            fontSize: 18,
                            color: const Color(0xFF281710),
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1, color: CubagColors.line),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: CubagColors.ink.withAlpha(15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                size: 14,
                                color: CubagColors.ink,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Issued by: ',
                              style: TextStyle(
                                fontSize: 15,
                                color: CubagColors.muted,
                              ),
                            ),
                            Text(
                              '${a['posted_by'] ?? 'CUBAG National Secretariat'}',
                              style: TextStyle(
                                fontSize: 15,
                                color: CubagColors.ink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
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

  Widget _buildAnnouncementCard(Map<String, dynamic> a) {
    final isRead = a['is_read'] == true;
    final category = (a['category'] ?? a['type'] ?? 'General').toString();
    final dateStr = _formatDate(a['created_at']);
    final iconData = _categoryIcon(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : _kOrange.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead ? CubagColors.line : _kOrange.withAlpha(80),
          width: isRead ? 1.0 : 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showAnnouncementDetail(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Category Icon Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isRead
                        ? CubagColors.sand
                        : _kOrange.withAlpha(20)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    iconData,
                    color: isRead ? CubagColors.muted : _kOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Decompressed Title & Subtitle Stack
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              a['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: CubagColors.ink,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 13,
                                color: const Color(0xFF5F6B7E),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _categoryBadge(category),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              a['body'] ?? a['content'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: CubagColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
