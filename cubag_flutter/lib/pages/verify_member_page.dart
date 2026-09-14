import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VerifyMemberPage extends StatefulWidget {
  final String? memberId;
  const VerifyMemberPage({super.key, this.memberId});
  @override
  State<VerifyMemberPage> createState() => _VerifyMemberPageState();
}

class _VerifyMemberPageState extends State<VerifyMemberPage> {
  bool _loading = true;
  Map<String, dynamic>? _member;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.memberId == null) {
      setState(() {
        _error =
            'Membership could not be verified. Please contact CUBAG for assistance.';
        _loading = false;
      });
      return;
    }
    try {
      final res = await ApiService().getPublic(
        'members/public/verify-member?query=${Uri.encodeComponent(widget.memberId!)}',
      );
      if (res is Map && res['verified'] == true) {
        setState(() => _member = Map<String, dynamic>.from(res));
      } else {
        setState(
          () => _error = (res is Map && res['message'] != null)
              ? res['message']
              : 'Membership could not be verified. Please contact CUBAG for assistance.',
        );
      }
    } catch (_) {
      setState(
        () => _error =
            'Membership could not be verified. Please contact CUBAG for assistance.',
      );
    }
    setState(() => _loading = false);
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
    final primary = Theme.of(context).primaryColor;

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'VERIFYING CUBAG CREDENTIALS...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _member == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 25,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Color(0xFFef4444), size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Invalid ID',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ??
                      'This QR code does not correspond to an active CUBAG member.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, height: 1.6),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.go('/'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Return to Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

    final m = _member!;
    final status = (m['status']?.toString().toLowerCase() ?? 'pending');
    final isVerified = status == 'active';
    final badgeColor = isVerified
        ? const Color(0xFF10b981)
        : const Color(0xFFf59e0b);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  children: [
                    // Verification banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isVerified ? Icons.verified : Icons.pending_actions,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (isVerified
                                ? 'AUTHENTIC CUBAG MEMBER'
                                : 'MEMBER STATUS: ${status.toUpperCase()}'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Card body
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 40,
                            offset: Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: badgeColor, width: 4),
                            ),
                            child: ClipOval(
                              child: m['profile_photo'] != null
                                  ? CachedNetworkImage(
                                      imageUrl: m['profile_photo'].toString(),
                                      memCacheWidth: 200,
                                      memCacheHeight: 200,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: const Color(0xFFF1F5F9),
                                      child: Center(
                                        child: Text(
                                          _initials(
                                            m['name']?.toString() ?? '',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 34,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF94a3b8),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            m['name']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A0F0A),
                            ),
                          ),
                          Text(
                            m['company']?.toString() ?? 'Independent Broker',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Details
                          ...[
                                {
                                  'label': 'Member / Company',
                                  'val':
                                      m['member_name'] ??
                                      m['company'] ??
                                      m['name'],
                                  'icon': Icons.business_outlined,
                                },
                                {
                                  'label': 'Membership ID / Number',
                                  'val':
                                      m['membership_number'] ??
                                      m['license_number'],
                                  'icon': Icons.card_membership_rounded,
                                },
                                {
                                  'label': 'Primary Port',
                                  'val': m['primary_port'],
                                  'icon': Icons.location_on_outlined,
                                },
                                {
                                  'label': 'Valid Until',
                                  'val': m['valid_until'],
                                  'icon': Icons.event_available_rounded,
                                },
                                {
                                  'label': 'Last Verified',
                                  'val': m['last_verified_date'],
                                  'icon': Icons.verified_user_rounded,
                                },
                              ]
                              .where((r) => r['val'] != null)
                              .map(
                                (r) => Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        r['icon'] as IconData,
                                        color: badgeColor,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r['label'].toString().toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          Text(
                                            r['val'].toString(),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF281710),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                            'Official verification for Customs Brokers Association of Ghana.\n© ${DateTime.now().year} CUBAG Secretariat.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Visit Official Website',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
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
    );
  }
}
