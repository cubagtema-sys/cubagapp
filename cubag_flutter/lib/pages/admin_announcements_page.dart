import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kOrange      = Color(0xFFFF5000);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);
const _kAmber       = Color(0xFFF59E0B);
const _kBlue        = Color(0xFF3B82F6);
const _kIndigo      = Color(0xFF6366F1);
const _kPurple      = Color(0xFF8B5CF6);

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});
  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _api = ApiService();

  String _tab = 'history'; // history, archived, create
  String _categoryFilter = 'All';
  String _searchQuery = '';
  String _toastMessage = '';
  Color _toastColor = _kGreen;
  bool _submitting = false;

  // New Broadcast Form
  String _newCategory = 'General';
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

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

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
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

  Future<void> _submitBroadcast() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showToast('Please provide both subject and broadcast details', _kAmber);
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await _api.postData('announcements', {
        'title': title,
        'body': body,
        'category': _newCategory,
        'posted_by': 'CUBAG Secretariat',
      });

      if (res != null) {
        _titleCtrl.clear();
        _bodyCtrl.clear();
        setState(() {
          _newCategory = 'General';
          _submitting = false;
          _tab = 'history';
        });
        _showToast('Official Circular broadcasted successfully to all members!', _kGreen);
        await _clearCache();
        await _fetchActive(page: 1);
      }
    } catch (e, st) {
      AppLogger.error('admin_announcements_page', e, st);
      _showToast('Failed to broadcast circular. Please try again.', _kRed);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _archiveAnnouncement(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kRed.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.archive_outlined, color: _kRed, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Archive Circular', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to archive this announcement? It will be removed from the live member broadcast feed.',
          style: GoogleFonts.inter(fontSize: 17, color: const Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Archive Now', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
      _showToast('Circular restored back to live broadcasts.', _kGreen);
      await _clearCache();
      _fetchActive(page: 1);
    } catch (_) {
      _fetchArchived(page: _pageArchived);
      _showToast('Failed to restore circular', _kRed);
    }
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
          final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
          final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
          final textCol = isDark ? Colors.white : const Color(0xFF0F172A);

          return Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.edit_note_rounded, color: _kOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Edit Broadcast Circular', style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w800, color: textCol)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    Text('CATEGORY', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['General', 'Urgent Alert', 'Regulatory & Port Advisory', 'System Maintenance', 'Event'].map((c) {
                        final sel = editCategory == c;
                        return ChoiceChip(
                          label: Text(c, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: sel ? Colors.white : textCol)),
                          selected: sel,
                          selectedColor: _kOrange,
                          backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                          onSelected: (val) {
                            if (val) setDialogState(() => editCategory = c);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('SUBJECT / TITLE', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleEditCtrl,
                      style: GoogleFonts.outfit(fontSize: 17, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('CONTENT DETAILS', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bodyEditCtrl,
                      maxLines: 4,
                      style: GoogleFonts.inter(fontSize: 17, color: textCol),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                        ),
                        const SizedBox(width: 10),
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
                                      _showToast('Circular updated successfully!', _kGreen);
                                      await _clearCache();
                                      _fetchActive(page: _pageActive);
                                    }
                                  } catch (e, st) {
                                    AppLogger.error('admin_announcements_page', e, st);
                                  }
                                  if (mounted) setDialogState(() => saving = false);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: saving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text('Save Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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

  int get _urgentCount => _active.where((a) => (a['category'] as String?) == 'Urgent Alert').length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white : const Color(0xFF475569);

    return AppLayout(
      title: 'Broadcast & Circulars Management',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP EXECUTIVE BANNER ─────────────────────────────────────────
            AdminHeader(
              title: 'Broadcasts & Circulars Hub',
              subtitle: 'Publish official customs circulars, urgent port advisories, statutory regulatory updates, and association bulletins to all members.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(color: border, width: 1.2),
                    backgroundColor: cardBg,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _clearCache();
                    _fetchActive(page: 1);
                    _fetchArchived(page: 1);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 17, color: _kOrange),
                  label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _tab == 'create' ? const Color(0xFF78350F) : _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    shadowColor: _kOrange.withAlpha(80),
                  ),
                  onPressed: () {
                    setState(() => _tab = _tab == 'create' ? 'history' : 'create');
                    if (_tab == 'history') _fetchActive(page: 1);
                  },
                  icon: Icon(_tab == 'create' ? Icons.list_alt_rounded : Icons.campaign_rounded, size: 18),
                  label: Text(
                    _tab == 'create' ? 'View Live Feed' : 'New Broadcast',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── KPI METRICS STRIP ───────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildMetricCard('Live Broadcasts', '$_totalActive', 'Active in member feeds', Icons.campaign_rounded, _kOrange, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('Urgent Advisories', '$_urgentCount', 'Priority alerts', Icons.priority_high_rounded, _kRed, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('Archived Circulars', '$_totalArchived', 'Stored historical bulletins', Icons.inventory_2_outlined, _kIndigo, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard('Audience Reach', '100%', 'All Corporate & SME Brokers', Icons.verified_user_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(width: 220, child: _buildMetricCard('Live Broadcasts', '$_totalActive', 'Active in feeds', Icons.campaign_rounded, _kOrange, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('Urgent Advisories', '$_urgentCount', 'Priority alerts', Icons.priority_high_rounded, _kRed, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('Archived', '$_totalArchived', 'Historical records', Icons.inventory_2_outlined, _kIndigo, cardBg, border, textPrimary, textMuted)),
                            const SizedBox(width: 10),
                            SizedBox(width: 220, child: _buildMetricCard('Audience', '100%', 'All members reached', Icons.verified_user_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                          ],
                        ),
                      );
              },
            ),
            const SizedBox(height: 14),

            // ── TOAST NOTIFICATION ──────────────────────────────────────────
            if (_toastMessage.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: _toastColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _toastColor.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _toastColor == _kGreen ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _toastColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _toastMessage,
                        style: GoogleFonts.outfit(color: _toastColor, fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                  ],
                ),
              ),

            // ── MAIN TAB CONTROL & FILTER TOOLBAR ───────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Segmented Tabs
                      _buildTabBtn('Live Broadcasts', 'history', _totalActive, Icons.sensors_rounded),
                      const SizedBox(width: 8),
                      _buildTabBtn('Archived Circulars', 'archived', _totalArchived, Icons.archive_outlined),
                      const SizedBox(width: 8),
                      _buildTabBtn('Compose Broadcast', 'create', null, Icons.edit_note_rounded),
                    ],
                  ),
                  if (_tab != 'create') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Search bar
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: GoogleFonts.outfit(fontSize: 17, color: textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search circular subject, body content or author...',
                                hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted),
                                prefixIcon: Icon(Icons.search_rounded, size: 17, color: textMuted),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 16),
                                        onPressed: () => setState(() => _searchQuery = ''),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Category pills
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCatPill('All Categories', 'All', Icons.apps_rounded),
                          const SizedBox(width: 8),
                          _buildCatPill('Urgent Alerts', 'Urgent Alert', Icons.priority_high_rounded, activeColor: _kRed),
                          const SizedBox(width: 8),
                          _buildCatPill('Regulatory & Port Advisory', 'Regulatory & Port Advisory', Icons.gavel_rounded, activeColor: _kIndigo),
                          const SizedBox(width: 8),
                          _buildCatPill('System Maintenance', 'System Maintenance', Icons.build_circle_outlined, activeColor: _kAmber),
                          const SizedBox(width: 8),
                          _buildCatPill('Events & News', 'Event', Icons.event_rounded, activeColor: _kPurple),
                          const SizedBox(width: 8),
                          _buildCatPill('General Circulars', 'General', Icons.article_outlined, activeColor: _kBlue),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── TAB CONTENT ─────────────────────────────────────────────────
            if (_tab == 'create')
              _buildComposeSection(isDark, cardBg, border, textPrimary, textMuted)
            else if (_tab == 'history')
              _buildFeedSection(
                _filterList(_active),
                archived: false,
                loading: _loadingActive,
                page: _pageActive,
                hasMore: _hasMoreActive,
                onPage: (p) => _fetchActive(page: p),
                isDark: isDark,
                cardBg: cardBg,
                border: border,
                textPrimary: textPrimary,
                textMuted: textMuted,
              )
            else
              _buildFeedSection(
                _filterList(_archived),
                archived: true,
                loading: _loadingArchived,
                page: _pageArchived,
                hasMore: _hasMoreArchived,
                onPage: (p) => _fetchArchived(page: p),
                isDark: isDark,
                cardBg: cardBg,
                border: border,
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
          ],
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ────────────────────────────────────────────────────────
  Widget _buildMetricCard(
    String label,
    String value,
    String desc,
    IconData icon,
    Color accentColor,
    Color bg,
    Color border,
    Color textCol,
    Color subCol,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withAlpha(40)),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textCol)),
                const SizedBox(height: 1),
                Text(label, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textCol)),
                Text(desc, style: GoogleFonts.inter(fontSize: 14, color: subCol), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn(String label, String key, int? count, IconData icon) {
    final isSel = _tab == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() => _tab = key);
        if (key == 'history') _fetchActive(page: 1);
        if (key == 'archived') _fetchArchived(page: 1);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? _kOrange : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSel
              ? [BoxShadow(color: _kOrange.withAlpha(60), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569))),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? Colors.white : (isDark ? Colors.white : const Color(0xFF334155)),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSel ? Colors.white.withAlpha(40) : (isDark ? Colors.white12 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSel ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCatPill(String label, String key, IconData icon, {Color? activeColor}) {
    final isSel = _categoryFilter == key;
    final color = activeColor ?? _kOrange;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _categoryFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel ? color.withAlpha(isDark ? 40 : 25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel ? color : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSel ? color : (isDark ? Colors.white60 : const Color(0xFF64748B))),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? color : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── COMPOSE BROADCAST SECTION ────────────────────────────────────────────
  Widget _buildComposeSection(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildComposeForm(isDark, cardBg, border, textPrimary, textMuted)),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: _buildLivePreview(isDark, cardBg, border, textPrimary, textMuted)),
                ],
              )
            : Column(
                children: [
                  _buildComposeForm(isDark, cardBg, border, textPrimary, textMuted),
                  const SizedBox(height: 18),
                  _buildLivePreview(isDark, cardBg, border, textPrimary, textMuted),
                ],
              );
      },
    );
  }

  Widget _buildComposeForm(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final categories = [
      {'label': 'General Notice', 'key': 'General', 'icon': Icons.article_outlined, 'color': _kBlue},
      {'label': 'Urgent Alert', 'key': 'Urgent Alert', 'icon': Icons.priority_high_rounded, 'color': _kRed},
      {'label': 'Regulatory & Port Advisory', 'key': 'Regulatory & Port Advisory', 'icon': Icons.gavel_rounded, 'color': _kIndigo},
      {'label': 'System Maintenance', 'key': 'System Maintenance', 'icon': Icons.build_circle_outlined, 'color': _kAmber},
      {'label': 'Association Event', 'key': 'Event', 'icon': Icons.event_rounded, 'color': _kPurple},
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kOrange.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.campaign_rounded, color: _kOrange, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Compose Official Circular', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                    Text('Broadcast real-time circulars & notices to member dashboards & mobile apps.', style: GoogleFonts.inter(fontSize: 15, color: textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          Text('CIRCULAR CATEGORY', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((c) {
              final sel = _newCategory == c['key'];
              final color = c['color'] as Color;
              return InkWell(
                onTap: () => setState(() => _newCategory = c['key'] as String),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? color.withAlpha(25) : (isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? color : border, width: sel ? 1.5 : 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(c['icon'] as IconData, size: 14, color: sel ? color : textMuted),
                      const SizedBox(width: 6),
                      Text(
                        c['label'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          color: sel ? color : textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          Text('SUBJECT / CIRCULAR TITLE', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.outfit(fontSize: 17, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. Revised GRA Customs Clearance Procedures for Tema Port',
              hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted),
              isDense: true,
              filled: true,
              fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          Text('CIRCULAR BODY & DIRECTIVES', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            onChanged: (_) => setState(() {}),
            maxLines: 6,
            style: GoogleFonts.inter(fontSize: 17, color: textPrimary, height: 1.4),
            decoration: InputDecoration(
              hintText: 'Enter complete announcement content, compliance guidelines, relevant dates, and instructions for customs brokers...',
              hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted),
              isDense: true,
              filled: true,
              fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 16, color: _kOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Target Audience: All registered Clearing & Forwarding Agents, Consolidators, and Sub-Admins',
                    style: GoogleFonts.inter(fontSize: 15, color: textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitBroadcast,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                _submitting ? 'Broadcasting Circular…' : 'Broadcast to All Members Now',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreview(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    final title = _titleCtrl.text.trim().isEmpty ? 'Draft Announcement Subject' : _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim().isEmpty
        ? 'Your circular content will be formatted dynamically and displayed live across all member dashboards and mobile push feeds.'
        : _bodyCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined, size: 18, color: _kIndigo),
              const SizedBox(width: 8),
              Text('Live Member Feed Preview', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _kGreen.withAlpha(20), borderRadius: BorderRadius.circular(6)),
                child: Text('LIVE VIEW', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: _kGreen)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          _buildAnnouncementCard(
            {
              'id': 0,
              'title': title,
              'body': body,
              'category': _newCategory,
              'posted_by': 'CUBAG Secretariat',
              'created_at': 'Just now',
            },
            archived: false,
            isPreview: true,
            isDark: isDark,
            cardBg: isDark ? const Color(0xFF281710) : const Color(0xFFF8FAFC),
            border: border,
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
        ],
      ),
    );
  }

  // ── FEED & CARDS SECTION ─────────────────────────────────────────────────
  Widget _buildFeedSection(
    List<dynamic> items, {
    required bool archived,
    required bool loading,
    required int page,
    required bool hasMore,
    required Function(int) onPage,
    required bool isDark,
    required Color cardBg,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    if (loading) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemBuilder: (_, index) => const ShimmerListTile(),
      );
    }

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (archived ? _kIndigo : _kOrange).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                archived ? Icons.archive_outlined : Icons.campaign_outlined,
                size: 36,
                color: archived ? _kIndigo : _kOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              archived ? 'No archived circulars found.' : 'No active broadcasts found.',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              archived
                  ? 'Archived circulars will be stored here for future compliance reference.'
                  : 'Broadcasted announcements & customs circulars will appear in this real-time stream.',
              style: GoogleFonts.inter(fontSize: 16, color: textMuted),
              textAlign: TextAlign.center,
            ),
            if (!archived) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => setState(() => _tab = 'create'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text('Create First Broadcast', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        ...items.map((ann) => _buildAnnouncementCard(
              Map<String, dynamic>.from(ann as Map),
              archived: archived,
              isPreview: false,
              isDark: isDark,
              cardBg: cardBg,
              border: border,
              textPrimary: textPrimary,
              textMuted: textMuted,
            )),

        // Pagination Bar
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${items.length} circulars (Page $page)',
                style: GoogleFonts.inter(fontSize: 16, color: textMuted, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: page > 1 ? () => onPage(page - 1) : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded, size: 16),
                    label: Text('Prev', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: hasMore ? () => onPage(page + 1) : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    label: Text('Next', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    icon: const Icon(Icons.chevron_right_rounded, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAnnouncementCard(
    Map<String, dynamic> item, {
    required bool archived,
    required bool isPreview,
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: category == 'Urgent Alert' ? _kRed.withAlpha(60) : border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 25 : 4), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Category Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: catColor.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(catIcon, size: 12, color: catColor),
                    const SizedBox(width: 5),
                    Text(
                      category.toUpperCase(),
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: catColor, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (createdAt.isNotEmpty)
                Text(
                  createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                  style: GoogleFonts.inter(fontSize: 15, color: textMuted),
                ),
              const Spacer(),

              // Quick Action Buttons
              if (!isPreview) ...[
                IconButton(
                  tooltip: 'Copy Text',
                  icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '$title\n\n$body'));
                    _showToast('Circular text copied to clipboard.', _kGreen);
                  },
                ),
                if (!archived) ...[
                  IconButton(
                    tooltip: 'Edit Circular',
                    icon: const Icon(Icons.edit_outlined, size: 16, color: _kOrange),
                    onPressed: () => _showEditDialog(item),
                  ),
                  IconButton(
                    tooltip: 'Archive Circular',
                    icon: const Icon(Icons.archive_outlined, size: 16, color: _kRed),
                    onPressed: () => _archiveAnnouncement(id),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () => _restoreAnnouncement(id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen.withAlpha(25),
                      foregroundColor: _kGreen,
                      side: BorderSide(color: _kGreen.withAlpha(80)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                    label: Text('Restore to Feed', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Subject Title
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: textPrimary),
          ),
          const SizedBox(height: 6),

          // Content Body
          Text(
            body,
            maxLines: isExpanded ? 50 : 3,
            overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 17, color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF475569), height: 1.45),
          ),

          if (body.length > 180 && !isPreview) ...[
            const SizedBox(height: 6),
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
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _kOrange),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Footer info
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Icon(Icons.person_rounded, size: 12, color: _kOrange)),
              ),
              const SizedBox(width: 8),
              Text(
                'Issued by: $postedBy',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
