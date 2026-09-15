import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/session_storage.dart';
import '../services/telemetry_service.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

import '../pages/public_home_page.dart';
import '../pages/guest_service_request_page.dart';
import '../pages/complaints_portal_page.dart';
import '../pages/membership_services_page.dart';

// ── Always-loaded pages ──────────────────────────────────────────────────────
import '../pages/splash_page.dart';
import '../pages/landing_page.dart';
import '../pages/login_page.dart';
import '../pages/register_page.dart';
import '../pages/forgot_password_page.dart';
import '../pages/reset_password_page.dart';
import '../pages/verify_email_page.dart';
import '../pages/otp_verification_page.dart';
import '../pages/verify_member_page.dart';
import '../pages/member_detail_page.dart';
import '../pages/public_directory_page.dart';
import '../pages/dashboard_page.dart';
import '../components/user_shell.dart';
import '../pages/application_documents_page.dart';

// ── Member pages ────────────────────────────────────────────────────────────
import '../pages/announcements_page.dart';
import '../pages/cargo_schedules_page.dart';
import '../pages/engagement_page.dart';
import '../pages/events_page.dart';
import '../pages/compliance_centre_page.dart';
import '../pages/live_data_page.dart';
import '../pages/messaging_page.dart';
import '../pages/networking_page.dart';
import '../pages/mobile_menu_page.dart';
import '../pages/notifications_page.dart';
import '../pages/payment_history_page.dart';
import '../pages/payments_page.dart';
import '../pages/profile_page.dart';
import '../pages/settings_page.dart';
import '../pages/surveys_page.dart';
import '../pages/tasks_page.dart';
import '../pages/vessel_movements_page.dart';
import '../pages/cti_courses_page.dart';
import '../pages/license_renewal_page.dart';

// ── Admin pages ─────────────────────────────────────────────────────────────
import '../pages/admin_analytics_page.dart';
import '../pages/admin_announcements_page.dart';
import '../pages/admin_audit_log_page.dart';
import '../pages/admin_dashboard_page.dart';
import '../pages/admin_documents_page.dart';
import '../pages/admin_document_rules_page.dart';
import '../pages/admin_events_page.dart';
import '../pages/admin_event_attendees_page.dart';
import '../pages/admin_fees_page.dart';
import '../pages/admin_ports_page.dart';
import '../pages/admin_port_news_page.dart';
import '../pages/admin_cti_courses_page.dart';
import '../pages/admin_gallery_page.dart';
import '../pages/admin_intelligence_page.dart';
import '../pages/admin_license_renewal_page.dart';
import '../pages/admin_members_page.dart';
import '../pages/admin_payments_page.dart';
import '../pages/admin_payment_settings_page.dart';
import '../pages/admin_settings_page.dart';
import '../pages/admin_surveys_page.dart';
import '../pages/admin_tasks_page.dart';
import '../pages/admin_tickets_page.dart';
import '../pages/admin_complaints_page.dart';
import '../pages/admin_sub_admins_page.dart';
import '../pages/admin_compliance_page.dart';

/// Routes accessible without a JWT token.
const _publicRoutes = {
  '/',
  '/splash',
  '/landing',
  '/login',
  '/register',
  '/forgot-password',
  '/reset-password',
  '/verify-email',
  '/otp-verification',
  '/public-services',
  '/guest-services',
  '/directory',
  '/members-directory',
  '/complaints',
  '/track-complaint',
};

bool _isPublic(String path) =>
    _publicRoutes.contains(path) ||
    path.startsWith('/verify-member/') ||
    path.startsWith('/member-detail/') ||
    path.startsWith('/guest-services') ||
    path.startsWith('/complaints');

bool _isAdminRoute(String path) => path.startsWith('/admin/');

// ── Pre-loader (no-op retained for backwards compatibility) ──────────────────
Future<void> preloadMemberLibraries() async {}
Future<void> preloadAdminLibraries() async {}

