import 'package:flutter/foundation.dart';

/// Single source of truth for "which platform is this build running on".
class PlatformInfo {
  PlatformInfo._();

  /// Value sent to the backend in the `X-Client-Platform` header.
  static String get clientPlatform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'other';
    }
  }

  /// True for the native iOS app (not iOS Safari on the web portal).
  static bool get isIOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
