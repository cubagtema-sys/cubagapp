import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../components/admin_search_delegate.dart';
import '../components/member_search_delegate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_logo.dart';
import '../utils/app_logger.dart';
import '../utils/session_storage.dart';

class AppLayout extends StatefulWidget {
  final Widget child;
  final String title;
  final bool hideSearch;
  final bool scrollable;

  const AppLayout({
    super.key,
    required this.child,
    required this.title,
    this.hideSearch = true,
    this.scrollable = true,
  });

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  bool _isSidebarCollapsed = false;
  static int _cachedComplianceBadge = 0;
  static DateTime? _lastBadgeFetch;
  int _complianceBadge = _cachedComplianceBadge;

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
    final isDesktop = size.width > 800;
    final isSmall = size.width < 600;
    final primary = Theme.of(context).primaryColor;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isThemeDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFF8F4F0),
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: primary,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleSpacing: isSmall ? 16 : 24,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Row(
                children: [
                  const AppLogo(size: 28, borderRadius: 6, showShadow: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: isSmall ? 20 : 22,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                _buildNotificationIcon(
                  context,
                  authService.userRole,
                  isSmall,
                  isDark: true,
                ),
                const SizedBox(width: 4),
                Consumer<AuthService>(
                  builder: (context, auth, _) =>
                      _buildProfileMenu(context, auth, isSmall, isDark: true),
                ),
                SizedBox(width: 12 + MediaQuery.of(context).padding.right),
              ],
            ),
      bottomNavigationBar: isDesktop
          ? null
          : _buildBottomNav(context, authService.userRole, currentRoute),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context, authService.userRole),
          Expanded(
            child: isDesktop
                ? Column(
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
                  )
                : Container(
                    color: primary,
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F4F0),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: SelectionArea(
                          child: widget.scrollable
                              ? SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: widget.child,
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: widget.child,
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

  Widget _buildNotificationIcon(
    BuildContext context,
    String? role,
    bool isSmall, {
    bool isDark = false,
  }) {
    final targetRoute = (role == 'admin' || role == 'sub_admin' || role == 'super_admin')
        ? '/admin/notifications'
        : '/notifications';
    final iconColor = isDark ? Colors.white : const Color(0xFF64748b);
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final textColor = isThemeDark ? Colors.white : const Color(0xFF1A0F0A);
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);

    return Consumer<NotificationService>(
      builder: (context, notificationService, _) {
        final unreadCount = notificationService.unreadCount;
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
                  size: isSmall ? 22 : 26,
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
                        color: const Color(0xFFef4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
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
                        style: GoogleFonts.outfit(
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
          offset: const Offset(0, 48),
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
          itemBuilder: (context) {
            final recent = notificationService.recentNotifications;
            
            return [
              PopupMenuItem<String>(
                enabled: false,
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notifications',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFef4444).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount New',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFef4444),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
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
              if (recent.isEmpty)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    child: Text(
                      'No recent notifications',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isThemeDark ? Colors.white70 : const Color(0xFF64748b),
                      ),
                    ),
                  ),
                )
              else
                ...recent.map((n) {
                  final isRead = n['read'] == true;
                  return PopupMenuItem<String>(
                    value: 'notif_${n['id']}',
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isRead ? Colors.transparent : const Color(0xFFFF5000),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n['title']?.toString() ?? '',
                                  style: GoogleFonts.outfit(
                                    fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  n['message']?.toString() ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: isThemeDark ? Colors.white70 : const Color(0xFF64748b),
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
                }),
              PopupMenuItem<String>(
                enabled: false,
                height: 1,
                child: Divider(color: borderThemeColor, height: 1),
              ),
              PopupMenuItem<String>(
                value: 'view_all',
                child: Container(
                  width: 280,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'View All Notifications',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: const Color(0xFFFF5000),
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
    final borderColor = isDark ? Colors.white30 : const Color(0xFFe2e8f0);
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final textColor = isThemeDark ? Colors.white : const Color(0xFF1A0F0A);
    final subTextColor = isThemeDark ? Colors.white70 : const Color(0xFF64748b);
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: SizedBox(
          width: isSmall ? 28 : 32,
          height: isSmall ? 28 : 32,
          child: ClipOval(
            child: photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: isSmall ? 28 : 32,
                    height: isSmall ? 28 : 32,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: isThemeDark
                          ? const Color(0xFF3E2418)
                          : const Color(0xFFf1f5f9),
                      child: Icon(
                        Icons.person_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                        size: isSmall ? 18 : 20,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: isThemeDark
                          ? const Color(0xFF3E2418)
                          : const Color(0xFFf1f5f9),
                      child: Icon(
                        Icons.person_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                        size: isSmall ? 18 : 20,
                      ),
                    ),
                  )
                : Container(
                    color: isThemeDark
                        ? const Color(0xFF3E2418)
                        : const Color(0xFFf1f5f9),
                    child: Icon(
                      Icons.person_rounded,
                      color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                      size: isSmall ? 18 : 20,
                    ),
                  ),
          ),
        ),
      ),
      offset: const Offset(0, 48),
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
              width: 170,
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                          style: GoogleFonts.outfit(
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
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isPending ? const Color(0xFFFF5000) : subTextColor,
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
                width: 170,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5000).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.assignment_turned_in_rounded,
                        size: 18,
                        color: Color(0xFFFF5000),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Complete Application',
                      style: GoogleFonts.outfit(
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
                width: 170,
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                      'My Profile',
                      style: GoogleFonts.outfit(
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
                width: 170,
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                      style: GoogleFonts.outfit(
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
              width: 170,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFef4444).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Color(0xFFef4444),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                      color: const Color(0xFFef4444),
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

  Widget _buildDesktopHeader(BuildContext context, AuthService authService) {
    final isAdmin =
        authService.userRole == 'admin' || authService.userRole == 'sub_admin';
    final isThemeDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isThemeDark ? const Color(0xFF281710) : Colors.white;
    final borderThemeColor = isThemeDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);
    final textColor = isThemeDark
        ? const Color(0xFFFFF8F3)
        : const Color(0xFF1A0F0A);
    final iconColor = isThemeDark
        ? const Color(0xFFC8ADA0)
        : const Color(0xFF64748b);
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
          if (!isAdmin) ...[
            const AppLogo(size: 32, borderRadius: 8, showShadow: false),
            const SizedBox(width: 12),
          ],
          Text(
            widget.title,
            style: GoogleFonts.outfit(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (!widget.hideSearch)
            IconButton(
              icon: Icon(Icons.search_rounded, color: iconColor),
              onPressed: () => showSearch(
                context: context,
                delegate: authService.userRole == 'admin'
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

  Widget _buildBottomNav(
    BuildContext context,
    String? role,
    String currentRoute,
  ) {
    final isAdmin = role == 'admin' || role == 'sub_admin' || role == 'super_admin';
    const orangeCTA = Color(0xFFFF5000);
    const brownNav = Color(0xFF6B3E26);

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

      if (currentRoute.startsWith('/networking')) {
        currentIndex = 1;
      } else if (currentRoute.startsWith('/compliance') ||
          currentRoute.startsWith('/payments')) {
        currentIndex = 2;
      } else if (currentRoute == '/menu') {
        currentIndex = 3;
      }
    }

    return BottomNavigationBar(
      currentIndex: currentIndex,
      selectedItemColor: orangeCTA,
      unselectedItemColor: brownNav.withAlpha(160),
      showUnselectedLabels: true,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF281710)
          : Colors.white,
      elevation: 16,
      onTap: (index) {
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
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(
          icon: Icon(Icons.group_rounded),
          label: 'Network',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.verified_user_rounded),
          label: 'Compliance',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.menu_rounded), label: 'Menu'),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, String? role) {
    final authService = Provider.of<AuthService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final borderThemeColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE8DED6);
    final textColor = isDark
        ? const Color(0xFFFFF8F3)
        : const Color(0xFF2B211D);
    final topPadding = MediaQuery.of(context).padding.top;
    final leftPadding = MediaQuery.of(context).padding.left;

    return AnimatedContainer(
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
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
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
      badgeBg = isDark ? const Color(0xFF4D2D20) : const Color(0xFFf1f5f9);
      badgeText = isDark ? const Color(0xFFcbd5e1) : const Color(0xFF475569);
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
          style: GoogleFonts.inter(
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
        : const Color(0xFFf1f5f9);
    final textColor = isDark ? Colors.white : const Color(0xFF1A0F0A);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF64748b);
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
              child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: Tooltip(
                  message: authService.userName ?? 'My Profile',
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
                                      : const Color(0xFFf1f5f9),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                                    size: 18,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: isDark
                                      ? const Color(0xFF3E2418)
                                      : const Color(0xFFf1f5f9),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                                    size: 18,
                                  ),
                                ),
                              )
                            : Container(
                                color: isDark
                                    ? const Color(0xFF3E2418)
                                    : const Color(0xFFf1f5f9),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: isDark ? Colors.white70 : const Color(0xFF94a3b8),
                                  size: 18,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF281710)
                    : const Color(0xFFf8fafc),
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
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          authService.userEmail ?? '',
                          style: GoogleFonts.inter(
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
                    message: 'Sign Out',
                    child: IconButton(
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: Color(0xFFef4444),
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
        : const Color(0xFFf1f5f9);

    List<Widget> sections = [];
    if (isAdmin) {
      sections = [
        _buildSection(context, 'CORE MANAGEMENT', currentRoute, [
          _NavItemData(
            'Dashboard',
            Icons.grid_view_rounded,
            '/admin/dashboard',
          ),
          _NavItemData('Members', Icons.people_alt_rounded, '/admin/members'),
          _NavItemData(
            'Registration',
            Icons.folder_copy_rounded,
            '/admin/documents',
          ),
          _NavItemData(
            'Document Rules',
            Icons.rule_folder_rounded,
            '/admin/document-rules',
          ),
          _NavItemData(
            'Renewal',
            Icons.verified_user_rounded,
            '/admin/compliance',
          ),
          _NavItemData(
            'Announcements',
            Icons.campaign_rounded,
            '/admin/announcements',
          ),
        ]),
        _buildSection(context, 'OPERATIONS & SUPPORT', currentRoute, [
          _NavItemData(
            'Port Operational News',
            Icons.feed_rounded,
            '/admin/port-news',
          ),
          _NavItemData(
            'Intelligence Hub',
            Icons.cell_tower_rounded,
            '/admin/intelligence',
          ),
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
          _NavItemData(
            'Messaging',
            Icons.chat_rounded,
            '/admin/messages',
          ),
        ]),
        _buildSection(context, 'FINANCIALS & RECORDS', currentRoute, [
          _NavItemData(
            'Financial Center',
            Icons.account_balance_wallet_rounded,
            '/admin/payments',
          ),
          _NavItemData(
            'Platform Analytics',
            Icons.analytics_rounded,
            '/admin/analytics',
          ),
          _NavItemData(
            'Payment Settings',
            Icons.payment_rounded,
            '/admin/payment-settings',
          ),
          _NavItemData('Platform Fees', Icons.receipt_rounded, '/admin/fees'),
        ]),
        _buildSection(context, 'ENGAGEMENT & EVENTS', currentRoute, [
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
          _NavItemData(
            'Surveys & Elections',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ]),
        _buildSection(context, 'ADMINISTRATION', currentRoute, [
          _NavItemData(
            'Sub-Admins',
            Icons.admin_panel_settings_rounded,
            '/admin/sub-admins',
          ),
          _NavItemData(
            'Ports of Operation',
            Icons.anchor_rounded,
            '/admin/ports',
          ),
          _NavItemData('Audit Log', Icons.history_rounded, '/admin/audit-log'),
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
            'Intelligence Hub',
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
          _NavItemData('Messaging', Icons.chat_rounded, '/admin/messages'),
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
            'Surveys & Elections',
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
          _buildSection(context, 'OVERVIEW', currentRoute, [
            _NavItemData(
              'Dashboard',
              Icons.grid_view_rounded,
              '/admin/dashboard',
            ),
          ]),
        if (permittedItems.isNotEmpty)
          _buildSection(context, 'MY MODULES', currentRoute, permittedItems),
      ];
    } else {
      final status = authService.membershipStatus.toLowerCase().trim();
      final isPending = status != 'active' && status != 'approved';

      if (isPending) {
        sections = [
          _buildSection(context, 'APPLICATION ONBOARDING', currentRoute, [
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
          _buildSection(context, 'MAIN', currentRoute, [
            _NavItemData('Dashboard', Icons.home_rounded, '/dashboard'),
          ]),
          _buildSection(context, 'SERVICES', currentRoute, [
            _NavItemData(
              'Membership Hub',
              Icons.card_membership_rounded,
              '/membership-services',
            ),
            _NavItemData(
              'Compliance Centre',
              Icons.verified_user_rounded,
              '/compliance',
            ),
            _NavItemData(
              'CTI Courses',
              Icons.school_rounded,
              '/courses',
            ),
            _NavItemData(
              'Payment Records',
              Icons.receipt_long_rounded,
              '/payment-history',
            ),
            _NavItemData(
                'Tasks & Compliance', Icons.task_alt_rounded, '/tasks'),
            _NavItemData(
              'Member Directory',
              Icons.people_alt_rounded,
              '/networking',
            ),
            _NavItemData(
              'Messaging',
              Icons.chat_bubble_outline_rounded,
              '/messaging',
            ),
            _NavItemData('Events', Icons.event_rounded, '/events'),
            _NavItemData(
              'Surveys & Elections',
              Icons.how_to_vote_rounded,
              '/surveys',
            ),
            _NavItemData(
              'Support & Inquiries',
              Icons.support_agent_rounded,
              '/engagement',
            ),
          ]),
          _buildSection(context, 'RESOURCES', currentRoute, [
            _NavItemData(
                'Live Logistics', Icons.analytics_rounded, '/live-data'),
            _NavItemData(
              'Vessel Movements',
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
            'Sign Out',
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
        : const Color(0xFFf1f5f9);

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94a3b8),
              letterSpacing: 1.2,
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
    const orangeCTA = Color(0xFFFF5000);
    const primaryBrown = Color(0xFF6B3E26);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeBg = isDark
        ? primaryBrown.withAlpha(40)
        : primaryBrown.withAlpha(18);
    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03);
    final activeIconColor = isDark ? const Color(0xFFFF5000) : primaryBrown;
    final inactiveIconColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF6F625B);
    final activeTextColor = isDark ? Colors.white : primaryBrown;
    final inactiveTextColor = isDark
        ? const Color(0xFFcbd5e1)
        : const Color(0xFF2B211D);

    final tileContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
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
                          style: GoogleFonts.outfit(
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
                            style: GoogleFonts.outfit(
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
