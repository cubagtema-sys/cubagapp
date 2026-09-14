import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/trend_line.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
part 'profile/profile_widgets.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kRed = Color(0xFFef4444);
const _kPurple = Color(0xFF8b5cf6);
const _kBlue = Color(0xFF3b82f6);
const _kAmber = Color(0xFFf59e0b);
const _kIndigo = Color(0xFF6366f1);

class StandingTier {
  final String label;
  final Color color;
  final IconData icon;
  final String badgeText;

  StandingTier({
    required this.label,
    required this.color,
    required this.icon,
    required this.badgeText,
  });

  static StandingTier getFromStars(double stars) {
    if (stars >= 4.5) {
      return StandingTier(
        label: 'Elite Standing',
        color: const Color(0xFFD4AF37), // Classic Gold
        icon: Icons.workspace_premium_rounded,
        badgeText: 'ELITE MEMBER',
      );
    } else if (stars >= 3.5) {
      return StandingTier(
        label: 'Good Standing',
        color: const Color(0xFF10B981), // Emerald Green
        icon: Icons.verified_user_rounded,
        badgeText: 'ACTIVE MEMBER',
      );
    } else if (stars >= 2.0) {
      return StandingTier(
        label: 'Warning / Probationary',
        color: const Color(0xFFF59E0B), // Amber
        icon: Icons.warning_amber_rounded,
        badgeText: 'PROBATIONARY',
      );
    } else {
      return StandingTier(
        label: 'Suspended / Delinquent',
        color: const Color(0xFFEF4444), // Red
        icon: Icons.block_rounded,
        badgeText: 'SUSPENDED',
      );
    }
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic> _user = {};
  bool _isLoading = true;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _fetchUser();
    SocketService().on('member_updated', _onLiveUpdate);
    SocketService().on('member_approved', _onLiveUpdate);
    SocketService().on('payment_approved', _onLiveUpdate);
    SocketService().on('fees_updated', _onLiveUpdate);
  }

  void _onLiveUpdate(dynamic _) {
    if (mounted) {
      ApiService.deleteCacheKeysMatching('auth/me');
      _fetchUser();
    }
  }

  @override
  void dispose() {
    SocketService().off('member_updated', _onLiveUpdate);
    SocketService().off('member_approved', _onLiveUpdate);
    SocketService().off('payment_approved', _onLiveUpdate);
    SocketService().off('fees_updated', _onLiveUpdate);
    super.dispose();
  }

