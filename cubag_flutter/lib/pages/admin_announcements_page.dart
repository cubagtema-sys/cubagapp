import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;
const _kAmber = CubagColors.due;
const _kBlue = Color(0xFF3B82F6);
const _kIndigo = Color(0xFF6366F1);
const _kPurple = Color(0xFF8B5CF6);

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});
  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _api = ApiService();

  String _tab = 'active'; // 'active' or 'archived'
  String _categoryFilter = 'All';
  String _searchQuery = '';
  String _toastMessage = '';
  Color _toastColor = _kGreen;

  // Active Broadcasts
  List<dynamic> _active = [];
  bool _loadingActive = true;
  int _pageActive = 1;
  bool _hasMoreActive = false;
  int _totalActive = 0;

  // Archived Broadcasts
  List<dynamic> _archived = [];
  bool _loadingArchived = true;
  int _pageArchived = 1;
  bool _hasMoreArchived = false;
  int _totalArchived = 0;

  // Expanded items state
  final Set<int> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchActive(page: 1);
    _fetchArchived(page: 1);
  }

  Future<void> _clearCache() async {
    await ApiService.deleteCacheKeysMatching('announcements/admin/all');
    await ApiService.deleteCacheKeysMatching('announcements');
  }

  Future<void> _fetchActive({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _pageActive = page;
      if (_active.isEmpty) _loadingActive = true;
    });

    await _api.fetchDataWithCache(
      '/announcements/admin/all?archived=false&page=$_pageActive&limit=15',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (hasError && _active.isEmpty) {
          setState(() => _loadingActive = false);
          return;
        }
        if (data == null) {
          setState(() => _loadingActive = false);
          return;
        }
        setState(() {
          _loadingActive = false;
          _active = ApiService.ensureList(data);
          if (data is Map && data.containsKey('total')) {
            _totalActive = (data['total'] as num?)?.toInt() ?? _active.length;
            _hasMoreActive = (_pageActive * 15) < _totalActive;
          } else {
            _totalActive = _active.length;
            _hasMoreActive = _active.length == 15;
          }
        });
      },
    );
  }

  Future<void> _fetchArchived({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _pageArchived = page;
      if (_archived.isEmpty) _loadingArchived = true;
    });

    await _api.fetchDataWithCache(
      '/announcements/admin/all?archived=true&page=$_pageArchived&limit=15',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (hasError && _archived.isEmpty) {
          setState(() => _loadingArchived = false);
          return;
        }
        if (data == null) {
          setState(() => _loadingArchived = false);
          return;
        }
        setState(() {
          _loadingArchived = false;
          _archived = ApiService.ensureList(data);
          if (data is Map && data.containsKey('total')) {
            _totalArchived = (data['total'] as num?)?.toInt() ?? _archived.length;
            _hasMoreArchived = (_pageArchived * 15) < _totalArchived;
          } else {
            _totalArchived = _archived.length;
            _hasMoreArchived = _archived.length == 15;
          }
        });
      },
    );
  }

  Future<void> _archiveAnnouncement(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kRed.withAlpha(25), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.archive_outlined, color: _kRed, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Archive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to archive this announcement? It will be moved from the live member broadcast feed.',
          style: TextStyle(fontSize: 14, color: const Color(0xFF6B5E55), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: const Color(0xFF6B5E55), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Archive', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _active.removeWhere((a) => a['id'] == id));
    try {
      await _api.deleteData('announcements/$id');
      _showToast('Circular moved to archive.', _kGreen);
      await _clearCache();
      _fetchArchived(page: 1);
    } catch (_) {
      _fetchActive(page: _pageActive);
      _showToast('Failed to archive circular', _kRed);
    }
  }

  Future<void> _restoreAnnouncement(int id) async {
    setState(() => _archived.removeWhere((a) => a['id'] == id));
    try {
      await _api.patchData('announcements/$id/restore', {});
      _showToast('Circular restored back to live feed.', _kGreen);
      await _clearCache();
      _fetchActive(page: 1);
    } catch (_) {
      _fetchArchived(page: _pageArchived);
      _showToast('Failed to restore circular', _kRed);
    }
  }

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String category = 'General';
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
          final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
          final textCol = isDark ? Colors.white : const Color(0xFF1F1612);
          final textMuted = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

          final categories = [
            {'label': 'General', 'key': 'General', 'icon': Icons.article_outlined, 'color': _kBlue},
            {'label': 'Urgent', 'key': 'Urgent Alert', 'icon': Icons.priority_high_rounded, 'color': _kRed},
            {'label': 'Regulatory', 'key': 'Regulatory & Port Advisory', 'icon': Icons.gavel_rounded, 'color': _kIndigo},
            {'label': 'Maintenance', 'key': 'System Maintenance', 'icon': Icons.build_circle_outlined, 'color': _kAmber},
            {'label': 'Event', 'key': 'Event', 'icon': Icons.event_rounded, 'color': _kPurple},
          ];

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.campaign_rounded, color: _kOrange, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'New announcement',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textCol),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    Text(
                      'Category',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: categories.map((c) {
                        final sel = category == c['key'];
                        const color = CubagColors.cocoa;
                        return InkWell(
                          onTap: () => setDialogState(() => category = c['key'] as String),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: sel ? color.withAlpha(25) : (isDark ? const Color(0xFF4D2D20) : CubagColors.sand),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: sel ? color : border, width: sel ? 1.5 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(c['icon'] as IconData, size: 13, color: sel ? color : textMuted),
                                const SizedBox(width: 5),
                                Text(
                                  c['label'] as String,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                    color: sel ? color : textCol,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      'Title',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(fontSize: 14, color: textCol),
                      decoration: InputDecoration(
                        hintText: 'For example: New clearance hours at Tema',
                        hintStyle: TextStyle(fontSize: 13, color: textMuted),
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      'Message',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bodyCtrl,
                      maxLines: 5,
                      style: TextStyle(fontSize: 13.5, color: textCol, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Enter announcement directives, dates, or guidelines for members...',
                        hintStyle: TextStyle(fontSize: 13, color: textMuted),
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final title = titleCtrl.text.trim();
                                  final body = bodyCtrl.text.trim();
                                  if (title.isEmpty || body.isEmpty) {
                                    _showToast('Please provide both title and message content', _kAmber);
                                    return;
                                  }
                                  setDialogState(() => submitting = true);
                                  try {
                                    final res = await _api.postData('announcements', {
                                      'title': title,
                                      'body': body,
                                      'category': category,
                                      'posted_by': 'CUBAG Secretariat',
                                    });
                                    if (res != null) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _showToast('Announcement published successfully!', _kGreen);
                                      await _clearCache();
                                      _fetchActive(page: 1);
                                    }
                                  } catch (e, st) {
                                    AppLogger.error('admin_announcements_create', e, st);
                                    _showToast('Failed to publish announcement', _kRed);
                                  }
                                  if (mounted) setDialogState(() => submitting = false);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: submitting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 15),
                          label: Text(submitting ? 'Publishing…' : 'Publish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final titleEditCtrl = TextEditingController(text: item['title'] ?? '');
    final bodyEditCtrl = TextEditingController(text: item['body'] ?? '');
    String editCategory = item['category'] ?? 'General';
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
          final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
          final textCol = isDark ? Colors.white : const Color(0xFF1F1612);
          final textMuted = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.edit_note_rounded, color: _kOrange, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Edit announcement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textCol)),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    Text('Category', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['General', 'Urgent Alert', 'Regulatory & Port Advisory', 'System Maintenance', 'Event'].map((c) {
                        final sel = editCategory == c;
                        return ChoiceChip(
                          label: Text(_shortCategory(c), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: sel ? Colors.white : textCol)),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: CubagColors.cocoa,
                          backgroundColor: isDark ? const Color(0xFF4D2D20) : CubagColors.sand,
                          onSelected: (val) {
                            if (val) setDialogState(() => editCategory = c);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('Title', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleEditCtrl,
                      style: TextStyle(fontSize: 14, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('Message', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bodyEditCtrl,
                      maxLines: 5,
                      style: TextStyle(fontSize: 13.5, color: textCol, height: 1.4),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? CubagColors.ink : const Color(0xFFFAF6F0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final newT = titleEditCtrl.text.trim();
                                  final newB = bodyEditCtrl.text.trim();
                                  if (newT.isEmpty || newB.isEmpty) return;

                                  setDialogState(() => saving = true);
                                  try {
                                    final res = await _api.put(
                                      '/announcements/${item['id']}',
                                      data: {'title': newT, 'body': newB, 'category': editCategory},
                                    );
                                    if (res.statusCode == 200) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _showToast('Announcement updated successfully!', _kGreen);
                                      await _clearCache();
                                      _fetchActive(page: _pageActive);
                                    }
                                  } catch (e, st) {
                                    AppLogger.error('admin_announcements_edit', e, st);
                                  }
                                  if (mounted) setDialogState(() => saving = false);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: saving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 15),
                          label: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showToast(String msg, Color color) {
    setState(() {
      _toastMessage = msg;
      _toastColor = color;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toastMessage = '');
    });
  }

  List<dynamic> _filterList(List<dynamic> list) {
    var filtered = list;
    if (_categoryFilter != 'All') {
      filtered = filtered.where((a) => (a['category'] as String? ?? 'General') == _categoryFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((a) {
        final title = (a['title'] as String? ?? '').toLowerCase();
        final body = (a['body'] as String? ?? '').toLowerCase();
        final posted = (a['posted_by'] as String? ?? '').toLowerCase();
        return title.contains(q) || body.contains(q) || posted.contains(q);
      }).toList();
    }
    return filtered;
  }

  static const _categories = [
    ('All', 'All categories'),
    ('Urgent Alert', 'Urgent'),
    ('Regulatory & Port Advisory', 'Regulatory'),
    ('System Maintenance', 'Maintenance'),
    ('Event', 'Events'),
    ('General', 'General'),
  ];

  String _shortCategory(String c) =>
      _categories.firstWhere((e) => e.$1 == c, orElse: () => (c, c)).$2;

  @override
  Widget build(BuildContext context) {
    final active = _tab == 'active';
    final displayList = active ? _filterList(_active) : _filterList(_archived);
    final isLoading = active ? _loadingActive : _loadingArchived;
    final page = active ? _pageActive : _pageArchived;
    final hasMore = active ? _hasMoreActive : _hasMoreArchived;

    return AppLayout(
      title: 'Announcements',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Announcements',
                subtitle: 'Notices every member sees on their Home screen. Archive one to take it down; you can restore it later.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _clearCache();
                      _fetchActive(page: 1);
                      _fetchArchived(page: 1);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New announcement'),
                  ),
                ],
              ),
              if (_toastMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: CubagSpace.md),
                  padding: const EdgeInsets.all(CubagSpace.md),
                  decoration: BoxDecoration(
                    color: _toastColor == _kRed ? CubagColors.lapsedTint : CubagColors.validTint,
                    borderRadius: BorderRadius.circular(CubagRadius.card),
                  ),
                  child: Text(
                    _toastMessage,
                    style: CubagType.label.copyWith(color: _toastColor == _kRed ? CubagColors.lapsed : CubagColors.valid),
                  ),
                ),
              FilterTabs(
                tabs: [('active', 'Live · $_totalActive'), ('archived', 'Archived · $_totalArchived')],
                selected: _tab,
                onSelected: (k) => setState(() => _tab = k),
              ),
              const SizedBox(height: CubagSpace.sm),
              LayoutBuilder(
                builder: (context, c) {
                  final search = AdminSearchField(
                    hint: 'Search title, text or author',
                    onChanged: (v) => setState(() => _searchQuery = v),
                  );
                  final category = SizedBox(
                    width: c.maxWidth < 560 ? double.infinity : 210,
                    child: CustomDropdown<String>(
                      value: _categoryFilter,
                      items: [for (final e in _categories) DropdownItem(value: e.$1, label: e.$2)],
                      onChanged: (v) => setState(() => _categoryFilter = v),
                    ),
                  );
                  if (c.maxWidth < 560) {
                    return Column(children: [search, const SizedBox(height: CubagSpace.xs), category]);
                  }
                  return Row(children: [Expanded(child: search), const SizedBox(width: CubagSpace.sm), category]);
                },
              ),
              const SizedBox(height: CubagSpace.md),
              if (isLoading)
                Column(
                  children: List.generate(
                    3,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (displayList.isEmpty)
                EmptyMessage(
                  icon: Icons.campaign_outlined,
                  title: _searchQuery.isNotEmpty || _categoryFilter != 'All'
                      ? 'No announcements match'
                      : (active ? 'Nothing live right now' : 'Nothing archived'),
                  message: _searchQuery.isNotEmpty || _categoryFilter != 'All'
                      ? 'Try other words or another category.'
                      : (active ? 'Post a notice and every member sees it on Home.' : 'Archived notices are kept here.'),
                  action: active && _searchQuery.isEmpty && _categoryFilter == 'All'
                      ? FilledButton.icon(
                          onPressed: _showCreateDialog,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New announcement'),
                        )
                      : null,
                )
              else ...[
                AdminRowGroup(children: [for (final a in displayList) _announcementItem(Map<String, dynamic>.from(a as Map))]),
                if (page > 1 || hasMore)
                  Row(
                    children: [
                      Expanded(child: Text('Page $page', style: CubagType.caption)),
                      IconButton(
                        tooltip: 'Previous page',
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: page > 1
                            ? () => active ? _fetchActive(page: page - 1) : _fetchArchived(page: page - 1)
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: hasMore
                            ? () => active ? _fetchActive(page: page + 1) : _fetchArchived(page: page + 1)
                            : null,
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _announcementItem(Map<String, dynamic> item) {
    final id = item['id'] as int? ?? 0;
    final title = (item['title'] as String? ?? '').trim();
    final body = (item['body'] as String? ?? '').trim();
    final category = (item['category'] as String? ?? 'General').trim();
    final postedBy = (item['posted_by'] as String? ?? 'CUBAG Secretariat').trim();
    final createdAt = (item['created_at'] as String? ?? '').trim();
    final date = createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt;
    final isExpanded = _expandedIds.contains(id);
    final isArchived = _tab == 'archived';
    final urgent = category == 'Urgent Alert';

    return Padding(
      padding: const EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.md, CubagSpace.xs, CubagSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (urgent)
                const StatusChip('Urgent', kind: StatusKind.bad)
              else
                Text(_shortCategory(category), style: CubagType.caption.copyWith(color: CubagColors.cocoa, fontWeight: FontWeight.w700)),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _showEditDialog(item);
                    case 'archive':
                      _archiveAnnouncement(id);
                    case 'restore':
                      _restoreAnnouncement(id);
                    case 'copy':
                      Clipboard.setData(ClipboardData(text: '$title\n\n$body'));
                      _showToast('Text copied.', _kGreen);
                  }
                },
                itemBuilder: (_) => [
                  if (!isArchived) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                  if (!isArchived)
                    PopupMenuItem(value: 'archive', child: Text('Archive', style: TextStyle(color: CubagColors.lapsed)))
                  else
                    const PopupMenuItem(value: 'restore', child: Text('Restore')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: CubagSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(title, style: CubagType.headline),
                const SizedBox(height: CubagSpace.xxs),
                Text(
                  body,
                  maxLines: isExpanded ? null : 3,
                  overflow: isExpanded ? null : TextOverflow.ellipsis,
                  style: CubagType.body.copyWith(color: CubagColors.inkSoft),
                ),
                if (body.length > 160)
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                    onPressed: () => setState(() => isExpanded ? _expandedIds.remove(id) : _expandedIds.add(id)),
                    child: Text(isExpanded ? 'Show less' : 'Read more'),
                  ),
                const SizedBox(height: CubagSpace.xxs),
                Text(
                  [if (date.isNotEmpty) date, postedBy].join(' · '),
                  style: CubagType.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
