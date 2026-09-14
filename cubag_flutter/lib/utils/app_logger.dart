import 'package:flutter/foundation.dart';

/// Centralized application logger.
///
/// Usage:
///   } catch (e, st) { AppLogger.error('PageName._fetch', e, st); }
///
/// In debug mode  → prints to console.
/// In release mode → forwards to Sentry (when SENTRY_DSN is configured).
class AppLogger {
  static const String _sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Log an error with optional stack trace.
  static void error(String context, dynamic error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] [$context] $error');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    } else {
      // In release builds, try Sentry if available.
      _sendToSentry(context, error, stackTrace);
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

  /// Attempt to forward the error to Sentry SDK.
  /// No-ops if sentry_flutter is not yet integrated.
  static void _sendToSentry(
    String context,
    dynamic error,
    StackTrace? stackTrace,
  ) {
    if (_sentryDsn.isEmpty) return;
    // When sentry_flutter is added, uncomment:
    // Sentry.captureException(error,
    //     stackTrace: stackTrace,
    //     hint: Hint.withMap({'context': context}));
  }
}
