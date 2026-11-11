import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/crash_scrub.dart';

/// BUG-04: crash reporting through Firebase Crashlytics (native apps only).
///
/// * Collection is ON only in release builds, so development crashes do not
///   reach the console.
/// * No user identifier is attached: reports are not linked to a member.
/// * Non-fatal reports from [AppLogger] are scrubbed (tokens, e-mails, numbers).
/// * Errors raised before Firebase finishes starting are buffered and sent
///   once [init] has run.
class CrashReporting {
  CrashReporting._();

  static bool _ready = false;
  static final PendingCrashBuffer<_Pending> _pending = PendingCrashBuffer<_Pending>();

  static bool get isReady => _ready;

  /// Call after `Firebase.initializeApp()`.
  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(kReleaseMode);
      _ready = true;
      for (final p in _pending.drain()) {
        _send(p);
      }
    } catch (e) {
      debugPrint('[CrashReporting] init failed: $e');
    }
  }

  /// Uncaught framework error (installed as `FlutterError.onError`).
  static void recordFlutterError(FlutterErrorDetails details) {
    if (kDebugMode) FlutterError.presentError(details);
    if (kIsWeb) return;
    final p = _Pending.flutter(details);
    _ready ? _send(p) : _pending.add(p);
  }

  /// Uncaught async error (installed as `PlatformDispatcher.instance.onError`).
  static bool recordUncaught(Object error, StackTrace stack) {
    debugPrint('Uncaught async error: $error');
    if (!kIsWeb) {
      final p = _Pending.error(error, stack, fatal: true, reason: 'uncaught');
      _ready ? _send(p) : _pending.add(p);
    }
    return true;
  }

  /// Handled error worth knowing about (used by AppLogger.error in release).
  static void recordNonFatal(String context, Object error, StackTrace? stack) {
    if (kIsWeb) return;
    final p = _Pending.error(
      _ScrubbedError(error.runtimeType.toString(), CrashScrub.scrub(error.toString())),
      stack ?? StackTrace.empty,
      fatal: false,
      reason: CrashScrub.scrub(context),
    );
    _ready ? _send(p) : _pending.add(p);
  }

  static void _send(_Pending p) {
    try {
      final c = FirebaseCrashlytics.instance;
      if (p.details != null) {
        c.recordFlutterFatalError(p.details!);
      } else {
        c.recordError(p.error, p.stack, fatal: p.fatal, reason: p.reason);
      }
    } catch (_) {
      // Reporting must never crash the app.
    }
  }
}

class _Pending {
  _Pending.flutter(this.details)
      : error = null,
        stack = null,
        fatal = true,
        reason = null;
  _Pending.error(this.error, this.stack, {required this.fatal, this.reason}) : details = null;

  final FlutterErrorDetails? details;
  final Object? error;
  final StackTrace? stack;
  final bool fatal;
  final String? reason;
}

/// Carries only the scrubbed text of a handled error, never the original object.
class _ScrubbedError {
  _ScrubbedError(this.type, this.message);
  final String type;
  final String message;
  @override
  String toString() => '$type: $message';
}
