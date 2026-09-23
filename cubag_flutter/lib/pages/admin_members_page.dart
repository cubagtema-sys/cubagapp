import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/custom_dropdown.dart';
import '../components/admin_components.dart';
import '../components/trend_line.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
part 'admin_members/admin_members_widgets.dart';

class StandingTier {
  final String label;
  final Color color;
  final IconData icon;
  final String badgeText;

  StandingTier({
    required this.label,
    required this.color,
    required this.icon,
    required this.badgeText,
  });

  static StandingTier getFromStars(double stars) {
    if (stars >= 4.5) {
      return StandingTier(
        label: 'Elite Standing',
        color: const Color(0xFFD4AF37), // Gold
        icon: Icons.workspace_premium,
        badgeText: 'ELITE MEMBER',
      );
    } else if (stars >= 3.5) {
      return StandingTier(
        label: 'Good Standing',
        color: const Color(0xFF10B981), // Emerald Green
        icon: Icons.verified_user,
        badgeText: 'ACTIVE MEMBER',
      );
    } else if (stars >= 2.0) {
      return StandingTier(
        label: 'Warning / Probationary',
        color: const Color(0xFFF59E0B), // Amber
        icon: Icons.warning_amber,
        badgeText: 'PROBATIONARY',
      );
    } else {
      return StandingTier(
        label: 'Suspended / Delinquent',
        color: const Color(0xFFEF4444), // Red
        icon: Icons.block,
        badgeText: 'SUSPENDED',
      );
    }
  }
}

class AdminMembersPage extends StatefulWidget {
  const AdminMembersPage({super.key});
  @override
  State<AdminMembersPage> createState() => _AdminMembersPageState();
}

class _AdminMembersPageState extends State<AdminMembersPage> {
  bool _loading = true;
  bool _hasError = false;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  List<dynamic> _members = [];
  String _search = '';
  String _filterStatus = 'all';
  String _sortBy = 'name';
  Map<String, dynamic>? _selected;
  double _editReviewScore = 10.0;
  bool _updating = false;
  final ScrollController _scrollController = ScrollController();

  final _statusStyle = {
    'active': {
      'bg': const Color(0x1910b981),
      'color': const Color(0xFF10b981),
      'label': 'Active',
    },
    'pending': {
      'bg': const Color(0x19f59e0b),
      'color': const Color(0xFFf59e0b),
      'label': 'Pending',
    },
    'inactive': {
      'bg': const Color(0x1964748b),
      'color': const Color(0xFF64748b),
      'label': 'Inactive',
    },
    'suspended': {
      'bg': const Color(0x19ef4444),
      'color': const Color(0xFFef4444),
      'label': 'Suspended',
    },
  };

