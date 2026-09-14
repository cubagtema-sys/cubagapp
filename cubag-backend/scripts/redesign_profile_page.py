import os

PROFILE_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/profile_page.dart"

NEW_CODE = '''import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui' show ImageFilter;
import '../components/app_layout.dart';
import '../components/trend_line.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
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
  bool _showIdCard = false;
  bool _isLoading = true;
  bool _uploadingPhoto = false;

  // Password change controllers
  final _curPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confPwdCtrl = TextEditingController();
  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureConf = true;
  bool _changingPwd = false;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  @override
  void dispose() {
    _curPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confPwdCtrl.dispose();
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

  Future<void> _changePassword() async {
    if (_curPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty || _confPwdCtrl.text.isEmpty) {
      _showToast('Please fill in all password fields', isError: true);
      return;
    }
    if (_newPwdCtrl.text != _confPwdCtrl.text) {
      _showToast('New passwords do not match', isError: true);
      return;
    }
    if (_newPwdCtrl.text.length < 6) {
      _showToast('New password must be at least 6 characters', isError: true);
      return;
    }

    setState(() => _changingPwd = true);
    try {
      final res = await ApiService().post('/auth/change-password', data: {
        'current_password': _curPwdCtrl.text,
        'new_password': _newPwdCtrl.text,
      });
      if (res.statusCode == 200) {
        _curPwdCtrl.clear();
        _newPwdCtrl.clear();
        _confPwdCtrl.clear();
        _showToast('Password changed successfully ✓');
      } else {
        _showToast(res.data['message'] ?? 'Failed to change password', isError: true);
      }
    } catch (e) {
      _showToast('Error changing password: $e', isError: true);
    } finally {
      if (mounted) setState(() => _changingPwd = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? _kRed : _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final memNo = _user['membership_number']?.toString().trim() ?? '';
    if (memNo.isNotEmpty && memNo != 'null' && memNo != 'None') return memNo;
    final lic = _user['license_number']?.toString().trim() ?? '';
    if (lic.isNotEmpty && lic != 'null' && lic != 'None' && lic.toLowerCase() != 'pending') return lic;
    final id = _user['id']?.toString() ?? '1';
    return 'CUBAG-${id.padLeft(4, '0')}';
  }

  String _formatDate(String? str) {
    if (str == null) return '—';
    final d = DateTime.tryParse(str);
    if (d == null) return '—';
    return '${d.day} ${[\'Jan\', \'Feb\', \'Mar\', \'Apr\', \'May\', \'Jun\', \'Jul\', \'Aug\', \'Sep\', \'Oct\', \'Nov\', \'Dec\'][d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF181C28) : Colors.white;
    final border = isDark ? const Color(0xFF262C3D) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF0F121A) : const Color(0xFFF8FAFC);

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
    final isMemberActive = statusStr == 'active' && !isExpired;

    final complianceScore = int.tryParse(_user['compliance_score']?.toString() ?? '') ?? 100;
    final starRating = double.tryParse(_user['star_rating']?.toString() ?? '') ?? 5.0;
    final tier = StandingTier.getFromStars(starRating);
    final scaleStr = (_user['company_scale'] ?? _user['member_scale'] ?? 'sme').toString().toLowerCase();
    final scaleLabel = scaleStr.contains('large') || scaleStr.contains('corp') ? 'Large Corporate' : 'SME Brokerage';
    final feeCat = (_user['fee_category'] ?? '').toString().toLowerCase();
    final feeCatLabel = feeCat == 'consolidation'
        ? 'Consolidation'
        : (feeCat == 'cf_consolidation' ? 'Consolidation, C&F' : 'Clearing & Forwarding');
    final portStr = (_user['port_of_operation'] ?? _user['port'] ?? 'Tema Port').toString();

    return AppLayout(
      title: 'My Profile',
      scrollable: true,
      child: Stack(
        children: [
          Container(
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
                                  color: Colors.black.withAlpha(100),
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
                                        fontSize: 11,
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
                                                placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange)),
                                                errorWidget: (_, __, ___) => _buildAvatarFallback(),
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
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _user['company']?.toString() ?? 'Customs Brokerage Entity',
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
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
                                  _buildPill(scaleLabel, Icons.business_rounded, _kIndigo, isDark),
                                  _buildPill(feeCatLabel, Icons.local_shipping_rounded, _kPurple, isDark),
                                  _buildPill(
                                    isMemberActive ? 'Verified Active' : 'Status Pending',
                                    isMemberActive ? Icons.verified_rounded : Icons.pending_rounded,
                                    isMemberActive ? _kGreen : _kAmber,
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
                                    onPressed: () => setState(() => _showIdCard = true),
                                    icon: const Icon(Icons.badge_rounded, size: 18),
                                    label: Text('View Digital ID', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
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
                                    label: Text('Compliance Centre', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
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
                    return isWide
                        ? Row(
                            children: [
                              Expanded(child: _buildMetricBox('Compliance Score', '$complianceScore/100', 'Calculated standing rate', Icons.speed_rounded, _kGreen, cardBg, border, textPrimary, textMuted)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildMetricBox('Membership Rating', '${starRating.toStringAsFixed(1)} ★', tier.label, Icons.star_rounded, const Color(0xFFD4AF37), cardBg, border, textPrimary, textMuted)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildMetricBox('Operating Port', portStr, 'Chapter Assignment', Icons.anchor_rounded, _kIndigo, cardBg, border, textPrimary, textMuted)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildMetricBox('Licence Expiry', expiry != null ? _formatDate(expiry) : 'Active / Valid', daysLeft != null ? (daysLeft < 0 ? 'Expired' : '$daysLeft days left') : 'No Expiry Set', Icons.event_available_rounded, daysLeft != null && daysLeft <= 30 ? _kRed : _kOrange, cardBg, border, textPrimary, textMuted)),
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
                                  Expanded(child: _buildMetricBox('Operating Port', portStr, 'Chapter', Icons.anchor_rounded, _kIndigo, cardBg, border, textPrimary, textMuted)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildMetricBox('Licence Expiry', expiry != null ? _formatDate(expiry) : 'Active', daysLeft != null ? (daysLeft < 0 ? 'Expired' : '$daysLeft days') : 'Valid', Icons.event_available_rounded, daysLeft != null && daysLeft <= 30 ? _kRed : _kOrange, cardBg, border, textPrimary, textMuted)),
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
                              Expanded(child: _buildCorporateCard(cardBg, border, textPrimary, textMuted, scaleLabel, feeCatLabel, portStr)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildComplianceCard(cardBg, border, textPrimary, textMuted, expiry, daysLeft, isMemberActive, isDark)),
                            ],
                          )
                        : Column(
                            children: [
                              _buildCorporateCard(cardBg, border, textPrimary, textMuted, scaleLabel, feeCatLabel, portStr),
                              const SizedBox(height: 16),
                              _buildComplianceCard(cardBg, border, textPrimary, textMuted, expiry, daysLeft, isMemberActive, isDark),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Historical Compliance & Standing Trend',
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                              ),
                              Text(
                                '30-day recorded compliance trajectory and mathematical breakdown points',
                                style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                              ),
                            ],
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
                const SizedBox(height: 18),

                // ── 5. SECURITY & PASSWORD MANAGEMENT CARD ─────────────────────
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
                              color: _kIndigo.withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: _kIndigo, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Security & Password Management',
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                              ),
                              Text(
                                'Update your portal credentials with high-strength security encryption',
                                style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 800;
                          return isWide
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: _buildPasswordField(
                                        'Current Password',
                                        _curPwdCtrl,
                                        _obscureCur,
                                        () => setState(() => _obscureCur = !_obscureCur),
                                        inputBg,
                                        border,
                                        textPrimary,
                                        textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildPasswordField(
                                        'New Password',
                                        _newPwdCtrl,
                                        _obscureNew,
                                        () => setState(() => _obscureNew = !_obscureNew),
                                        inputBg,
                                        border,
                                        textPrimary,
                                        textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildPasswordField(
                                        'Confirm Password',
                                        _confPwdCtrl,
                                        _obscureConf,
                                        () => setState(() => _obscureConf = !_obscureConf),
                                        inputBg,
                                        border,
                                        textPrimary,
                                        textMuted,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildPasswordField(
                                      'Current Password',
                                      _curPwdCtrl,
                                      _obscureCur,
                                      () => setState(() => _obscureCur = !_obscureCur),
                                      inputBg,
                                      border,
                                      textPrimary,
                                      textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildPasswordField(
                                      'New Password',
                                      _newPwdCtrl,
                                      _obscureNew,
                                      () => setState(() => _obscureNew = !_obscureNew),
                                      inputBg,
                                      border,
                                      textPrimary,
                                      textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildPasswordField(
                                      'Confirm Password',
                                      _confPwdCtrl,
                                      _obscureConf,
                                      () => setState(() => _obscureConf = !_obscureConf),
                                      inputBg,
                                      border,
                                      textPrimary,
                                      textMuted,
                                    ),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kIndigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                          onPressed: _changingPwd ? null : _changePassword,
                          icon: _changingPwd
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_outline_rounded, size: 17),
                          label: Text('Update Password', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── DIGITAL ID CARD MODAL OVERLAY ──────────────────────────────────
          if (_showIdCard)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showIdCard = false),
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    color: Colors.black.withAlpha(120),
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: GestureDetector(
                        onTap: () {}, // Prevent dismissal on card click
                        child: _buildDigitalIdCard(tier, expiry, daysLeft),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() => CircleAvatar(
        radius: 45,
        backgroundColor: _kOrange.withAlpha(30),
        child: Text(
          _initials,
          style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w900, color: _kOrange),
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
            style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox(
    String title,
    String value,
    String subtitle,
    IconData icon,
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary.withAlpha(200),
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
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

  Widget _buildCorporateCard(Color cardBg, Color border, Color textPrimary, Color textMuted, String scale, String feeCat, String port) {
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
                  color: _kOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.corporate_fare_rounded, color: _kOrange, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Corporate & Entity Details',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  Text(
                    'Official company credentials & Secretariat profile',
                    style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _itemRow('Entity / Company', _user['company']?.toString() ?? 'Customs Broker Entity', Icons.domain_rounded, textPrimary, textMuted),
          _itemRow('Membership ID', _membershipId, Icons.badge_outlined, textPrimary, textMuted),
          _itemRow('Primary Contact', _user['name']?.toString() ?? '—', Icons.person_outline_rounded, textPrimary, textMuted),
          _itemRow('Official Email', _user['email']?.toString() ?? '—', Icons.email_outlined, textPrimary, textMuted),
          _itemRow('Phone Number', _user['phone']?.toString() ?? 'Not provided', Icons.phone_outlined, textPrimary, textMuted),
          _itemRow('Operating Chapter', port, Icons.location_on_outlined, textPrimary, textMuted, isLast: true),
        ],
      ),
    );
  }

  Widget _buildComplianceCard(Color cardBg, Color border, Color textPrimary, Color textMuted, String? expiry, int? daysLeft, bool isActive, bool isDark) {
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
                  color: _kGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.gavel_rounded, color: _kGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Licencing & Standing Status',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  Text(
                    'Statutory compliance validity & annual renewal schedule',
                    style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _itemRow('Standing Status', isActive ? '🟢 Active Standing' : '🔴 Renewal Required', Icons.shield_outlined, textPrimary, textMuted),
          _itemRow('Customs Licence PIN', _user['license_number']?.toString() ?? _membershipId, Icons.confirmation_number_outlined, textPrimary, textMuted),
          _itemRow('Licence Expiry', expiry != null ? _formatDate(expiry) : 'Active & Valid', Icons.calendar_month_outlined, textPrimary, textMuted),
          _itemRow(
            'Timeline Notice',
            daysLeft == null
                ? 'Valid / Active'
                : (daysLeft < 0
                    ? 'Expired $daysLeft days ago'
                    : '$daysLeft days remaining'),
            Icons.timelapse_rounded,
            daysLeft != null && daysLeft <= 30 ? _kRed : textPrimary,
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
                  label: Text('Payment Receipts', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () => context.go('/compliance'),
                  icon: const Icon(Icons.verified_user_rounded, size: 16),
                  label: Text('Compliance Hub', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(String label, String value, IconData icon, Color textPrimary, Color textMuted, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(value, style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    TextEditingController ctrl,
    bool obscure,
    VoidCallback onToggle,
    Color inputBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted)),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: textMuted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 17, color: textMuted),
                onPressed: onToggle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 6. DIGITAL IDENTITY CARD (Clean, Executive Layout with NO redundant Member ID) ──
  Widget _buildDigitalIdCard(StandingTier tier, String? expiry, int? daysLeft) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kOrange.withAlpha(80), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
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
                                    fontSize: 18,
                                    color: const Color(0xFF0F172A),
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  'DIGITAL IDENTITY CARD',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 8.5,
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
                            color: tier.color.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tier.color.withAlpha(80)),
                          ),
                          child: Text(
                            tier.badgeText,
                            style: GoogleFonts.outfit(
                              color: tier.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 9.5,
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
                          border: Border.all(color: tier.color, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: tier.color.withAlpha(60),
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
                                  errorWidget: (_, __, ___) => _buildAvatarFallback(),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user['company']?.toString() ?? 'Customs Brokerage Entity',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),

                    // Clean Credentials Box (Official Membership ID ONLY - NO internal member ID)
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
                                    Text('MEMBERSHIP ID', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('LICENCE PIN', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(_user['license_number']?.toString() ?? _membershipId, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF0F172A))),
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
                                    Text('VALID UNTIL', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(expiry != null ? _formatDate(expiry) : 'Active / Valid', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ),
                              Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('STANDING', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
                                    const SizedBox(height: 2),
                                    Text(tier.label, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 12.5, color: tier.color)),
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
                        onPressed: () => setState(() => _showIdCard = false),
                        child: Text('Close Card', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
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
      return Text('Compliance points math calculated from real-time Secretariat records.', style: GoogleFonts.inter(color: textMuted, fontSize: 12));
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
            '• License renewal status: $licenseScore / 15 pts',
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
                    fontSize: 13,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                scoreText,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 13,
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
                style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
'''

with open(PROFILE_FILE, "w", encoding="utf-8") as f:
    f.write(NEW_CODE)

print("Overhauled profile_page.dart successfully")
