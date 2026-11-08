import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../components/app_logo.dart';

class VerifyPaymentPage extends StatefulWidget {
  final String? paymentRef;
  final String? amount;

  const VerifyPaymentPage({
    super.key,
    this.paymentRef,
    this.amount,
  });

  @override
  State<VerifyPaymentPage> createState() => _VerifyPaymentPageState();
}

class _VerifyPaymentPageState extends State<VerifyPaymentPage> {
  bool _loading = true;
  Map<String, dynamic>? _payment;
  String? _error;

  static const Color _kBrown = Color(0xFF6B3E26);
  static const Color _kOrange = Color(0xFFFF5000);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String? _resolveRef() {
    if (widget.paymentRef != null && widget.paymentRef!.trim().isNotEmpty) {
      return widget.paymentRef!.trim();
    }
    // Check fragment query params in web
    final frag = Uri.tryParse(Uri.base.fragment);
    if (frag != null && frag.queryParameters['ref'] != null) {
      return frag.queryParameters['ref']!.trim();
    }
    return Uri.base.queryParameters['ref']?.trim();
  }

  String? _resolveAmount() {
    if (widget.amount != null && widget.amount!.trim().isNotEmpty) {
      return widget.amount!.trim();
    }
    final frag = Uri.tryParse(Uri.base.fragment);
    if (frag != null && frag.queryParameters['amount'] != null) {
      return frag.queryParameters['amount']!.trim();
    }
    return Uri.base.queryParameters['amount']?.trim();
  }

  Future<void> _fetch() async {
    final ref = _resolveRef();
    final amt = _resolveAmount();

    if (ref == null || ref.isEmpty) {
      setState(() {
        _error = 'No payment reference provided in QR code verification request.';
        _loading = false;
      });
      return;
    }

    try {
      var query = 'payments/public/verify-receipt?ref=${Uri.encodeComponent(ref)}';
      if (amt != null && amt.isNotEmpty) {
        query += '&amount=${Uri.encodeComponent(amt)}';
      }
      final res = await ApiService().getPublic(query);
      if (res is Map && res['verified'] == true) {
        setState(() => _payment = Map<String, dynamic>.from(res));
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : 'Payment receipt not recognized in CUBAG official treasury registry.';
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Unable to reach CUBAG Payment Verification Gateway. Please check internet connection.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatAmount(dynamic amt) {
    if (amt == null) return 'GH₵ 0.00';
    final n = double.tryParse(amt.toString()) ?? 0.0;
    return 'GH₵ ${NumberFormat('#,##0.00').format(n)}';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '—';
    final parsed = DateTime.tryParse(date.toString());
    if (parsed == null) return date.toString();
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF9F7),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 64, showShadow: false),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: _kOrange, strokeWidth: 3),
              const SizedBox(height: 16),
              Text(
                'VERIFYING TREASURY RECEIPT...',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: _kBrown,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Contacting CUBAG Live Clearance Ledger',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF8C7A70),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _payment == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF9F7),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1E8E0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 52, showShadow: false),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cancel_rounded,
                      color: Color(0xFFDC2626),
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Receipt Unverified',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E130D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? 'No payment record found with this reference token.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: const Color(0xFF786A61),
                      height: 1.5,
                    ),
                  ),
                  if (_resolveRef() != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F4F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Ref: ${_resolveRef()}',
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kBrown,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrown,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Return to CUBAG Portal',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
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
      );
    }

    final p = _payment!;
    final status = (p['status']?.toString().toLowerCase() ?? 'pending').trim();
    final bool isApproved = status == 'approved' || status == 'paid' || status == 'completed';
    final bool isRejected = status == 'rejected' || status == 'declined' || status == 'failed';

    final Color statusColor = isApproved
        ? const Color(0xFF16A34A)
        : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));
    final Color statusBg = isApproved
        ? const Color(0xFFF0FDF4)
        : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
    final String statusLabel = isApproved
        ? 'OFFICIAL PAYMENT CLEARED'
        : (isRejected ? 'PAYMENT DECLINED' : 'PAYMENT UNDER REVIEW');
    final IconData statusIcon = isApproved
        ? Icons.verified_rounded
        : (isRejected ? Icons.highlight_off_rounded : Icons.pending_rounded);

    final ref = p['payment_ref']?.toString() ?? '—';
    final desc = p['description']?.toString() ?? 'CUBAG Official Fee';
    final memberName = p['member_name']?.toString() ?? 'Registered Member';
    final company = p['member_company']?.toString() ?? '';
    final license = p['license_number'] ?? p['membership_number'] ?? '';
    final method = p['payment_method']?.toString() ?? 'MoMo / Bank Transfer';
    final dateStr = _formatDate(p['created_at']);
    final verifiedAt = _formatDate(p['verified_at'] ?? DateTime.now().toIso8601String());

    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 26, showShadow: false),
            const SizedBox(width: 10),
            Text(
              'CUBAG Official Clearance',
              style: GoogleFonts.inter(
                color: const Color(0xFF1E130D),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1E8E0), height: 1),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF1E8E0), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Status Banner ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusLabel,
                              style: GoogleFonts.inter(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isApproved
                                  ? 'Cleared by CUBAG Treasury Services'
                                  : (isRejected
                                      ? 'Secretariat flagged / rejected transaction'
                                      : 'Receipt queued for Secretariat reconciliation'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF6F625B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Amount Callout ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    children: [
                      Text(
                        'Total Amount Settled',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8C7A70),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatAmount(p['amount']),
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E130D),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF6F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE8DED6)),
                        ),
                        child: Text(
                          desc,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _kBrown,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: Color(0xFFF1E8E0)),

                // ── Receipt Line Details ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _receiptRow('Transaction Ref', ref, isMono: true, canCopy: true),
                      _receiptRow('Payment Date', dateStr),
                      _receiptRow('Member Name', memberName),
                      if (company.isNotEmpty) _receiptRow('Company / Agency', company),
                      if (license.toString().isNotEmpty) _receiptRow('License / Membership', license.toString()),
                      _receiptRow('Payment Channel', method.toUpperCase()),
                      _receiptRow('Clearance Verified', verifiedAt),
                    ],
                  ),
                ),

                // ── Official Authenticity Stamp ────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF8F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8DED6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        color: _kBrown,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AUTHENTICATED BY CUBAG TREASURY',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _kBrown,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Customs Brokers Association of Ghana • Verified against live treasury database',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: const Color(0xFF8C7A70),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Actions ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrown,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Open CUBAG Portal',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
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

  Widget _receiptRow(String label, String value, {bool isMono = false, bool canCopy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF8C7A70),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: isMono
                  ? GoogleFonts.sourceCodePro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E130D),
                    )
                  : GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E130D),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
