import 'dart:math';

/// Pure helpers for the SEC-14 biometric device credential (no plugins, so
/// they can be unit-tested). See docs/CUBAG_SEC14_DESIGN.md.
class BiometricCredential {
  BiometricCredential._();

  /// Error code the backend returns when a device credential can no longer be
  /// used (expired, revoked, rotated, password changed, ...).
  static const invalidCode = 'BIOMETRIC_TOKEN_INVALID';

  static final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  /// Random identifier for this installation. Not derived from any hardware
  /// identifier; a reinstall produces a new one.
  static String generateDeviceId([Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool isValidDeviceId(String? id) =>
      id != null && _deviceIdPattern.hasMatch(id);

  /// True when the server says this device's credential is dead and the local
  /// copy must be deleted. Anything else (network error, 5xx, suspension) must
  /// NOT delete it.
  static bool isInvalidated(int? statusCode, dynamic body) =>
      statusCode == 401 && body is Map && body['error_code'] == invalidCode;

  /// A credential looks like `<row id>.<secret>`.
  static bool looksLikeCredential(String? value) {
    if (value == null) return false;
    final dot = value.indexOf('.');
    if (dot <= 0) return false;
    return int.tryParse(value.substring(0, dot)) != null &&
        value.length - dot - 1 >= 32;
  }
}
