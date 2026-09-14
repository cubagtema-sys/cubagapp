import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart'; // F-39 fix
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/app_logo.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

class LicenseRenewalPage extends StatefulWidget {
  const LicenseRenewalPage({super.key});
  @override
  State<LicenseRenewalPage> createState() => _LicenseRenewalPageState();
}

class _LicenseRenewalPageState extends State<LicenseRenewalPage> {
  bool _loading = true;
  List<dynamic> _history = [];
  Map<String, dynamic>? _memberInfo;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!_loading) setState(() => _loading = true);
    await ApiService().fetchDataWithCache('/members/license-history', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null && data is Map) {
        setState(() {
          _loading = false;
          _history = data['history'] ?? [];
          _memberInfo = data['member'] as Map<String, dynamic>?;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final user = _memberInfo ?? {};
    final isActive = user['status'] == 'active';
    final yr = DateTime.now().year;

    // ── Active License Guard ──────────────────────────────────────────────────
    // Determine if the license is active and not yet in the 30-day renewal window
    DateTime? expiryDate;
    final expiryRaw = user['license_expiry_date'];
    if (expiryRaw != null) {
      try {
        expiryDate = DateTime.tryParse(expiryRaw.toString());
      } catch (e, st) {
        AppLogger.error('license_renewal_page', e, st);
      }
    }
    final today = DateTime.now();
    final renewalOpenDate = expiryDate?.subtract(const Duration(days: 30));
    // Block payment if: active + has expiry + today is before the 30-day window
    final isLicenseBlocked =
        isActive &&
        expiryDate != null &&
        renewalOpenDate != null &&
        today.isBefore(renewalOpenDate);

    return AppLayout(
      title: 'License & Receipts',
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 24.0,
                ),
                child: !isActive && !_loading && _history.isEmpty
                    ? _buildLockedView(primary)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Active License Banner ──
                          if (isLicenseBlocked && !_loading)
                            _buildActiveLicenseBanner(
                              expiryDate,
                              renewalOpenDate,
                            ),

                          // ── Status Timeline ──
                          if (!_loading && _history.isNotEmpty) ...[
                            _buildStatusTimeline(primary, user),
                            const SizedBox(height: 32),
                          ],

                          if (_loading)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 3,
                              separatorBuilder: (ctx, i) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (ctx, i) => const ShimmerListTile(),
                            )
                          else if (_history.isEmpty)
                            _buildEmptyState(primary)
                          else ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4.0,
                                bottom: 16.0,
                              ),
                              child: Text(
                                'Membership History',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF1A0F0A),
                                ),
                              ),
                            ),
                            ..._history
                                .asMap()
                                .map(
                                  (i, rec) => MapEntry(
                                    i,
                                    _buildRecordCard(rec, primary, yr),
                                  ),
                                )
                                .values,
                          ],

                          const SizedBox(height: 32),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/engagement'),
                              child: Text(
                                'Need help? Contact Support',
                                style: GoogleFonts.inter(
                                  color: primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
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

  // ── License Status Timeline ──
  Widget _buildStatusTimeline(Color primary, Map<String, dynamic> user) {
    final status = user['status']?.toString() ?? 'pending';
    final steps = [
      _TimelineStep('Application', 'Submitted', _StepState.done),
      _TimelineStep(
        'Payment',
        'Dues Received',
        status == 'pending' ? _StepState.active : _StepState.done,
      ),
      _TimelineStep(
        'Verification',
        'Under Review',
        status == 'pending'
            ? _StepState.pending
            : status == 'suspended'
            ? _StepState.error
            : _StepState.done,
      ),
      _TimelineStep(
        'License',
        'Issued',
        status == 'active' ? _StepState.done : _StepState.pending,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark
              ? [const Color(0xFF1A0F0A), const Color(0xFF1A0F0A)]
              : [primary, primary.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF4D2D20)
              : Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.timeline_rounded,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? primary
                      : Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Renewal Progress',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Track your membership renewal status',
                      style: GoogleFonts.inter(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF9ca3af)
                            : Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: status == 'active'
                      ? const Color(0xFF10b981).withValues(alpha: 0.2)
                      : status == 'suspended'
                      ? const Color(0xFFef4444).withValues(alpha: 0.2)
                      : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: status == 'active'
                        ? const Color(0xFF10b981).withValues(alpha: 0.4)
                        : status == 'suspended'
                        ? const Color(0xFFef4444).withValues(alpha: 0.4)
                        : Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: status == 'active'
                        ? const Color(0xFF10b981)
                        : status == 'suspended'
                        ? const Color(0xFFef4444)
                        : Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Timeline row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (i) {
              final step = steps[i];
              final isLast = i == steps.length - 1;
              final Color nodeColor = _stepColor(step.state, primary);

              return Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: nodeColor,
                              shape: BoxShape.circle,
                              border: step.state == _StepState.active
                                  ? Border.all(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? primary
                                          : Colors.white,
                                      width: 2,
                                    )
                                  : null,
                              boxShadow: step.state == _StepState.active
                                  ? [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              step.state == _StepState.done
                                  ? Icons.check_rounded
                                  : step.state == _StepState.error
                                  ? Icons.close_rounded
                                  : step.state == _StepState.active
                                  ? Icons.autorenew_rounded
                                  : Icons.circle_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step.title,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.subtitle,
                            style: GoogleFonts.inter(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF9ca3af)
                                  : Colors.white.withValues(alpha: 0.65),
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 24,
                        height: 2.5,
                        margin: const EdgeInsets.only(bottom: 40),
                        decoration: BoxDecoration(
                          color: step.state == _StepState.done
                              ? const Color(0xFF10b981)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Color _stepColor(_StepState state, Color primary) {
    switch (state) {
      case _StepState.done:
        return const Color(0xFF10b981);
      case _StepState.active:
        return primary;
      case _StepState.error:
        return const Color(0xFFef4444);
      case _StepState.pending:
        return Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF4D2D20)
            : Colors.white.withValues(alpha: 0.25);
    }
  }

  Widget _buildActiveLicenseBanner(DateTime expiry, DateTime renewalOpens) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expiryStr =
        '${_monthName(expiry.month)} ${expiry.day}, ${expiry.year}';
    final renewalStr =
        '${_monthName(renewalOpens.month)} ${renewalOpens.day}, ${renewalOpens.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10b981).withAlpha(isDark ? 25 : 18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10b981).withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10b981).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Color(0xFF10b981),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'License Active — No Payment Required',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: const Color(0xFF10b981),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your license is valid until $expiryStr. '
                  'To prevent duplicate payments, renewal will open on $renewalStr (30 days before expiry).',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.55,
                    color: isDark
                        ? const Color(0xFFa7f3d0)
                        : const Color(0xFF065f46),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  Widget _buildLockedView(Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF4D2D20)
              : const Color(0xFFE8DED6),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFef4444).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFFef4444),
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Records Restricted',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF1A0F0A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your official receipts and membership licenses will appear here once your annual dues are settled and approved by the secretariat.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFF6b6375),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.go('/compliance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Make Payment',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go('/dashboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    minimumSize: const Size(0, 52),
                    side: BorderSide(color: primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Dashboard',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF4D2D20)
              : const Color(0xFFE8DED6),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 36,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Records Found',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF1A0F0A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "You don't have any receipts or license history yet.",
            style: GoogleFonts.inter(
              color: const Color(0xFF6b6375),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            height: 48,
            child: ElevatedButton(
              onPressed: () => context.go('/compliance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Make Payment',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> rec, Color primary, int yr) {
    final approved = rec['approved'] == true;
    final suspended = rec['status'] == 'suspended';
    final statusColor = approved
        ? const Color(0xFF10b981)
        : suspended
        ? const Color(0xFFef4444)
        : const Color(0xFFf59e0b);
    final statusLabel = approved
        ? 'Active'
        : suspended
        ? 'Suspended'
        : 'In Approval';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF4D2D20)
              : const Color(0xFFE8DED6),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.card_membership_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Membership License',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A0F0A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...([
            {
              'icon': Icons.verified_user_outlined,
              'label': 'License Number',
              'val':
                  rec['license_number'] ??
                  (approved ? 'Active Standing' : 'Pending Approval'),
            },
            {
              'icon': Icons.business_outlined,
              'label': 'Organization',
              'val': rec['company'],
            },
            {
              'icon': Icons.location_on_outlined,
              'label': 'Port of Operation',
              'val': rec['port_of_operation'],
            },
          ].where((r) => r['val'] != null)).map(
            (r) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A0F0A)
                    : Colors.grey.shade50,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      r['icon'] as IconData,
                      color: primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['label'].toString().toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF6b6375),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r['val'].toString(),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).brightness == Brightness.dark
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
          ),
          const SizedBox(height: 12),
          if (approved)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCertificate(rec, yr),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: Text(
                      'View License',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      minimumSize: const Size(0, 52),
                      side: BorderSide(color: primary, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final memberId = _memberInfo?['id'];
                      if (memberId == null) return;

                      String base = ApiService.baseUrl;
                      if (base.endsWith('/')) {
                        base = base.substring(0, base.length - 1);
                      }

                      final ts = DateTime.now().millisecondsSinceEpoch;
                      final url = Uri.parse(
                        '$base/members/$memberId/certificate-pdf?t=$ts',
                      );

                      try {
                        await launchUrl(url);
                      } catch (e) {
                        final fallback = Uri.parse(
                          '$base/members/$memberId/certificate-pdf?t=$ts',
                        );
                        await launchUrl(fallback);
                      }
                    },
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Download PDF',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFf59e0b).withValues(alpha: 0.1),
                border: Border.all(
                  color: const Color(0xFFf59e0b).withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.hourglass_empty_rounded,
                    color: Color(0xFFf59e0b),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Awaiting admin approval...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFf59e0b),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showCertificate(Map<String, dynamic> rec, int yr) {
    final user = _memberInfo ?? {};
    final licenseNum =
        user['license_number']?.toString() ??
        user['licenseNumber']?.toString() ??
        rec['license_number']?.toString() ??
        'PENDING';

    showDialog(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final isMobile = screenWidth < 500;
        final borderWidth = isMobile ? 6.0 : 12.0;
        final marginVal = isMobile ? 4.0 : 8.0;
        final paddingVal = isMobile ? 16.0 : 32.0;
        final innerBorderWidth = isMobile ? 1.5 : 3.0;

        Widget buildSignatureColumn(String name, String role) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: GoogleFonts.dancingScript(
                  fontSize: 28,
                  color: const Color(0xFF1e3a8a),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(width: 100, height: 1, color: Colors.black87),
              const SizedBox(height: 6),
              Text(
                role,
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          );
        }

        Widget buildOfficialSeal() {
          return Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.brightness_7,
                size: 80,
                color: Color(0xFFd4af37),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'OFFICIAL',
                    style: GoogleFonts.cinzel(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'SEAL',
                    style: GoogleFonts.cinzel(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8.0 : 16.0,
            vertical: isMobile ? 12.0 : 24.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 800),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4F0), // Off-white paper color
              border: Border.all(
                color: const Color(0xFFFF5000),
                width: borderWidth,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Container(
              margin: EdgeInsets.all(marginVal),
              padding: EdgeInsets.all(paddingVal),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFd4af37),
                  width: innerBorderWidth,
                ), // Inner gold border
              ),
              child: Stack(
                children: [
                  // Watermark
                  Positioned.fill(
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.5,
                        child: Text(
                          'CUBAG',
                          style: TextStyle(
                            fontSize: isMobile ? 60 : 120,
                            fontWeight: FontWeight.w900,
                            color: const Color(
                              0xFFFF5000,
                            ).withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Content
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: isMobile ? 24 : 40,
                            ), // Spacer to balance close button
                            Expanded(
                              child: Column(
                                children: [
                                  // Logo image - use cached AppLogo component
                                  AppLogo(
                                    size: isMobile ? 44 : 60,
                                    borderRadius: 8,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'CUBAG',
                                    style: GoogleFonts.cinzel(
                                      fontWeight: FontWeight.w900,
                                      fontSize: isMobile ? 28 : 42,
                                      color: const Color(0xFFFF5000),
                                      letterSpacing: isMobile ? 2 : 4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'CUSTOMS BROKERS ASSOCIATION OF GHANA',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.montserrat(
                                      fontSize: isMobile ? 8 : 10,
                                      color: const Color(0xFF64748b),
                                      letterSpacing: isMobile ? 1.0 : 1.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.grey,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        SizedBox(height: isMobile ? 24 : 40),
                        Text(
                          'CERTIFICATE OF LICENSURE',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cinzel(
                            fontSize: isMobile ? 16 : 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A0F0A),
                            letterSpacing: isMobile ? 1 : 2,
                          ),
                        ),
                        SizedBox(height: isMobile ? 20 : 32),
                        Text(
                          'This is to officially certify that',
                          style: GoogleFonts.lora(
                            fontSize: isMobile ? 14 : 16,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        SizedBox(height: isMobile ? 10 : 16),
                        Text(
                          user['company']?.toString() ??
                              rec['company']?.toString() ??
                              'Company Name',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w900,
                            fontSize: isMobile ? 18 : 24,
                            color: const Color(0xFF281710),
                          ),
                        ),
                        SizedBox(height: isMobile ? 6 : 8),
                        Text(
                          'represented by ${user['name']?.toString() ?? rec['name']?.toString() ?? 'Member Name'}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lora(
                            color: const Color(0xFF64748b),
                            fontStyle: FontStyle.italic,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                        SizedBox(height: isMobile ? 16 : 24),
                        Text(
                          'is a registered and active ${user['member_type']?.toString() ?? rec['member_type']?.toString() ?? 'Member'} of CUBAG',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lora(
                            fontSize: isMobile ? 14 : 16,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Authorized Port of Operation: ${user['port_of_operation']?.toString() ?? rec['port_of_operation']?.toString() ?? 'All Ports'}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lora(
                            fontSize: isMobile ? 12 : 14,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        SizedBox(height: isMobile ? 24 : 32),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 16 : 24,
                            vertical: isMobile ? 8 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFf8fafc),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'License Number:',
                                    style: GoogleFonts.montserrat(
                                      fontSize: isMobile ? 9 : 10,
                                      color: const Color(0xFF64748b),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Valid Until:',
                                    style: GoogleFonts.montserrat(
                                      fontSize: isMobile ? 9 : 10,
                                      color: const Color(0xFF64748b),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(width: isMobile ? 8 : 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    licenseNum,
                                    style: GoogleFonts.montserrat(
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1A0F0A),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '31 Dec $yr',
                                    style: GoogleFonts.montserrat(
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1A0F0A),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isMobile ? 32 : 48),
                        // Signatures and Seal
                        isMobile
                            ? Column(
                                children: [
                                  buildSignatureColumn(
                                    'Alhaji A. R. Busia',
                                    'President',
                                  ),
                                  const SizedBox(height: 24),
                                  buildOfficialSeal(),
                                  const SizedBox(height: 24),
                                  buildSignatureColumn(
                                    'Kwame E. Mensah',
                                    'Secretary General',
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  buildSignatureColumn(
                                    'Alhaji A. R. Busia',
                                    'President',
                                  ),
                                  buildOfficialSeal(),
                                  buildSignatureColumn(
                                    'Kwame E. Mensah',
                                    'Secretary General',
                                  ),
                                ],
                              ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _StepState { done, active, error, pending }

class _TimelineStep {
  final String title;
  final String subtitle;
  final _StepState state;
  const _TimelineStep(this.title, this.subtitle, this.state);
}
