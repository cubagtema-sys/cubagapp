import 'package:cubag_flutter/utils/crash_scrub.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-04: what may leave the phone in a crash report.
void main() {
  group('CrashScrub.scrub', () {
    test('removes URL query strings (tokens)', () {
      final s = CrashScrub.scrub(
          'DioException GET https://api.cubag.org/api/v1/compliance/applications/5/certificate?token=abc.def&format=pdf failed');
      expect(s, isNot(contains('token=abc')));
      expect(s, contains('/certificate?[redacted]'));
    });

    test('removes bearer tokens and bare JWTs', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMCJ9.c2lnbmF0dXJlX2hlcmU';
      final s = CrashScrub.scrub('Authorization: Bearer $jwt; also $jwt');
      expect(s, isNot(contains('eyJ')));
    });

    test('removes e-mail addresses and phone / account numbers', () {
      final s = CrashScrub.scrub('user ama.mensah@example.com phone +233 24 123 4567 acct 1441002452360');
      expect(s, isNot(contains('ama.mensah')));
      expect(s, isNot(contains('4567')));
      expect(s, isNot(contains('1441002452360')));
      expect(s, contains('[email]'));
    });

    test('keeps short numbers such as status codes and ids readable', () {
      expect(CrashScrub.scrub('HTTP 500 on member 42'), 'HTTP 500 on member 42');
    });

    test('truncates very long messages', () {
      final s = CrashScrub.scrub('x' * 2000);
      expect(s.length, lessThanOrEqualTo(CrashScrub.maxLength + 1));
    });
  });

  group('PendingCrashBuffer', () {
    test('keeps errors raised before start-up, oldest first, then empties', () {
      final b = PendingCrashBuffer<int>();
      b..add(1)..add(2)..add(3);
      expect(b.drain(), [1, 2, 3]);
      expect(b.length, 0);
      expect(b.drain(), isEmpty);
    });

    test('is bounded: a crash loop cannot grow it without limit', () {
      final b = PendingCrashBuffer<int>(capacity: 3);
      for (var i = 0; i < 10; i++) {
        b.add(i);
      }
      expect(b.drain(), [0, 1, 2]);
      expect(b.dropped, 7);
    });
  });
}
