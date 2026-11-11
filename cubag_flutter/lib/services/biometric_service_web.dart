// Web stub — loaded by dart2js instead of biometric_service_native.dart.
// All functions are no-ops: local_auth and flutter_secure_storage
// platform-specific code never enters the web bundle.

Future<bool> isBiometricAvailable() => Future.value(false);

Future<bool> authenticate({required String reason}) => Future.value(false);

Future<String> getOrCreateDeviceId() => Future.value('');

Future<void> saveToken(String token) => Future.value();

Future<String?> readToken() => Future.value(null);

Future<void> clearToken() => Future.value();

Future<bool> purgeLegacyPassword() => Future.value(false);
