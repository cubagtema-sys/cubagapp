import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class MemberDetailPage extends StatefulWidget {
  final String? memberId;
  const MemberDetailPage({super.key, this.memberId});
  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  bool _loading = true;
  Map<String, dynamic>? _member;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_member == null) setState(() => _loading = true);
    await ApiService().fetchDataWithCache('/members/${widget.memberId}', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null && data is Map) {
        setState(() {
          _member = Map<String, dynamic>.from(data);
          _loading = false;
        });
      }
    });
    if (mounted && _loading) setState(() => _loading = false);
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return 'M';
    return name
        .trim()
        .split(' ')
        .where((n) => n.isNotEmpty)
        .map((n) => n[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return AppLayout(
      title: 'Member Profile',
      child: Column(
        children: [
          if (_loading)
            const ShimmerLoader(
              width: double.infinity,
              height: 300,
              borderRadius: 16,
            )
          else if (_member == null)
            Container(
              padding: const EdgeInsets.all(60),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.person_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Profile Not Found',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.go('/networking'),
                    child: const Text('Back to Directory'),
                  ),
                ],
              ),
            )
          else ...[
            // Header card with gradient banner
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Theme.of(context).cardColor,
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary, primary.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, -36),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).scaffoldBackgroundColor,
                                  width: 3.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _initials(_member!['name']?.toString()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _member!['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _member!['member_type']?.toString() ?? '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _member!['status'] == 'active'
                                        ? const Color(0x1910b981)
                                        : const Color(0x19ef4444),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (_member!['status']?.toString() ??
                                            'pending')
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: _member!['status'] == 'active'
                                          ? const Color(0xFF10b981)
                                          : const Color(0xFFef4444),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    final id = _member!['id'];
                                    final name = Uri.encodeComponent(
                                      _member!['name']?.toString() ?? '',
                                    );
                                    final company = Uri.encodeComponent(
                                      _member!['company']?.toString() ?? '',
                                    );
                                    final authService = AuthService();
                                    final isAdmin = authService.userRole == 'admin' ||
                                        authService.userRole == 'sub_admin' ||
                                        authService.userRole == 'super_admin';
                                    final prefix = isAdmin ? '/admin/messages' : '/messaging';
                                    context.go(
                                      '$prefix?id=$id&name=$name&company=$company',
                                    );
                                  },
                                  icon: const Icon(Icons.chat, size: 16),
                                  label: const Text('Start A Conversation'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 40),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                    Uri.parse('mailto:${_member!['email']}'),
                                  ),
                                  icon: const Icon(Icons.email, size: 16),
                                  label: const Text('Email'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                    Uri.parse('tel:${_member!['phone']}'),
                                  ),
                                  icon: const Icon(Icons.call, size: 16),
                                  label: const Text('Call'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Credentials card
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Text(
                          'Credentials',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...[
                        {
                          'icon': Icons.business,
                          'label': 'Agency / Company',
                          'value': _member!['company'],
                        },
                        {
                          'icon': Icons.badge,
                          'label': 'Membership ID',
                          'value':
                              _member!['membership_number'] ??
                              _member!['license_number'],
                        },
                        {
                          'icon': Icons.fingerprint,
                          'label': 'Agency Code',
                          'value': _member!['agency_code'],
                        },
                        {
                          'icon': Icons.location_on,
                          'label': 'Office Location',
                          'value': _member!['location'],
                        },
                        {
                          'icon': Icons.pin_drop,
                          'label': 'Digital Address (GPS)',
                          'value': _member!['digital_address'],
                        },
                        {
                          'icon': Icons.subtitles,
                          'label': 'Taxpayer TIN',
                          'value': _member!['tin'],
                        },
                        {
                          'icon': Icons.directions_boat,
                          'label': 'Port',
                          'value': _member!['port_of_operation'],
                        },
                      ]
                      .where(
                        (i) =>
                            i['value'] != null &&
                            i['value'].toString().trim().isNotEmpty,
                      )
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                        final item = entry.value;
                        final itemsList =
                            [
                                  {
                                    'icon': Icons.business,
                                    'label': 'Agency / Company',
                                    'value': _member!['company'],
                                  },
                                  {
                                    'icon': Icons.badge,
                                    'label': 'Membership ID',
                                    'value':
                                        _member!['membership_number'] ??
                                        _member!['license_number'],
                                  },
                                  {
                                    'icon': Icons.fingerprint,
                                    'label': 'Agency Code',
                                    'value': _member!['agency_code'],
                                  },
                                  {
                                    'icon': Icons.location_on,
                                    'label': 'Office Location',
                                    'value': _member!['location'],
                                  },
                                  {
                                    'icon': Icons.pin_drop,
                                    'label': 'Digital Address (GPS)',
                                    'value': _member!['digital_address'],
                                  },
                                  {
                                    'icon': Icons.subtitles,
                                    'label': 'Taxpayer TIN',
                                    'value': _member!['tin'],
                                  },
                                  {
                                    'icon': Icons.directions_boat,
                                    'label': 'Port',
                                    'value': _member!['port_of_operation'],
                                  },
                                ]
                                .where(
                                  (i) =>
                                      i['value'] != null &&
                                      i['value'].toString().trim().isNotEmpty,
                                )
                                .toList();
                        final isLast = entry.key == itemsList.length - 1;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: isLast
                                  ? BorderSide.none
                                  : const BorderSide(color: Color(0x19000000)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  item['icon'] as IconData,
                                  color: primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['label'].toString().toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    item['value'].toString(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
