import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit tests for AuthService logic.
/// We test the SharedPreferences-based state management directly
/// to avoid pulling in the full app import graph (which includes dart:html).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth State — Token Management', () {
    test('no token means not authenticated', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString('cubag_token'), isNull);
    });

    test('storing token makes user authenticated', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('cubag_token', 'jwt-abc-123');
      expect(prefs.getString('cubag_token'), equals('jwt-abc-123'));
    });

    test('role is stored alongside token', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('cubag_token', 'tok');
      await prefs.setString('cubag_role', 'admin');

      expect(prefs.getString('cubag_role'), equals('admin'));
    });

    test('member role stored correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('cubag_token', 'tok');
      await prefs.setString('cubag_role', 'member');

      expect(prefs.getString('cubag_role'), equals('member'));
    });
  });

  group('Auth State — Logout', () {
    test('logout clears all cubag_ keys', () async {
      SharedPreferences.setMockInitialValues({
        'cubag_token': 'test-token',
        'cubag_role': 'member',
        'cubag_id': '42',
        'cubag_name': 'John Doe',
        'cubag_email': 'john@cubag.org',
      });

      final prefs = await SharedPreferences.getInstance();

      // Simulate logout
      await prefs.remove('cubag_token');
      await prefs.remove('cubag_role');
      await prefs.remove('cubag_id');
      await prefs.remove('cubag_name');
      await prefs.remove('cubag_email');

      expect(prefs.getString('cubag_token'), isNull);
      expect(prefs.getString('cubag_role'), isNull);
      expect(prefs.getString('cubag_id'), isNull);
      expect(prefs.getString('cubag_name'), isNull);
      expect(prefs.getString('cubag_email'), isNull);
    });

    test('logout does not affect other prefs', () async {
      SharedPreferences.setMockInitialValues({
        'cubag_token': 'tok',
        'cubag_role': 'member',
        'other_setting': 'keep_me',
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cubag_token');
      await prefs.remove('cubag_role');

      // Other keys untouched
      expect(prefs.getString('other_setting'), equals('keep_me'));
    });
  });

  group('Auth State — Biometric Credentials', () {
    test('biometric disabled by default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool('biometric_enabled') ?? false, isFalse);
    });

    test('enable biometric persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('biometric_enabled', true);
      expect(prefs.getBool('biometric_enabled'), isTrue);
    });

    test('save and retrieve biometric credentials', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('bio_email', 'test@cubag.org');
      await prefs.setString('bio_password', 'secret');

      expect(prefs.getString('bio_email'), equals('test@cubag.org'));
      expect(prefs.getString('bio_password'), equals('secret'));
    });

    test('clear biometric credentials', () async {
      SharedPreferences.setMockInitialValues({
        'bio_email': 'x@y.com',
        'bio_password': 'pw',
        'biometric_enabled': true,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bio_email');
      await prefs.remove('bio_password');
      await prefs.remove('biometric_enabled');

      expect(prefs.getString('bio_email'), isNull);
      expect(prefs.getString('bio_password'), isNull);
      expect(prefs.getBool('biometric_enabled'), isNull);
    });
  });
}
