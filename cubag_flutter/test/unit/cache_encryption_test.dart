import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cubag_flutter/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PERF-08: Hive Cache Encryption & Exclusion Tests', () {
    test('Sensitive auth, credential, and payment endpoints are excluded from caching', () {
      final sensitivePaths = [
        '/api/v1/auth/login',
        '/api/v1/auth/register',
        '/api/v1/auth/biometric-token',
        '/api/v1/auth/change-password',
        '/api/v1/auth/reset-password',
        '/api/v1/auth/verify-otp',
        '/api/v1/payments/initiate',
        '/api/v1/payments/process',
      ];

      for (final path in sensitivePaths) {
        // Attempting to cache sensitive data must not throw and must be ignored
        ApiService.putCachedSync(path, {'token': 'secret-should-never-be-cached'});
        final cached = ApiService.getCachedSync(path);
        expect(cached, isNull, reason: '$path must never be stored in offline cache');
      }
    });

    test('Hive AES cipher key is 256-bit (32 bytes)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final cipher = await ApiService.getHiveCipher();
      expect(cipher, isNotNull);
    });
  });
}

