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
const _kAmber = Color(0xFFf59e0b);

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
        color: const Color(0xFFD4AF37),
        icon: Icons.workspace_premium_rounded,
        badgeText: 'ELITE MEMBER',
      );
    } else if (stars >= 3.5) {
      return StandingTier(
        label: 'Good Standing',
        color: const Color(0xFF10B981),
        icon: Icons.verified_user_rounded,
        badgeText: 'ACTIVE MEMBER',
      );
    } else if (stars >= 2.0) {
      return StandingTier(
        label: 'Warning / Probationary',
        color: const Color(0xFFF59E0B),
        icon: Icons.warning_amber_rounded,
        badgeText: 'PROBATIONARY',
      );
    } else {
      return StandingTier(
        label: 'Suspended / Delinquent',
        color: const Color(0xFFEF4444),
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

    final scaleLabel = isLicentiate
        ? 'Licentiate Member'
        : (isAssociate ? 'Associate Member' : 'Corporate Entity');

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
            // ── 1. SIMPLE HERO BANNER ─────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 8),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Avatar with upload
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _uploadAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _kOrange, width: 2.5),
                          ),
                          child: ClipOval(
                            child: _user['profile_photo'] != null && _user['profile_photo'].toString().isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: ApiService.resolveImageUrl(_user['profile_photo'].toString()),
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                    errorWidget: (ctx, url, err) => _buildAvatarFallback(),
                                  )
                                : _buildAvatarFallback(),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: _kOrange,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardBg, width: 2),
                          ),
                          child: _uploadingPhoto
                              ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _user['name']?.toString() ?? 'Broker Member',
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _user['company']?.toString() ?? scaleLabel,
                    style: GoogleFonts.inter(fontSize: 14.5, color: textMuted, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isGoodStanding ? _kGreen : _kAmber).withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: (isGoodStanding ? _kGreen : _kAmber).withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isGoodStanding ? Icons.verified_rounded : Icons.pending_rounded, size: 14, color: isGoodStanding ? _kGreen : _kAmber),
                        const SizedBox(width: 6),
                        Text(
                          isGoodStanding ? 'Active in Good Standing' : 'Status Pending',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: isGoodStanding ? _kGreen : _kAmber),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () => _openDigitalIdDialog(tier, expiry, daysLeft, isGoodStanding, isPackagePending),
                        icon: const Icon(Icons.badge_rounded, size: 16),
                        label: Text('Digital ID', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => context.go('/compliance'),
                        icon: const Icon(Icons.verified_user_outlined, size: 16, color: _kGreen),
                        label: Text('Compliance', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 2. SIMPLE DETAILS CARD ────────────────────────────────────
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
                  Text(
                    'Profile Particulars',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 14),
                  _itemRow('Membership ID', _membershipId, Icons.badge_outlined, textPrimary, textMuted),
                  _itemRow('Email Address', _user['email']?.toString() ?? '—', Icons.email_outlined, textPrimary, textMuted),
                  _itemRow('Phone Number', _user['phone']?.toString() ?? 'Not provided', Icons.phone_outlined, textPrimary, textMuted),
                  _itemRow('Operating Port', portStr, Icons.anchor_outlined, textPrimary, textMuted),
                  _itemRow('Compliance Score', '$complianceScore / 100', Icons.speed_rounded, textPrimary, textMuted, isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 3. TREND CHART ───────────────────────────────────────────
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
                  Text(
                    '30-Day Compliance Trend',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 12),
                  TrendLineWidget(
                    points: (_user['rating_history'] as List?)
                            ?.map((h) => double.tryParse(h['compliance_score']?.toString() ?? '') ?? 100.0)
                            .toList() ??
                        [complianceScore.toDouble()],
                    color: tier.color,
                    height: 80,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() => CircleAvatar(
        radius: 42,
        backgroundColor: _kOrange.withAlpha(30),
        child: Text(
          _initials,
          style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: _kOrange),
        ),
      );

  Widget _itemRow(String label, String value, IconData? icon, Color textPrimary, Color textMuted, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 14, color: textMuted, fontWeight: FontWeight.w500)),
                Text(
                  value,
                  style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. DIGITAL IDENTITY CARD MODAL DIALOG ──────────────────────────────────
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
}
