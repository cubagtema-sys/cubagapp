import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kCream = Color(0xFFF8F4F0); // Light Background Cream
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = Color(0xFF2B211D); // Deep Body Text
const _kMuted = Color(0xFF6F625B); // Secondary Muted Text
const _kBorder = Color(0xFFE8DED6); // Soft Warm Border

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
    'Associate': const Color(0xFF10b981),
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

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : _kCream,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _kBrown : _kBorder, width: 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kBrown.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : _kText,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
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
              style: GoogleFonts.outfit(
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
              style: GoogleFonts.inter(
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

  Widget _buildMemberCard(Map<String, dynamic> m) {
    final mType = (m['member_type'] ?? '').toString().trim();
    final color =
        _typeColors[mType] ?? _typeColors[mType.toLowerCase()] ?? _kBrown;
    final initials = _initials(m['name']?.toString() ?? '');
    final port = m['port_of_operation'] ?? m['primary_port'] ?? 'Tema Port';
    final name = m['name']?.toString() ?? 'Licensed Member';
    final company = m['company']?.toString() ?? 'Independent Broker';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _kCream,
                backgroundImage:
                    (m['profile_photo'] != null &&
                        m['profile_photo'].toString().isNotEmpty)
                    ? CachedNetworkImageProvider(m['profile_photo'].toString())
                    : null,
                child:
                    (m['profile_photo'] == null ||
                        m['profile_photo'].toString().isEmpty)
                    ? Text(
                        initials,
                        style: GoogleFonts.outfit(
                          color: _kBrown,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: _kText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
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
                        mType.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.business_rounded, size: 14, color: _kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  company,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _kMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 14, color: _kOrange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  port.toString(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _kMuted,
                    fontWeight: FontWeight.w500,
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
                    foregroundColor: _kBrown,
                    side: const BorderSide(color: _kBorder, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Details',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
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
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 13),
                  label: Text(
                    'Start A Conversation',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _kBrown,
                      ),
                    ),
                    IconButton(
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
                      style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
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
            'label': 'PORT OF OPERATION',
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
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _kMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row['val'].toString(),
                          style: GoogleFonts.inter(
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
              style: GoogleFonts.outfit(
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
                    textStyle: GoogleFonts.outfit(
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
                    textStyle: GoogleFonts.outfit(
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

    return AppLayout(
      title: 'Member Directory',
      hideSearch: false,
      scrollable: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Search Bar ─────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: _kWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: TextFormField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: _kText,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Search members by name, company, or operating port...',
                      hintStyle: TextStyle(
                        color: _kMuted.withAlpha(160),
                        fontSize: 15,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _kBrown,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: _kMuted,
                                size: 18,
                              ),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _search = '';
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
                const SizedBox(height: 12),

                // ── 2. Type filter chips ──────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'All Members'),
                      _buildFilterChip('Licentiate', 'Licentiate'),
                      _buildFilterChip('Associate', 'Associate'),
                      _buildFilterChip('Corporate', 'Corporate'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'SHOWING ${filtered.length} ACTIVE MEMBERS',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: _kBrown,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),

                // ── 3. Grid / List View ───────────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetch,
                    color: _kOrange,
                    child: _loading && filtered.isEmpty
                        ? ListView.separated(
                            itemCount: 6,
                            separatorBuilder: (ctx, i) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => const ShimmerListTile(),
                          )
                        : filtered.isEmpty
                        ? _buildEmptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth > 650;
                              if (isWide) {
                                return GridView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 1.55,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    return _buildMemberCard(
                                      filtered[i] as Map<String, dynamic>,
                                    );
                                  },
                                );
                              } else {
                                return ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (ctx, i) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) {
                                    return SizedBox(
                                      height: 200,
                                      child: _buildMemberCard(
                                        filtered[i] as Map<String, dynamic>,
                                      ),
                                    );
                                  },
                                );
                              }
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
