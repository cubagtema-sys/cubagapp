import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

// ── Balanced CUBAG Brand Palette ───────────────────────────────────────────
const _kBrown = Color(0xFF6B3E26); // Primary Brand Brown
const _kOrange = Color(0xFFFF5000); // Primary CTA Orange
const _kDarkBrown = Color(0xFF3E2418); // Deep Contrast Brown
const _kGreen = Color(0xFF10B981); // Success / Active Emerald
const _kPurple = Color(0xFF8B5CF6); // Election / Presidential Violet
const _kBlue = Color(0xFF2563EB); // Policy / Port Poll Ocean Blue
const _kAmber = Color(0xFFF59E0B); // Action Required / Rating Gold
const _kRed = Color(0xFFEF4444); // Closed / Error Crimson
const _kText = Color(0xFF1E293B); // Slate Text Primary
const _kMuted = Color(0xFF64748B); // Slate Text Muted
const _kBorder = Color(0xFFE2E8F0); // Subtle Border Color

class SurveysPage extends StatefulWidget {
  const SurveysPage({super.key});

  @override
  State<SurveysPage> createState() => _SurveysPageState();
}

class _SurveysPageState extends State<SurveysPage> {
  bool _loading = true;
  List<dynamic> _surveys = [];
  String _tab = 'active'; // 'active' or 'past'
  String _typeFilter = 'all'; // 'all', 'election', 'poll', 'survey'
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, dynamic>? _answering;
  String _selected = '';
  bool _submitting = false;
  String? _toast;
  bool _toastSuccess = true;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = v.trim());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_loading) setState(() => _loading = true);
    await ApiService().fetchDataWithCache('/surveys', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _surveys = ApiService.ensureList(data);
          _loading = false;
        });
      }
    });
  }

  void _showToast(String msg, bool success) {
    setState(() {
      _toast = msg;
      _toastSuccess = success;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      _showToast(
        'Please select a candidate or option before submitting.',
        false,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
        '/surveys/${_answering!['id']}/respond',
        data: {
          'answers': {'vote': _selected},
        },
      );
      if (res.statusCode == 200) {
        final surveyTitle = _answering!['title']?.toString() ?? 'Ballot';
        final selectedChoice = _selected;
        setState(() {
          _answering = null;
          _selected = '';
        });
        _fetch();
        if (mounted) {
          _showVoteSuccessDialog(title: surveyTitle, selected: selectedChoice);
        }
      } else {
        _showToast(
          res.data?['message'] ?? 'Submission failed. Please try again.',
          false,
        );
      }
    } catch (_) {
      _showToast(
        'An error occurred while submitting your vote. Please try again.',
        false,
      );
    }
    setState(() => _submitting = false);
  }

  void _showVoteSuccessDialog({
    required String title,
    required String selected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0F0A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(28),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _kGreen.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: _kGreen,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Ballot Cast Successfully!',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kOrange,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(10)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_vote_rounded,
                      size: 20,
                      color: _kGreen,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RECORDED CHOICE',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _kMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selected,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A0F0A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: _kGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cryptographically secured & audited',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: _kMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Done & Return to Surveys',
                    style: GoogleFonts.outfit(
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
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  Color _typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'election':
        return _kPurple;
      case 'poll':
        return _kOrange;
      default:
        return _kOrange;
    }
  }

  IconData _typeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'election':
        return Icons.how_to_vote_rounded;
      case 'poll':
        return Icons.insert_chart_outlined_rounded;
      default:
        return Icons.assignment_turned_in_outlined;
    }
  }

  String _typeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'election':
        return 'EXECUTIVE ELECTION';
      case 'poll':
        return 'GENERAL POLL';
      default:
        return 'OPINION SURVEY';
    }
  }

  String _typeEmoji(String? type) {
    switch (type?.toLowerCase()) {
      case 'election':
        return '🗳️';
      case 'poll':
        return '📊';
      default:
        return '📋';
    }
  }

  String _deadlineLabel(dynamic deadline) {
    if (deadline == null) return 'No deadline';
    final d = DateTime.tryParse(deadline.toString());
    if (d == null) return deadline.toString();
    const months = [
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  bool _isSurveyActive(dynamic s) {
    final activeVal = s['active'];
    final isActive =
        activeVal == true ||
        activeVal == 1 ||
        activeVal == 'true' ||
        activeVal == null;
    if (!isActive) return false;
    final deadlineStr = s['deadline'] ?? s['expiry'];
    if (deadlineStr == null || deadlineStr.toString().isEmpty) return true;
    final d = DateTime.tryParse(deadlineStr.toString());
    if (d == null) return true;
    final endOfDay = DateTime(d.year, d.month, d.day, 23, 59, 59);
    return endOfDay.isAfter(DateTime.now());
  }

  List<dynamic> get _active => _surveys.where(_isSurveyActive).toList();
  List<dynamic> get _past =>
      _surveys.where((s) => !_isSurveyActive(s)).toList();

  int get _votedCount =>
      _surveys.where((s) => s['has_responded'] == true).length;

  List<dynamic> _filterList(List<dynamic> raw) {
    return raw.where((s) {
      // Filter by type
      if (_typeFilter != 'all') {
        final type = (s['type'] ?? 'survey').toString().toLowerCase();
        if (_typeFilter == 'election' && type != 'election') return false;
        if (_typeFilter == 'poll' && type != 'poll') return false;
        if (_typeFilter == 'survey' && type != 'survey' && type.isNotEmpty) {
          return false;
        }
      }
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (s['title'] ?? '').toString().toLowerCase();
        final desc = (s['description'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !desc.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ── Build Page ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentList = _tab == 'active' ? _active : _past;
    final filteredList = _filterList(currentList);

    return AppLayout(
      title: 'Surveys & Elections',
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_answering != null)
                _buildAnswerForm(isDark)
              else ...[
                // ── 1. Hero Banner with Live Metrics ───────────────────
                _buildHeroBanner(isDark),
                const SizedBox(height: 24),

                // ── 2. Segmented Pill Tab Bar ──────────────────────────
                _buildSegmentedTabs(isDark),
                const SizedBox(height: 16),

                // ── 3. Search & Category Filters ───────────────────────
                _buildSearchAndFilters(isDark),
                const SizedBox(height: 16),

                // ── 4. Main Survey Content Cards ───────────────────────
                if (_loading && filteredList.isEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 14),
                    itemBuilder: (ctx, i) => const ShimmerListTile(),
                  )
                else if (filteredList.isEmpty)
                  _buildEmptyState(isDark)
                else
                  ...filteredList.map(
                    (s) =>
                        _buildSurveyCard(Map<String, dynamic>.from(s), isDark),
                  ),
              ],
            ],
          ),

          // Toast notification
          if (_toast != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _toastSuccess ? _kGreen : _kRed,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _toastSuccess
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _toast!,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Hero Banner with Metrics ─────────────────────────────────

  Widget _buildHeroBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF281710), const Color(0xFF1A0F0A)]
              : [_kDarkBrown, _kBrown],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kDarkBrown.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kOrange.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gavel_rounded, size: 14, color: _kOrange),
                    const SizedBox(width: 6),
                    Text(
                      'CUBAG DEMOCRATIC GOVERNANCE',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _kOrange,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Verified Ballots',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Surveys, Polls & General Elections',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Participate in executive elections, cast official ballots, and provide direct feedback on trade policies, port operations, and customs tariffs.',
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: Colors.white.withAlpha(200),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Metric Counters
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpiMetricCard(
                label: 'Active Ballots',
                value: '${_active.length}',
                icon: Icons.how_to_vote_rounded,
                color: _kOrange,
                isDark: isDark,
              ),
              _kpiMetricCard(
                label: 'My Votes Cast',
                value: '$_votedCount',
                icon: Icons.check_circle_rounded,
                color: _kGreen,
                isDark: isDark,
              ),
              _kpiMetricCard(
                label: 'Past Archives',
                value: '${_past.length}',
                icon: Icons.inventory_2_rounded,
                color: _kPurple,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Segmented Tab Bar (Active vs Past) ────────────────────────

  Widget _buildSegmentedTabs(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : _kBorder),
      ),
      child: Row(
        children: [
          _tabPill(
            id: 'active',
            label: 'Active Ballots & Surveys',
            count: _active.length,
            icon: Icons.bolt_rounded,
            activeColor: _kOrange,
            isDark: isDark,
          ),
          _tabPill(
            id: 'past',
            label: 'Past Archives & Results',
            count: _past.length,
            icon: Icons.history_rounded,
            activeColor: _kBrown,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required String id,
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required bool isDark,
  }) {
    final isSelected = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF281710) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 50 : 15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : _kMuted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 15,
                    color: isSelected
                        ? (isDark ? Colors.white : _kText)
                        : _kMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withAlpha(25)
                      : (isDark ? Colors.white10 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? activeColor : _kMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search & Filter Chips ─────────────────────────────────────

  Widget _buildSearchAndFilters(bool isDark) {
    return Column(
      children: [
        // Search Bar
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.white12 : _kBorder),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: isDark ? Colors.white : _kText,
            ),
            decoration: InputDecoration(
              hintText: 'Search surveys, candidates, policies...',
              hintStyle: GoogleFonts.outfit(fontSize: 15, color: _kMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: _kMuted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: _kMuted,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
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
        const SizedBox(height: 10),

        // Type Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                'all',
                'All Categories',
                Icons.grid_view_rounded,
                isDark,
              ),
              const SizedBox(width: 8),
              _filterChip(
                'election',
                'Elections Only',
                Icons.how_to_vote_rounded,
                isDark,
              ),
              const SizedBox(width: 8),
              _filterChip(
                'poll',
                'General Polls',
                Icons.insert_chart_outlined_rounded,
                isDark,
              ),
              const SizedBox(width: 8),
              _filterChip(
                'survey',
                'Opinion Surveys',
                Icons.assignment_outlined,
                isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String id, String label, IconData icon, bool isDark) {
    final isSelected = _typeFilter == id;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _kOrange
              : (isDark ? const Color(0xFF1A0F0A) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _kOrange : (isDark ? Colors.white12 : _kBorder),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : _kMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Survey Card (Active vs Past) ──────────────────────────────

  Widget _buildSurveyCard(Map<String, dynamic> s, bool isDark) {
    final type = s['type']?.toString();
    final color = _typeColor(type);
    final icon = _typeIcon(type);
    final emoji = _typeEmoji(type);
    final hasVoted = s['has_responded'] == true;
    final isTabActive = _tab == 'active';
    final coverImage = s['cover_image']?.toString();
    final isMemberOnly = s['target_audience'] == 'members';
    final totalResponses =
        int.tryParse(s['total_responses']?.toString() ?? '0') ?? 0;
    final myVote = s['my_vote']?.toString();
    final tallies = (s['tallies'] is Map)
        ? Map<String, dynamic>.from(s['tallies'])
        : <String, dynamic>{};

    List<dynamic> options = [];
    try {
      final rawOptions = s['options'];
      if (rawOptions is List) {
        options = rawOptions;
      } else if (rawOptions is String && rawOptions.isNotEmpty) {
        options = jsonDecode(rawOptions) as List;
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasVoted
              ? _kGreen.withAlpha(100)
              : (isDark ? Colors.white12 : _kBorder),
          width: hasVoted ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 8),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Optional Cover Banner
            if (coverImage != null && coverImage.isNotEmpty)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: coverImage,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withAlpha(160),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                ],
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges Header Row
                  Row(
                    children: [
                      // Category Tag
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withAlpha(60)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 12, color: color),
                            const SizedBox(width: 5),
                            Text(
                              '$emoji ${_typeLabel(type)}',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Target Audience Tag
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isMemberOnly
                              ? _kPurple.withAlpha(20)
                              : _kBlue.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMemberOnly
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              size: 11,
                              color: isMemberOnly ? _kPurple : _kBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isMemberOnly
                                  ? 'Members Only'
                                  : 'Public & Members',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isMemberOnly ? _kPurple : _kBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Status Badge
                      if (hasVoted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _kGreen.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kGreen.withAlpha(80)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: _kGreen,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'VOTED',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: _kGreen,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isTabActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kOrange.withAlpha(80)),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _kOrange,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'CONCLUDED',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _kMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Title & Description
                  Text(
                    s['title']?.toString() ?? '',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s['description']?.toString() ?? '',
                    style: GoogleFonts.outfit(
                      color: isDark ? Colors.white70 : _kMuted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Metadata Ribbon: Responses + Deadline Date
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(8)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          size: 15,
                          color: _kMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$totalResponses ${totalResponses == 1 ? "Response" : "Responses"} Recorded',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kMuted,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.event_outlined,
                          size: 15,
                          color: _kMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Deadline: ${_deadlineLabel(s['deadline'])}',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── If Past Tab OR Member Voted: Display Results Progress Bars ──
                  if (!isTabActive || hasVoted) ...[
                    const SizedBox(height: 16),
                    _buildResultsBreakdown(
                      options: options,
                      tallies: tallies,
                      totalResponses: totalResponses,
                      myVote: myVote,
                      isDark: isDark,
                      type: type,
                    ),
                  ],

                  // ── If Active Tab and Not Voted: Action Button ──
                  if (isTabActive && !hasVoted) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _answering = s;
                          _selected = '';
                        }),
                        icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                        label: Text(
                          type == 'election'
                              ? 'Cast Official Ballot'
                              : 'Participate & Submit Vote',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results Breakdown Bars (for Past or Voted Surveys) ─────────

  Widget _buildResultsBreakdown({
    required List<dynamic> options,
    required Map<String, dynamic> tallies,
    required int totalResponses,
    required String? myVote,
    required bool isDark,
    required String? type,
  }) {
    if (options.isEmpty && tallies.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: _kMuted),
            const SizedBox(width: 8),
            Text(
              'No detailed breakdown available.',
              style: GoogleFonts.outfit(fontSize: 14, color: _kMuted),
            ),
          ],
        ),
      );
    }

    // Determine option list: from options or keys of tallies
    List<String> optionNames = [];
    if (options.isNotEmpty) {
      for (var opt in options) {
        final name = opt['name']?.toString() ?? opt.toString();
        optionNames.add(name);
      }
    } else {
      optionNames = tallies.keys.toList();
    }

    // Find highest vote count for winner badge
    int maxVotes = 0;
    for (var name in optionNames) {
      final v = int.tryParse(tallies[name]?.toString() ?? '0') ?? 0;
      if (v > maxVotes) maxVotes = v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'OFFICIAL TALLY & RESULTS',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kMuted,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (myVote != null && myVote.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'You voted: $myVote',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...optionNames.map((name) {
          final count = int.tryParse(tallies[name]?.toString() ?? '0') ?? 0;
          final pct = totalResponses > 0 ? (count / totalResponses) : 0.0;
          final isUserPick = myVote == name;
          final isTopChoice = maxVotes > 0 && count == maxVotes;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUserPick
                  ? _kGreen.withAlpha(15)
                  : (isDark
                        ? Colors.white.withAlpha(5)
                        : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isUserPick
                    ? _kGreen.withAlpha(80)
                    : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isTopChoice)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.emoji_events_rounded,
                          size: 16,
                          color: _kAmber,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontWeight: isUserPick
                              ? FontWeight.w800
                              : FontWeight.w700,
                          fontSize: 15,
                          color: isDark ? Colors.white : _kText,
                        ),
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? "vote" : "votes"} (${(pct * 100).toStringAsFixed(1)}%)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isUserPick ? _kGreen : _kMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white12
                        : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isUserPick ? _kGreen : (isTopChoice ? _kOrange : _kBrown),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Voting / Balloting Interface Form ─────────────────────────

  Widget _buildAnswerForm(bool isDark) {
    final s = _answering!;
    final type = s['type']?.toString();
    final color = _typeColor(type);
    final icon = _typeIcon(type);

    List<dynamic> options = [];
    try {
      final rawOptions = s['options'];
      if (rawOptions is List) {
        options = rawOptions;
      } else if (rawOptions is String && rawOptions.isNotEmpty) {
        options = jsonDecode(rawOptions) as List;
      }
    } catch (e, st) {
      AppLogger.error('surveys_page', e, st);
    }

    final isYesNo =
        options.length == 2 &&
        options.any((o) => o['name']?.toString().toLowerCase() == 'yes');
    final isStarRating = options.isEmpty && type != 'election';
    final isMultiple = !isYesNo && !isStarRating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        TextButton.icon(
          onPressed: () => setState(() {
            _answering = null;
            _selected = '';
          }),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(
            'Back to Surveys & Ballots',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          style: TextButton.styleFrom(
            foregroundColor: _kBrown,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),

        // Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withAlpha(25), color.withAlpha(10)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(60), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _typeLabel(type),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withAlpha(40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 12,
                          color: _kGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Encrypted Ballot',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                s['title']?.toString() ?? '',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s['description']?.toString() ?? '',
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white70 : _kMuted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Voting Options Selector
        if (isYesNo)
          _buildYesNoOptions(color, isDark)
        else if (isStarRating)
          _buildStarRatingOptions(isDark)
        else if (isMultiple)
          _buildMultipleChoiceOptions(options, color, isDark),

        const SizedBox(height: 32),

        // Submit Button
        Center(
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_submitting || _selected.isEmpty) ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.how_to_vote_rounded, size: 20),
              label: Text(
                _submitting
                    ? 'Submitting Official Ballot...'
                    : (_selected.isEmpty
                          ? 'Select a Choice to Cast Vote'
                          : 'Confirm & Cast Official Vote'),
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty
                    ? const Color(0xFFcbd5e1)
                    : color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Option Formatters (Yes/No, Rating, Multiple Candidates) ──

  Widget _buildYesNoOptions(Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT YOUR DECISION',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: _kMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _voteButton(
                'Yes',
                Icons.thumb_up_alt_rounded,
                _kGreen,
                isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _voteButton(
                'No',
                Icons.thumb_down_alt_rounded,
                _kRed,
                isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _voteButton(String label, IconData icon, Color color, bool isDark) {
    final sel = _selected == label;
    return GestureDetector(
      onTap: () => setState(() => _selected = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 90,
        decoration: BoxDecoration(
          color: sel
              ? color
              : (isDark ? Colors.white.withAlpha(8) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: sel
                ? color
                : (isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
            width: sel ? 2.5 : 1.5,
          ),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: color.withAlpha(60),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: sel ? Colors.white : color, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 19,
                color: sel ? Colors.white : (isDark ? Colors.white : _kText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRatingOptions(bool isDark) {
    final rating = int.tryParse(_selected) ?? 0;
    const labels = [
      '',
      '1 - Poor',
      '2 - Fair',
      '3 - Good',
      '4 - Very Good',
      '5 - Excellent',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RATE YOUR ASSESSMENT (1 - 5 STARS)',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: _kMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? Colors.white12 : _kBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  final filled = rating >= star;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = '$star'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: _kAmber,
                        size: filled ? 46 : 40,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              if (rating > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _kAmber.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    labels[rating],
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _kAmber,
                    ),
                  ),
                )
              else
                Text(
                  'Tap a star to register rating',
                  style: GoogleFonts.outfit(color: _kMuted, fontSize: 15),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleChoiceOptions(
    List<dynamic> options,
    Color color,
    bool isDark,
  ) {
    final isElection =
        _answering?['type']?.toString().toLowerCase() == 'election';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isElection ? 'SELECT CANDIDATE' : 'SELECT RESPONSE OPTION',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: _kMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 14),
        if (isElection)
          // Candidate Cards
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: options.map((opt) {
              final name = opt['name']?.toString() ?? opt.toString();
              final photoUrl = opt['photo']?.toString();
              final sel = _selected == name;
              return GestureDetector(
                onTap: () => setState(() => _selected = name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 160,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: sel
                        ? color.withAlpha(20)
                        : (isDark ? const Color(0xFF1A0F0A) : Colors.white),
                    border: Border.all(
                      color: sel ? color : (isDark ? Colors.white12 : _kBorder),
                      width: sel ? 2.5 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: color.withAlpha(40),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel
                              ? color.withAlpha(30)
                              : const Color(0xFFF1F5F9),
                          border: sel
                              ? Border.all(color: color, width: 2.5)
                              : null,
                          image: (photoUrl != null && photoUrl.isNotEmpty)
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(photoUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Icon(
                                Icons.person_rounded,
                                color: sel ? color : _kMuted,
                                size: 32,
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: sel ? color : (isDark ? Colors.white : _kText),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? color : Colors.transparent,
                          border: Border.all(
                            color: sel ? color : _kMuted,
                            width: 2,
                          ),
                        ),
                        child: sel
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        else
          // Standard Multiple Choice List
          Column(
            children: options.map((opt) {
              final name = opt['name']?.toString() ?? opt.toString();
              final sel = _selected == name;
              return GestureDetector(
                onTap: () => setState(() => _selected = name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? color.withAlpha(15)
                        : (isDark ? const Color(0xFF1A0F0A) : Colors.white),
                    border: Border.all(
                      color: sel ? color : (isDark ? Colors.white12 : _kBorder),
                      width: sel ? 2.2 : 1.2,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: color.withAlpha(30),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? color : Colors.transparent,
                          border: Border.all(
                            color: sel ? color : _kMuted,
                            width: 2,
                          ),
                        ),
                        child: sel
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 16,
                            color: sel
                                ? color
                                : (isDark ? Colors.white : _kText),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── Empty State ──────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    final isTabActive = _tab == 'active';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : _kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTabActive
                  ? Icons.how_to_vote_outlined
                  : Icons.inventory_2_outlined,
              size: 44,
              color: _kMuted,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isTabActive
                ? 'No Active Ballots or Surveys'
                : 'No Past Archives Found',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 19,
              color: isDark ? Colors.white : _kText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isTabActive
                ? 'There are currently no open surveys or elections scheduled. Check back soon.'
                : 'Concluded elections and closed surveys will appear here for historical transparency.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: _kMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
