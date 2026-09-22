import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';

class MemberDetailPage extends StatefulWidget {
  final String? memberId;
  const MemberDetailPage({super.key, this.memberId});
  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  bool _loading = true;
  bool _actionLoading = false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authService = AuthService();
    final isAdmin = authService.userRole == 'admin' ||
        authService.userRole == 'sub_admin' ||
        authService.userRole == 'super_admin';
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
            _buildPaymentsSection(context, primary, isDark, isAdmin),
          ],
        ],
      ),
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  Future<void> _confirmPayment(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Confirm Payment'),
          ],
        ),
        content: const Text(
          'Are you sure you want to verify this bank deposit receipt? This will mark the payment as PAID and update the member\'s status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify & Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      final res = await ApiService().post('/payments/admin/mark-paid/$id');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment verified and confirmed successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        ApiService.deleteCacheKeysMatching('members/${widget.memberId}');
        await _fetch();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message']?.toString() ?? 'Failed to confirm payment.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error('member_detail_confirm_payment', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error approving payment. Please check network connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _showReceiptDialog(
    String receiptUrl,
    String memberName,
    double amount,
    String date, {
    dynamic txId,
    bool isPending = false,
  }) {
    final fullUrl = _resolveUrl(receiptUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0F0A);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5000).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                color: Color(0xFFFF5000),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bank Deposit Receipt Slip',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  Text(
                    '$memberName · GH₵ ${amount.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'Open in new tab',
              onPressed: () => launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                child: CorsImageWidget(
                  url: fullUrl,
                  fit: BoxFit.contain,
                  placeholder: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF5000)),
                  ),
                  errorWidget: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'Unable to load receipt slip image.',
                          style: GoogleFonts.inter(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (isPending && txId != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmPayment(txId);
              },
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Verify & Mark Paid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsSection(BuildContext context, Color primary, bool isDark, bool isAdmin) {
    final payments = ApiService.ensureList(_member!['payments']);
    if (payments.isEmpty && !isAdmin) {
      return const SizedBox.shrink();
    }

    final cardBg = Theme.of(context).cardColor;
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank Deposit Receipts & Payments',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Attached wire slips and transaction records tied to this profile',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (payments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${payments.length} Records',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (payments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No bank deposit receipts or payments on file yet.',
                      style: GoogleFonts.inter(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final p = payments[index] as Map<String, dynamic>;
                final rawReceipt = p['receipt_url']?.toString() ?? '';
                final hasReceipt = rawReceipt.trim().isNotEmpty;
                final receiptUrl = hasReceipt ? _resolveUrl(rawReceipt) : '';
                final amount = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
                final desc = p['description']?.toString() ?? 'Payment';
                final status = p['status']?.toString().toLowerCase() ?? 'pending';
                final isPaid = status == 'paid' || status == 'success' || status == 'completed';
                final isPending = status == 'pending' || status == 'submitted' || status == 'processing';
                final pRef = p['payment_ref']?.toString() ?? p['ref_code']?.toString() ?? 'N/A';
                final bankName = p['bank_name']?.toString() ?? (p['payment_method'] == 'bank' ? 'Bank Deposit' : 'MoMo');
                final dateStr = p['date']?.toString() ?? p['created_at']?.toString() ?? '';
                final pId = p['id'] ?? p['tx_id'];

                final statusColor = isPaid
                    ? const Color(0xFF10B981)
                    : isPending
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFEF4444);

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      if (hasReceipt)
                        GestureDetector(
                          onTap: () => _showReceiptDialog(
                            receiptUrl,
                            _member!['name']?.toString() ?? 'Member',
                            amount,
                            dateStr,
                            txId: pId,
                            isPending: isPending,
                          ),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                              color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CorsImageWidget(
                                  url: receiptUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                                ),
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: Icon(Icons.zoom_in, color: Colors.white, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            p['payment_method'] == 'bank'
                                ? Icons.account_balance_rounded
                                : Icons.phone_android_rounded,
                            color: primary,
                            size: 24,
                          ),
                        ),
                      const SizedBox(width: 14),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    desc,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  'GH₵ ${amount.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    color: isPaid ? const Color(0xFF10B981) : primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$bankName · Ref: $pRef',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (p['notes'] != null && p['notes'].toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Note: ${p['notes']}',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            ],

                            // Admin action buttons if pending
                            if (isAdmin && isPending && pId != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _actionLoading ? null : () => _confirmPayment(pId),
                                    icon: const Icon(Icons.check_circle_rounded, size: 14),
                                    label: const Text('Verify & Confirm'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      textStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (hasReceipt)
                                    OutlinedButton.icon(
                                      onPressed: () => _showReceiptDialog(
                                        receiptUrl,
                                        _member!['name']?.toString() ?? 'Member',
                                        amount,
                                        dateStr,
                                        txId: pId,
                                        isPending: isPending,
                                      ),
                                      icon: const Icon(Icons.visibility_rounded, size: 14),
                                      label: const Text('View Slip'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        textStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                            ] else if (hasReceipt) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _showReceiptDialog(
                                  receiptUrl,
                                  _member!['name']?.toString() ?? 'Member',
                                  amount,
                                  dateStr,
                                  txId: pId,
                                  isPending: isPending,
                                ),
                                child: Text(
                                  'View Attached Deposit Slip →',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
