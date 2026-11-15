import '../components/admin_dialog.dart';
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

const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

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

  Future<void> _showCreateDialog() => _showAnnouncementDialog();

  Future<void> _showEditDialog(Map<String, dynamic> item) => _showAnnouncementDialog(item);

  /// One form for new and existing announcements.
  Future<void> _showAnnouncementDialog([Map<String, dynamic>? item]) async {
    final editing = item != null;
    final titleCtrl = TextEditingController(text: item?['title']?.toString() ?? '');
    final bodyCtrl = TextEditingController(text: item?['body']?.toString() ?? '');
    String category = item?['category']?.toString() ?? 'General';
    bool busy = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final title = titleCtrl.text.trim();
            final body = bodyCtrl.text.trim();
            if (title.isEmpty || body.isEmpty) {
              setDialogState(() => error = 'Add a title and a message.');
              return;
            }
            setDialogState(() {
              busy = true;
              error = null;
            });
            try {
              bool ok;
              if (editing) {
                final res = await _api.put(
                  '/announcements/${item['id']}',
                  data: {'title': title, 'body': body, 'category': category},
                );
                ok = res.statusCode == 200;
              } else {
                final res = await _api.postData('announcements', {
                  'title': title,
                  'body': body,
                  'category': category,
                });
                ok = res != null;
              }
              if (ok) {
                if (ctx.mounted) Navigator.pop(ctx);
                _showToast(editing ? 'Announcement updated.' : 'Announcement published.', _kGreen);
                await _clearCache();
                _fetchActive(page: editing ? _pageActive : 1);
                return;
              }
              setDialogState(() => error = 'Could not save. Try again.');
            } catch (e, st) {
              AppLogger.error('admin_announcement_save', e, st);
              setDialogState(() => error = 'Could not save. Check the connection and try again.');
            }
            if (mounted) setDialogState(() => busy = false);
          }

          return AdminDialog(
            title: editing ? 'Edit announcement' : 'New announcement',
            subtitle: editing
                ? 'Changes show on members\' Home screen straight away.'
                : 'Every member sees it on their Home screen and gets a notification.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Saving…' : (editing ? 'Save changes' : 'Publish')),
              ),
            ],
            children: [
              AdminField(
                label: 'Category',
                child: AdminChoice<String>(
                  options: [for (final c in _categories.skip(1)) (c.$1, c.$2)],
                  value: category,
                  onChanged: (v) => setDialogState(() => category = v),
                ),
              ),
              AdminField(
                label: 'Title',
                child: TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'For example: New clearance hours at Tema'),
                ),
              ),
              AdminField(
                label: 'Message',
                child: TextField(
                  controller: bodyCtrl,
                  minLines: 5,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'What members need to know, and what to do'),
                ),
              ),
              if (error != null)
                Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
  }

  /// Send a notification (and optionally an email) to one group of members,
  /// for example everyone whose renewal is due and not paid.
  Future<void> _showGroupMessageDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    List<Map<String, dynamic>> groups = [];
    String? group;
    bool email = true;
    bool loading = true;
    bool sending = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          if (loading && groups.isEmpty && error == null) {
            _api.get('/notifications/admin/groups').then((res) {
              final list = (res.data is Map ? res.data['groups'] : null) as List? ?? [];
              setD(() {
                groups = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                group ??= groups.isNotEmpty ? groups.first['key'].toString() : null;
                loading = false;
              });
            }).catchError((_) {
              setD(() {
                loading = false;
                error = 'Could not load the groups. Close and try again.';
              });
            });
          }
          final chosen = groups.where((g) => g['key'] == group).firstOrNull;
          final count = (chosen?['count'] as num?)?.toInt() ?? 0;

          Future<void> send() async {
            if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) {
              setD(() => error = 'Add a title and a message.');
              return;
            }
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: Text('Send to $count ${count == 1 ? 'member' : 'members'}?'),
                content: Text(email
                    ? 'They get it in the app, as a phone notification, and by email. This cannot be undone.'
                    : 'They get it in the app and as a phone notification. This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
                ],
              ),
            );
            if (ok != true) return;
            setD(() {
              sending = true;
              error = null;
            });
            try {
              final res = await _api.post('/notifications/admin/send-group', data: {
                'group': group,
                'title': titleCtrl.text.trim(),
                'message': bodyCtrl.text.trim(),
                'email': email,
              });
              if (res.statusCode == 200) {
                final sent = res.data['sent'] ?? 0;
                final emailed = res.data['emailed'] ?? 0;
                if (ctx.mounted) Navigator.pop(ctx);
                _showToast(
                  email ? 'Sent to $sent members ($emailed emails).' : 'Sent to $sent members.',
                  _kGreen,
                );
                return;
              }
              setD(() => error = (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not send.');
            } catch (_) {
              setD(() => error = 'Could not send. Check the connection and try again.');
            }
            setD(() => sending = false);
          }

          return AdminDialog(
            title: 'Message a group',
            subtitle: 'Groups are worked out when you send, so members who already paid are left out.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: sending || loading || group == null || count == 0 ? null : send,
                child: Text(sending ? 'Sending…' : (count == 0 ? 'No one to send to' : 'Send to $count')),
              ),
            ],
            children: [
              AdminField(
                label: 'Who gets it',
                child: loading
                    ? const LinearProgressIndicator()
                    : RadioGroup<String>(
                        groupValue: group,
                        onChanged: (v) => setD(() => group = v),
                        child: Column(
                        children: [
                          for (final g in groups)
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: g['key'].toString(),
                              title: Text(g['label'].toString(), style: CubagType.bodyStrong),
                              subtitle: Text('${g['count']} ${g['count'] == 1 ? 'member' : 'members'}', style: CubagType.caption),
                            ),
                        ],
                        ),
                      ),
              ),
              AdminField(
                label: 'Title',
                child: TextField(
                  controller: titleCtrl,
                  maxLength: 120,
                  decoration: const InputDecoration(hintText: 'For example: Your renewal is due'),
                ),
              ),
              AdminField(
                label: 'Message',
                child: TextField(
                  controller: bodyCtrl,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'What you want them to know or do'),
                ),
              ),
              AdminSwitchRow(
                title: 'Also send by email',
                subtitle: 'Reaches members whose phones do not show notifications.',
                value: email,
                onChanged: (v) => setD(() => email = v),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
            ],
          );
        },
      ),
    );
    titleCtrl.dispose();
    bodyCtrl.dispose();
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
                    onPressed: _showGroupMessageDialog,
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Message a group'),
                  ),
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
