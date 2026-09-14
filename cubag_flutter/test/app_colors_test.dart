import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cubag_flutter/utils/app_colors.dart';

void main() {
  group('AppColors.parseHexColor Tests (BUG-08)', () {
    test('Parses valid 6-character hex with hash', () {
      final color = AppColors.parseHexColor('#FF0000');
      expect(color, equals(const Color(0xFFFF0000)));
    });

    test('Parses valid 6-character hex without hash', () {
      final color = AppColors.parseHexColor('00FF00');
      expect(color, equals(const Color(0xFF00FF00)));
    });

    test('Parses valid 8-character hex (ARGB)', () {
      final color = AppColors.parseHexColor('#80123456');
      expect(color, equals(const Color(0x80123456)));
    });

    test('Parses valid 3-character hex shorthand', () {
      final color = AppColors.parseHexColor('#FFF');
      expect(color, equals(const Color(0xFFFFFFFF)));
    });

    test('Returns fallback for null', () {
      final color = AppColors.parseHexColor(null, fallback: Colors.blue);
      expect(color, equals(Colors.blue));
    });

    test('Returns fallback for empty string', () {
      final color = AppColors.parseHexColor('', fallback: Colors.green);
      expect(color, equals(Colors.green));
    });

    test('Returns fallback for non-string invalid types without crashing', () {
      final color = AppColors.parseHexColor(12345, fallback: Colors.amber);
      expect(color, equals(Colors.amber));
    });

    test('Returns fallback for malformed hex characters', () {
      final color = AppColors.parseHexColor('#ZZZZZZ', fallback: Colors.purple);
      expect(color, equals(Colors.purple));
    });
  });
}
