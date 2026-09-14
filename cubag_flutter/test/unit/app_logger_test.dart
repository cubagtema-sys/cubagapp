import 'package:flutter_test/flutter_test.dart';
import 'package:cubag_flutter/utils/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('error() does not throw in debug or release mode', () {
      expect(
        () => AppLogger.error('TestContext', 'Something went wrong'),
        returnsNormally,
      );
    });

    test('error() with exception object does not throw', () {
      final error = Exception('Test exception');
      expect(() => AppLogger.error('TestContext', error), returnsNormally);
    });

    test('error() with stack trace does not throw', () {
      try {
        throw Exception('Test');
      } catch (e, st) {
        expect(() => AppLogger.error('TestContext', e, st), returnsNormally);
      }
    });

    test('warn() does not throw', () {
      expect(
        () => AppLogger.warn('TestContext', 'Warning message'),
        returnsNormally,
      );
    });

    test('info() does not throw', () {
      expect(
        () => AppLogger.info('TestContext', 'Info message'),
        returnsNormally,
      );
    });
  });
}
