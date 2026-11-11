import 'dart:math';

import 'package:cubag_flutter/utils/biometric_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SEC-14: logic of the biometric device credential that can be tested
/// without the secure-storage / local_auth plugins.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Biometric preference flag', () {
    test('biometric is disabled by default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometric_enabled') ?? false, isFalse);
    });
  });

  group('Device id', () {
    test('generated ids are valid, 32 hex characters and differ', () {
      final a = BiometricCredential.generateDeviceId();
      final b = BiometricCredential.generateDeviceId();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(BiometricCredential.isValidDeviceId(a), isTrue);
      expect(a, isNot(equals(b)));
    });

    test('generation is driven by the supplied random source', () {
      expect(
        BiometricCredential.generateDeviceId(Random(1)),
        equals(BiometricCredential.generateDeviceId(Random(1))),
      );
    });

    test('rejects malformed ids', () {
      for (final bad in [null, '', 'short', 'has spaces in it......', 'x' * 65, 'abc/def/ghi/jkl/mno']) {
        expect(BiometricCredential.isValidDeviceId(bad), isFalse, reason: '$bad');
      }
    });
  });

  group('Server refusal handling', () {
    test('only the dedicated error code invalidates the local credential', () {
      expect(
        BiometricCredential.isInvalidated(401, {'error_code': 'BIOMETRIC_TOKEN_INVALID'}),
        isTrue,
      );
    });

    test('suspension, server errors and plain 401s keep the credential', () {
      expect(BiometricCredential.isInvalidated(403, {'message': 'suspended'}), isFalse);
      expect(BiometricCredential.isInvalidated(500, {'error_code': 'BIOMETRIC_TOKEN_INVALID'}), isFalse);
      expect(BiometricCredential.isInvalidated(401, {'message': 'Invalid credentials'}), isFalse);
      expect(BiometricCredential.isInvalidated(401, 'BIOMETRIC_TOKEN_INVALID'), isFalse);
      expect(BiometricCredential.isInvalidated(null, null), isFalse);
      expect(BiometricCredential.isInvalidated(429, {'message': 'slow down'}), isFalse);
    });
  });

  group('Credential shape', () {
    test('accepts <id>.<secret>', () {
      expect(BiometricCredential.looksLikeCredential('12.${'a' * 43}'), isTrue);
    });

    test('rejects anything that could be a password or junk', () {
      for (final bad in [null, '', 'MyPassword123!', '.${'a' * 43}', 'x.${'a' * 43}', '12.short', '12']) {
        expect(BiometricCredential.looksLikeCredential(bad), isFalse, reason: '$bad');
      }
    });
  });
}
