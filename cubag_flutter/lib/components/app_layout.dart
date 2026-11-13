import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../components/admin_search_delegate.dart';
import '../components/member_search_delegate.dart';
import 'app_logo.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

class AppLayout extends StatefulWidget {
  final Widget child;
  final String title;
  final bool hideSearch;
  final bool scrollable;
  final Widget? floatingActionButton;

  /// Mobile screen background. Redesigned screens use white
  /// (CubagColors.paper); older screens keep the sand tone so their white
  /// cards still separate from the page.
  final Color? background;

  /// Mobile header: hide the page title (e.g. Home, where the screen has its
  /// own greeting).
  final bool showMobileTitle;

  const AppLayout({
    super.key,
    required this.child,
    required this.title,
    this.hideSearch = true,
    this.scrollable = true,
    this.floatingActionButton,
    this.background,
    this.showMobileTitle = true,
  });

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  bool _isSidebarCollapsed = false;
  Timer? _sidebarInactivityTimer;
  static int _cachedComplianceBadge = 0;
  static DateTime? _lastBadgeFetch;
  int _complianceBadge = _cachedComplianceBadge;

  @override
  void dispose() {
    _sidebarInactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.userRole == 'member') {
        auth.refreshProfile();
      }
      Provider.of<NotificationService>(
        context,
        listen: false,
      ).fetchUnreadCount(force: false);
      _fetchComplianceBadge();
    });
    _loadUserPhoto();
  }

  Future<void> _fetchComplianceBadge() async {
    if (_lastBadgeFetch != null &&
        DateTime.now().difference(_lastBadgeFetch!).inSeconds < 30) {
      return;
    }
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final role = auth.userRole;
      if (role != 'admin' && role != 'sub_admin' && role != 'super_admin') return;
      if (role == 'sub_admin' &&
          !auth.hasPermission('compliance') &&
          !auth.hasPermission('members')) {
        return;
      }
      final res = await ApiService().get('/compliance/admin/stats');
      if (mounted && res.statusCode == 200) {
        final under = (res.data['total_under_review'] as num?)?.toInt() ?? 0;
        final revision =
            (res.data['total_revision_requested'] as num?)?.toInt() ?? 0;
        _cachedComplianceBadge = under + revision;
        _lastBadgeFetch = DateTime.now();
        setState(() => _complianceBadge = _cachedComplianceBadge);
      }
    } catch (_) {}
  }

  Future<void> _loadUserPhoto() async {
    try {
      final res = await ApiService().get('/auth/me');
      if (res.statusCode == 200 && mounted) {
        final rawPhoto = res.data['profile_photo']?.toString();
        if (rawPhoto != null && rawPhoto.isNotEmpty) {
          final photoUrl = ApiService.resolveImageUrl(rawPhoto);
          if (photoUrl.isNotEmpty && mounted) {
            final auth = Provider.of<AuthService>(context, listen: false);
            if (auth.userPhotoUrl != photoUrl) {
              await auth.updatePhoto(photoUrl);
            }
          }
        }
      }
    } catch (e, st) {
      AppLogger.error('app_layout', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final size = MediaQuery.of(context).size;
    final role = authService.userRole;
    final isAdminRole = role == 'admin' || role == 'sub_admin' || role == 'super_admin';
    // The desktop shell (sidebar) is the admin web portal. Members on tablets
    // and wide windows keep the member app's header with a navigation rail.
    final isDesktop = size.width > 800 && isAdminRole;
    final isTablet = size.width >= 800 && !isAdminRole;
    final isSmall = size.width < 600;
    final isNarrow = size.width < 380;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isThemeDark
          ? Theme.of(context).scaffoldBackgroundColor
          : (isDesktop
              ? CubagColors.sand
              : (widget.background ?? CubagColors.sand)),
      floatingActionButton: widget.floatingActionButton,
      appBar: isDesktop
          ? null
          // Mobile header: quiet white bar with a hairline, the seal, and the
          // page name; the brand colour is saved for each screen's hero.
          : AppBar(
              backgroundColor: widget.background ?? CubagColors.sand,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              shape: const Border(bottom: BorderSide(color: CubagColors.line)),
              centerTitle: false,
              titleSpacing: isNarrow ? 12 : CubagSpace.lg,
              iconTheme: const IconThemeData(color: CubagColors.ink),
              title: Row(
                children: [
                  const AppLogo(size: 30, borderRadius: 15, showShadow: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: widget.showMobileTitle
                        ? Text(
                            widget.title,
                            style: CubagType.headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const Text('CUBAG', style: CubagType.headline),
                  ),
                ],
              ),
              actions: [
                _buildNotificationIcon(
                  context,
                  authService.userRole,
                  isSmall,
                ),
                const SizedBox(width: 4),
                Consumer<AuthService>(
                  builder: (context, auth, _) =>
                      _buildProfileMenu(context, auth, isSmall),
                ),
                SizedBox(width: (isNarrow ? 6 : 12) + MediaQuery.of(context).padding.right),
              ],
            ),
      bottomNavigationBar: (isDesktop || isTablet)
          ? null
          : _buildBottomNav(context, authService.userRole, currentRoute),
      body: Row(
        // Stretch: otherwise a short page sizes to its content and the Row
        // centres it vertically (pages floated mid-screen on tablets).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop) _buildSidebar(context, authService.userRole),
          if (isTablet) ..._buildMemberRail(context, currentRoute, size.width),
          Expanded(
            child: isDesktop
                ? MouseRegion(
                    onEnter: (_) {
                      if (!_isSidebarCollapsed) {
                        _sidebarInactivityTimer?.cancel();
                        _sidebarInactivityTimer = Timer(const Duration(milliseconds: 600), () {
                          if (mounted && !_isSidebarCollapsed) {
                            setState(() => _isSidebarCollapsed = true);
                          }
                        });
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (!_isSidebarCollapsed) {
                          setState(() => _isSidebarCollapsed = true);
                        }
                      },
                      child: Column(
                        children: [
                          _buildDesktopHeader(context, authService),
                          Expanded(
                            child: SelectionArea(
                              child: widget.scrollable
                                  ? SingleChildScrollView(
                                      padding: EdgeInsets.only(
                                        left: 20,
                                        right: 20,
                                        top: 20,
                                        bottom: 20 + MediaQuery.of(context).padding.bottom,
                                      ),
                                      child: widget.child,
                                    )
                                  : Padding(
                                      padding: EdgeInsets.only(
                                        left: 20,
                                        right: 20,
                                        top: 20,
                                        bottom: 20 + MediaQuery.of(context).padding.bottom,
                                      ),
                                      child: widget.child,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // Phone body: just the screen on its background. Redesigned
                // screens (those passing [background]) lay out their own
                // gutters; older screens keep the 16 px padding they expect.
                : Container(
                    width: double.infinity,
                    color: widget.background ?? CubagColors.sand,
                    child: Builder(
                      builder: (context) {
                        final pad = widget.background != null
                            ? EdgeInsets.zero
                            : EdgeInsets.symmetric(
                                horizontal: isNarrow ? 10 : 16,
                                vertical: isNarrow ? 10 : 16,
                              );
                        return widget.scrollable
                            ? SingleChildScrollView(padding: pad, child: widget.child)
                            : Padding(padding: pad, child: widget.child);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon(
    BuildContext context,
    String? role,
    bool isSmall, {
    bool isDark = false,
  }) {
    final targetRoute = (role == 'admin' || role == 'sub_admin' || role == 'super_admin')
        ? '/admin/notifications'
        : '/notifications';
    final iconColor = isDark ? Colors.white : CubagColors.muted;
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final textColor = isThemeDark ? Colors.white : CubagColors.ink;
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : CubagColors.line;

    return Consumer<NotificationService>(
      builder: (context, notificationService, _) {
        final unreadCount = notificationService.unreadCount;

        if (isSmall) {
          return InkWell(
            onTap: () => _showMobileNotificationSheet(
              context,
              notificationService,
              targetRoute,
              isDark: isDark,
            ),
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        color: iconColor,
                        size: 24,
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: CubagColors.lapsed,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? CubagColors.ink : Colors.white,
                                width: 1.5,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 14,
                              minHeight: 14,
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
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

        Future<void> handleMenuTap(String value) async {
          Navigator.of(context).pop();
          if (value == 'view_all') {
            context.go(targetRoute);
            return;
          }
          if (value.startsWith('notif_')) {
            final idStr = value.substring(6);
            try {
              await ApiService().post(
                '/notifications/mark-read',
                data: {'notification_id': idStr},
              );
              notificationService.decrementCount();
            } catch (_) {}
            if (!context.mounted) return;
            context.go(targetRoute);
          }
        }

        return PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'Notifications',
          icon: SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  color: iconColor,
                  size: 24,
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: CubagColors.lapsed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? CubagColors.ink : Colors.white,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Drop down directly under the icon, like a standard app menu.
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          color: dropdownBg,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderThemeColor, width: 1.5),
          ),
          onSelected: (value) async {
            if (value == 'view_all') {
              context.go(targetRoute);
            } else if (value.startsWith('notif_')) {
              final idStr = value.substring(6);
              final notificationService = Provider.of<NotificationService>(context, listen: false);
              try {
                await ApiService().post(
                  '/notifications/mark-read',
                  data: {'notification_id': idStr},
                );
                notificationService.decrementCount();
              } catch (_) {}
              if (!context.mounted) return;
              context.go(targetRoute);
            }
          },
          itemBuilder: (popupContext) {
            final recent = notificationService.recentNotifications;
            final maxListHeight = () {
              final h = MediaQuery.of(popupContext).size.height * 0.45;
              return h < 360 ? h : 360.0;
            }();

            return [
              PopupMenuItem<String>(
                enabled: false,
                padding: EdgeInsets.zero,
                child: _NotificationAutoCloseTray(
                  onExit: () {
                    if (Navigator.of(popupContext).canPop()) {
                      Navigator.of(popupContext).pop();
                    }
                  },
                  child: SizedBox(
                    width: 360,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Fixed header ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Notifications',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            if (unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFef4444,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$unreadCount New',
                                  style: TextStyle(
                                    color: CubagColors.lapsed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderThemeColor),

                      // ── Scrollable notification list ──────────────────────
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxListHeight),
                        child: recent.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 28,
                                  horizontal: 16,
                                ),
                                child: Center(
                                  child: Text(
                                    'No recent notifications',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isThemeDark
                                          ? Colors.white70
                                          : CubagColors.muted,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                itemCount: recent.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: borderThemeColor.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                                itemBuilder: (_, i) {
                                  final n = recent[i];
                                  final isRead = n['read'] == true;
                                  return InkWell(
                                    onTap: () =>
                                        handleMenuTap('notif_${n['id']}'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(
                                              top: 6,
                                              right: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isRead
                                                  ? Colors.transparent
                                                  : CubagColors.action,
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  n['title']?.toString() ?? '',
                                                  style: TextStyle(
                                                    fontWeight: isRead
                                                        ? FontWeight.w600
                                                        : FontWeight.w800,
                                                    fontSize: 14,
                                                    color: textColor,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  n['message']?.toString() ?? '',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isThemeDark
                                                        ? Colors.white70
                                                        : const Color(
                                                            0xFF64748b,
                                                          ),
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Divider(height: 1, color: borderThemeColor),

                      // ── Fixed footer ──────────────────────────────────────
                      InkWell(
                        onTap: () => handleMenuTap('view_all'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View All Notifications',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.accentOrangeText,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: CubagColors.action,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ];
          },
        );
      },
    );
  }

  Widget _buildProfileMenu(
    BuildContext context,
    AuthService authService,
    bool isSmall, {
    bool isDark = false,
  }) {
    final photoUrl = ApiService.resolveImageUrl(authService.userPhotoUrl);
    final primary = Theme.of(context).primaryColor;
    final borderColor = isDark ? Colors.white30 : CubagColors.line;
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final textColor = isThemeDark ? Colors.white : CubagColors.ink;
    final subTextColor = isThemeDark ? Colors.white70 : CubagColors.muted;
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : CubagColors.line;

    if (isSmall) {
      return Semantics(button: true, label: 'Account menu', child: InkWell(
        onTap: () => _showMobileProfileSheet(
          context,
          authService,
          isDark: isDark,
        ),
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: SizedBox(
                width: 28,
                height: 28,
                child: ClipOval(
                  child: photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: isThemeDark
                                ? const Color(0xFF3E2418)
                                : CubagColors.sand,
                            child: Icon(
                              Icons.person_rounded,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                              size: 18,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: isThemeDark
                                ? const Color(0xFF3E2418)
                                : CubagColors.sand,
                            child: Icon(
                              Icons.person_rounded,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                              size: 18,
                            ),
                          ),
                        )
                      : Container(
                          color: isThemeDark
                              ? const Color(0xFF3E2418)
                              : CubagColors.sand,
                          child: Icon(
                            Icons.person_rounded,
                            color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                            size: 18,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: SizedBox(
          width: 32,
          height: 32,
          child: ClipOval(
            child: photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: isThemeDark
                          ? const Color(0xFF3E2418)
                          : CubagColors.sand,
                      child: Icon(
                        Icons.person_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                        size: 20,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: isThemeDark
                          ? const Color(0xFF3E2418)
                          : CubagColors.sand,
                      child: Icon(
                        Icons.person_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                        size: 20,
                      ),
                    ),
                  )
                : Container(
                    color: isThemeDark
                        ? const Color(0xFF3E2418)
                        : CubagColors.sand,
                    child: Icon(
                      Icons.person_rounded,
                      color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                      size: 20,
                    ),
                  ),
          ),
        ),
      ),
      // Drop down directly under the icon, like a standard app menu.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: dropdownBg,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderThemeColor, width: 1.5),
      ),
      itemBuilder: (context) {
        final isMember = authService.userRole == 'member';
        final status = (authService.membershipStatus.isNotEmpty && authService.membershipStatus != 'none')
            ? authService.membershipStatus.toLowerCase().trim()
            : (SessionStorage.instance.getStringSync('cubag_member_status') ?? 'pending').toLowerCase().trim();
        final isRegPaid = authService.isRegistrationFeePaid || (SessionStorage.instance.getStringSync('cubag_registration_fee_paid') == 'true');
        final isApproved = status == 'active' || status == 'approved';
        final isPending = isMember && (!isApproved || !isRegPaid);

        return [
          // User Details Header
          PopupMenuItem<String>(
            enabled: false,
            child: Container(
              width: 250,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: primary.withValues(alpha: 0.1),
                                child: Icon(Icons.person_rounded, color: primary, size: 22),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: primary.withValues(alpha: 0.1),
                                child: Icon(Icons.person_rounded, color: primary, size: 22),
                              ),
                            )
                          : Container(
                              color: primary.withValues(alpha: 0.1),
                              child: Icon(Icons.person_rounded, color: primary, size: 22),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          authService.userName ?? 'Member',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.5,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPending
                              ? 'APPLICANT (ONBOARDING)'
                              : (authService.userEmail ??
                                  (authService.userRole ?? 'Member').toUpperCase()),
                          style: TextStyle(
                            fontSize: 13,
                            color: isPending ? CubagColors.action : subTextColor,
                            fontWeight: isPending ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuItem<String>(
            enabled: false,
            height: 1,
            child: Divider(color: borderThemeColor, height: 1),
          ),
          if (isPending) ...[
            // Complete Application Item
            PopupMenuItem<String>(
              onTap: () => context.go('/application-documents'),
              child: Container(
                width: 250,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: CubagColors.action.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.assignment_turned_in_rounded,
                        size: 18,
                        color: CubagColors.action,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Complete Application',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // My Profile Item
            PopupMenuItem<String>(
              onTap: () => context.go('/profile'),
              child: Container(
                width: 250,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 18,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16.5,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Settings Item
            PopupMenuItem<String>(
              onTap: () => context.go(
                (authService.userRole == 'admin' ||
                        authService.userRole == 'super_admin' ||
                        authService.userRole == 'sub_admin')
                    ? '/admin/settings'
                    : '/settings',
              ),
              child: Container(
                width: 250,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16.5,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          PopupMenuItem<String>(
            enabled: false,
            height: 1,
            child: Divider(color: borderThemeColor, height: 1),
          ),
          // Sign Out Item
          PopupMenuItem<String>(
            onTap: () async {
              await authService.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: Container(
              width: 250,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CubagColors.lapsed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: CubagColors.lapsed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign out',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                      color: CubagColors.lapsed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      },
    );
  }

  Widget _buildSheetActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subTextColor,
    required Color borderCol,
    required Color cardBg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CubagColors.action.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: CubagColors.action),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: subTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: subTextColor),
          ],
        ),
      ),
    );
  }

  void _showMobileNotificationSheet(
    BuildContext context,
    NotificationService notificationService,
    String targetRoute, {
    bool isDark = false,
  }) {
    final isThemeDark = Theme.of(context).brightness == Brightness.dark || isDark;
    final bg = isThemeDark ? const Color(0xFF23140D) : Colors.white;
    final textColor = isThemeDark ? Colors.white : CubagColors.ink;
    final subTextColor = isThemeDark ? Colors.white70 : CubagColors.muted;
    final borderCol = isThemeDark ? const Color(0xFF4D2D20) : CubagColors.line;
    final unreadCount = notificationService.unreadCount;
    final recent = notificationService.recentNotifications;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isThemeDark ? Colors.white24 : CubagColors.lineStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CubagColors.action.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.notifications_active_outlined,
                          color: CubagColors.action,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: CubagColors.lapsed.withAlpha(25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unreadCount New',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: CubagColors.lapsed,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderCol),
                Flexible(
                  child: recent.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 40,
                                  color: isThemeDark ? Colors.white38 : const Color(0xFF5F6B7E),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No new notifications',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'You will be alerted about billings, approvals, and announcements.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: recent.length,
                          separatorBuilder: (_, _) => Divider(height: 1, indent: 20, endIndent: 20, color: borderCol.withAlpha(80)),
                          itemBuilder: (ctx, i) {
                            final n = recent[i];
                            final isRead = n['read'] == true;
                            return InkWell(
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                final idStr = n['id']?.toString() ?? '';
                                if (idStr.isNotEmpty) {
                                  try {
                                    await ApiService().post('/notifications/mark-read', data: {'notification_id': idStr});
                                    notificationService.decrementCount();
                                  } catch (_) {}
                                }
                                if (context.mounted) context.go(targetRoute);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 6, right: 12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isRead ? Colors.transparent : CubagColors.action,
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n['title']?.toString() ?? '',
                                            style: TextStyle(
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                              fontSize: 14.5,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            n['message']?.toString() ?? '',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: subTextColor,
                                              height: 1.35,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Divider(height: 1, color: borderCol),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CubagColors.action,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.go(targetRoute);
                      },
                      child: Text(
                        'View All Notifications',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMobileProfileSheet(
    BuildContext context,
    AuthService authService, {
    bool isDark = false,
  }) {
    final photoUrl = ApiService.resolveImageUrl(authService.userPhotoUrl);
    final isThemeDark = Theme.of(context).brightness == Brightness.dark || isDark;
    final bg = isThemeDark ? const Color(0xFF23140D) : Colors.white;
    final cardBg = isThemeDark ? const Color(0xFF2D1B13) : const Color(0xFFF9F6F2);
    final textColor = isThemeDark ? Colors.white : CubagColors.ink;
    final subTextColor = isThemeDark ? Colors.white70 : CubagColors.muted;
    final borderCol = isThemeDark ? const Color(0xFF4D2D20) : CubagColors.line;
    final primary = CubagColors.action;

    final isMember = authService.userRole == 'member';
    final status = (authService.membershipStatus.isNotEmpty && authService.membershipStatus != 'none')
        ? authService.membershipStatus.toLowerCase().trim()
        : (SessionStorage.instance.getStringSync('cubag_member_status') ?? 'pending').toLowerCase().trim();
    final isRegPaid = authService.isRegistrationFeePaid || (SessionStorage.instance.getStringSync('cubag_registration_fee_paid') == 'true');
    final isApproved = status == 'active' || status == 'approved';
    final isPending = isMember && (!isApproved || !isRegPaid);

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isThemeDark ? Colors.white24 : CubagColors.lineStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // Member Profile Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderCol, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: ClipOval(
                          child: photoUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photoUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => Container(
                                    color: primary.withAlpha(25),
                                    child: Icon(Icons.person_rounded, color: primary, size: 28),
                                  ),
                                )
                              : Container(
                                  color: primary.withAlpha(25),
                                  child: Icon(Icons.person_rounded, color: primary, size: 28),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authService.userName ?? 'Member',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              authService.userEmail ?? (authService.userRole ?? 'Member').toUpperCase(),
                              style: TextStyle(
                                fontSize: 13,
                                color: subTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isPending ? CubagColors.action : CubagColors.valid).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isPending ? 'Applicant (Onboarding)' : 'Active Member',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isPending ? CubagColors.action : CubagColors.valid,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Navigation actions
                _buildSheetActionTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Profile',
                  subtitle: 'Your details',
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderCol: borderCol,
                  cardBg: cardBg,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go('/profile');
                  },
                ),
                const SizedBox(height: 8),

                _buildSheetActionTile(
                  icon: Icons.shield_outlined,
                  title: 'Compliance',
                  subtitle: 'Renewals and status',
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderCol: borderCol,
                  cardBg: cardBg,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go('/compliance');
                  },
                ),
                const SizedBox(height: 8),

                _buildSheetActionTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Password and preferences',
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderCol: borderCol,
                  cardBg: cardBg,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(
                      (authService.userRole == 'admin' ||
                              authService.userRole == 'super_admin' ||
                              authService.userRole == 'sub_admin')
                          ? '/admin/settings'
                          : '/settings',
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Sign Out Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CubagColors.lapsed,
                      side: const BorderSide(color: CubagColors.lapsed, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await authService.logout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      'Sign out',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopHeader(BuildContext context, AuthService authService) {
    final isAdmin =
        authService.userRole == 'admin' || authService.userRole == 'sub_admin';
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : CubagColors.sand;
    final textColor = isThemeDark
        ? const Color(0xFFFFF8F3)
        : CubagColors.ink;
    final iconColor = isThemeDark
        ? const Color(0xFFC8ADA0)
        : CubagColors.muted;
    final topPadding = MediaQuery.of(context).padding.top;
    final rightPadding = MediaQuery.of(context).padding.right;

    return Container(
      height: 64 + topPadding,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 16,
        right: 16 + rightPadding,
      ),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(bottom: BorderSide(color: borderThemeColor, width: 1.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isSidebarCollapsed
                  ? Icons.menu_rounded
                  : Icons.menu_open_rounded,
              color: iconColor,
            ),
            onPressed: () {
              setState(() {
                _isSidebarCollapsed = !_isSidebarCollapsed;
              });
            },
            tooltip: _isSidebarCollapsed
                ? 'Expand Sidebar'
                : 'Collapse Sidebar',
          ),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (!widget.hideSearch)
            IconButton(
              tooltip: 'Search',
              icon: Icon(Icons.search_rounded, color: iconColor),
              onPressed: () => showSearch(
                context: context,
                delegate: isAdmin
                    ? AdminSearchDelegate()
                    : MemberSearchDelegate(),
              ),
            ),
          _buildNotificationIcon(
            context,
            authService.userRole,
            false,
            isDark: isThemeDark,
          ),
          const SizedBox(width: 4),
          Consumer<AuthService>(
            builder: (context, auth, _) =>
                _buildProfileMenu(context, auth, false, isDark: isThemeDark),
          ),
        ],
      ),
    );
  }

  /// Members on tablets / wide windows: the bottom bar's four destinations
  /// as a navigation rail (labels beside icons on very wide screens).
  /// Which member tab owns a route. Pages opened from the Menu (membership,
  /// history, profile, settings, courses…) highlight Menu, not Home.
  static int _memberTabFor(String route) {
    if (route == '/dashboard' || route == '/') return 0;
    if (route.startsWith('/networking') || route.startsWith('/members-directory') || route.startsWith('/messaging')) {
      return 1;
    }
    if (route.startsWith('/compliance') ||
        route.startsWith('/payments') ||
        route.startsWith('/license-renewal') ||
        route.startsWith('/application-documents')) {
      return 2;
    }
    return 3;
  }

  List<Widget> _buildMemberRail(BuildContext context, String currentRoute, double width) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final status = authService.membershipStatus.toLowerCase().trim();
    if (status != 'active' && status != 'approved') return const [];
    final index = _memberTabFor(currentRoute);
    const routes = ['/dashboard', '/networking', '/compliance', '/menu'];
    final extended = width >= 1200;
    return [
      NavigationRail(
        selectedIndex: index,
        extended: extended,
        minExtendedWidth: 220,
        backgroundColor: CubagColors.paper,
        indicatorColor: CubagColors.actionTint,
        labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
        selectedIconTheme: const IconThemeData(color: CubagColors.action),
        unselectedIconTheme: const IconThemeData(color: CubagColors.muted),
        selectedLabelTextStyle: CubagType.label,
        unselectedLabelTextStyle: CubagType.small,
        groupAlignment: -0.9,
        onDestinationSelected: (i) => context.go(routes[i]),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: Text('Home'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: Text('Network'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user_rounded),
            label: Text('Compliance'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: Text('Menu'),
          ),
        ],
      ),
      const VerticalDivider(width: 1, thickness: 1, color: CubagColors.line),
    ];
  }

  Widget _buildBottomNav(
    BuildContext context,
    String? role,
    String currentRoute,
  ) {
    final isAdmin = role == 'admin' || role == 'sub_admin' || role == 'super_admin';

    int currentIndex = 0;
    if (isAdmin) {
      if (currentRoute.startsWith('/admin/members')) {
        currentIndex = 1;
      } else if (currentRoute.startsWith('/admin/payments') ||
          currentRoute.startsWith('/admin/fees')) {
        currentIndex = 2;
      } else if (currentRoute == '/menu') {
        currentIndex = 3;
      }
    } else {
      final authService = Provider.of<AuthService>(context, listen: false);
      final status = authService.membershipStatus.toLowerCase().trim();
      final isPending = status != 'active' && status != 'approved';
      if (isPending) {
        return const SizedBox.shrink();
      }

      currentIndex = _memberTabFor(currentRoute);
    }

    void go(int index) {
      if (isAdmin) {
        if (index == 0) context.go('/admin/dashboard');
        if (index == 1) context.go('/admin/members');
        if (index == 2) context.go('/admin/payments');
        if (index == 3) context.go('/menu');
      } else {
        if (index == 0) context.go('/dashboard');
        if (index == 1) context.go('/networking');
        if (index == 2) context.go('/compliance');
        if (index == 3) context.go('/menu');
      }
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CubagColors.line)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: go,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user_rounded),
            label: 'Compliance',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: 'Menu',
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, String? role) {
    final authService = Provider.of<AuthService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? CubagColors.ink : Colors.white;
    final borderThemeColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.line;
    final textColor = isDark
        ? const Color(0xFFFFF8F3)
        : CubagColors.ink;
    final topPadding = MediaQuery.of(context).padding.top;
    final leftPadding = MediaQuery.of(context).padding.left;

    return MouseRegion(
      onEnter: (_) {
        _sidebarInactivityTimer?.cancel();
      },
      onExit: (_) {
        if (!_isSidebarCollapsed) {
          _sidebarInactivityTimer?.cancel();
          _sidebarInactivityTimer = Timer(const Duration(milliseconds: 1200), () {
            if (mounted && !_isSidebarCollapsed) {
              setState(() => _isSidebarCollapsed = true);
            }
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: _isSidebarCollapsed ? 76 : 260,
        decoration: BoxDecoration(
          color: sidebarBg,
          border: Border(right: BorderSide(color: borderThemeColor, width: 1.5)),
        ),
        child: Column(
          children: [
            // Sidebar Header
            Container(
              height: 64 + topPadding,
              padding: EdgeInsets.only(
                top: topPadding,
                left: 16 + leftPadding,
                right: 16,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderThemeColor, width: 1.5),
                ),
              ),
              child: _isSidebarCollapsed
                  ? const Center(
                      child: AppLogo(
                        size: 32,
                        borderRadius: 8,
                        showShadow: false,
                      ),
                    )
                  : Row(
                      children: [
                        const AppLogo(
                          size: 32,
                          borderRadius: 8,
                          showShadow: false,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'CUBAG',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              _buildRoleBadge(context, role),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            // Sidebar Items
            Expanded(child: _buildNavItems(context, role)),
            // Sidebar Footer
            _buildSidebarFooter(context, authService),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context, String? role) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayRole = (role ?? 'Member').replaceAll('_', ' ').toUpperCase();
    Color badgeBg;
    Color badgeText;

    if (role == 'admin' || role == 'super_admin') {
      badgeBg = isDark ? const Color(0xFF4D2D20) : const Color(0xFFfff3e0);
      badgeText = isDark ? const Color(0xFFffb74d) : const Color(0xFFe65100);
    } else if (role == 'sub_admin') {
      badgeBg = isDark ? const Color(0xFF004d40) : const Color(0xFFe0f2f1);
      badgeText = isDark ? const Color(0xFF4db6ac) : const Color(0xFF004d40);
    } else {
      badgeBg = isDark ? const Color(0xFF4D2D20) : CubagColors.sand;
      badgeText = isDark ? CubagColors.lineStrong : CubagColors.inkSoft;
    }

    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayRole,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: badgeText,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(BuildContext context, AuthService authService) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderThemeColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.sand;
    final textColor = isDark ? Colors.white : CubagColors.ink;
    final subTextColor = isDark ? Colors.white70 : CubagColors.muted;
    final photoUrl = ApiService.resolveImageUrl(authService.userPhotoUrl);
    final primary = Theme.of(context).primaryColor;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final leftPadding = MediaQuery.of(context).padding.left;

    return Container(
      padding: EdgeInsets.only(
        top: 16,
        bottom: 16 + bottomPadding,
        left: 12 + leftPadding,
        right: 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderThemeColor, width: 1.5)),
      ),
      child: _isSidebarCollapsed
          ? Center(
              child: Semantics(button: true, label: 'Profile', child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: Tooltip(
                  message: authService.userName ?? 'Profile',
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: borderThemeColor, width: 1.5),
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: isDark
                                      ? const Color(0xFF3E2418)
                                      : CubagColors.sand,
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                                    size: 18,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: isDark
                                      ? const Color(0xFF3E2418)
                                      : CubagColors.sand,
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                                    size: 18,
                                  ),
                                ),
                              )
                            : Container(
                                color: isDark
                                    ? const Color(0xFF3E2418)
                                    : CubagColors.sand,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: isDark ? Colors.white70 : const Color(0xFF5F6B7E),
                                  size: 18,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              )),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF281710)
                    : CubagColors.sand,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderThemeColor),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: ClipOval(
                      child: photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: primary.withValues(alpha: 0.1),
                                child: Icon(Icons.person_rounded, color: primary, size: 18),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: primary.withValues(alpha: 0.1),
                                child: Icon(Icons.person_rounded, color: primary, size: 18),
                              ),
                            )
                          : Container(
                              color: primary.withValues(alpha: 0.1),
                              child: Icon(Icons.person_rounded, color: primary, size: 18),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          authService.userName ?? 'Member',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          authService.userEmail ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: subTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Sign out',
                    child: IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: CubagColors.lapsed,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        await authService.logout();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildNavItems(
    BuildContext context,
    String? role, {
    ScrollController? controller,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAdmin = role == 'admin' || role == 'super_admin';
    final isPending = role == 'member' && authService.membershipStatus.toLowerCase().trim() != 'active';
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.sand;

    List<Widget> sections = [];
    if (isAdmin) {
      // Grouped by the Secretariat's daily work, in plain words.
      sections = [
        _buildSection(context, 'Overview', currentRoute, [
          _NavItemData('Dashboard', Icons.space_dashboard_rounded, '/admin/dashboard'),
        ]),
        _buildSection(context, 'Members', currentRoute, [
          _NavItemData('Members', Icons.people_alt_rounded, '/admin/members'),
          _NavItemData('Applications', Icons.folder_shared_rounded, '/admin/documents'),
          _NavItemData('Compliance', Icons.verified_user_rounded, '/admin/compliance'),
        ]),
        _buildSection(context, 'Money', currentRoute, [
          _NavItemData('Payments', Icons.account_balance_wallet_rounded, '/admin/payments'),
          _NavItemData('Revenue', Icons.insights_rounded, '/admin/analytics'),
          _NavItemData('Fees', Icons.receipt_rounded, '/admin/fees'),
          _NavItemData('Bank accounts', Icons.tune_rounded, '/admin/payment-settings'),
        ]),
        _buildSection(context, 'Communication', currentRoute, [
          _NavItemData('Announcements', Icons.campaign_rounded, '/admin/announcements'),
          _NavItemData('Messages', Icons.chat_rounded, '/admin/messages'),
          _NavItemData('Reports', Icons.flag_rounded, '/admin/message-reports'),
          _NavItemData('Tickets', Icons.support_agent_rounded, '/admin/tickets'),
          _NavItemData('Complaints', Icons.gavel_rounded, '/admin/complaints'),
        ]),
        _buildSection(context, 'Events & content', currentRoute, [
          _NavItemData('Events', Icons.event_rounded, '/admin/events'),
          _NavItemData('Courses', Icons.school_rounded, '/admin/cti-courses'),
          _NavItemData('Polls', Icons.how_to_vote_rounded, '/admin/surveys'),
          _NavItemData('Gallery', Icons.photo_library_rounded, '/admin/gallery'),
          _NavItemData('News', Icons.newspaper_rounded, '/admin/port-news'),
          _NavItemData('Insights', Icons.cell_tower_rounded, '/admin/intelligence'),
        ]),
        _buildSection(context, 'Setup', currentRoute, [
          _NavItemData('Requirements', Icons.rule_folder_rounded, '/admin/document-rules'),
          _NavItemData('Ports', Icons.anchor_rounded, '/admin/ports'),
          _NavItemData('Admins', Icons.admin_panel_settings_rounded, '/admin/sub-admins'),
          _NavItemData('Audit', Icons.history_rounded, '/admin/audit-log'),
        ]),
      ];
    } else if (role == 'sub_admin') {
      final auth = authService;
      final allAdminItems = <String, List<_NavItemData>>{
        'members': [
          _NavItemData('Members', Icons.people_alt_rounded, '/admin/members'),
        ],
        'compliance': [
          _NavItemData(
            'Renewal',
            Icons.verified_user_rounded,
            '/admin/compliance',
          ),
        ],
        'documents': [
          _NavItemData(
            'Registration',
            Icons.folder_shared_rounded,
            '/admin/documents',
          ),
          _NavItemData(
            'Document Rules',
            Icons.rule_folder_rounded,
            '/admin/document-rules',
          ),
        ],
        'announcements': [
          _NavItemData(
            'Announcements',
            Icons.campaign_rounded,
            '/admin/announcements',
          ),
          _NavItemData(
            'Port Operational News',
            Icons.feed_rounded,
            '/admin/port-news',
          ),
        ],
        'intelligence': [
          _NavItemData(
            'Insights',
            Icons.cell_tower_rounded,
            '/admin/intelligence',
          ),
        ],
        'tickets': [
          _NavItemData(
            'Support Tickets',
            Icons.support_agent_rounded,
            '/admin/tickets',
          ),
          _NavItemData(
            'Complaints',
            Icons.gavel_rounded,
            '/admin/complaints',
          ),
        ],
        'messaging': [
          _NavItemData('Messages', Icons.chat_rounded, '/admin/messages'),
          _NavItemData(
            'Reported Messages',
            Icons.flag_rounded,
            '/admin/message-reports',
          ),
        ],
        'notifications': [
          _NavItemData(
            'Notifications',
            Icons.notifications_rounded,
            '/admin/notifications',
          ),
        ],
        'payments': [
          _NavItemData(
            'Financial Center',
            Icons.account_balance_wallet_rounded,
            '/admin/payments',
          ),
        ],
        'analytics': [
          _NavItemData(
            'Platform Analytics',
            Icons.analytics_rounded,
            '/admin/analytics',
          ),
        ],
        'fees': [
          _NavItemData('Platform Fees', Icons.receipt_rounded, '/admin/fees'),
        ],
        'events': [
          _NavItemData(
            'Events & Meetings',
            Icons.event_rounded,
            '/admin/events',
          ),
          _NavItemData(
            'CTI Short Courses',
            Icons.school_rounded,
            '/admin/cti-courses',
          ),
          _NavItemData(
            'Photo Gallery',
            Icons.photo_library_rounded,
            '/admin/gallery',
          ),
        ],
        'surveys': [
          _NavItemData(
            'Surveys',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ],
        'audit_log': [
          _NavItemData('Audit Log', Icons.history_rounded, '/admin/audit-log'),
        ],
      };

      final permittedItems = <_NavItemData>[];
      final orderedKeys = [
        'members',
        'compliance',
        'documents',
        'announcements',
        'schedules',
        'intelligence',
        'tickets',
        'messaging',
        'notifications',
        'payments',
        'analytics',
        'fees',
        'events',
        'surveys',
        'audit_log',
      ];
      for (final key in orderedKeys) {
        if (auth.hasPermission(key)) {
          permittedItems.addAll(allAdminItems[key] ?? []);
        }
      }

      final showDashboard = auth.hasPermission('dashboard');

      sections = [
        if (showDashboard)
          _buildSection(context, 'Overview', currentRoute, [
            _NavItemData(
              'Dashboard',
              Icons.grid_view_rounded,
              '/admin/dashboard',
            ),
          ]),
        if (permittedItems.isNotEmpty)
          _buildSection(context, 'My modules', currentRoute, permittedItems),
      ];
    } else {
      final status = authService.membershipStatus.toLowerCase().trim();
      final isPending = status != 'active' && status != 'approved';

      if (isPending) {
        sections = [
          _buildSection(context, 'Application onboarding', currentRoute, [
            _NavItemData(
              'Complete Application',
              Icons.assignment_turned_in_rounded,
              '/application-documents',
            ),
            _NavItemData(
              'Payment & Fees',
              Icons.payment_rounded,
              '/payments',
            ),
          ]),
        ];
      } else {
        sections = [
          _buildSection(context, 'Main', currentRoute, [
            _NavItemData('Dashboard', Icons.home_rounded, '/dashboard'),
          ]),
          _buildSection(context, 'Services', currentRoute, [
            _NavItemData(
              'Membership',
              Icons.card_membership_rounded,
              '/membership-services',
            ),
            _NavItemData(
              'Compliance',
              Icons.verified_user_rounded,
              '/compliance',
            ),
            _NavItemData(
              'Courses',
              Icons.school_rounded,
              '/courses',
            ),
            _NavItemData(
              'Payments',
              Icons.receipt_long_rounded,
              '/payment-history',
            ),
            _NavItemData(
                'Tasks', Icons.task_alt_rounded, '/tasks'),
            _NavItemData(
              'Directory',
              Icons.people_alt_rounded,
              '/networking',
            ),
            _NavItemData(
              'Messages',
              Icons.chat_bubble_outline_rounded,
              '/messaging',
            ),
            _NavItemData('Events', Icons.event_rounded, '/events'),
            _NavItemData(
              'Surveys',
              Icons.how_to_vote_rounded,
              '/surveys',
            ),
            _NavItemData(
              'Support',
              Icons.support_agent_rounded,
              '/engagement',
            ),
          ]),
          _buildSection(context, 'Resources', currentRoute, [
            _NavItemData(
                'Insights', Icons.analytics_rounded, '/live-data'),
            _NavItemData(
              'Vessels',
              Icons.directions_boat_rounded,
              '/vessel-movements',
            ),
          ]),
        ];
      }
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        ...sections,
        Divider(
          indent: _isSidebarCollapsed ? 12 : 20,
          endIndent: _isSidebarCollapsed ? 12 : 20,
          color: dividerColor,
        ),
        if (isPending)
          _navTile(
            context,
            'Sign out',
            Icons.logout_rounded,
            '/login',
            currentRoute,
            onTapOverride: () async {
              await authService.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          )
        else
          _navTile(
            context,
            'Settings',
            Icons.settings_rounded,
            (isAdmin || role == 'sub_admin') ? '/admin/settings' : '/settings',
            currentRoute,
          ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String currentRoute,
    List<_NavItemData> items,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF4D2D20)
        : CubagColors.sand;

    if (_isSidebarCollapsed) {
      return Column(
        children: [
          ...items.map(
            (item) => _navTile(
              context,
              item.title,
              item.icon,
              item.route,
              currentRoute,
            ),
          ),
          Divider(indent: 12, endIndent: 12, color: dividerColor, height: 16),
        ],
      );
    }
    final headerColor =
        isDark ? const Color(0xFF9E8F84) : const Color(0xFF7A6B60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: headerColor,
            ),
          ),
        ),
        ...items.map(
          (item) => _navTile(
            context,
            item.title,
            item.icon,
            item.route,
            currentRoute,
            badge: item.route == '/admin/compliance' ? _complianceBadge : 0,
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _navTile(
    BuildContext context,
    String title,
    IconData icon,
    String route,
    String current, {
    int badge = 0,
    VoidCallback? onTapOverride,
  }) {
    final active =
        current == route || (route != '/' && current.startsWith(route));
    const orangeCTA = CubagColors.action;
    const primaryBrown = Color(0xFF6B3E26);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeBg = isDark
        ? primaryBrown.withAlpha(40)
        : primaryBrown.withAlpha(18);
    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03);
    final activeIconColor = isDark ? CubagColors.action : primaryBrown;
    final inactiveIconColor = isDark
        ? const Color(0xFF5F6B7E)
        : CubagColors.muted;
    final activeTextColor = isDark ? Colors.white : primaryBrown;
    final inactiveTextColor = isDark
        ? CubagColors.lineStrong
        : CubagColors.ink;

    final tileContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            if (!_isSidebarCollapsed) {
              setState(() {
                _isSidebarCollapsed = true;
              });
            }
            if (onTapOverride != null) {
              onTapOverride();
            } else {
              context.go(route);
            }
            if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
              Navigator.pop(context);
            }
          },
          borderRadius: BorderRadius.circular(8),
          hoverColor: hoverBg,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 0 : 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: _isSidebarCollapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      color: active ? activeIconColor : inactiveIconColor,
                      size: 20,
                    ),
                    if (!_isSidebarCollapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: active ? activeTextColor : inactiveTextColor,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w500,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // FIX #6: Compliance unread badge
                      if (badge > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: orangeCTA,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : badge.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (active)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3.5,
                    decoration: const BoxDecoration(
                      color: orangeCTA,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (_isSidebarCollapsed) {
      return Tooltip(
        message: title,
        preferBelow: false,
        verticalOffset: 20,
        margin: const EdgeInsets.only(left: 8),
        child: tileContent,
      );
    }
    return tileContent;
  }
}

class _NavItemData {
  final String title;
  final IconData icon;
  final String route;
  _NavItemData(this.title, this.icon, this.route);
}

class _NotificationAutoCloseTray extends StatefulWidget {
  final VoidCallback onExit;
  final Widget child;
  const _NotificationAutoCloseTray({required this.onExit, required this.child});

  @override
  State<_NotificationAutoCloseTray> createState() => _NotificationAutoCloseTrayState();
}

class _NotificationAutoCloseTrayState extends State<_NotificationAutoCloseTray> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _timer?.cancel();
      },
      onExit: (_) {
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            widget.onExit();
          }
        });
      },
      child: widget.child,
    );
  }
}