// ── Router ───────────────────────────────────────────────────────────────────
final GoRouter appRouter = GoRouter(
  initialLocation: kIsWeb ? '/' : '/splash',
  refreshListenable: AuthService(),
  observers: [TelemetryRouteObserver()],
  redirect: (context, state) {
    final storage = SessionStorage.instance;
    final auth = AuthService();
    final token = storage.getStringSync('cubag_token');
    final role = storage.getStringSync('cubag_role') ?? auth.userRole;

    final bool loggedIn = (token != null && token.isNotEmpty) || auth.isAuthenticated;
    final String loc = state.matchedLocation;

    final bool isAdminRole = role == 'admin' || role == 'sub_admin' || role == 'super_admin';

    if (!loggedIn && !_isPublic(loc)) return '/login';

    // ── Messaging Route Synchronizer: Admin -> /admin/messages, Member -> /messaging ──
    if (loggedIn) {
      if (isAdminRole && (loc == '/messaging' || loc.startsWith('/messaging'))) {
        final q = state.uri.hasQuery ? '?${state.uri.query}' : '';
        return '/admin/messages$q';
      }
      if (!isAdminRole && (loc == '/admin/messages' || loc == '/admin/messaging')) {
        final q = state.uri.hasQuery ? '?${state.uri.query}' : '';
        return '/messaging$q';
      }
    }

    if (loggedIn && _isAdminRoute(loc)) {
      if (!isAdminRole) return '/dashboard';
      if (!kIsWeb) return '/admin-unavailable';
    }

    // ── Member Status Guard: Lock unapproved or unpaid members to onboarding ──
    if (loggedIn && role == 'member') {
      final status = (storage.getStringSync('cubag_member_status') ??
              storage.getStringSync('cubag_status') ??
              auth.membershipStatus)
          .toLowerCase()
          .trim();
      final regPaidStr = storage.getStringSync('cubag_registration_fee_paid');
      final bool isRegFeePaid = regPaidStr == 'true' || auth.isRegistrationFeePaid;
      final bool isDocApproved = status == 'active' || status == 'approved';

      // You can ONLY access the dashboard if Admin has approved documents AND Registration Fee is paid
      final bool canAccessDashboard = isDocApproved && isRegFeePaid;

      if (!canAccessDashboard) {
        final bool isAllowedOnboardingRoute = loc == '/splash' ||
            loc == '/' ||
            loc == '/landing' ||
            loc == '/application-documents' ||
            loc == '/compliance' ||
            loc.startsWith('/compliance/') ||
            loc == '/payments' ||
            loc.startsWith('/payments/') ||
            loc == '/settings' ||
            loc == '/profile' ||
            loc == '/login' ||
            loc == '/otp-verification' ||
            loc == '/verify-email';
        if (!isAllowedOnboardingRoute) {
          return '/application-documents';
        }
      }
    }

    if (loggedIn && (loc == '/login' || loc == '/register')) {
      if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
        if (!kIsWeb) return '/admin-unavailable';
        if (role == 'sub_admin') {
          final perms = storage.getStringListSync('cubag_permissions') ?? auth.permissions;
          if (!perms.contains('dashboard')) {
            if (perms.contains('announcements')) return '/admin/announcements';
            if (perms.contains('members')) return '/admin/members';
            if (perms.contains('events')) return '/admin/events';
            if (perms.contains('compliance')) return '/admin/compliance';
            if (perms.contains('intelligence')) return '/admin/intelligence';
            if (perms.contains('messaging')) return '/admin/messages';
            if (perms.isNotEmpty) return '/admin/${perms.first}';
          }
        }
        return '/admin/dashboard';
      }
      final status = (storage.getStringSync('cubag_member_status') ??
              storage.getStringSync('cubag_status') ??
              auth.membershipStatus)
          .toLowerCase()
          .trim();
      final regPaidStr = storage.getStringSync('cubag_registration_fee_paid');
      final bool isRegFeePaid = regPaidStr == 'true' || auth.isRegistrationFeePaid;
      final bool isDocApproved = status == 'active' || status == 'approved';
      final bool canAccessDashboard = isDocApproved && isRegFeePaid;

      if (!canAccessDashboard) {
        return '/application-documents';
      }
      return '/dashboard';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (c, s) => const SplashPage()),
    GoRoute(path: '/', builder: (c, s) => const PublicHomePage()),
    GoRoute(path: '/landing', builder: (c, s) => const LandingPage()),
    GoRoute(path: '/login', builder: (c, s) => const LoginPage()),
    GoRoute(path: '/register', builder: (c, s) => const RegisterPage()),
    GoRoute(
      path: '/forgot-password',
      builder: (c, s) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (c, s) => ResetPasswordPage(
        token: s.uri.queryParameters['token'],
        email: s.uri.queryParameters['email'],
      ),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (c, s) => VerifyEmailPage(token: s.uri.queryParameters['token']),
    ),
    GoRoute(
      path: '/otp-verification',
      builder: (c, s) =>
          OTPVerificationPage(email: s.uri.queryParameters['email']),
    ),
    GoRoute(
      path: '/verify-member/:id',
      builder: (c, s) => VerifyMemberPage(memberId: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/member-detail/:id',
      builder: (c, s) => MemberDetailPage(memberId: s.pathParameters['id']),
    ),
    GoRoute(path: '/directory', builder: (c, s) => const PublicDirectoryPage()),
    GoRoute(
      path: '/members-directory',
      builder: (c, s) => const PublicDirectoryPage(),
    ),
    GoRoute(
      path: '/public-services',
      builder: (c, s) => const PublicHomePage(),
    ),
    GoRoute(
      path: '/guest-services',
      builder: (c, s) => GuestServiceRequestPage(
        initialService: s.uri.queryParameters['service'],
        initialCourse: s.uri.queryParameters['course'] ??
            s.uri.queryParameters['course_name'] ??
            s.uri.queryParameters['course_title'],
      ),
    ),
    GoRoute(
      path: '/guest-services/:service',
      builder: (c, s) => GuestServiceRequestPage(
        initialService: s.pathParameters['service'],
        initialCourse: s.uri.queryParameters['course'] ??
            s.uri.queryParameters['course_name'] ??
            s.uri.queryParameters['course_title'],
      ),
    ),
    GoRoute(
      path: '/complaints',
      builder: (c, s) => ComplaintsPortalPage(
        initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/complaints/track/:id',
      builder: (c, s) => ComplaintsPortalPage(
        initialTab: 1,
        initialTrackingId: s.pathParameters['id'],
      ),
    ),
    GoRoute(
      path: '/track-complaint',
      builder: (c, s) => const ComplaintsPortalPage(initialTab: 1),
    ),
    GoRoute(
      path: '/admin-unavailable',
      builder: (c, s) => const _AdminUnavailablePage(),
    ),

    // ── Member pages ─────────────────────────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          UserShell(child: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: DashboardPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/announcements',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AnnouncementsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cargo-schedules',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CargoSchedulesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/engagement',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: EngagementPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/events',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: EventsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/compliance',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: ComplianceCentrePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/membership-services',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: MembershipServicesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/live-data',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: LiveDataPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/messaging',
              pageBuilder: (c, s) => NoTransitionPage(
                child: MessagingPage(
                  initialUserId: s.uri.queryParameters['id'],
                  initialUserName: s.uri.queryParameters['name'],
                  initialUserCompany: s.uri.queryParameters['company'],
                ),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/networking',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: NetworkingPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/notifications',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: NotificationsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/menu',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: MobileMenuPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/payment-history',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: PaymentHistoryPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/payments',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: PaymentsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: ProfilePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/surveys',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: SurveysPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              pageBuilder: (c, s) => const NoTransitionPage(child: TasksPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/vessel-movements',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: VesselMovementsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/courses',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CtiCoursesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cti-courses',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CtiCoursesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/license-renewal',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: LicenseRenewalPage()),
            ),
          ],
        ),
      ],
    ),

    // ── Pending member document upload ─────────────────────────────────────
    GoRoute(
      path: '/application-documents',
      builder: (c, s) => const ApplicationDocumentsPage(),
    ),

    // ── Admin pages ──────────────────────────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => navigationShell,
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/announcements',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminAnnouncementsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/notifications',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminAnnouncementsPage()),
            ),
          ],
        ),

        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/analytics',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminAnalyticsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/audit-log',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminAuditLogPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/dashboard',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminDashboardPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/events',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminEventsPage()),
            ),
            GoRoute(
              path: '/admin/events/:id/attendees',
              pageBuilder: (context, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: AdminEventAttendeesPage(
                  eventId: int.parse(state.pathParameters['id'] ?? '0'),
                  title: state.uri.queryParameters['title'] ?? 'Event',
                ),
                transitionDuration: const Duration(milliseconds: 200),
                reverseTransitionDuration: const Duration(milliseconds: 150),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: child,
                        ),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/fees',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminFeesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/ports',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminPortsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/port-news',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminPortNewsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/cti-courses',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminCtiCoursesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/gallery',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminGalleryPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/intelligence',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminIntelligencePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/license-renewal',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminLicenseRenewalPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/compliance',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminCompliancePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/members',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminMembersPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/documents',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminDocumentsPage()),
              routes: [
                GoRoute(
                  path: ':memberId',
                  pageBuilder: (c, s) => NoTransitionPage(
                    child: AdminMemberDocumentsPage(
                      memberId: s.pathParameters['memberId']!,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/document-rules',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminDocumentRulesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/payments',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminPaymentsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/payment-settings',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminPaymentSettingsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/settings',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminSettingsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/surveys',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminSurveysPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/tasks',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminTasksPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/tickets',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminTicketsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/complaints',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminComplaintsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/sub-admins',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AdminSubAdminsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/messages',
              pageBuilder: (c, s) => NoTransitionPage(
                child: MessagingPage(
                  initialUserId: s.uri.queryParameters['id'],
                  initialUserName: s.uri.queryParameters['name'],
                  initialUserCompany: s.uri.queryParameters['company'],
                ),
              ),
            ),
            GoRoute(
              path: '/admin/messaging',
              pageBuilder: (c, s) => NoTransitionPage(
                child: MessagingPage(
                  initialUserId: s.uri.queryParameters['id'],
                  initialUserName: s.uri.queryParameters['name'],
                  initialUserCompany: s.uri.queryParameters['company'],
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

// ── Admin Unavailable (mobile) ───────────────────────────────────────────────
class _AdminUnavailablePage extends StatelessWidget {
  const _AdminUnavailablePage();
  @override
  Widget build(BuildContext context) => _AdminUnavailableBody();
}

class _AdminUnavailableBody extends StatefulWidget {
  @override
  State<_AdminUnavailableBody> createState() => _AdminUnavailableBodyState();
}

class _AdminUnavailableBodyState extends State<_AdminUnavailableBody> {
  String? _email;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final email = await SessionStorage.instance.getString('cubag_email');
    if (mounted) setState(() => _email = email);
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFfff7ed),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFF5000).withAlpha(40),
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.desktop_windows_rounded,
                          size: 48,
                          color: Color(0xFFFF5000),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Admin Portal Restricted',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A0F0A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'To maintain security and full functionality, the admin dashboard is only accessible via a desktop web browser.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          color: Color(0xFF64748b),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 40),
                      if (_email != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFf8fafc),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFe2e8f0),
                                radius: 18,
                                child: Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Color(0xFF64748b),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'LOGGED IN AS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF94a3b8),
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      _email!,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF281710),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFfff7ed),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFF5000).withAlpha(50),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.link,
                              size: 18,
                              color: Color(0xFFFF5000),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'cubag-platform.web.app',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF5000),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _loggingOut ? null : _logout,
                          icon: _loggingOut
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.logout_rounded, size: 20),
                          label: Text(
                            _loggingOut ? 'Signing out...' : 'Sign Out',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5000),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
