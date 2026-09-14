import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// This file is ONLY loaded on native (Android/iOS).
// dart2js (Flutter Web) never imports this file, so local_auth_android
// and its native-only methods are never compiled into main.dart.js.

final _auth = LocalAuthentication();

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

const _keyEmail = 'bio_email';
const _keyPassword = 'bio_password';

Future<bool> isBiometricAvailable() async {
  try {
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    return canCheck && isSupported;
  } on PlatformException catch (e) {
    debugPrint('Biometric availability check failed: $e');
    return false;
  }
}

Future<bool> authenticate({required String reason}) async {
  try {
    return await _auth.authenticate(localizedReason: reason);
  } on PlatformException catch (e) {
    debugPrint('Biometric authentication failed: $e');
    return false;
  }
}

Future<void> saveCredentials(String email, String password) async {
  await _storage.write(key: _keyEmail, value: email);
  await _storage.write(key: _keyPassword, value: password);
  debugPrint('[BiometricService] Credentials saved.');
}

Future<Map<String, String>?> getSavedCredentials() async {
  try {
    final email = await _storage.read(key: _keyEmail);
    final password = await _storage.read(key: _keyPassword);
    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  } catch (e) {
    debugPrint('[BiometricService] Failed to read credentials: $e');
    return null;
  }
}

Future<void> clearCredentials() async {
  await _storage.delete(key: _keyEmail);
  await _storage.delete(key: _keyPassword);
  debugPrint('[BiometricService] Credentials cleared.');
}
