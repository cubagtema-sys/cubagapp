import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

// Unified CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary brand brown
const _kDark = Color(0xFF2B211D); // Deep dark contrast & hero
const _kAccent = Color(0xFFFF5000); // Accent CTA orange
const _kBg = Color(0xFFFFFFFF); // Page background
const _kCream = Color(0xFFF8F4F0); // Surface light cream
const _kText = Color(0xFF2B211D); // Body primary text
const _kMuted = Color(0xFF6F625B); // Secondary muted text
const _kBorder = Color(0xFFE8DED6); // Soft warm border
const _kGreen = Color(0xFF10B981); // Verified good standing green

class PublicDirectoryPage extends StatefulWidget {
  const PublicDirectoryPage({super.key});

  @override
  State<PublicDirectoryPage> createState() => _PublicDirectoryPageState();
}

class _PublicDirectoryPageState extends State<PublicDirectoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  List<dynamic> _allMembers = [];
  String _selectedPort = 'all';
  String _selectedCategory = 'all';

  final List<String> _portsList = [
    'all',
    'Accra International Airport',
    'Aflao Border',
    'Elubo Border',
    'Takoradi Port',
    'Tema Port',
  ];

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fetchMembers(v);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers([String? search]) async {
    setState(() => _loading = true);
    try {
      final q = (search ?? _searchCtrl.text).trim();
      final url = 'members/public/members?search=${Uri.encodeComponent(q)}';
      final res = await ApiService().getPublic(url);
      if (res is List && mounted) {
        setState(() {
          // Strictly only Good Standing members (excluding admins)
          _allMembers = res.where((m) {
            final role = (m['role'] ?? '').toString().toLowerCase();
            if ([
                  'admin',
                  'super_admin',
                  'sub_admin',
                  'staff',
                  'system',
                ].contains(role) ||
                m['is_admin'] == true) {
              return false;
            }
            final isGood =
                (m['is_good_standing'] == true ||
                    m['good_standing'] == true ||
                    [
                      'active',
                      'approved',
                    ].contains((m['status'] ?? '').toString().toLowerCase())) &&
                ![
                  'pending',
                  'rejected',
                  'suspended',
                  'expelled',
                  'inactive',
                ].contains((m['status'] ?? '').toString().toLowerCase());
            return isGood;
          }).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _matchesPort(dynamic m, String filterPort) {
    if (filterPort == 'all' || filterPort.isEmpty) return true;
    final port = '${m['primary_port'] ?? ''} ${m['port_of_operation'] ?? ''}'
        .toLowerCase();
    final target = filterPort.toLowerCase();
    if (target.contains('tema')) return port.contains('tema');
    if (target.contains('takoradi') || target.contains('tkd')) {
      return port.contains('takoradi') || port.contains('tkd');
    }
    if (target.contains('accra') ||
        target.contains('kia') ||
        target.contains('kotoka') ||
        target.contains('airport')) {
      return port.contains('accra') ||
          port.contains('kia') ||
          port.contains('kotoka') ||
          port.contains('airport');
    }
    if (target.contains('aflao')) return port.contains('aflao');
    if (target.contains('elubo')) return port.contains('elubo');
    if (target.contains('paga')) return port.contains('paga');
    return port.contains(target) || target.contains(port);
  }

  List<dynamic> get _filteredMembers {
    return _allMembers.where((m) {
      if (!_matchesPort(m, _selectedPort)) return false;
      if (_selectedCategory != 'all') {
        final cat = (m['member_type']?.toString() ?? '').toLowerCase();
        if (!cat.contains(_selectedCategory.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  void _showVerifyModal(Map<String, dynamic> m) {
    final company =
        m['company']?.toString() ?? m['name']?.toString() ?? 'CUBAG Member';
    final name = m['name']?.toString() ?? '';
    final port = m['primary_port']?.toString() ?? 'Tema Port';
    final type = m['member_type']?.toString() ?? 'Licentiate';
    final phone = m['phone']?.toString() ?? '';
    final email = m['email']?.toString() ?? '';
    final location = m['location']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kGreen.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: _kGreen,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Accredited Customs Broker',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: _kText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Customs Brokers Association of Ghana (CUBAG)',
              style: GoogleFonts.inter(fontSize: 14, color: _kMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Company Entity', company),
                  if (name.isNotEmpty && name != company) ...[
                    const Divider(height: 16),
                    _detailRow('Lead Broker / Contact', name),
                  ],
                  const Divider(height: 16),
                  _detailRow('Primary Port', port),
                  const Divider(height: 16),
                  _detailRow('Member Category', type),
                  if (location.isNotEmpty) ...[
                    const Divider(height: 16),
                    _detailRow('Office Location', location),
                  ],
                  if (phone.isNotEmpty) ...[
                    const Divider(height: 16),
                    _detailRow('Direct Phone', phone),
                  ],
                  if (email.isNotEmpty) ...[
                    const Divider(height: 16),
                    _detailRow('Official Email', email, isEmail: true),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      final id = m['id']?.toString() ?? '';
                      final n = m['name']?.toString() ?? company;
                      final c = company;
                      context.go(
                        '/messaging?id=$id&name=${Uri.encodeComponent(n)}&company=${Uri.encodeComponent(c)}',
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: Text(
                      'Start A Conversation',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kText,
                      side: const BorderSide(color: _kBorder, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Close',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isEmail = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 14.5, color: _kMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: SelectableText(
              value,
              style: GoogleFonts.outfit(
                fontSize: isEmail ? 14.5 : 15,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 800;
    final members = _filteredMembers;

    return Scaffold(
      backgroundColor: _kBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Top Public Navbar ───────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                top: 16 + MediaQuery.of(context).padding.top,
                bottom: 16,
                left: (isMobile ? 16 : 48) + MediaQuery.of(context).padding.left,
                right: (isMobile ? 16 : 48) + MediaQuery.of(context).padding.right,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _kBrown,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'C',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                                Text(
                              'CUBAG',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: _kBrown,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              'Customs Brokers Association',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _kMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => context.go('/'),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: _kBrown,
                        ),
                        label: Text(
                          'Back to Home',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: _kBrown,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => context.go('/login'),
                        child: Text(
                          'Member Portal',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _kBorder),

            // ── Hero Directory Header ───────────────────────────────────────
            Container(
              width: double.infinity,
              color: _kDark,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 20 : 48,
                vertical: 48,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccent.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _kAccent.withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              color: _kAccent,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'OFFICIAL PUBLIC DIRECTORY',
                              style: GoogleFonts.outfit(
                                color: _kAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Accredited Customs Brokers in Ghana',
                        style: GoogleFonts.outfit(
                          fontSize: isMobile ? 28 : 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search and verify registered CUBAG members holding active licenses across Ghana.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      // Search bar
                      Container(
                        constraints: const BoxConstraints(maxWidth: 720),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText:
                                'Search by company name, licensed broker, or membership ID...',
                            hintStyle: GoogleFonts.inter(
                              color: _kMuted,
                              fontSize: 16,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: _kBrown,
                              size: 22,
                            ),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                      color: _kMuted,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _fetchMembers('');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Filters & Directory Body ────────────────────────────────────
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 48,
                vertical: 36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filter toolbar
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.tune_rounded,
                                      size: 18,
                                      color: _kBrown,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Filter by Port of Operation',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: _kBrown,
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
                                    color: _kGreen.withAlpha(20),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${members.length} Accredited Members',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _kGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _portsList.map((port) {
                                final isSelected = _selectedPort == port;
                                final label = port == 'all'
                                    ? 'All Ports & Borders'
                                    : port;
                                return FilterChip(
                                  label: Text(label),
                                  selected: isSelected,
                                  selectedColor: _kAccent.withAlpha(30),
                                  checkmarkColor: _kAccent,
                                  labelStyle: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: isSelected ? _kAccent : _kText,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _selectedPort = port),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Member Cards Grid
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(60),
                          child: Center(
                            child: CircularProgressIndicator(color: _kAccent),
                          ),
                        )
                      else if (members.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: _kMuted.withAlpha(160),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No Verified Members Found',
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _kText,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No customs broker matched your search filter criteria.',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    color: _kMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 18),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kBrown,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _selectedPort = 'all';
                                      _selectedCategory = 'all';
                                    });
                                    _fetchMembers('');
                                  },
                                  child: Text(
                                    'Reset Filters',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isMobile ? 1 : 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: isMobile ? 2.2 : 2.5,
                              ),
                          itemCount: members.length,
                          itemBuilder: (ctx, idx) {
                            final m = members[idx];
                            final company =
                                m['company']?.toString() ??
                                m['name']?.toString() ??
                                'CUBAG Member';
                            final name = m['name']?.toString() ?? '';
                            final memNo =
                                m['membership_number']?.toString() ??
                                'CUBAG-2026-000';
                            final port =
                                m['primary_port']?.toString() ?? 'Tema Port';
                            final type =
                                m['member_type']?.toString() ?? 'Licentiate';

                            return Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _kBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: _kBrown.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.business_outlined,
                                          color: _kBrown,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company,
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 17,
                                                color: _kText,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (name.isNotEmpty &&
                                                name != company)
                                              Text(
                                                'Broker: $name',
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  color: _kMuted,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.pin_drop_outlined,
                                                  size: 13,
                                                  color: _kMuted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$port • $memNo',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: _kMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 14),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _kGreen.withAlpha(25),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: _kGreen.withAlpha(60),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.verified_rounded,
                                                  size: 12,
                                                  color: _kGreen,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Verified',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kGreen,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _kBrown.withAlpha(15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              type.toUpperCase(),
                                              style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: _kBrown,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => _showVerifyModal(
                                          Map<String, dynamic>.from(m),
                                        ),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 14,
                                          color: _kBrown,
                                        ),
                                        label: Text(
                                          'View',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: _kBrown,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              color: _kDark,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Center(
                child: Text(
                  '© 2026 Customs Brokers Association of Ghana (CUBAG). All rights reserved.',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
