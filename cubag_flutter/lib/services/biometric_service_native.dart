import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/biometric_credential.dart';

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

// SEC-14: the device holds a random, server-revocable credential.
const _keyDeviceId = 'bio_device_id';
const _keyToken = 'bio_token';
// Legacy (removed): the account e-mail and PASSWORD used to be stored here.
const _legacyKeyEmail = 'bio_email';
const _legacyKeyPassword = 'bio_password';

Future<bool> isBiometricAvailable() async {
  try {
    final isSupported = await _auth.isDeviceSupported();
    final canCheck = await _auth.canCheckBiometrics;
    return isSupported || canCheck;
  } on PlatformException catch (e) {
    debugPrint('Biometric availability check failed: ${e.code}');
    return false;
  }
}

Future<bool> authenticate({required String reason}) async {
  try {
    return await _auth.authenticate(localizedReason: reason);
  } on PlatformException catch (e) {
    debugPrint('Biometric authentication failed: ${e.code}');
    return false;
  }
}

/// Stable random id for this installation (created on first use).
Future<String> getOrCreateDeviceId() async {
  final existing = await _storage.read(key: _keyDeviceId);
  if (BiometricCredential.isValidDeviceId(existing)) return existing!;
  final created = BiometricCredential.generateDeviceId();
  await _storage.write(key: _keyDeviceId, value: created);
  return created;
}

Future<void> saveToken(String token) =>
    _storage.write(key: _keyToken, value: token);

Future<String?> readToken() async {
  try {
    final token = await _storage.read(key: _keyToken);
    return BiometricCredential.looksLikeCredential(token) ? token : null;
  } catch (e) {
    debugPrint('[BiometricService] Could not read device credential.');
    return null;
  }
}

Future<void> clearToken() => _storage.delete(key: _keyToken);

/// Deletes the password an older app version stored. Returns true if one was found.
Future<bool> purgeLegacyPassword() async {
  try {
    final hadPassword = await _storage.containsKey(key: _legacyKeyPassword);
    final hadEmail = await _storage.containsKey(key: _legacyKeyEmail);
    if (hadPassword) await _storage.delete(key: _legacyKeyPassword);
    if (hadEmail) await _storage.delete(key: _legacyKeyEmail);
    return hadPassword || hadEmail;
  } catch (e) {
    debugPrint('[BiometricService] Legacy credential cleanup failed.');
    return false;
  }
}
