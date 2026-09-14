import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Conditional import: dart2js (web) loads the stub; native loads the real impl.
import 'biometric_service_native.dart'
    if (dart.library.html) 'biometric_service_web.dart'
    as impl;

/// Biometric authentication service.
/// On Web: all methods are no-ops.
/// On Android/iOS: uses local_auth + flutter_secure_storage (hardware-backed).
///
/// Uses conditional imports so dart2js NEVER compiles local_auth_android,
/// preventing the "NoSuchMethodError: method not found: 'kl'" crash on web.
class BiometricService {
  static const _keyEnabled = 'biometric_enabled';

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

  /// Store credentials securely (native only).
  Future<void> saveCredentials(String email, String password) {
    if (kIsWeb) return Future.value();
    return impl.saveCredentials(email, password);
  }

  /// Read saved credentials (native only).
  Future<Map<String, String>?> getSavedCredentials() {
    if (kIsWeb) return Future.value(null);
    return impl.getSavedCredentials();
  }

  /// Wipe saved credentials.
  Future<void> clearCredentials() async {
    if (!kIsWeb) await impl.clearCredentials();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }
}
