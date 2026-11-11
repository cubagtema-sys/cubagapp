import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
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
            Text('Archive Circular', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            {'label': 'General Notice', 'key': 'General', 'icon': Icons.article_outlined, 'color': _kBlue},
            {'label': 'Urgent Alert', 'key': 'Urgent Alert', 'icon': Icons.priority_high_rounded, 'color': _kRed},
            {'label': 'Regulatory & Port Advisory', 'key': 'Regulatory & Port Advisory', 'icon': Icons.gavel_rounded, 'color': _kIndigo},
            {'label': 'System Maintenance', 'key': 'System Maintenance', 'icon': Icons.build_circle_outlined, 'color': _kAmber},
            {'label': 'Event / News', 'key': 'Event', 'icon': Icons.event_rounded, 'color': _kPurple},
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
                            'New Announcement',
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
                        final color = c['color'] as Color;
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
                      'Title / subject',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(fontSize: 14, color: textCol),
                      decoration: InputDecoration(
                        hintText: 'e.g. Revised Port Clearance Procedures...',
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
                      'Message content',
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
                          label: Text(submitting ? 'Publishing...' : 'Publish Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
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
                          child: Text('Edit Announcement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textCol)),
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
                          label: Text(c, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: sel ? Colors.white : textCol)),
                          selected: sel,
                          selectedColor: _kOrange,
                          backgroundColor: isDark ? const Color(0xFF4D2D20) : CubagColors.sand,
                          onSelected: (val) {
                            if (val) setDialogState(() => editCategory = c);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('Title / subject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5)),
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

                    Text('Message content', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.5)),
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
                          label: Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F1612);
    final textMuted = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    final displayList = _tab == 'active' ? _filterList(_active) : _filterList(_archived);
    final isLoading = _tab == 'active' ? _loadingActive : _loadingArchived;

    return AppLayout(
      title: 'Announcements & Circulars',
      scrollable: true,
      child: Container(
        color: bg,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // ── TOP HEADER ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: _kOrange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Announcements & Circulars',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'Publish official customs notices, port advisories, and member circulars.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      _clearCache();
                      _fetchActive(page: 1);
                      _fetchArchived(page: 1);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 15, color: _kOrange),
                    label: Text('Refresh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text('New Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── TOAST MESSAGE ───────────────────────────────────────────────
            if (_toastMessage.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _toastColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _toastColor.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    Icon(_toastColor == _kGreen ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: _toastColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _toastMessage,
                        style: TextStyle(color: _toastColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── TABS & SEARCH BAR ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildTabButton('Active Feed', 'active', _totalActive, Icons.sensors_rounded, isDark),
                      const SizedBox(width: 8),
                      _buildTabButton('Archived', 'archived', _totalArchived, Icons.archive_outlined, isDark),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Search input
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: isDark ? CubagColors.ink : CubagColors.sand,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: border),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: TextStyle(fontSize: 13, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search by title, subject or content...',
                              hintStyle: TextStyle(fontSize: 12.5, color: textMuted),
                              prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Close',
                                      icon: const Icon(Icons.close_rounded, size: 15),
                                      onPressed: () => setState(() => _searchQuery = ''),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip('All', 'All', isDark),
                        const SizedBox(width: 6),
                        _buildCategoryChip('Urgent Alerts', 'Urgent Alert', isDark, activeColor: _kRed),
                        const SizedBox(width: 6),
                        _buildCategoryChip('Regulatory & Port Advisory', 'Regulatory & Port Advisory', isDark, activeColor: _kIndigo),
                        const SizedBox(width: 6),
                        _buildCategoryChip('System Maintenance', 'System Maintenance', isDark, activeColor: _kAmber),
                        const SizedBox(width: 6),
                        _buildCategoryChip('Events & News', 'Event', isDark, activeColor: _kPurple),
                        const SizedBox(width: 6),
                        _buildCategoryChip('General', 'General', isDark, activeColor: _kBlue),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── LIST FEED ───────────────────────────────────────────────────
            if (isLoading)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) => const ShimmerListTile(),
              )
            else if (displayList.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tab == 'archived' ? Icons.archive_outlined : Icons.campaign_outlined,
                      size: 36,
                      color: textMuted.withAlpha(120),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _tab == 'archived' ? 'No archived circulars found' : 'No active announcements found',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tab == 'archived'
                          ? 'Archived circulars will be stored here.'
                          : 'Create your first broadcast to notify all members.',
                      style: TextStyle(fontSize: 13, color: textMuted),
                    ),
                    if (_tab == 'active') ...[
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _showCreateDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: Text('Create Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 950;
                  return Column(
                    children: [
                      if (isWide)
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: displayList.map((ann) {
                            return SizedBox(
                              width: (constraints.maxWidth - 14) / 2,
                              child: _buildAnnouncementCard(
                                Map<String, dynamic>.from(ann as Map),
                                isDark: isDark,
                                cardBg: cardBg,
                                border: border,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              ),
                            );
                          }).toList(),
                        )
                      else
                        Column(
                          children: displayList.map((ann) => _buildAnnouncementCard(
                                Map<String, dynamic>.from(ann as Map),
                                isDark: isDark,
                                cardBg: cardBg,
                                border: border,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              )).toList(),
                        ),
                      const SizedBox(height: 16),
                      // Pagination
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Showing ${displayList.length} circulars (Page ${_tab == 'active' ? _pageActive : _pageArchived})',
                              style: TextStyle(fontSize: 12.5, color: textMuted),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: (_tab == 'active' ? _pageActive : _pageArchived) > 1
                                      ? () {
                                          if (_tab == 'active') {
                                            _fetchActive(page: _pageActive - 1);
                                          } else {
                                            _fetchArchived(page: _pageArchived - 1);
                                          }
                                        }
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: border),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.chevron_left_rounded, size: 14),
                                  label: Text('Prev', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: (_tab == 'active' ? _hasMoreActive : _hasMoreArchived)
                                      ? () {
                                          if (_tab == 'active') {
                                            _fetchActive(page: _pageActive + 1);
                                          } else {
                                            _fetchArchived(page: _pageArchived + 1);
                                          }
                                        }
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: border),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  label: Text('Next', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  icon: const Icon(Icons.chevron_right_rounded, size: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildTabButton(String label, String key, int count, IconData icon, bool isDark) {
    final isSel = _tab == key;
    return InkWell(
      onTap: () {
        setState(() => _tab = key);
        if (key == 'active') _fetchActive(page: 1);
        if (key == 'archived') _fetchArchived(page: 1);
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? _kOrange : (isDark ? const Color(0xFF4D2D20) : CubagColors.sand),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSel ? Colors.white : (isDark ? Colors.white70 : CubagColors.inkSoft)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? Colors.white : (isDark ? Colors.white : CubagColors.inkSoft),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? Colors.white.withAlpha(40) : (isDark ? Colors.white12 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSel ? Colors.white : (isDark ? Colors.white70 : CubagColors.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String key, bool isDark, {Color? activeColor}) {
    final isSel = _categoryFilter == key;
    final color = activeColor ?? _kOrange;

    return InkWell(
      onTap: () => setState(() => _categoryFilter = key),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color.withAlpha(isDark ? 40 : 25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel ? color : (isDark ? const Color(0xFF3D261C) : CubagColors.line),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel ? color : (isDark ? Colors.white70 : CubagColors.inkSoft),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(
    Map<String, dynamic> item, {
    required bool isDark,
    required Color cardBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final id = item['id'] as int? ?? 0;
    final title = (item['title'] as String? ?? '').trim();
    final body = (item['body'] as String? ?? '').trim();
    final category = (item['category'] as String? ?? 'General').trim();
    final postedBy = (item['posted_by'] as String? ?? 'CUBAG Secretariat').trim();
    final createdAt = (item['created_at'] as String? ?? '').trim();
    final isExpanded = _expandedIds.contains(id);
    final isArchived = _tab == 'archived';

    Color catColor;
    IconData catIcon;
    switch (category) {
      case 'Urgent Alert':
        catColor = _kRed;
        catIcon = Icons.priority_high_rounded;
        break;
      case 'Regulatory & Port Advisory':
        catColor = _kIndigo;
        catIcon = Icons.gavel_rounded;
        break;
      case 'System Maintenance':
        catColor = _kAmber;
        catIcon = Icons.build_circle_outlined;
        break;
      case 'Event':
        catColor = _kPurple;
        catIcon = Icons.event_rounded;
        break;
      default:
        catColor = _kBlue;
        catIcon = Icons.article_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: category == 'Urgent Alert' ? _kRed.withAlpha(50) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: catColor.withAlpha(50)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(catIcon, size: 11, color: catColor),
                    const SizedBox(width: 4),
                    Text(
                      category.toUpperCase(),
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: catColor, letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (createdAt.isNotEmpty)
                Text(
                  createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
              const Spacer(),

              IconButton(
                tooltip: 'Copy Text',
                icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF5F6B7E)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$title\n\n$body'));
                  _showToast('Circular text copied to clipboard.', _kGreen);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              if (!isArchived) ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 14, color: _kOrange),
                  onPressed: () => _showEditDialog(item),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  tooltip: 'Archive',
                  icon: const Icon(Icons.archive_outlined, size: 14, color: _kRed),
                  onPressed: () => _archiveAnnouncement(id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ] else ...[
                InkWell(
                  onTap: () => _restoreAnnouncement(id),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kGreen.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.settings_backup_restore_rounded, size: 12, color: _kGreen),
                        const SizedBox(width: 4),
                        Text('Restore', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _kGreen)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Title
          SelectableText(
            title,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: textPrimary),
          ),
          const SizedBox(height: 6),

          // Body
          SelectableText(
            body,
            maxLines: isExpanded ? 50 : 4,
            style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFFD1D5DB) : CubagColors.inkSoft, height: 1.4),
          ),

          if (body.length > 160) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedIds.remove(id);
                  } else {
                    _expandedIds.add(id);
                  }
                });
              },
              child: Text(
                isExpanded ? 'Show Less' : 'Read Full Circular →',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accentOrangeText),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 6),

          // Footer
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 12, color: textMuted),
              const SizedBox(width: 4),
              Text(
                'Issued by: $postedBy',
                style: TextStyle(fontSize: 11.5, color: textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
