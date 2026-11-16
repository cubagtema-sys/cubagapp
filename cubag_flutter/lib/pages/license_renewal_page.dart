import 'package:flutter/material.dart';
import '../components/cubag_ui.dart';
import 'package:go_router/go_router.dart';
import '../components/app_layout.dart';
import '../components/app_logo.dart';
import '../components/in_app_document_viewer.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

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
      title: 'Licence & receipts',
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loading)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 3,
                              separatorBuilder: (ctx, i) => const SizedBox(height: 16),
                              itemBuilder: (ctx, i) => const ShimmerListTile(),
                            )
                          else if (_history.isEmpty)
                            _buildEmptyState(primary)
                          else ...[
                            // The current licence: the page's one bold surface.
                            _buildRecordCard(_history.first, primary, yr),
                            if (isLicenseBlocked)
                              _buildActiveLicenseBanner(expiryDate, renewalOpenDate),
                            const SizedBox(height: CubagSpace.xl),
                            _buildStatusTimeline(primary, user),
                            if (_history.length > 1) ...[
                              const SizedBox(height: CubagSpace.xxl),
                              Text('Earlier licences', style: CubagType.headline),
                              const SizedBox(height: CubagSpace.sm),
                              for (final rec in _history.skip(1))
                                _buildRecordCard(rec, primary, yr),
                            ],
                          ],

                          const SizedBox(height: CubagSpace.xxl),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/engagement'),
                              child: const Text('Need help? Contact support'),
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
    final isDuesSettled = user['dues_settled'] == true ||
        user['has_active_license'] == true ||
        user['package_fee_paid'] == true ||
        user['is_renewal_paid'] == true ||
        user['renewal_paid'] == true;
    final isActive = status == 'active' && isDuesSettled;
    final paid = isDuesSettled;
    final verify = !isDuesSettled
        ? _StepState.pending
        : status == 'suspended'
            ? _StepState.error
            : _StepState.done;
    final steps = [
      _TimelineStep('Application', 'Submitted & Vetted', _StepState.done),
      _TimelineStep('Payment', paid ? 'Paid' : 'Waiting for payment',
          paid ? _StepState.done : _StepState.active),
      _TimelineStep(
        'Verification',
        switch (verify) {
          _StepState.done => 'Approved',
          _StepState.error => 'Suspended',
          _ => 'Pending dues',
        },
        verify,
      ),
      _TimelineStep('Licence', isActive ? 'Issued' : 'Pending settlement',
          isActive ? _StepState.done : _StepState.pending),
    ];
    final (chipLabel, chipKind) = switch (status) {
      'active' when isDuesSettled => ('Active', StatusKind.good),
      'suspended' => ('Suspended', StatusKind.bad),
      _ => ('Pending Dues Settlement', StatusKind.pending),
    };

    return Container(
      padding: const EdgeInsets.all(CubagSpace.lg),
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text("Licence & Membership Status", style: CubagType.headline)),
              if (chipLabel != 'Pending Dues Settlement')
                StatusChip(chipLabel, kind: chipKind),
            ],
          ),
          const SizedBox(height: CubagSpace.lg),
          LayoutBuilder(
            builder: (context, c) {
              // Large text or a narrow phone: list the steps top to bottom
              // instead of cutting their names off.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (c.maxWidth / steps.length < 84 * scale) {
                return Column(
                  children: [for (var i = 0; i < steps.length; i++) _timelineRow(steps[i], i)],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Expanded(child: _timelineNode(steps[i], i, i == steps.length - 1)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(_TimelineStep step, int i) {
    final (bg, fg) = switch (step.state) {
      _StepState.done => (CubagColors.valid, Colors.white),
      _StepState.active => (CubagColors.action, Colors.white),
      _StepState.error => (CubagColors.lapsed, Colors.white),
      _StepState.pending => (CubagColors.sand, CubagColors.muted),
    };
    return Semantics(
      label: '${step.title}: ${step.subtitle}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: switch (step.state) {
                _StepState.done => Icon(Icons.check_rounded, size: 18, color: fg),
                _StepState.error => Icon(Icons.close_rounded, size: 18, color: fg),
                _ => Text('${i + 1}', style: CubagType.label.copyWith(color: fg)),
              },
            ),
            const SizedBox(width: CubagSpace.sm),
            Expanded(child: Text(step.title, style: CubagType.label)),
          ],
        ),
      ),
    );
  }

  Widget _timelineNode(_TimelineStep step, int i, bool last) {
    final (bg, fg) = switch (step.state) {
      _StepState.done => (CubagColors.valid, Colors.white),
      _StepState.active => (CubagColors.action, Colors.white),
      _StepState.error => (CubagColors.lapsed, Colors.white),
      _StepState.pending => (CubagColors.sand, CubagColors.muted),
    };
    return Semantics(
      label: step.title,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: i == 0
                    ? const SizedBox()
                    : Container(height: 2, color: step.state == _StepState.pending ? CubagColors.line : CubagColors.valid),
              ),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: switch (step.state) {
                  _StepState.done => Icon(Icons.check_rounded, size: 18, color: fg),
                  _StepState.error => Icon(Icons.close_rounded, size: 18, color: fg),
                  _ => Text('${i + 1}', style: CubagType.label.copyWith(color: fg)),
                },
              ),
              Expanded(
                child: last ? const SizedBox() : Container(height: 2, color: CubagColors.line),
              ),
            ],
          ),
          const SizedBox(height: CubagSpace.sm),
          Text(step.title, style: CubagType.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }


  Widget _buildActiveLicenseBanner(DateTime expiry, DateTime renewalOpens) {
    final renewalStr = '${renewalOpens.day} ${_monthName(renewalOpens.month)} ${renewalOpens.year}';
    return Padding(
      padding: const EdgeInsets.only(top: CubagSpace.md),
      child: Container(
        padding: const EdgeInsets.all(CubagSpace.md),
        decoration: BoxDecoration(
          color: CubagColors.validTint,
          borderRadius: BorderRadius.circular(CubagRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded, color: CubagColors.valid, size: 20),
            const SizedBox(width: CubagSpace.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Nothing to pay now. ', style: CubagType.label.copyWith(color: CubagColors.valid)),
                    TextSpan(text: 'Renewal opens on $renewalStr, 30 days before your licence expires.'),
                  ],
                ),
                style: CubagType.small.copyWith(color: CubagColors.inkSoft),
              ),
            ),
          ],
        ),
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
              : CubagColors.line,
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
              color: CubagColors.lapsed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: CubagColors.lapsed,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Records Restricted',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : CubagColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your official receipts and membership licenses will appear here once your annual dues are settled and approved by the secretariat.',
            textAlign: TextAlign.center,
            style: TextStyle(
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
                    'Submit Renewal Documents (Step 1)',
                    style: TextStyle(
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
                    style: TextStyle(
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
              : CubagColors.line,
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : CubagColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "You don't have any receipts or license history yet.",
            style: TextStyle(
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
                'Submit Documents (Step 1)',
                style: TextStyle(
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
    final isDuesSettled = rec['dues_settled'] == true ||
        _memberInfo?['dues_settled'] == true ||
        _memberInfo?['has_active_license'] == true ||
        _memberInfo?['package_fee_paid'] == true ||
        _memberInfo?['is_renewal_paid'] == true ||
        _memberInfo?['renewal_paid'] == true;
    final approved = (rec['approved'] == true) && isDuesSettled;
    final suspended = rec['status'] == 'suspended';
    final (statusLabel, statusFg, statusBg) = approved
        ? ('Active', CubagColors.valid, CubagColors.validTint)
        : suspended
            ? ('Suspended', CubagColors.lapsed, CubagColors.lapsedTint)
            : ('Pending Dues Settlement', CubagColors.due, CubagColors.dueTint);
    final rawLicenceNo = rec['license_number']?.toString();
    final licenceNo = isDuesSettled ? rawLicenceNo : 'PENDING DUES SETTLEMENT';
    final expiry = DateTime.tryParse((_memberInfo?['license_expiry_date'] ?? '').toString());
    final expiryStr = expiry == null ? null : '${expiry.day} ${_monthName(expiry.month)} ${expiry.year}';

    Widget field(String label, String value, {bool figure = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: CubagType.caption.copyWith(color: CubagColors.onCocoaMuted)),
            const SizedBox(height: 2),
            Text(
              value,
              style: (figure ? CubagType.figure : CubagType.bodyStrong).copyWith(color: CubagColors.onCocoa),
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(CubagSpace.xl),
            decoration: BoxDecoration(
              color: CubagColors.cocoa,
              borderRadius: BorderRadius.circular(CubagRadius.hero),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CUBAG membership licence',
                        style: CubagType.caption.copyWith(color: CubagColors.onCocoaMuted, letterSpacing: 0.3),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(statusLabel, style: CubagType.caption.copyWith(color: statusFg, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: CubagSpace.md),
                Text(
                  rec['company']?.toString() ?? _memberInfo?['name']?.toString() ?? 'Member',
                  style: CubagType.title.copyWith(color: CubagColors.onCocoa),
                ),
                const SizedBox(height: CubagSpace.lg),
                Wrap(
                  spacing: CubagSpace.xxl,
                  runSpacing: CubagSpace.md,
                  children: [
                    field('Licence number', licenceNo ?? (approved ? 'Issued' : 'Not issued yet'), figure: true),
                    if (expiryStr != null && approved) field('Valid until', expiryStr, figure: true),
                    if (rec['port_of_operation'] != null) field('District', rec['port_of_operation'].toString()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CubagSpace.sm),
          if (approved)
            Builder(builder: (context) {
              final view = FilledButton.icon(
                    onPressed: () => _showCertificate(rec, yr),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('View licence'),
                  );
              final cert = OutlinedButton.icon(
                    onPressed: () {
                      final memberId = _memberInfo?['id'];
                      if (memberId == null) return;
                      String base = ApiService.baseUrl;
                      if (base.endsWith('/')) {
                        base = base.substring(0, base.length - 1);
                      }
                      final ts = DateTime.now().millisecondsSinceEpoch;
                      final url = '$base/members/$memberId/certificate-pdf?t=$ts';
                      InAppDocumentViewer.show(
                        context,
                        url: url,
                        title: 'Certificate of membership',
                        subtitle: 'Annual licence certificate',
                      );
                    },
                    icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                    label: const Text('Certificate'),
                  );
              // Older members often use large text: stack the buttons rather than squeeze them.
              final stacked = MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) < 360;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [view, const SizedBox(height: CubagSpace.xs), cert],
                );
              }
              return Row(
                children: [
                  Expanded(child: view),
                  const SizedBox(width: CubagSpace.sm),
                  Expanded(child: cert),
                ],
              );
            })
          else if (!suspended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: CubagColors.actionTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CubagColors.lineStrong),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: CubagColors.action),
                  const SizedBox(width: CubagSpace.sm),
                  Expanded(
                    child: Text(
                      'Annual dues settlement is required to activate and issue your licence certificate.',
                      style: CubagType.small.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: CubagSpace.xs),
                  TextButton(
                    onPressed: () => context.go('/payments?fee=Annual%20Dues'),
                    child: const Text('Pay Dues'),
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
                style: TextStyle(fontFamily: 'Source Serif Display', 
                  fontSize: 28,
                  color: const Color(0xFF1e3a8a),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(width: 100, height: 1, color: Colors.black87),
              const SizedBox(height: 6),
              Text(
                role,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
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
                    'Official',
                    style: TextStyle(fontFamily: 'Source Serif Display', 
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Seal',
                    style: TextStyle(fontFamily: 'Source Serif Display', 
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
              color: CubagColors.sand, // Off-white paper color
              border: Border.all(
                color: CubagColors.action,
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
                                    style: TextStyle(fontFamily: 'Source Serif Display', 
                                      fontWeight: FontWeight.w900,
                                      fontSize: isMobile ? 28 : 42,
                                      color: AppColors.accentOrangeText,
                                      letterSpacing: isMobile ? 2 : 4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Customs brokers association of ghana',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isMobile ? 8 : 10,
                                      color: CubagColors.muted,
                                      letterSpacing: isMobile ? 1.0 : 1.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
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
                          'Certificate of licensure',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Source Serif Display', 
                            fontSize: isMobile ? 16 : 22,
                            fontWeight: FontWeight.bold,
                            color: CubagColors.ink,
                            letterSpacing: isMobile ? 1 : 2,
                          ),
                        ),
                        SizedBox(height: isMobile ? 20 : 32),
                        Text(
                          'This is to officially certify that',
                          style: TextStyle(fontFamily: 'Source Serif Display', 
                            fontSize: isMobile ? 14 : 16,
                            fontStyle: FontStyle.italic,
                            color: CubagColors.inkSoft,
                          ),
                        ),
                        SizedBox(height: isMobile ? 10 : 16),
                        Text(
                          user['company']?.toString() ??
                              rec['company']?.toString() ??
                              'Company Name',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: isMobile ? 18 : 24,
                            color: const Color(0xFF281710),
                          ),
                        ),
                        SizedBox(height: isMobile ? 6 : 8),
                        Text(
                          'represented by ${user['name']?.toString() ?? rec['name']?.toString() ?? 'Member Name'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Source Serif Display', 
                            color: CubagColors.muted,
                            fontStyle: FontStyle.italic,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                        SizedBox(height: isMobile ? 16 : 24),
                        Text(
                          'is a registered and active ${user['member_type']?.toString() ?? rec['member_type']?.toString() ?? 'Member'} of CUBAG',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Source Serif Display', 
                            fontSize: isMobile ? 14 : 16,
                            color: CubagColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Authorized Port of Operation: ${user['port_of_operation']?.toString() ?? rec['port_of_operation']?.toString() ?? 'All Ports'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Source Serif Display', 
                            fontSize: isMobile ? 12 : 14,
                            color: CubagColors.inkSoft,
                          ),
                        ),
                        SizedBox(height: isMobile ? 24 : 32),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 16 : 24,
                            vertical: isMobile ? 8 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: CubagColors.sand,
                            border: Border.all(color: CubagColors.line),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Licence number:',
                                    style: TextStyle(
                                      fontSize: isMobile ? 9 : 10,
                                      color: CubagColors.muted,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Valid Until:',
                                    style: TextStyle(
                                      fontSize: isMobile ? 9 : 10,
                                      color: CubagColors.muted,
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
                                    style: TextStyle(
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: CubagColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '31 Dec $yr',
                                    style: TextStyle(
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: CubagColors.ink,
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
