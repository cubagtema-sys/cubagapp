import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../design/cubag_design.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = CubagColors.action; // Primary Orange CTA
const _kCream = CubagColors.sand; // Light Background Cream
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = CubagColors.ink; // Deep Body Text
const _kMuted = CubagColors.muted; // Secondary Muted Text
const _kBorder = CubagColors.line; // Soft Warm Border

class NetworkingPage extends StatefulWidget {
  const NetworkingPage({super.key});
  @override
  State<NetworkingPage> createState() => _NetworkingPageState();
}

class _NetworkingPageState extends State<NetworkingPage> {
  bool _loading = true;
  List<dynamic> _members = [];
  String _search = '';
  String _filterType = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  final Map<String, Color> _typeColors = {
    'Licentiate': _kOrange,
    'Associate': CubagColors.valid,
    'Corporate': _kBrown,
  };

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = _search;
    _fetch();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _search = v);
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

    try {
      final res = await ApiService().get('/members');
      if (mounted && res.data != null) {
        final list = ApiService.ensureList(res.data);
        if (list.isNotEmpty) {
          setState(() {
            _members = list;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    try {
      final pubRes = await ApiService().getPublic('members/public/members');
      if (mounted) {
        final pubList = ApiService.ensureList(pubRes);
        setState(() {
          _members = pubList;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _initials(String name) => name.trim().isEmpty
      ? '?'
      : name
            .split(' ')
            .where((n) => n.isNotEmpty)
            .map((n) => n[0])
            .take(2)
            .join()
            .toUpperCase();

  Widget _buildFilterChip(String value, String label, bool isDark) {
    final isSelected = _filterType == value;
    final chipBg = isSelected
        ? _kBrown
        : (isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0));
    final chipBorder = isSelected
        ? _kBrown
        : (isDark ? const Color(0xFF3D261C) : CubagColors.line);

    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: chipBorder, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? const Color(0xFFFFF8F3) : _kText),
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _kCream, shape: BoxShape.circle),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: _kBrown,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Members Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _search.isNotEmpty
                  ? 'Try refining your keywords or clearing the search query.'
                  : 'There are no active members currently registered in this category.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _kMuted,
                height: 1.4,
              ),
            ),
            if (_search.isNotEmpty || _filterType != 'All') ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _search = '';
                  _filterType = 'All';
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBrown,
                  side: const BorderSide(color: _kBrown),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reset Filters',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> m, bool isDark) {
    final mType = (m['member_type'] ?? 'Licensed').toString().trim();
    final initials = _initials(m['name']?.toString() ?? '');
    final port = m['port_of_operation'] ?? m['primary_port'] ?? 'Tema Maritime Port';
    final name = m['name']?.toString() ?? 'Licensed Member';
    final company = m['company']?.toString() ?? 'Accredited Member Enterprise';
    final regId = m['license_number'] ?? m['membership_number'] ?? 'GH-${(m['id']?.toString() ?? '00').padLeft(4, '0')}';

    final cardBg = isDark ? const Color(0xFF1E130D) : _kWhite;
    final textColor = isDark ? const Color(0xFFFFF8F3) : _kText;
    final mutedColor = isDark ? const Color(0xFFC8ADA0) : _kMuted;
    final borderColor = isDark ? const Color(0xFF3D261C) : _kBorder;
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 1.0),
                  image: (m['profile_photo'] != null &&
                          m['profile_photo'].toString().isNotEmpty)
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(m['profile_photo'].toString()),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (m['profile_photo'] == null ||
                        m['profile_photo'].toString().isEmpty)
                    ? Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: _kBrown,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: surfaceRaised,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderColor, width: 1.0),
                          ),
                          child: Text(
                            mType.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: _kBrown,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            regId.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: borderColor, height: 1.0),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.business_rounded, size: 14, color: mutedColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  company,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.anchor_rounded, size: 14, color: mutedColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  port.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: mutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _showMemberDetails(context, m);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor, width: 1.0),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'Profile',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final id = m['id']?.toString() ?? '';
                    final n = m['name']?.toString() ?? 'Member';
                    final c = m['company']?.toString() ?? '';
                    context.go(
                      '/messaging?id=$id&name=${Uri.encodeComponent(n)}&company=${Uri.encodeComponent(c)}',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'Message',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMemberDetails(BuildContext context, Map<String, dynamic> m) {
    final selectedMember = Map<String, dynamic>.from(m);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: BoxDecoration(
            color: _kWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Member Information',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _kBrown,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: _kMuted),
                      onPressed: () => Navigator.pop(ctx),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _kBorder),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: _buildDetailSheet(selectedMember),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSheet(Map<String, dynamic> m) {
    final mType = (m['member_type'] ?? '').toString().trim();
    final color =
        _typeColors[mType] ?? _typeColors[mType.toLowerCase()] ?? _kBrown;
    final initials = _initials(m['name']?.toString() ?? '');
    final name = m['name']?.toString() ?? 'Licensed Member';
    final email = m['email']?.toString();
    final phone = m['phone']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: _kCream,
              backgroundImage:
                  (m['profile_photo'] != null &&
                      m['profile_photo'].toString().isNotEmpty)
                  ? CachedNetworkImageProvider(
                      m['profile_photo'].toString(),
                      maxWidth: 80,
                      maxHeight: 80,
                    )
                  : null,
              child:
                  (m['profile_photo'] == null ||
                      m['profile_photo'].toString().isEmpty)
                  ? Text(
                      initials,
                      style: TextStyle(
                        color: _kBrown,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(60)),
                    ),
                    child: Text(
                      (mType.isNotEmpty ? mType : 'MEMBER').toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Info Rows
        ...([
          {
            'icon': Icons.business_rounded,
            'label': 'ORGANISATION',
            'val': m['company'],
          },
          {
            'icon': Icons.location_on_rounded,
            'label': 'DISTRICT(S)',
            'val': m['port_of_operation'] ?? m['primary_port'],
          },
          {
            'icon': Icons.badge_rounded,
            'label': 'MEMBERSHIP ID',
            'val': m['membership_number'] ?? m['license_number'],
          },
          {
            'icon': Icons.mail_outline_rounded,
            'label': 'EMAIL ADDRESS',
            'val': email,
          },
          {'icon': Icons.phone_outlined, 'label': 'TELEPHONE', 'val': phone},
        ].where((r) => r['val'] != null && r['val'].toString().isNotEmpty)).map(
          (row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kBrown.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      row['icon'] as IconData,
                      color: _kBrown,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['label'].toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: _kMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row['val'].toString(),
                          style: TextStyle(
                            fontSize: 15,
                            color: _kText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Primary Chat Action Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final id = m['id']?.toString() ?? '';
              final n = m['name']?.toString() ?? 'Member';
              final c = m['company']?.toString() ?? '';
              context.go(
                '/messaging?id=$id&name=${Uri.encodeComponent(n)}&company=${Uri.encodeComponent(c)}',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(
              'Start A Conversation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Secondary Communication Actions (Call & Email)
        Row(
          children: [
            if (phone != null && phone.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBrown,
                    side: const BorderSide(color: _kBorder, width: 1.2),
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: const Text('Call'),
                ),
              ),
            if (phone != null &&
                phone.isNotEmpty &&
                email != null &&
                email.isNotEmpty)
              const SizedBox(width: 10),
            if (email != null && email.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('mailto:$email');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBrown,
                    side: const BorderSide(color: _kBorder, width: 1.2),
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  icon: const Icon(Icons.mail_rounded, size: 16),
                  label: const Text('Send Email'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : _kWhite;
    final borderColor = isDark ? const Color(0xFF3D261C) : _kBorder;
    final textColor = isDark ? const Color(0xFFFFF8F3) : _kText;

    final filtered = _members.where((m) {
      if (m['role'] == 'admin' || m['role'] == 'sub_admin') return false;
      final q = _search.toLowerCase();
      final matchSearch =
          (m['name'] ?? '').toString().toLowerCase().contains(q) ||
          (m['company'] ?? '').toString().toLowerCase().contains(q) ||
          (m['port_of_operation'] ?? m['primary_port'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
      final matchType =
          _filterType == 'All' ||
          (m['member_type'] ?? '').toString().trim().toLowerCase() ==
              _filterType.toLowerCase();
      return matchSearch && matchType;
    }).toList();

    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

    return AppLayout(
      title: 'Directory',
      hideSearch: false,
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Editorial Ledger Registry Header ────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: surfaceRaised,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor, width: 1.0),
                        ),
                        child: const Icon(Icons.badge_outlined, color: _kBrown, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'National Register of Accredited Members',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: textColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── 1. Search Bar ─────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: TextFormField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Search members by name, company, or operating port...',
                      hintStyle: TextStyle(
                        color: _kMuted.withValues(alpha: 0.7),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _kBrown,
                        size: 18,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: Icon(
                                Icons.clear_rounded,
                                color: _kMuted,
                                size: 16,
                              ),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _search = '';
                              }),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── 2. Type filter chips ──────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'All Members', isDark),
                      _buildFilterChip('Corporate', 'Corporate', isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'SHOWING ${filtered.length} ACTIVE PRACTITIONERS',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _kBrown,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),

                // ── 3. Grid / List View ───────────────────────────────────────
                if (_loading && filtered.isEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 6,
                    separatorBuilder: (ctx, i) =>
                        const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => const ShimmerListTile(),
                  )
                else if (filtered.isEmpty)
                  _buildEmptyState()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final isWide = width > 600;
                      if (isWide) {
                        final int crossAxisCount = width >= 1200
                            ? 4
                            : (width >= 850 ? 3 : 2);
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 178,
                              ),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            return _buildMemberCard(
                              filtered[i] as Map<String, dynamic>,
                              isDark,
                            );
                          },
                        );
                      } else {
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            return SizedBox(
                              height: 178,
                              child: _buildMemberCard(
                                filtered[i] as Map<String, dynamic>,
                                isDark,
                              ),
                            );
                          },
                        );
                      }
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
