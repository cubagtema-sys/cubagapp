import 'dart:async';
import 'package:flutter/widgets.dart';
import 'api_service.dart';

class TelemetryService {
  static final TelemetryService instance = TelemetryService._internal();
  final ApiService _api = ApiService();

  TelemetryService._internal();

  /// Logs a telemetry event asynchronously in the background.
  void logEvent(String eventType, Map<String, dynamic> properties) {
    // Run asynchronously to make sure it doesn't block the UI thread/operations
    scheduleMicrotask(() async {
      try {
        final payload = {
          'event_type': eventType,
          'timestamp': DateTime.now().toIso8601String(),
          ...properties,
        };
        // Print locally in debug mode
        debugPrint('[TELEMETRY] Logging event: $payload');

        // Asynchronously post to backend telemetry endpoint in fire-and-forget style
        await _api.postData('/analytics/telemetry', payload);
      } catch (e) {
        debugPrint('[TELEMETRY] Error logging telemetry: $e');
      }
    });
  }
}

/// A navigator observer that tracks page routing/views in the background.
class TelemetryRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logRouteEvent('page_view', route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _logRouteEvent('page_replace', newRoute);
    }
  }

  void _logRouteEvent(String eventType, Route<dynamic> route) {
    final routeName =
        route.settings.name ??
        route.settings.arguments?.toString() ??
        route.toString();
    TelemetryService.instance.logEvent(eventType, {'route_name': routeName});
  }
}
