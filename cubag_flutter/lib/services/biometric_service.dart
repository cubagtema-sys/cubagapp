import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/biometric_credential.dart';
import '../utils/platform_info.dart';
import 'api_service.dart';
// Conditional import: dart2js (web) loads the stub; native loads the real impl.
import 'biometric_service_native.dart'
    if (dart.library.html) 'biometric_service_web.dart'
    as impl;

/// A device credential read from secure storage.
class BiometricDeviceCredential {
  final String deviceId;
  final String token;
  const BiometricDeviceCredential(this.deviceId, this.token);
}

/// Biometric sign-in (SEC-14).
///
/// The phone never stores the account password. After a password sign-in the
/// server issues a random credential for this device; Face ID / fingerprint
/// unlocks its use. The server can expire or revoke it, and replaces it on
/// every use. See docs/CUBAG_SEC14_DESIGN.md.
///
/// On Web: all methods are no-ops.
class BiometricService {
  static const _keyEnabled = 'biometric_enabled';
  static bool _legacyChecked = false;

  /// Check if biometric auth is available on this device.
  Future<bool> isBiometricAvailable() {
    if (kIsWeb) return Future.value(false);
    return impl.isBiometricAvailable();
  }

  /// Prompt biometric authentication.
  Future<bool> authenticate({
    String reason = 'Authenticate to sign in to CUBAG',
  }) {
    if (kIsWeb) return Future.value(false);
    return impl.authenticate(reason: reason);
  }

  /// One-time cleanup: older versions kept the password in secure storage.
  /// Remove it; if this device has no new-style credential, biometric sign-in
  /// is switched off until the next password sign-in.
  Future<void> _migrateLegacy() async {
    if (kIsWeb || _legacyChecked) return;
    _legacyChecked = true;
    final hadLegacy = await impl.purgeLegacyPassword();
    if (hadLegacy && await impl.readToken() == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, false);
    }
  }

  /// The credential stored on this device, or null.
  Future<BiometricDeviceCredential?> credential() async {
    if (kIsWeb) return null;
    await _migrateLegacy();
    final token = await impl.readToken();
    if (token == null) return null;
    return BiometricDeviceCredential(await impl.getOrCreateDeviceId(), token);
  }

  Future<bool> hasCredential() async => (await credential()) != null;

  /// Ask the server for a credential for this device. Needs a signed-in
  /// session and the current password. Returns null on success, otherwise a
  /// message that can be shown to the user.
  Future<String?> enroll(String password) async {
    if (kIsWeb) return 'Biometric sign-in is not available on the web.';
    await _migrateLegacy();
    try {
      final deviceId = await impl.getOrCreateDeviceId();
      final res = await ApiService().post(
        '/auth/biometric/enroll',
        data: {
          'device_id': deviceId,
          'password': password,
          'platform': PlatformInfo.clientPlatform,
          'device_name': PlatformInfo.clientPlatform == 'ios'
              ? 'iPhone / iPad'
              : 'Android device',
        },
      );
      final body = res.data;
      if (res.statusCode == 201 &&
          body is Map &&
          BiometricCredential.looksLikeCredential(
            body['biometric_token']?.toString(),
          )) {
        await impl.saveToken(body['biometric_token'].toString());
        await setBiometricEnabled(true);
        return null;
      }
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
      return 'Could not enable biometric sign-in. Please try again.';
    } catch (_) {
      return 'Could not enable biometric sign-in. Please check your connection and try again.';
    }
  }

  /// Store the replacement credential the server returns on every use.
  Future<void> storeRotated(String token) async {
    if (kIsWeb || !BiometricCredential.looksLikeCredential(token)) return;
    await impl.saveToken(token);
  }

  /// Forget the credential on this device only (the server already refused it).
  Future<void> clearLocal() async {
    if (!kIsWeb) await impl.clearToken();
    await setBiometricEnabled(false);
  }

  /// Turn biometric sign-in off: revoke on the server (best effort), then
  /// delete the local credential.
  Future<void> disable() async {
    if (!kIsWeb) {
      try {
        final cred = await credential();
        if (cred != null) {
          await ApiService().post(
            '/auth/biometric/revoke',
            data: {'device_id': cred.deviceId, 'biometric_token': cred.token},
          );
        }
      } catch (_) {
        // Offline: the local copy is still deleted below, and the server-side
        // credential expires or is revoked by the next password change.
      }
    }
    await clearLocal();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    await _migrateLegacy();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }
}
