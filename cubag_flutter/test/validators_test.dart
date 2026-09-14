import 'package:flutter_test/flutter_test.dart';
import 'package:cubag_flutter/utils/validators.dart';

void main() {
  group('GhanaPostGPS Digital Address Validation Tests', () {
    test('Official GhanaPostGPS formats pass validation', () {
      expect(AppValidators.validateGhanaDigitalAddress('GA-543-0125'), isNull);
      expect(AppValidators.validateGhanaDigitalAddress('GA-183-8164'), isNull);
      expect(AppValidators.validateGhanaDigitalAddress('AK-039-5028'), isNull);
      expect(AppValidators.validateGhanaDigitalAddress('ER-200-1987'), isNull);
      expect(AppValidators.validateGhanaDigitalAddress('WS-1234-5678'), isNull);
    });

    test('Null or empty input is treated as valid (optional field)', () {
      expect(AppValidators.validateGhanaDigitalAddress(null), isNull);
      expect(AppValidators.validateGhanaDigitalAddress(''), isNull);
      expect(AppValidators.validateGhanaDigitalAddress('   '), isNull);
    });

    test('Invalid formats are rejected', () {
      expect(AppValidators.validateGhanaDigitalAddress('12345'), isNotNull);
      expect(AppValidators.validateGhanaDigitalAddress('GA5430125'), isNotNull);
      expect(
        AppValidators.validateGhanaDigitalAddress('INVALID-ADDRESS'),
        isNotNull,
      );
      expect(
        AppValidators.validateGhanaDigitalAddress('G-123-45678901'),
        isNotNull,
      );
    });
  });

  group('Name Validation Tests (BUG-11)', () {
    test('Valid names with special characters and accents pass', () {
      expect(AppValidators.isValidName("O'Connor"), isTrue);
      expect(AppValidators.isValidName('Jean-Luc Picard'), isTrue);
      expect(AppValidators.isValidName('Nana-Yaw Mensah'), isTrue);
      expect(AppValidators.isValidName('Dr. Kwame Nkrumah'), isTrue);
      expect(AppValidators.isValidName('Kofi Annan'), isTrue);
      expect(AppValidators.isValidName('Müller St. Clair'), isTrue);
    });

    test('Invalid names are rejected', () {
      expect(AppValidators.isValidName(''), isFalse);
      expect(AppValidators.isValidName('A'), isFalse);
      expect(AppValidators.isValidName('John123'), isFalse);
      expect(AppValidators.isValidName('User@Domain'), isFalse);
      expect(AppValidators.isValidName('Test #1'), isFalse);
    });
  });

  group('Phone Normalization & Validation Tests (BUG-12)', () {
    test('Ghanaian phone numbers normalize correctly', () {
      expect(
        AppValidators.normalizePhoneNumber('0241234567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('+233241234567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('233241234567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('024 123 4567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('024-123-4567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('+233 24 123 4567'),
        equals('0241234567'),
      );
      expect(
        AppValidators.normalizePhoneNumber('00233241234567'),
        equals('0241234567'),
      );
    });

    test('Valid Ghanaian phones pass validation', () {
      expect(AppValidators.isValidGhanaPhone('0241234567'), isTrue);
      expect(AppValidators.isValidGhanaPhone('+233241234567'), isTrue);
      expect(AppValidators.isValidGhanaPhone('233241234567'), isTrue);
      expect(AppValidators.isValidGhanaPhone('020-555-1234'), isTrue);
      expect(AppValidators.isValidGhanaPhone('055 123 4567'), isTrue);
    });

    test('Invalid phone numbers are rejected', () {
      expect(AppValidators.isValidGhanaPhone('12345'), isFalse);
      expect(AppValidators.isValidGhanaPhone('02412345'), isFalse); // 8 digits
      expect(
        AppValidators.isValidGhanaPhone('024123456789'),
        isFalse,
      ); // 12 digits
      expect(AppValidators.isValidGhanaPhone('abcdefghij'), isFalse);
      expect(AppValidators.isValidGhanaPhone(''), isFalse);
    });
  });
}
