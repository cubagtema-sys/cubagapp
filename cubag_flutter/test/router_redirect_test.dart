import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit tests for router redirect logic.
/// Tests the same logic used in router.dart without needing the full GoRouter.

// Mirror the route helpers from router.dart
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
};

bool _isPublic(String path) =>
    _publicRoutes.contains(path) || path.startsWith('/verify-member/');

bool _isAdminRoute(String path) => path.startsWith('/admin/');

/// Simulates the redirect logic from router.dart
Future<String?> simulateRedirect({
  required String location,
  required bool isWeb,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final bool loggedIn = prefs.getString('cubag_token') != null;
  final role = prefs.getString('cubag_role');

  if (!loggedIn && !_isPublic(location)) return '/login';
  if (loggedIn && _isAdminRoute(location)) {
    if (role != 'admin') return '/dashboard';
    if (!isWeb) return '/admin-unavailable';
  }
  if (loggedIn && (location == '/' || location == '/login')) {
    if (role == 'admin') {
      return isWeb ? '/admin/dashboard' : '/admin-unavailable';
    }
    return '/dashboard';
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Route Guards — Unauthenticated', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'unauthenticated user accessing /dashboard redirects to /login',
      () async {
        final result = await simulateRedirect(
          location: '/dashboard',
          isWeb: true,
        );
        expect(result, equals('/login'));
      },
    );

    test(
      'unauthenticated user accessing /admin/dashboard redirects to /login',
      () async {
        final result = await simulateRedirect(
          location: '/admin/dashboard',
          isWeb: true,
        );
        expect(result, equals('/login'));
      },
    );

    test('unauthenticated user can access /login without redirect', () async {
      final result = await simulateRedirect(location: '/login', isWeb: true);
      expect(result, isNull);
    });

    test('unauthenticated user can access / without redirect', () async {
      final result = await simulateRedirect(location: '/', isWeb: true);
      expect(result, isNull);
    });

    test(
      'unauthenticated user can access /register without redirect',
      () async {
        final result = await simulateRedirect(
          location: '/register',
          isWeb: true,
        );
        expect(result, isNull);
      },
    );

    test(
      'unauthenticated user can access /public-services without redirect',
      () async {
        final result = await simulateRedirect(
          location: '/public-services',
          isWeb: true,
        );
        expect(result, isNull);
      },
    );

    test(
      'unauthenticated user can access /verify-member/:id without redirect',
      () async {
        final result = await simulateRedirect(
          location: '/verify-member/abc123',
          isWeb: true,
        );
        expect(result, isNull);
      },
    );

    test(
      'unauthenticated user accessing /payments redirects to /login',
      () async {
        final result = await simulateRedirect(
          location: '/payments',
          isWeb: true,
        );
        expect(result, equals('/login'));
      },
    );
  });

  group('Route Guards — Authenticated Member', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'cubag_token': 'member-token',
        'cubag_role': 'member',
      }),
    );

    test('member accessing / redirects to /dashboard', () async {
      final result = await simulateRedirect(location: '/', isWeb: true);
      expect(result, equals('/dashboard'));
    });

    test('member accessing /login redirects to /dashboard', () async {
      final result = await simulateRedirect(location: '/login', isWeb: true);
      expect(result, equals('/dashboard'));
    });

    test('member accessing /dashboard gets no redirect', () async {
      final result = await simulateRedirect(
        location: '/dashboard',
        isWeb: true,
      );
      expect(result, isNull);
    });

    test('member accessing /admin/dashboard redirects to /dashboard', () async {
      final result = await simulateRedirect(
        location: '/admin/dashboard',
        isWeb: true,
      );
      expect(result, equals('/dashboard'));
    });

    test('member accessing /admin/members redirects to /dashboard', () async {
      final result = await simulateRedirect(
        location: '/admin/members',
        isWeb: true,
      );
      expect(result, equals('/dashboard'));
    });

    test('member accessing /payments gets no redirect', () async {
      final result = await simulateRedirect(location: '/payments', isWeb: true);
      expect(result, isNull);
    });

    test('member accessing /license-renewal gets no redirect', () async {
      final result = await simulateRedirect(
        location: '/license-renewal',
        isWeb: true,
      );
      expect(result, isNull);
    });
  });

  group('Route Guards — Authenticated Admin', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'cubag_token': 'admin-token',
        'cubag_role': 'admin',
      }),
    );

    test('admin accessing / on web redirects to /admin/dashboard', () async {
      final result = await simulateRedirect(location: '/', isWeb: true);
      expect(result, equals('/admin/dashboard'));
    });

    test(
      'admin accessing /login on web redirects to /admin/dashboard',
      () async {
        final result = await simulateRedirect(location: '/login', isWeb: true);
        expect(result, equals('/admin/dashboard'));
      },
    );

    test(
      'admin accessing / on mobile redirects to /admin-unavailable',
      () async {
        final result = await simulateRedirect(location: '/', isWeb: false);
        expect(result, equals('/admin-unavailable'));
      },
    );

    test('admin accessing /admin/dashboard on web gets no redirect', () async {
      final result = await simulateRedirect(
        location: '/admin/dashboard',
        isWeb: true,
      );
      expect(result, isNull);
    });

    test(
      'admin accessing /admin/dashboard on mobile redirects to /admin-unavailable',
      () async {
        final result = await simulateRedirect(
          location: '/admin/dashboard',
          isWeb: false,
        );
        expect(result, equals('/admin-unavailable'));
      },
    );

    test('admin accessing member /dashboard gets no redirect', () async {
      final result = await simulateRedirect(
        location: '/dashboard',
        isWeb: true,
      );
      expect(result, isNull);
    });
  });

  group('Route Helper Functions', () {
    test('_isPublic identifies all public routes', () {
      expect(_isPublic('/'), isTrue);
      expect(_isPublic('/login'), isTrue);
      expect(_isPublic('/register'), isTrue);
      expect(_isPublic('/forgot-password'), isTrue);
      expect(_isPublic('/public-services'), isTrue);
      expect(_isPublic('/verify-member/abc'), isTrue);
    });

    test('_isPublic rejects protected routes', () {
      expect(_isPublic('/dashboard'), isFalse);
      expect(_isPublic('/payments'), isFalse);
      expect(_isPublic('/admin/dashboard'), isFalse);
      expect(_isPublic('/profile'), isFalse);
    });

    test('_isAdminRoute identifies admin paths', () {
      expect(_isAdminRoute('/admin/dashboard'), isTrue);
      expect(_isAdminRoute('/admin/members'), isTrue);
      expect(_isAdminRoute('/admin/settings'), isTrue);
    });

    test('_isAdminRoute rejects non-admin paths', () {
      expect(_isAdminRoute('/dashboard'), isFalse);
      expect(_isAdminRoute('/login'), isFalse);
      expect(_isAdminRoute('/payments'), isFalse);
    });
  });
}
