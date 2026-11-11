import 'package:flutter/foundation.dart';

import '../services/crash_reporting.dart';

/// Centralized application logger.
///
/// Usage:
///   } catch (e, st) { AppLogger.error('PageName._fetch', e, st); }
///
/// In debug mode  → prints to console.
/// In release mode → recorded as a non-fatal Crashlytics report, scrubbed of
/// tokens, e-mail addresses and phone/account numbers (BUG-04).
class AppLogger {
  /// Log an error with optional stack trace.
  static void error(String context, dynamic error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] [$context] $error');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    } else {
      CrashReporting.recordNonFatal(context, error ?? 'null', stackTrace);
    }
  }

  /// Log a warning (non-fatal).
  static void warn(String context, String message) {
    if (kDebugMode) {
      debugPrint('[WARN]  [$context] $message');
    }
  }

  /// Log an informational message.
  static void info(String context, String message) {
    if (kDebugMode) {
      debugPrint('[INFO]  [$context] $message');
    }
  }
}