  Future<void> _fetchUser() async {
    if (_user.isEmpty) setState(() => _isLoading = true);
    await ApiService().fetchDataWithCache('/auth/me', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null && data is Map) {
        setState(() {
          _user = Map<String, dynamic>.from(data);
          _isLoading = false;
        });
      }
    });
    if (mounted && _isLoading) setState(() => _isLoading = false);
  }

  Future<void> _uploadAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null && file.path == null) return;

    final String? previousPhoto = _user['profile_photo']?.toString();
    setState(() => _uploadingPhoto = true);

    try {
      final api = ApiService();
      late MultipartFile mpFile;
      if (file.bytes != null) {
        mpFile = MultipartFile.fromBytes(file.bytes!, filename: file.name);
      } else if (file.path != null && file.path!.isNotEmpty) {
        mpFile = await MultipartFile.fromFile(file.path!, filename: file.name);
      } else {
        final bytes = await file.xFile.readAsBytes();
        mpFile = MultipartFile.fromBytes(bytes, filename: file.name);
      }

      final formData = FormData.fromMap({'photo': mpFile});
      final res = await api.upload('/auth/upload-photo', formData);

      if (res.statusCode == 200 && res.data['photo_url'] != null) {
        final photoUrl = res.data['photo_url'].toString();
        setState(() {
          _user = {..._user, 'profile_photo': photoUrl};
        });
        if (mounted) {
          await Provider.of<AuthService>(
            context,
            listen: false,
          ).updatePhoto(photoUrl);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile photo updated successfully', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              backgroundColor: _kGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        final msg = res.data['message']?.toString() ?? 'Upload failed';
        setState(() => _user = {..._user, 'profile_photo': previousPhoto});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _user = {..._user, 'profile_photo': previousPhoto});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _openDigitalIdDialog(StandingTier tier, String? expiry, int? daysLeft, bool isGoodStanding, bool isPackagePending) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _buildDigitalIdCard(ctx, tier, expiry, daysLeft, isGoodStanding, isPackagePending),
      ),
    );
  }

  String get _initials {
    final name = _user['name']?.toString().trim() ?? '';
    if (name.isEmpty) return '??';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '??';
    final initials = parts.map((n) => n[0]).join('').toUpperCase();
    return initials.length > 2 ? initials.substring(0, 2) : initials;
  }

  String get _membershipId {
    final isPkgPaid = _user['package_fee_paid'] == true;
    if (!isPkgPaid) return 'PENDING SETTLEMENT';
    final memNo = _user['membership_number']?.toString().trim() ?? '';
    if (memNo.isNotEmpty && memNo != 'null' && memNo != 'None' && !memNo.toLowerCase().contains('pending')) return memNo;
    final lic = _user['license_number']?.toString().trim() ?? '';
    if (lic.isNotEmpty && lic != 'null' && lic != 'None' && !lic.toLowerCase().contains('pending')) return lic;
    final id = _user['id']?.toString() ?? '1';
    return 'CUBAG-${id.padLeft(4, '0')}';
  }

  String _formatPortAbbreviation(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty || s == 'NULL' || s == 'NONE') return 'KIA';
    if (s.contains('KOTOKA') || s.contains('AIRPORT') || s.contains('ACCRA') || s == 'AIA' || s == 'KIA') return 'KIA';
    if (s.contains('TEMA')) return 'TEMA';
    if (s.contains('TAKORADI') || s == 'TKD' || s.contains('SEKONDI')) return 'TKD';
    if (s.contains('AFLAO')) return 'AFLAO';
    if (s.contains('ELUBO')) return 'ELUBO';
    if (s.contains('PAGA')) return 'PAGA';
    if (s.contains('SUNYANI')) return 'SUN';
    if (s.contains('KUMASI')) return 'KMS';
    final cleaned = s.replaceAll('PORT', '').replaceAll('BORDER', '').replaceAll('CHAPTER', '').trim();
    if (cleaned.length > 5) return cleaned.substring(0, 4);
    return cleaned.isNotEmpty ? cleaned : 'KIA';
  }

  String _formatDate(String? str) {
    if (str == null) return '—';
    final d = DateTime.tryParse(str);
    if (d == null) return '—';
    return '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final border = isDark ? const Color(0xFF281710) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    if (_isLoading) {
      return AppLayout(
        title: 'My Profile',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _kOrange),
              const SizedBox(height: 16),
              Text('Loading profile details...', style: GoogleFonts.outfit(color: textMuted)),
            ],
          ),
        ),
      );
    }

    final rawExpiry = _user['license_expiry_date']?.toString() ?? _user['licenseExpiryDate']?.toString();
    final expiry = (rawExpiry == null || rawExpiry == 'None' || rawExpiry == 'null' || rawExpiry.isEmpty) ? null : rawExpiry;
    final daysLeft = expiry != null ? DateTime.tryParse(expiry)?.difference(DateTime.now()).inDays : null;
    final statusStr = (_user['status']?.toString() ?? 'active').trim().toLowerCase();
    final isExpired = daysLeft != null && daysLeft < 0;
    final isApprovedOrActive = statusStr == 'active' || statusStr == 'approved';
    final bool isPkgPaid = _user['package_fee_paid'] == true;
    final bool isPackagePending = !isPkgPaid &&
        (_user['role'] != 'admin' && _user['role'] != 'sub_admin');
    final bool isGoodStanding = isPkgPaid &&
        (_user['is_good_standing'] == true || _user['good_standing'] == true || isApprovedOrActive);

    final complianceScore = int.tryParse(_user['compliance_score']?.toString() ?? '') ?? 100;
    final starRating = double.tryParse(_user['star_rating']?.toString() ?? '') ?? 5.0;
    final tier = StandingTier.getFromStars(starRating);

    final rawMemberType = (_user['member_type'] ?? _user['memberType'] ?? '').toString().toLowerCase();
    final isLicentiate = rawMemberType.contains('licentiate') || rawMemberType.contains('individual');
    final isAssociate = rawMemberType.contains('associate') || rawMemberType.contains('affiliate');
    final isCorporate = !isLicentiate && !isAssociate;

    final scaleStr = (_user['company_scale'] ?? _user['member_scale'] ?? 'sme').toString().toLowerCase();
    final scaleLabel = isLicentiate
        ? 'Licentiate Member'
        : (isAssociate
            ? 'Associate Member'
            : (scaleStr.contains('large') || scaleStr.contains('corp') ? 'Large Corporate' : 'SME Brokerage'));
    final scaleIcon = isLicentiate
        ? Icons.badge_rounded
        : (isAssociate ? Icons.group_rounded : Icons.business_rounded);
    final scaleColor = isLicentiate ? _kOrange : (isAssociate ? _kGreen : _kIndigo);

    final feeCat = (_user['fee_category'] ?? '').toString().toLowerCase();
    final feeCatLabel = isLicentiate
        ? 'Customs House Agent'
        : (isAssociate
            ? 'Allied Logistics Partner'
            : (feeCat == 'consolidation'
                ? 'Consolidation'
                : (feeCat == 'cf_consolidation' ? 'Consolidation, C&F' : 'Clearing & Forwarding')));
    final feeCatIcon = isLicentiate
        ? Icons.person_pin_rounded
        : (isAssociate ? Icons.handshake_rounded : Icons.local_shipping_rounded);
    final feeCatColor = isLicentiate ? _kPurple : (isAssociate ? _kIndigo : _kPurple);

    final portRaw = (_user['port_of_operation'] ?? _user['port'] ?? 'Tema Port').toString();
    final portStr = _formatPortAbbreviation(portRaw);

    return AppLayout(
      title: 'My Profile',
      scrollable: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. EXECUTIVE HERO PROFILE BANNER ───────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Branded Top Pattern Header
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1E293B),
                          _kOrange.withAlpha(200),
                          const Color(0xFF0F172A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 20,
                          top: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(tier.icon, size: 14, color: tier.color),
                                const SizedBox(width: 6),
                                Text(
                                  tier.badgeText,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Avatar & User Info
                  Transform.translate(
                    offset: const Offset(0, -45),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          // Profile Photo with Camera Upload
                          GestureDetector(
                            onTap: _uploadingPhoto ? null : _uploadAvatar,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardBg, width: 4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _kOrange.withAlpha(60),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _user['profile_photo'] != null && _user['profile_photo'].toString().isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: ApiService.resolveImageUrl(_user['profile_photo'].toString()),
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                            placeholder: (ctx, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange)),
                                            errorWidget: (ctx, url, err) => _buildAvatarFallback(),
                                          )
                                        : _buildAvatarFallback(),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _kOrange,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardBg, width: 2),
                                  ),
                                  child: _uploadingPhoto
                                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Name & Title
                          Text(
                            _user['name']?.toString() ?? 'Broker Member',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _user['company']?.toString() ?? 'Customs Brokerage Entity',
                            style: GoogleFonts.inter(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),

                          // Tag Chips (Scale, Operating Scope, Verified Status)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPill(scaleLabel, scaleIcon, scaleColor, isDark),
                              if (isCorporate)
                                _buildPill(feeCatLabel, feeCatIcon, feeCatColor, isDark),
                              _buildPill(
                                isGoodStanding
                                    ? 'Active in Good Standing'
                                    : (isPackagePending ? 'Waiting For Payment' : 'Status Pending'),
                                isGoodStanding
                                    ? Icons.verified_rounded
                                    : (isPackagePending ? Icons.payment_rounded : Icons.pending_rounded),
                                isGoodStanding ? _kGreen : _kAmber,
                                isDark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Quick Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                onPressed: () => _openDigitalIdDialog(tier, expiry, daysLeft, isGoodStanding, isPackagePending),
                                icon: const Icon(Icons.badge_rounded, size: 18),
                                label: Text('View Digital ID', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: textPrimary,
                                  side: BorderSide(color: border, width: 1.2),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => context.go('/compliance'),
                                icon: const Icon(Icons.verified_user_outlined, size: 17, color: _kGreen),
                                label: Text('Compliance Centre', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── 2. METRIC STATS STRIP ─────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 750;
                final expireBoxText = (!isGoodStanding || isPackagePending)
                    ? 'Not Active'
                    : (expiry != null ? _formatDate(expiry) : 'Active & Valid');
                final expireBoxSub = isPackagePending
                    ? 'Settle Package'
                    : (daysLeft != null ? (daysLeft < 0 ? 'Expired' : '$daysLeft days left') : (isGoodStanding ? 'Valid' : 'Not Active'));
                final expireBoxColor = isPackagePending ? _kOrange : (daysLeft != null && daysLeft <= 30 ? _kRed : _kGreen);

                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildMetricBox('Compliance Score', '$complianceScore/100', 'Calculated standing rate', Icons.speed_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricBox('Membership Rating', '${starRating.toStringAsFixed(1)} ★', tier.label, Icons.star_rounded, const Color(0xFFD4AF37), cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricBox('Operating Port', portStr, 'Chapter', null, _kIndigo, cardBg, border, textPrimary, textMuted)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricBox('Member Expire', expireBoxText, expireBoxSub, Icons.event_available_rounded, expireBoxColor, cardBg, border, textPrimary, textMuted)),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricBox('Compliance Score', '$complianceScore/100', 'Standing rate', Icons.speed_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricBox('Rating', '${starRating.toStringAsFixed(1)} ★', tier.label, Icons.star_rounded, const Color(0xFFD4AF37), cardBg, border, textPrimary, textMuted)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildMetricBox('Operating Port', portStr, 'Chapter', null, _kIndigo, cardBg, border, textPrimary, textMuted)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricBox('Member Expire', expireBoxText, expireBoxSub, Icons.event_available_rounded, expireBoxColor, cardBg, border, textPrimary, textMuted)),
                            ],
                          ),
                        ],
                      );
              },
            ),
            const SizedBox(height: 18),

            // ── 3. TWO-COLUMN DETAILS SECTION ─────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                return isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildCorporateCard(cardBg, border, textPrimary, textMuted, scaleLabel, feeCatLabel, portStr, isLicentiate, isAssociate)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildComplianceCard(cardBg, border, textPrimary, textMuted, expiry, daysLeft, isGoodStanding, isPackagePending, isExpired, isDark)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildCorporateCard(cardBg, border, textPrimary, textMuted, scaleLabel, feeCatLabel, portStr, isLicentiate, isAssociate),
                          const SizedBox(height: 16),
                          _buildComplianceCard(cardBg, border, textPrimary, textMuted, expiry, daysLeft, isGoodStanding, isPackagePending, isExpired, isDark),
                        ],
                      );
              },
            ),
            const SizedBox(height: 18),

            // ── 4. HISTORICAL TREND & COMPLIANCE MATH ─────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tier.color.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.show_chart_rounded, color: tier.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Historical Compliance & Standing Trend',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
                              softWrap: true,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '30-day recorded compliance trajectory and mathematical breakdown points',
                              style: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                              softWrap: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TrendLineWidget(
                    points: (_user['rating_history'] as List?)
                            ?.map((h) => double.tryParse(h['compliance_score']?.toString() ?? '') ?? 100.0)
                            .toList() ??
                        [complianceScore.toDouble()],
                    color: tier.color,
                    height: 90,
                  ),
                  const Divider(height: 28),
                  _buildMathBreakdownSection(_user, _kOrange, isDark, textPrimary, textMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() => CircleAvatar(
        radius: 45,
        backgroundColor: _kOrange.withAlpha(30),
        child: Text(
          _initials,
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: _kOrange),
        ),
      );

  Widget _buildPill(String label, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox(
    String title,
    String value,
    String subtitle,
    IconData? icon,
    Color color,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary.withAlpha(200),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorporateCard(Color cardBg, Color border, Color textPrimary, Color textMuted, String scale, String feeCat, String port, bool isLicentiate, bool isAssociate) {
    final title = isLicentiate
        ? 'Licentiate Member'
        : (isAssociate ? 'Associate Member' : 'Corporate Identity & Scope');
    final subtitle = isLicentiate
        ? 'Licentiate member credentials & registration particulars'
        : (isAssociate ? 'Associate member credentials & registration particulars' : 'Entity registration particulars & operational scope');
    final entityLabel = isLicentiate
        ? 'Licensed Practice / Name'
        : (isAssociate ? 'Entity / Partner Name' : 'Entity / Company');
    final entityIcon = isLicentiate ? Icons.person_outline_rounded : (isAssociate ? Icons.groups_rounded : Icons.domain_rounded);
    final cardThemeColor = isLicentiate ? _kOrange : (isAssociate ? _kGreen : _kIndigo);
    final cardIcon = isLicentiate ? Icons.badge_rounded : (isAssociate ? Icons.handshake_rounded : Icons.apartment_rounded);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardThemeColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cardIcon, color: cardThemeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _itemRow(entityLabel, _user['company']?.toString() ?? _user['name']?.toString() ?? 'Customs Licentiate', entityIcon, textPrimary, textMuted),
          _itemRow('Membership ID', _membershipId, Icons.badge_outlined, textPrimary, textMuted),
          _itemRow('Primary Contact', _user['name']?.toString() ?? '—', Icons.person_outline_rounded, textPrimary, textMuted),
          _itemRow('Official Email', _user['email']?.toString() ?? '—', Icons.email_outlined, textPrimary, textMuted),
          _itemRow('Phone Number', _user['phone']?.toString() ?? 'Not provided', Icons.phone_outlined, textPrimary, textMuted),
          _itemRow('Operating Chapter', port, null, textPrimary, textMuted, isLast: true),
        ],
      ),
    );
  }

  Widget _buildComplianceCard(
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
    String? expiry,
    int? daysLeft,
    bool isGoodStanding,
    bool isPackagePending,
    bool isExpired,
    bool isDark,
  ) {
    String standingStatus;
    String memberExpireText;
    String timelineNotice;
    Color standingColor;

    if (isPackagePending) {
      standingStatus = '🟡 Waiting For Membership Payment';
      memberExpireText = 'Not Active';
      timelineNotice = 'Not Active • Settle Entrance Package to Activate';
      standingColor = _kAmber;
    } else if (isExpired) {
      standingStatus = '🔴 Renewal Required';
      memberExpireText = expiry != null ? _formatDate(expiry) : 'Expired';
      timelineNotice = 'Expired ${daysLeft?.abs()} days ago • Renewal Required';
      standingColor = _kRed;
    } else if (daysLeft != null && daysLeft <= 30) {
      standingStatus = '🟡 Renewal Due Soon';
      memberExpireText = _formatDate(expiry);
      timelineNotice = '$daysLeft days remaining until expiration';
      standingColor = _kAmber;
    } else if (isGoodStanding) {
      standingStatus = '🟢 Active in Good Standing';
      memberExpireText = expiry != null ? _formatDate(expiry) : 'Active & Valid';
      timelineNotice = daysLeft != null ? '$daysLeft days remaining' : 'Active in Good Standing';
      standingColor = _kGreen;
    } else {
      standingStatus = '🟡 Pending Activation';
      memberExpireText = 'Not Active';
      timelineNotice = 'Not Active • Pending Verification & Activation';
      standingColor = _kAmber;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: standingColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.gavel_rounded, color: standingColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Membership & Standing Status',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Statutory compliance validity & annual renewal schedule',
                      style: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _itemRow('Standing Status', standingStatus, Icons.shield_outlined, standingColor, textMuted),
          _itemRow('Membership ID', _membershipId, Icons.badge_outlined, textPrimary, textMuted),
          _itemRow('Member Expire', memberExpireText, Icons.calendar_month_outlined, isGoodStanding ? textPrimary : textMuted, textMuted),
          _itemRow(
            'Timeline Notice',
            timelineNotice,
            Icons.timelapse_rounded,
            standingColor,
            textMuted,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kOrange,
                    side: const BorderSide(color: _kOrange),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => context.go('/payment-history'),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: Text('Payment Receipts', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPackagePending ? _kOrange : _kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () => context.go(isPackagePending ? '/payments?fee=New%20Membership%20Dues' : '/compliance'),
                  icon: Icon(isPackagePending ? Icons.payment_rounded : Icons.verified_user_rounded, size: 16),
                  label: Text(isPackagePending ? 'Pay Entrance Package' : 'Compliance Hub', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(String label, String value, IconData? icon, Color textPrimary, Color textMuted, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w800, color: textPrimary),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. DIGITAL IDENTITY CARD MODAL DIALOG ──────────────────────────────────
  Widget _buildDigitalIdCard(
    BuildContext dialogCtx,
    StandingTier tier,
    String? expiry,
    int? daysLeft,
    bool isGoodStanding,
    bool isPackagePending,
  ) {
    final badgeText = isPackagePending
        ? 'NOT ACTIVE'
        : (isGoodStanding ? 'ACTIVE IN GOOD STANDING' : 'NOT ACTIVE');
    final badgeColor = isPackagePending
        ? const Color(0xFFF59E0B)
        : (isGoodStanding ? tier.color : const Color(0xFFEF4444));

    final expireText = (!isGoodStanding || isPackagePending)
        ? 'Not Active'
        : (expiry != null ? _formatDate(expiry) : 'Active & Valid');
    final expireColor = (!isGoodStanding || isPackagePending)
        ? const Color(0xFFEF4444)
        : const Color(0xFF0F172A);

    final standingText = isPackagePending
        ? 'Waiting For Payment'
        : (isGoodStanding ? 'Active in Good Standing' : 'Inactive');
    final standingColor = isPackagePending
        ? const Color(0xFFF59E0B)
        : (isGoodStanding ? tier.color : const Color(0xFFEF4444));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kOrange.withAlpha(90), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _IdGridPainter(color: const Color(0xFFFF5000))),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _kOrange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _kOrange.withAlpha(80)),
                              ),
                              child: const Center(child: Icon(Icons.shield_rounded, color: _kOrange, size: 18)),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CUBAG',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    color: const Color(0xFF0F172A),
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  'DIGITAL IDENTITY CARD',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                    color: _kOrange,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: badgeColor.withAlpha(80)),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.outfit(
                              color: badgeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Avatar
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: badgeColor, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withAlpha(60),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _user['profile_photo'] != null && _user['profile_photo'].toString().isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: ApiService.resolveImageUrl(_user['profile_photo'].toString()),
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                  errorWidget: (ctx, url, err) => _buildAvatarFallback(),
                                )
                              : _buildAvatarFallback(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Member Name & Company
                    Text(
                      _user['name']?.toString() ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user['company']?.toString() ?? 'Customs Brokerage Entity',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),

                    // Clean Credentials Box (Official Membership ID ONLY)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBERSHIP ID', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CHAPTER / PORT', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_formatPortAbbreviation((_user['port_of_operation'] ?? _user['port'] ?? 'Tema').toString()), style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBER EXPIRE', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(expireText, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 14.5, color: expireColor)),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('STANDING', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(standingText, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 14.5, color: standingColor)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: Text('Close Card', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMathBreakdownSection(Map<String, dynamic> m, Color primary, bool isDark, Color textPrimary, Color textMuted) {
    final bd = m['breakdown'] as Map<String, dynamic>?;
    if (bd == null) {
      return Text('Compliance points math calculated from real-time Secretariat records.', style: GoogleFonts.inter(color: textMuted, fontSize: 14));
    }

    final paymentScore = bd['payment_score'] ?? 0;
    final paymentPunctual = bd['payment_punctual_score'] ?? 0;
    final paymentHistory = bd['payment_history_score'] ?? 0;
    final overdueCount = bd['overdue_payments_count'] ?? 0;
    final totalPaid = bd['total_payments_paid'] ?? 0;
    final onTimePaid = bd['on_time_payments_paid'] ?? 0;

    final taskScore = bd['task_score'] ?? 0;
    final licenseScore = bd['license_score'] ?? 0;
    final taskCompletionScore = bd['task_completion_score'] ?? 0;
    final totalTasks = bd['total_tasks'] ?? 0;
    final completedTasks = bd['completed_tasks'] ?? 0;

    final engagementScore = bd['engagement_score'] ?? 0;
    final surveyScore = bd['survey_score'] ?? 0;
    final totalSurveys = bd['total_surveys'] ?? 0;
    final respondedSurveys = bd['responded_surveys'] ?? 0;
    final agmScore = bd['agm_score'] ?? 0;
    final adminScore = bd['admin_score'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _breakdownTile(
          icon: Icons.payments_outlined,
          color: _kGreen,
          title: 'Payment Compliance',
          scoreText: '$paymentScore / 40 pts',
          details: [
            '• Punctual payment (no outstanding overdue): $paymentPunctual / 25 pts',
            '• On-time payment history ratio ($onTimePaid / $totalPaid paid on time): $paymentHistory / 15 pts',
            if (overdueCount > 0) '• WARNING: $overdueCount overdue payments detected.',
          ],
          isDark: isDark,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        _breakdownTile(
          icon: Icons.task_alt_outlined,
          color: _kBlue,
          title: 'Task & Document Compliance',
          scoreText: '$taskScore / 30 pts',
          details: [
            '• Membership validity status: $licenseScore / 15 pts',
            '• Required tasks compliance ($completedTasks / $totalTasks completed): $taskCompletionScore / 15 pts',
          ],
          isDark: isDark,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        _breakdownTile(
          icon: Icons.campaign_outlined,
          color: _kPurple,
          title: 'Engagement & Activities',
          scoreText: '$engagementScore / 20 pts',
          details: [
            '• Survey response rate ($respondedSurveys / $totalSurveys completed): $surveyScore / 10 pts',
            '• Annual General Meeting (AGM) attendance: $agmScore / 10 pts',
          ],
          isDark: isDark,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
        _breakdownTile(
          icon: Icons.rate_review_outlined,
          color: _kAmber,
          title: 'Admin Manual Review',
          scoreText: '$adminScore / 10 pts',
          details: [
            '• Direct administrative compliance modifier: $adminScore / 10 pts',
          ],
          isDark: isDark,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
      ],
    );
  }

  Widget _breakdownTile({
    required IconData icon,
    required Color color,
    required String title,
    required String scoreText,
    required List<String> details,
    required bool isDark,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textPrimary,
                  ),
                  softWrap: true,
                ),
              ),
              Text(
                scoreText,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...details.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(
                detail,
                style: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                softWrap: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
