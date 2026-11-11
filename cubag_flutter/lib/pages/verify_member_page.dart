import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import 'admin_qr_scanner_page.dart';

const _kBrown = Color(0xFF6B3E26);
const _kOrange = Color(0xFFFF5000);
const _kDark = Color(0xFF1A0F0A);

class VerifyMemberPage extends StatefulWidget {
  final String? memberId;
  const VerifyMemberPage({super.key, this.memberId});

  @override
  State<VerifyMemberPage> createState() => _VerifyMemberPageState();
}

class _VerifyMemberPageState extends State<VerifyMemberPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _member;
  String? _error;
  String? _currentQuery;

  @override
  void initState() {
    super.initState();
    final initialId = _resolveMemberId();
    if (initialId != null && initialId.isNotEmpty) {
      _searchCtrl.text = initialId;
      _fetch(initialId);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? _resolveMemberId() {
    if (widget.memberId != null && widget.memberId!.trim().isNotEmpty) {
      return widget.memberId!.trim();
    }
    final frag = Uri.tryParse(Uri.base.fragment);
    if (frag != null && frag.queryParameters['id'] != null) {
      return frag.queryParameters['id']!.trim();
    }
    if (frag != null && frag.queryParameters['query'] != null) {
      return frag.queryParameters['query']!.trim();
    }
    return Uri.base.queryParameters['id']?.trim() ?? Uri.base.queryParameters['query']?.trim();
  }

  Future<void> _fetch([String? targetId]) async {
    final queryId = (targetId ?? _searchCtrl.text).trim();
    if (queryId.isEmpty) {
      setState(() {
        _error = 'Please enter a member ID, customs license number, or scan a QR code.';
        _member = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _currentQuery = queryId;
    });

    try {
      final res = await ApiService().getPublic(
        'members/public/verify-member?query=${Uri.encodeComponent(queryId)}',
      );
      if (res is Map && res['verified'] == true) {
        setState(() {
          _member = Map<String, dynamic>.from(res);
          _error = null;
        });
      } else {
        setState(() {
          _member = null;
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : 'This credential does not correspond to an active CUBAG member.';
        });
      }
    } catch (_) {
      setState(() {
        _member = null;
        _error = 'Unable to verify membership at this time. Please check your connection and try again.';
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminQrScannerPage(
          onScan: (scanned) {
            final clean = scanned.trim();
            if (clean.isNotEmpty) {
              _searchCtrl.text = clean;
              _fetch(clean);
            }
          },
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _kDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Credential Verification',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: _kOrange),
            tooltip: 'Scan Member QR Badge',
            onPressed: _openQrScanner,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) ...[
                    const SizedBox(height: 60),
                    const Center(child: CircularProgressIndicator(color: _kOrange)),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'VERIFYING CUBAG CREDENTIALS...',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ] else if (_member != null) ...[
                    _buildVerifiedCard(_member!),
                  ] else ...[
                    _buildLookupCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLookupCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _error != null
                  ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                  : _kOrange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _error != null ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
              color: _error != null ? const Color(0xFFEF4444) : _kOrange,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _error != null ? 'Verification Result' : 'Verify Member Credentials',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ??
                'Scan a physical CUBAG digital badge QR code or enter a member number below to confirm active accreditation and good standing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _error != null ? const Color(0xFFDC2626) : Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Primary Action: Camera QR Scanner
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openQrScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
              label: Text(
                'Scan Badge QR Code',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR SEARCH MANUALLY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 20),

          // Manual Entry Field
          TextField(
            controller: _searchCtrl,
            onSubmitted: (val) => _fetch(val),
            decoration: InputDecoration(
              hintText: 'Member ID or License # (e.g. CUBAG-0042)',
              hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search_rounded, color: _kBrown, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _error = null;
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kOrange, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => _fetch(_searchCtrl.text),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBrown, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Verify Member ID',
                style: TextStyle(
                  color: _kBrown,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
          TextButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
            child: Text(
              'Back to Portal',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedCard(Map<String, dynamic> m) {
    final status = (m['status']?.toString().toLowerCase() ?? 'active').trim();
    final isVerified = m['verified'] == true || status == 'active' || m['good_standing'] == true;
    final badgeColor = isVerified ? const Color(0xFF10b981) : const Color(0xFFf59e0b);

    return Column(
      children: [
        // Verification banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isVerified ? Icons.verified_rounded : Icons.pending_actions_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                (isVerified ? 'AUTHENTIC CUBAG MEMBER' : 'MEMBER STATUS: ${status.toUpperCase()}'),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        // Card body
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 30,
                offset: Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            children: [
              // Avatar
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeColor, width: 3.5),
                ),
                child: ClipOval(
                  child: m['profile_photo'] != null
                      ? CachedNetworkImage(
                          imageUrl: m['profile_photo'].toString(),
                          memCacheWidth: 180,
                          memCacheHeight: 180,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: const Color(0xFFF1F5F9),
                          child: Center(
                            child: Text(
                              _initials(m['name']?.toString() ?? ''),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF5F6B7E),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                m['name']?.toString() ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _kDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                m['company']?.toString() ?? 'Independent Broker',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),

              // Details
              ...[
                {
                  'label': 'Member / Company',
                  'val': m['member_name'] ?? m['company'] ?? m['name'],
                  'icon': Icons.business_outlined,
                },
                {
                  'label': 'Membership ID / Number',
                  'val': m['membership_number'] ?? m['license_number'] ?? _currentQuery,
                  'icon': Icons.card_membership_rounded,
                },
                {
                  'label': 'Operating Port(s)',
                  'val': m['primary_port'] ?? m['port_of_operation'],
                  'icon': Icons.location_on_outlined,
                },
                {
                  'label': 'Valid Until',
                  'val': m['valid_until'] ?? 'December 31, ${DateTime.now().year}',
                  'icon': Icons.event_available_rounded,
                },
                {
                  'label': 'Status Verification',
                  'val': 'Active Accreditation & Good Standing',
                  'icon': Icons.verified_user_rounded,
                },
              ].where((r) => r['val'] != null).map(
                    (r) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(r['icon'] as IconData, color: badgeColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['label'].toString().toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r['val'].toString(),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF281710),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

              const SizedBox(height: 20),

              // Actions: Scan Another Badge & Close
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _openQrScanner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
                  label: Text(
                    'Scan Another Member Badge',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _member = null;
                      _error = null;
                      _searchCtrl.clear();
                    });
                  },
                  child: Text(
                    'Search Another Credential',
                    style: TextStyle(
                      color: _kBrown,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const Divider(height: 28),
              Text(
                'Official digital verification by Customs Brokers Association Ghana.\n© ${DateTime.now().year} CUBAG Secretariat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
