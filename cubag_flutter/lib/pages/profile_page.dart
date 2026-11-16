import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../components/app_layout.dart';
import '../components/cubag_ui.dart';
import '../components/trend_line.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;

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
        badgeText: 'Elite member',
      );
    } else if (stars >= 3.5) {
      return StandingTier(
        label: 'Good Standing',
        color: CubagColors.valid,
        icon: Icons.verified_user_rounded,
        badgeText: 'Active member',
      );
    } else if (stars >= 2.0) {
      return StandingTier(
        label: 'Warning / Probationary',
        color: CubagColors.due,
        icon: Icons.warning_amber_rounded,
        badgeText: 'Probationary',
      );
    } else {
      return StandingTier(
        label: 'Suspended / Delinquent',
        color: CubagColors.lapsed,
        icon: Icons.block_rounded,
        badgeText: 'Suspended',
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
    // 1. Instant Cache Paint (0ms) from synchronous Hive memory/disk cache
    final cachedMe = ApiService.getCachedSync('/auth/me');
    if (cachedMe is Map && cachedMe.isNotEmpty) {
      _user = Map<String, dynamic>.from(cachedMe);
      _isLoading = false;
    }
    // 2. Silent Background Sync (no full-screen spinner if cached data exists)
    _fetchUser(silent: _user.isNotEmpty);

    SocketService().on('member_updated', _onLiveUpdate);
    SocketService().on('member_approved', _onLiveUpdate);
    SocketService().on('payment_approved', _onLiveUpdate);
    SocketService().on('fees_updated', _onLiveUpdate);
  }

  void _onLiveUpdate(dynamic _) {
    if (mounted) {
      ApiService.deleteCacheKeysMatching('auth/me');
      _fetchUser(silent: true);
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

  Future<void> _fetchUser({bool silent = false, bool forceRefresh = false}) async {
    if (!silent && _user.isEmpty) {
      setState(() => _isLoading = true);
    }
    if (forceRefresh) {
      ApiService.deleteCacheKeysMatching('auth/me');
    }
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
        final exactBytes = Uint8List.fromList(file.bytes!);
        mpFile = MultipartFile.fromBytes(exactBytes, filename: file.name);
      } else if (file.path != null && file.path!.isNotEmpty) {
        mpFile = await MultipartFile.fromFile(file.path!, filename: file.name);
      } else {
        final bytes = await file.xFile.readAsBytes();
        mpFile = MultipartFile.fromBytes(Uint8List.fromList(bytes), filename: file.name);
      }

      final formData = FormData.fromMap({
        'photo': mpFile,
      });
      final res = await api.upload('/auth/upload-photo', formData);

      if (res.statusCode == 200 && (res.data['photo_url'] != null || res.data['profile_photo'] != null)) {
        final rawUrl = (res.data['photo_url'] ?? res.data['profile_photo']).toString();
        final photoUrl = ApiService.resolveImageUrl(rawUrl);
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
              content: Text('Profile photo updated successfully', style: TextStyle(fontWeight: FontWeight.bold)),
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
              content: Text(msg, style: TextStyle(fontWeight: FontWeight.bold)),
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
            content: Text('Upload error: $e', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showEditProfileDialog() {
    final emailCtrl = TextEditingController(text: _user['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: _user['phone']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final sheetBg = isDark ? const Color(0xFF1E130D) : Colors.white;
          final textPrimary = isDark ? Colors.white : CubagColors.ink;
          final textMuted = isDark ? const Color(0xFF5F6B7E) : CubagColors.muted;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_note_rounded, color: _kOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Update Profile Particulars',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                        hintText: 'member@company.com',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF281710) : CubagColors.sand,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : CubagColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : CubagColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kOrange, width: 1.5),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Email address is required';
                        if (!val.contains('@') || !val.contains('.')) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Phone Number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                        hintText: '024 123 4567',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF281710) : CubagColors.sand,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : CubagColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : CubagColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kOrange, width: 1.5),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Phone number is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : () async {
                          if (!formKey.currentState!.validate()) return;
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          setSheetState(() => saving = true);
                          try {
                            var res = await ApiService().put(
                              '/auth/profile',
                              data: {
                                'email': emailCtrl.text.trim().toLowerCase(),
                                'phone': phoneCtrl.text.trim(),
                              },
                            );
                            // SEC-15: a new email must be confirmed with a code
                            // sent to that address before it is applied.
                            if (res.statusCode == 202 && res.data is Map &&
                                res.data['email_verification_required'] == true) {
                              if (!ctx.mounted) return;
                              final code = await _promptEmailChangeCode(
                                ctx,
                                res.data['pending_email']?.toString() ?? emailCtrl.text.trim(),
                              );
                              if (code == null) {
                                setSheetState(() => saving = false);
                                return;
                              }
                              res = await ApiService().put(
                                '/auth/profile',
                                data: {
                                  'email': emailCtrl.text.trim().toLowerCase(),
                                  'phone': phoneCtrl.text.trim(),
                                  'email_otp': code,
                                },
                              );
                            }
                            if (res.statusCode == 200) {
                              final updatedData = (res.data is Map && res.data['member'] != null)
                                  ? res.data['member']
                                  : null;
                              if (mounted) {
                                setState(() {
                                  _user['email'] = emailCtrl.text.trim().toLowerCase();
                                  _user['phone'] = phoneCtrl.text.trim();
                                  if (updatedData is Map) {
                                    _user = {..._user, ...Map<String, dynamic>.from(updatedData)};
                                  }
                                });
                                ApiService.deleteCacheKeysMatching('auth/me');
                                if (nav.canPop()) {
                                  nav.pop();
                                }
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Profile particulars updated successfully', style: TextStyle(fontWeight: FontWeight.bold)),
                                    backgroundColor: _kGreen,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            } else {
                              final msg = res.data?['message']?.toString() ?? 'Failed to update profile';
                              setSheetState(() => saving = false);
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(msg, style: TextStyle(fontWeight: FontWeight.bold)),
                                  backgroundColor: _kRed,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          } catch (e) {
                            setSheetState(() => saving = false);
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text('Update error: $e', style: TextStyle(fontWeight: FontWeight.bold)),
                                backgroundColor: _kRed,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  bool get _isAdminRole {
    final role = _user['role']?.toString().toLowerCase().trim() ?? '';
    return role == 'admin' || role == 'super_admin' || role == 'sub_admin';
  }

  String get _userId {
    final rawUserId = _user['user_id']?.toString().trim() ?? '';
    if (rawUserId.isNotEmpty && rawUserId != 'null' && rawUserId != 'None') {
      return rawUserId;
    }
    final id = _user['id']?.toString() ?? '1';
    return 'USR-${id.padLeft(4, '0')}';
  }

  String get _displayId {
    if (_isAdminRole) {
      return _userId;
    }
    return _membershipId;
  }

  String get _idLabel => _isAdminRole ? 'User ID' : 'Membership ID';

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

  String _portFullName(String code) {
    switch (code) {
      case 'KIA':
        return 'KIA · Kotoka International Airport';
      case 'TEMA':
        return 'TEMA · Port of Tema';
      case 'TKD':
        return 'TKD · Port of Takoradi';
      case 'AFLAO':
        return 'AFLAO · Aflao Border Station';
      case 'ELUBO':
        return 'ELUBO · Elubo Border Station';
      case 'PAGA':
        return 'PAGA · Paga Border Station';
      case 'KMS':
        return 'KMS · Kumasi Inland Depot';
      case 'SUN':
        return 'SUN · Sunyani Station';
      default:
        return code;
    }
  }

  String _formatDate(String? str) {
    if (str == null) return '—';
    final d = DateTime.tryParse(str);
    if (d == null) return '—';
    return '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  }

  /// Asks for the 6-digit code emailed to [email]. Returns null if cancelled.
  Future<String?> _promptEmailChangeCode(BuildContext ctx, String email) {
    final codeCtrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        scrollable: true,
        title: const Text('Confirm your new email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the 6-digit code we sent to $email.'),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Verification code'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final c = codeCtrl.text.trim();
              if (c.length == 6) Navigator.of(dCtx).pop(c);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(codeCtrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = isDark ? const Color(0xFF5F6B7E) : CubagColors.muted;

    if (_isLoading) {
      return AppLayout(
        title: 'Profile',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _kOrange),
              const SizedBox(height: 16),
              Text('Loading profile details...', style: TextStyle(color: textMuted)),
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

    const scaleLabel = 'Corporate Entity';

    final portRaw = (_user['port_of_operation'] ?? _user['port'] ?? 'Tema Port').toString();
    final portStr = _formatPortAbbreviation(portRaw);

    final photo = _user['profile_photo']?.toString() ?? '';
    final scoreGood = complianceScore >= 80;

    return AppLayout(
      title: 'Profile',
      scrollable: false,
      child: PageBody(
        onRefresh: () => _fetchUser(forceRefresh: true),
        children: [
          // ── Identity: the one bold surface on the page ──
          Container(
            padding: const EdgeInsets.all(CubagSpace.xl),
            decoration: BoxDecoration(
              color: CubagColors.cocoa,
              borderRadius: BorderRadius.circular(CubagRadius.hero),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: 'Change profile photo',
                  child: GestureDetector(
                    onTap: _uploadingPhoto ? null : _uploadAvatar,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: CubagColors.onCocoaMuted.withAlpha(120), width: 2),
                          ),
                          child: ClipOval(
                            child: photo.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: ApiService.resolveImageUrl(photo),
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.cover,
                                    errorWidget: (ctx, url, err) => _buildAvatarFallback(),
                                  )
                                : _buildAvatarFallback(),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: CubagColors.paper,
                              shape: BoxShape.circle,
                              border: Border.all(color: CubagColors.cocoa, width: 2),
                            ),
                            child: _uploadingPhoto
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(strokeWidth: 2, color: CubagColors.action),
                                  )
                                : const Icon(Icons.photo_camera_outlined, size: 15, color: CubagColors.cocoa),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: CubagSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user['name']?.toString() ?? 'Member',
                        style: CubagType.title.copyWith(color: CubagColors.onCocoa),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _user['company']?.toString() ?? (_isAdminRole ? 'CUBAG Secretariat' : scaleLabel),
                        style: CubagType.small.copyWith(color: CubagColors.onCocoaMuted),
                      ),
                      const SizedBox(height: CubagSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isAdminRole
                              ? CubagColors.action.withAlpha(40)
                              : (isGoodStanding ? CubagColors.validTint : CubagColors.dueTint),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isAdminRole
                                  ? Icons.admin_panel_settings_rounded
                                  : (isGoodStanding ? Icons.verified_rounded : Icons.schedule_rounded),
                              size: 14,
                              color: _isAdminRole
                                  ? Colors.white
                                  : (isGoodStanding ? CubagColors.valid : CubagColors.due),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isAdminRole
                                  ? (_user['role'] == 'super_admin' ? 'Super Admin · Staff' : (_user['role'] == 'sub_admin' ? 'Staff · Sub-admin' : 'Administrator · Staff'))
                                  : (isGoodStanding ? 'In good standing' : 'Membership pending'),
                              style: CubagType.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _isAdminRole
                                    ? Colors.white
                                    : (isGoodStanding ? CubagColors.valid : CubagColors.due),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CubagSpace.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openDigitalIdDialog(tier, expiry, daysLeft, isGoodStanding, isPackagePending),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text(_isAdminRole ? 'Staff ID' : 'Digital ID'),
                ),
              ),
              const SizedBox(width: CubagSpace.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go(_isAdminRole ? '/admin' : '/compliance'),
                  icon: Icon(_isAdminRole ? Icons.admin_panel_settings_outlined : Icons.verified_user_outlined, size: 18),
                  label: Text(_isAdminRole ? 'Admin Console' : 'Compliance'),
                ),
              ),
            ],
          ),

          // ── Details ──
          const SizedBox(height: CubagSpace.xxl),
          Row(
            children: [
              Expanded(child: Text('Your details', style: CubagType.headline)),
              TextButton.icon(
                onPressed: _showEditProfileDialog,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: CubagSpace.xs),
          _group([
            _detailRow(_idLabel, _displayId, copy: true, figure: true),
            _detailRow('Email', _user['email']?.toString() ?? '—', copy: true),
            _detailRow('Phone', _user['phone']?.toString() ?? 'Not provided', copy: _user['phone'] != null),
            _detailRow('District', _portFullName(portStr)),
          ]),

          // ── Compliance (Members only) ──
          if (!_isAdminRole) ...[
            const SizedBox(height: CubagSpace.xxl),
            Text('Compliance', style: CubagType.headline),
            const SizedBox(height: CubagSpace.xs),
            _group([
              Padding(
                padding: const EdgeInsets.all(CubagSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$complianceScore',
                          style: CubagType.figure.copyWith(fontFamily: CubagType.serif, fontSize: 36, height: 1.1),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 4),
                          child: Text('/ 100', style: CubagType.small),
                        ),
                        const Spacer(),
                        StatusChip(
                          scoreGood ? 'Excellent' : 'Being monitored',
                          kind: scoreGood ? StatusKind.good : StatusKind.pending,
                        ),
                      ],
                    ),
                    const SizedBox(height: CubagSpace.xxs),
                    Text('Your compliance score over the last 30 days', style: CubagType.small),
                    const SizedBox(height: CubagSpace.md),
                    TrendLineWidget(
                      points: (_user['rating_history'] as List?)
                              ?.map((h) => double.tryParse(h['compliance_score']?.toString() ?? '') ?? 100.0)
                              .toList() ??
                          [complianceScore.toDouble()],
                      color: scoreGood ? CubagColors.valid : CubagColors.due,
                      height: 72,
                    ),
                  ],
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// White grouped list with hairlines between rows.
  Widget _group(List<Widget> rows) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: CubagSpace.md, color: CubagColors.line),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool copy = false, bool figure = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CubagSpace.md, 12, copy ? CubagSpace.xxs : CubagSpace.md, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CubagType.small),
                const SizedBox(height: 2),
                Text(value, style: figure ? CubagType.figure : CubagType.bodyStrong),
              ],
            ),
          ),
          if (copy)
            IconButton(
              tooltip: 'Copy $label',
              icon: const Icon(Icons.copy_rounded, size: 18, color: CubagColors.muted),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() => CircleAvatar(
        radius: 42,
        backgroundColor: _kOrange.withAlpha(30),
        child: Text(
          _initials,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.accentOrangeText),
        ),
      );

  Widget _buildDigitalIdCard(
    BuildContext dialogCtx,
    StandingTier tier,
    String? expiry,
    int? daysLeft,
    bool isGoodStanding,
    bool isPackagePending,
  ) {
    final badgeText = _isAdminRole
        ? (_user['role'] == 'super_admin' ? 'Super Admin' : (_user['role'] == 'sub_admin' ? 'Staff' : 'Admin'))
        : (isPackagePending
            ? 'Pending'
            : (isGoodStanding ? 'Active' : 'Inactive'));
    final badgeColor = _isAdminRole
        ? CubagColors.action
        : (isPackagePending
            ? CubagColors.due
            : (isGoodStanding ? CubagColors.valid : CubagColors.lapsed));

    final expireText = _isAdminRole
        ? 'Staff / Secretariat'
        : ((!isGoodStanding || isPackagePending)
            ? 'Pending Renewal'
            : (expiry != null ? _formatDate(expiry) : 'Valid Member'));

    final memberName = _user['name']?.toString().trim() ?? 'Member';
    final companyName = _user['company']?.toString().trim().isNotEmpty == true
        ? _user['company'].toString().trim()
        : (_isAdminRole ? 'CUBAG Secretariat' : 'Member Enterprise / Firm');
    final port = _formatPortAbbreviation((_user['port_of_operation'] ?? _user['port'] ?? 'Tema').toString());

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 350),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sleek Dismiss Action Bar above card
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(button: true, label: 'Close', child: GestureDetector(
                onTap: () => Navigator.of(dialogCtx).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(220),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close_rounded, size: 20, color: CubagColors.ink),
                ),
              )),
            ),
          ),

          // ID Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CubagColors.line, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header: CUBAG Brand & Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _kOrange.withAlpha(25),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Center(
                            child: Icon(Icons.shield_rounded, color: _kOrange, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUBAG',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: CubagColors.ink,
                              ),
                            ),
                            Text(
                              _isAdminRole ? 'Staff ID' : 'Digital ID',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 8.5,
                                color: AppColors.accentOrangeText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: badgeColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: badgeColor.withAlpha(80), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 2. Middle Section: Photo & Member Details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _kOrange.withAlpha(80), width: 2),
                      ),
                      child: ClipOval(
                        child: _user['profile_photo'] != null && _user['profile_photo'].toString().isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: ApiService.resolveImageUrl(_user['profile_photo'].toString()),
                                width: 66,
                                height: 66,
                                fit: BoxFit.cover,
                                errorWidget: (ctx, url, err) => _buildAvatarFallback(),
                              )
                            : _buildAvatarFallback(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memberName,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: CubagColors.ink,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            companyName,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: CubagColors.muted,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: CubagColors.sand,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$port Chapter',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: CubagColors.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: CubagColors.line),
                const SizedBox(height: 12),

                // 3. Footer: Credentials & Verification QR
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isAdminRole ? 'User ID' : 'Member ID',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF5F6B7E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayId,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: CubagColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Valid thru',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF5F6B7E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expireText,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: isGoodStanding ? CubagColors.inkSoft : CubagColors.lapsed,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CubagColors.line, width: 1),
                      ),
                      child: QrImageView(
                        data: 'https://cubag-api-server.fly.dev/#/verify-member?id=${_displayId.isNotEmpty && _displayId != 'Pending' ? _displayId : (_user['id']?.toString() ?? '')}',
                        version: QrVersions.auto,
                        size: 52.0,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        padding: EdgeInsets.zero,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: CubagColors.ink,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: CubagColors.ink,
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
    );
  }
}