  final _typeColors = {
    'Licentiate': const Color(0xFFFF5000),
    'Associate': const Color(0xFF10b981),
    'Corporate': const Color(0xFF3b82f6),
  };

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
        _members = [];
      });
    } else {
      if (_members.isEmpty) setState(() => _loading = true);
    }

    await ApiService().fetchDataWithCache(
      '/members/admin/all?page=$_page&limit=20',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;

        if (isCached && _members.isNotEmpty && !refresh) {
          setState(() => _loading = false);
          return;
        }

        if (hasError) {
          if (_members.isEmpty) {
            setState(() {
              _loading = false;
              _hasError = true;
            });
          } else {
            setState(() {
              _loading = false;
            });
          }
          return;
        }

        if (data == null) {
          setState(() => _loading = false);
          return;
        }

        setState(() {
          _loading = false;
          _hasError = false;
          final List<dynamic> newMembers = ApiService.ensureList(data);

          if (refresh || _page == 1 || _members.isEmpty) {
            _members = newMembers;
          } else {
            _members = [..._members, ...newMembers];
          }

          if (data is Map && data.containsKey('total')) {
            _total = int.tryParse(data['total']?.toString() ?? '0') ?? 0;
            _hasMore = _members.length < _total;
          } else {
            _hasMore = false;
          }
        });
      },
    );
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final res = await ApiService().get(
        '/members/admin/all?page=$_page&limit=20',
      );
      if (res.statusCode == 200) {
        final data = res.data;
        final newItems = ApiService.ensureList(data);
        setState(() {
          _members.addAll(newItems);
          if (data is Map && data.containsKey('total')) {
            _hasMore = _members.length < data['total'];
          } else {
            _hasMore = newItems.isEmpty ? false : true;
          }
        });
      }
    } catch (_) {
      _page--;
    }
    setState(() => _loadingMore = false);
  }

  Future<void> _selectMember(Map<String, dynamic> m) async {
    setState(() {
      _selected = Map<String, dynamic>.from(m);
      _editReviewScore =
          double.tryParse((m['manual_review_score'] ?? 10).toString()) ?? 10.0;
    });
    await ApiService().fetchDataWithCache('/members/${m['id']}', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted &&
          data != null &&
          data is Map &&
          _selected?['id'] == m['id']) {
        setState(() {
          _selected = Map<String, dynamic>.from(data);
        });
      }
    });
  }

  Future<void> _updateStatus(dynamic id, String status) async {
    setState(() => _updating = true);
    try {
      final res = await ApiService().put(
        '/members/admin/status/$id',
        data: {'status': status},
      );
      final d = res.data ?? {};
      setState(() {
        _members = _members
            .map(
              (m) => m['id'] == id
                  ? {
                      ...m,
                      'status': status,
                      'license_number':
                          d['license_number'] ?? m['license_number'],
                      'compliance_score':
                          d['compliance_score'] ?? m['compliance_score'],
                      'star_rating': d['star_rating'] ?? m['star_rating'],
                    }
                  : m,
            )
            .toList();
        if (_selected?['id'] == id) {
          _selected = {
            ..._selected!,
            'status': status,
            'compliance_score':
                d['compliance_score'] ?? _selected!['compliance_score'],
            'star_rating': d['star_rating'] ?? _selected!['star_rating'],
          };
        }
      });
    } catch (e, st) {
      AppLogger.error('admin_members_page', e, st);
    }
    setState(() => _updating = false);
  }

  Future<void> _updateReviewScore(dynamic id) async {
    setState(() => _updating = true);
    try {
      final res = await ApiService().put(
        '/members/admin/set-review-score/$id',
        data: {'manual_review_score': _editReviewScore.round()},
      );
      if (res.statusCode == 200) {
        final d = res.data ?? {};
        if (mounted) {
          setState(() {
            _members = _members
                .map(
                  (m) => m['id'] == id
                      ? {
                          ...m,
                          'manual_review_score': _editReviewScore.round(),
                          'compliance_score':
                              d['compliance_score'] ?? m['compliance_score'],
                          'star_rating': d['star_rating'] ?? m['star_rating'],
                        }
                      : m,
                )
                .toList();
            if (_selected?['id'] == id) {
              _selected = {
                ..._selected!,
                'manual_review_score': _editReviewScore.round(),
                'compliance_score':
                    d['compliance_score'] ?? _selected!['compliance_score'],
                'star_rating': d['star_rating'] ?? _selected!['star_rating'],
              };
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Manual review score saved successfully'),
            ),
          );
        }
      }
    } catch (e, st) {
      AppLogger.error('admin_members_page', e, st);
    }
    setState(() => _updating = false);
  }

  String _initials(String n) => n.trim().isEmpty
      ? '?'
      : n
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join()
            .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final total = _members.length;
    final active = _members
        .where((m) => m['status']?.toString().toLowerCase() == 'active')
        .length;
    final pending = _members
        .where((m) {
          final st = m['status']?.toString().toLowerCase() ?? '';
          return st == 'pending' || st == 'pending_review';
        })
        .length;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFFcbd5e1)
        : const Color(0xFF64748b);

    final filtered = _members.where((m) {
      final q = _search.toLowerCase();
      final status = m['status']?.toString().toLowerCase() ?? '';
      if (_filterStatus != 'all' && status != _filterStatus) return false;
      return ((m['name'] ?? '').toString().toLowerCase().contains(q) ||
          (m['email'] ?? '').toString().toLowerCase().contains(q));
    }).toList();

    // Sort logic
    if (_sortBy == 'name') {
      filtered.sort(
        (a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo(
          (b['name']?.toString() ?? '').toLowerCase(),
        ),
      );
    } else if (_sortBy == 'score_desc') {
      filtered.sort((a, b) {
        final scoreA =
            int.tryParse(a['compliance_score']?.toString() ?? '') ?? 100;
        final scoreB =
            int.tryParse(b['compliance_score']?.toString() ?? '') ?? 100;
        return scoreB.compareTo(scoreA);
      });
    } else if (_sortBy == 'score_asc') {
      filtered.sort((a, b) {
        final scoreA =
            int.tryParse(a['compliance_score']?.toString() ?? '') ?? 100;
        final scoreB =
            int.tryParse(b['compliance_score']?.toString() ?? '') ?? 100;
        return scoreA.compareTo(scoreB);
      });
    }

    return AppLayout(
      title: 'Association Members',
      scrollable: false,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminHeader(
                  title: 'Association Members Directory',
                  subtitle:
                      'Manage member compliance standings, branch classifications, verify credentials, and review records.',
                  actions: [
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
                      onPressed: () => _fetch(refresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        'Refresh',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AdminStatCard(
                        icon: Icons.group_rounded,
                        color: kAdminBlue,
                        label: 'Total Members',
                        value: '$total',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdminStatCard(
                        icon: Icons.verified_user_rounded,
                        color: kAdminGreen,
                        label: 'Active Standing',
                        value: '$active',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdminStatCard(
                        icon: Icons.pending_actions_rounded,
                        color: kAdminAmber,
                        label: 'Pending Approval',
                        value: '$pending',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AdminToolbar(
                  searchHint: 'Search members by name, company, email...',
                  onSearchChanged: (v) => setState(() => _search = v),
                  filters: [
                    SizedBox(
                      width: 150,
                      child: CustomDropdown<String>(
                        value: _filterStatus,
                        prefixIcon: const Icon(
                          Icons.filter_alt_outlined,
                          size: 16,
                          color: Color(0xFF64748b),
                        ),
                        items: [
                          DropdownItem(value: 'all', label: 'All ($total)'),
                          DropdownItem(
                            value: 'active',
                            label: 'Active ($active)',
                          ),
                          DropdownItem(
                            value: 'pending',
                            label: 'Pending ($pending)',
                          ),
                          const DropdownItem(
                            value: 'inactive',
                            label: 'Inactive',
                          ),
                          const DropdownItem(
                            value: 'suspended',
                            label: 'Suspended',
                          ),
                        ],
                        onChanged: (v) => setState(() => _filterStatus = v),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: CustomDropdown<String>(
                        value: _sortBy,
                        prefixIcon: const Icon(
                          Icons.sort,
                          size: 16,
                          color: Color(0xFF64748b),
                        ),
                        items: const [
                          DropdownItem(value: 'name', label: 'Name (A-Z)'),
                          DropdownItem(
                            value: 'score_desc',
                            label: 'High Score',
                          ),
                          DropdownItem(value: 'score_asc', label: 'At Risk'),
                        ],
                        onChanged: (v) => setState(() => _sortBy = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 8,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => const ShimmerListTile(),
                  )
                else if (_hasError && _members.isEmpty)
                  FetchErrorView(onRetry: () => _fetch(refresh: true))
                else if (filtered.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        'No members found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  _buildMembersTable(
                    filtered,
                    primary,
                    context,
                    isDark,
                    cardBg,
                    borderColor,
                    textColor,
                    subTextColor,
                  ),
                const SizedBox(height: 12),
                if (_loadingMore)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (!_loading)
                  Center(
                    child: Text(
                      '${filtered.length} members shown${_total > 0 ? " of $_total" : ""}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),

          if (_selected != null)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: GestureDetector(
                  onTap: () => setState(() => _selected = null),
                  child: Container(
                    color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.4),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {},
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        margin: const EdgeInsets.all(24),
                        constraints: const BoxConstraints(
                          maxWidth: 580,
                          maxHeight: 520,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.4 : 0.15,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 24,
                                right: 16,
                                top: 16,
                                bottom: 6,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Member Profile',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: subTextColor,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _selected = null),
                                    splashRadius: 20,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  20,
                                ),
                                child: _buildSheet(
                                  primary,
                                  isDark,
                                  cardBg,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSheet(
    Color primary,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final m = _selected!;
    final c = _typeColors[m['member_type']] ?? primary;
    final ss = _statusStyle[m['status']] ?? _statusStyle['inactive']!;

    final starRating =
        double.tryParse(m['star_rating']?.toString() ?? '') ?? 5.0;
    final complianceScore =
        int.tryParse(m['compliance_score']?.toString() ?? '') ?? 100;
    final tier = StandingTier.getFromStars(starRating);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [c, c.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child:
                  m['profile_photo'] != null &&
                      m['profile_photo'].toString().isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: m['profile_photo'].toString(),
                        width: 52,
                        height: 52,
                        memCacheWidth: 104,
                        memCacheHeight: 104,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      _initials(m['name']?.toString() ?? ''),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['name']?.toString() ?? '',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m['email']?.toString() ?? '',
                    style: GoogleFonts.outfit(
                      color: subTextColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Standing and compliance scorecard
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A0F0A)
                : Colors.grey.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STANDING & COMPLIANCE',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: subTextColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${starRating.toStringAsFixed(1)} / 5.0',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tier.color.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      tier.label,
                      style: GoogleFonts.outfit(
                        color: tier.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: complianceScore / 100.0,
                  backgroundColor: isDark
                      ? const Color(0xFF4D2D20)
                      : Colors.grey.shade200,
                  color: tier.color,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Compliance Score: $complianceScore%',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: subTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Divider(height: 32, color: borderColor),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Manual Review Score: ${_editReviewScore.round()} / 10',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: textColor,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _updating
                        ? null
                        : () => _updateReviewScore(m['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Save Score',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Slider(
                value: _editReviewScore,
                min: 0.0,
                max: 10.0,
                divisions: 10,
                activeColor: primary,
                inactiveColor: primary.withValues(alpha: 0.2),
                onChanged: (val) {
                  setState(() {
                    _editReviewScore = val;
                  });
                },
              ),
            ],
          ),
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A0F0A)
                : Colors.grey.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HISTORICAL COMPLIANCE TREND',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: subTextColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              TrendLineWidget(
                points:
                    (m['rating_history'] as List?)
                        ?.map(
                          (h) =>
                              double.tryParse(
                                h['compliance_score']?.toString() ?? '',
                              ) ??
                              100.0,
                        )
                        .toList() ??
                    [complianceScore.toDouble()],
                color: tier.color,
                height: 100,
              ),
            ],
          ),
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A0F0A)
                : Colors.grey.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: _buildMathBreakdownSection(
            m,
            primary,
            isDark,
            textColor,
            subTextColor,
          ),
        ),

        ...([
          ['Organisation', m['company']],
          ['Membership Type', m['member_type']],
          ['Primary Port', m['port_of_operation']],
          [
            'Membership ID / Number',
            (m['membership_number'] ?? m['license_number'] ?? m['id'])
                    ?.toString() ??
                'N/A',
          ],
          [
            'Agency Code',
            (m['agency_code']?.toString().trim().isEmpty ?? true)
                ? 'N/A'
                : m['agency_code'],
          ],
          [
            'Office Location',
            (m['location']?.toString().trim().isEmpty ?? true)
                ? 'N/A'
                : m['location'],
          ],
          [
            'Digital Address (GPS)',
            (m['digital_address']?.toString().trim().isEmpty ?? true)
                ? 'N/A'
                : m['digital_address'],
          ],
          [
            'Taxpayer TIN',
            (m['tin']?.toString().trim().isEmpty ?? true) ? 'N/A' : m['tin'],
          ],
          [
            'Payment Ref',
            (m['payment_ref']?.toString().trim().isEmpty ?? true)
                ? 'None'
                : m['payment_ref'],
          ],
        ].where((r) => r[1] != null)).map(
          (r) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  r[0].toString().toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: subTextColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    r[1].toString(),
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildMemberPaymentProofSection(m, primary, isDark, cardBg, borderColor, textColor, subTextColor),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A0F0A)
                : Colors.grey.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (ss['bg'] as Color).withValues(
                        alpha: isDark ? 0.25 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (ss['color'] as Color).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      (ss['label'] as String).toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: ss['color'] as Color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Status Controls',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: subTextColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (m['status'] != 'active')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _updating
                            ? null
                            : () => _updateStatus(m['id'], 'active'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Activate',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  if (m['status'] != 'suspended') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _updating
                            ? null
                            : () => _updateStatus(m['id'], 'suspended'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Suspend',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (m['status'] != 'inactive') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _updating
                            ? null
                            : () => _updateStatus(m['id'], 'inactive'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Disable',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => setState(() => _selected = null),
            child: Text(
              'Close Profile',
              style: GoogleFonts.outfit(
                color: subTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersTable(
    List<dynamic> members,
    Color primary,
    BuildContext context,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 950.0;
            final tableWidth = constraints.maxWidth > minTableWidth
                ? constraints.maxWidth
                : minTableWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Table Header Row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1A0F0A)
                            : const Color(0xFFf8fafc),
                        border: Border(
                          bottom: BorderSide(color: borderColor, width: 1.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildHeaderCell('ASSOCIATION MEMBER', 3, textColor),
                          _buildHeaderCell('MEMBER TYPE', 2, textColor),
                          _buildHeaderCell(
                            'STANDING & COMPLIANCE',
                            2,
                            textColor,
                          ),
                          _buildHeaderCell('STATUS', 1, textColor),
                          _buildHeaderCell(
                            'ACTIONS',
                            2,
                            textColor,
                            align: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                    // Table Body Rows (Lazy List Builder)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final m = members[index];
                        final isLast = index == members.length - 1;
                        return _buildTableRow(
                          m,
                          index,
                          isLast,
                          primary,
                          context,
                          isDark,
                          cardBg,
                          borderColor,
                          textColor,
                          subTextColor,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    String label,
    int flex,
    Color textColor, {
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: textColor.withValues(alpha: 0.7),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildTableRow(
    dynamic m,
    int index,
    bool isLast,
    Color primary,
    BuildContext ctx,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final ss = _statusStyle[m['status']] ?? _statusStyle['inactive']!;
    final c = _typeColors[m['member_type']] ?? primary;
    final starRating =
        double.tryParse(m['star_rating']?.toString() ?? '') ?? 5.0;
    final score = int.tryParse(m['compliance_score']?.toString() ?? '') ?? 100;
    final tier = StandingTier.getFromStars(starRating);

    return Container(
      decoration: BoxDecoration(
        color: index.isEven
            ? cardBg
            : (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8F4F0)),
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: borderColor.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectMember(m as Map<String, dynamic>),
          hoverColor: primary.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                // 1. Association Member (Avatar + Name/Email)
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [c, c.withValues(alpha: 0.7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child:
                            m['profile_photo'] != null &&
                                m['profile_photo'].toString().isNotEmpty
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: m['profile_photo'].toString(),
                                  width: 40,
                                  height: 40,
                                  memCacheWidth: 80,
                                  memCacheHeight: 80,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Text(
                                _initials(m['name']?.toString() ?? ''),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              m['name']?.toString() ?? '',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m['email']?.toString() ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                color: subTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Member Type
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m['member_type']?.toString() ?? 'General Member',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: textColor.withValues(alpha: 0.9),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Standing & Compliance
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            color: Color(0xFFFFD700),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${starRating.toStringAsFixed(1)} / 5.0',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '($score%)',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: subTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tier.color.withValues(
                            alpha: isDark ? 0.2 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tier.label,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: tier.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Status
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (ss['bg'] as Color).withValues(
                          alpha: isDark ? 0.25 : 0.15,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (ss['color'] as Color).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        (ss['label'] as String).toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: ss['color'] as Color,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // 5. Actions (View button + Approve if pending)
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (m['status'] == 'pending' || m['status'] == 'pending_review') ...[
                        ElevatedButton.icon(
                          onPressed: () => context.push('/admin/compliance'),
                          icon: const Icon(Icons.verified_outlined, size: 14),
                          label: Text(
                            'Review Compliance',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10b981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: () =>
                            _selectMember(m as Map<String, dynamic>),
                        icon: const Icon(Icons.visibility_outlined, size: 15),
                        label: Text(
                          'View',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary.withValues(
                            alpha: isDark ? 0.2 : 0.1,
                          ),
                          foregroundColor: primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 34),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
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

  Widget _buildMathBreakdownSection(
    Map<String, dynamic> m,
    Color primary,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    final bd = m['breakdown'] as Map<String, dynamic>?;
    if (bd == null || bd.isEmpty || !bd.containsKey('standing')) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'Loading compliance breakdown details...',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    final standingScore = bd['standing'] ?? 0;
    final financialScore = bd['financial'] ?? 0;
    final eventScore = bd['events'] ?? bd['documents'] ?? 0;
    final adminScore = bd['admin'] ?? bd['trust'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMPLIANCE BREAKDOWN MATH',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: subTextColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),

        _breakdownTile(
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF3B82F6),
          title: 'Licensing & Good Standing',
          scoreText: '$standingScore / 40 pts',
          details: [
            '• 40 pts: Active member with valid license.',
            '• 20 pts: Active member but license recently expired.',
            '• 0 pts: Pending, Suspended, or Inactive status.',
          ],
          isDark: isDark,
          textColor: textColor,
          subTextColor: subTextColor,
        ),

        _breakdownTile(
          icon: Icons.payments_outlined,
          color: const Color(0xFF10B981),
          title: 'Financial Compliance',
          scoreText: '$financialScore / 30 pts',
          details: [
            '• Evaluates the ratio of paid invoices vs total issued invoices.',
            '• Members without any invoices start with full points automatically.',
          ],
          isDark: isDark,
          textColor: textColor,
          subTextColor: subTextColor,
        ),

        _breakdownTile(
          icon: Icons.event_available_outlined,
          color: const Color(0xFF8B5CF6),
          title: 'Event Attendance',
          scoreText: '$eventScore / 20 pts',
          details: [
            '• Evaluates ratio of attended events vs total events held since joining.',
            '• If no events have been held since joining, member gets full points.',
          ],
          isDark: isDark,
          textColor: textColor,
          subTextColor: subTextColor,
        ),

        _breakdownTile(
          icon: Icons.admin_panel_settings_outlined,
          color: const Color(0xFFF59E0B),
          title: 'Admin Trust Score',
          scoreText: '$adminScore / 10 pts',
          details: ['• Derived directly from the manual review slider above.'],
          isDark: isDark,
          textColor: textColor,
          subTextColor: subTextColor,
        ),
      ],
    );
  }

  Widget _breakdownTile({
    required IconData icon,
    required Color color,
    required String title,
    required String scoreText,
    required List<String> details,
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
              ),
              Text(
                scoreText,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...details.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(
                detail,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberPaymentProofSection(
    Map<String, dynamic> m,
    Color primary,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final rawReceipt = m['receipt_url']?.toString() ?? '';
    final hasReceipt = rawReceipt.trim().isNotEmpty;
    final payRef = m['payment_ref']?.toString() ?? '';
    final hasPayRef = payRef.trim().isNotEmpty && payRef != 'None';

    if (!hasReceipt && !hasPayRef) {
      return const SizedBox.shrink();
    }

    final receiptUrl = hasReceipt
        ? (rawReceipt.startsWith('http')
            ? rawReceipt
            : '${ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '')}${rawReceipt.startsWith('/') ? '' : '/'}$rawReceipt')
        : '';
    final amount = double.tryParse(m['payment_amount']?.toString() ?? '0') ?? 0.0;
    final status = m['payment_status']?.toString().toLowerCase() ?? 'pending';
    final isPaid = status == 'paid' || status == 'success' || status == 'completed';
    final bankName = m['bank_name']?.toString() ?? 'Bank Deposit';
    final paymentId = m['payment_id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : Colors.grey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPaid ? const Color(0xFF10B981).withValues(alpha: 0.4) : const Color(0xFFFF5000).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isPaid ? const Color(0xFF10B981) : const Color(0xFFFF5000)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: isPaid ? const Color(0xFF10B981) : const Color(0xFFFF5000),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ATTACHED BANK DEPOSIT SLIP',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        color: subTextColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Proof of payment submitted by member',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isPaid ? 'PAID' : 'PENDING REVIEW',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasReceipt)
                GestureDetector(
                  onTap: () => _showDepositSlipModal(context, receiptUrl, payRef, m['name']?.toString() ?? 'Member', amount),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                      color: isDark ? const Color(0xFF281710) : const Color(0xFFF8FAFC),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: receiptUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                        ),
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Icon(Icons.zoom_in, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Color(0xFFFF5000), size: 26),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (amount > 0) ...[
                      Text(
                        'GH₵ ${amount.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isPaid ? const Color(0xFF10B981) : primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      'Ref: $payRef',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    Text(
                      bankName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    if (m['notes'] != null && m['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Note: ${m['notes']}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (!isPaid && paymentId != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _confirmMemberPayment(paymentId),
                  icon: const Icon(Icons.check_circle_rounded, size: 14),
                  label: const Text('Verify & Confirm Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasReceipt)
                  OutlinedButton.icon(
                    onPressed: () => _showDepositSlipModal(context, receiptUrl, payRef, m['name']?.toString() ?? 'Member', amount),
                    icon: const Icon(Icons.visibility_rounded, size: 14),
                    label: const Text('View Slip'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ] else if (hasReceipt) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showDepositSlipModal(context, receiptUrl, payRef, m['name']?.toString() ?? 'Member', amount),
              child: Text(
                'View Attached Deposit Slip Image →',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmMemberPayment(dynamic paymentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Bank Deposit'),
        content: const Text('Are you sure you want to verify and confirm this member\'s bank deposit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService().post('/payments/admin/mark-paid/$paymentId');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed successfully!'), backgroundColor: Color(0xFF10B981)),
        );
        if (_selected != null) {
          setState(() {
            _selected!['payment_status'] = 'paid';
          });
        }
        _fetch(refresh: true);
      }
    } catch (e, st) {
      AppLogger.error('admin_members_confirm_payment', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error confirming payment.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDepositSlipModal(BuildContext context, String fullUrl, String payRef, String memberName, double amount) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 800,
          height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded, color: Color(0xFFFF5000), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Deposit Slip · $memberName · Ref: $payRef',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: fullUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF5000))),
                    errorWidget: (_, _, _) => const Center(child: Text('Failed to load deposit slip image.')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
