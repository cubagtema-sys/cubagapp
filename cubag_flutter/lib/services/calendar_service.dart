import 'package:flutter/foundation.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

class CalendarService {
  /// Adds an event directly into the device's native calendar app (iOS/Android)
  /// or opens Google Calendar in a new tab (Web).
  static Future<bool> addEventToCalendar({
    required String title,
    required String description,
    required String location,
    required DateTime startDate,
    DateTime? endDate,
    bool allDay = false,
  }) async {
    // Ensure startDate has valid hours/minutes if parsed without time
    DateTime adjustedStart = startDate;
    if (startDate.hour == 0 && startDate.minute == 0) {
      adjustedStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        9,
        0,
      );
    }
    final effectiveEndDate =
        endDate ?? adjustedStart.add(const Duration(hours: 2));

    if (kIsWeb) {
      return _addWebCalendarEvent(
        title: title,
        description: description,
        location: location,
        startDate: adjustedStart,
        endDate: effectiveEndDate,
      );
    }

    try {
      final event = Event(
        title: title,
        description: description,
        location: location,
        startDate: adjustedStart,
        endDate: effectiveEndDate,
        allDay: allDay,
        iosParams: const IOSParams(
          reminder: Duration(minutes: 60), // Set a 1-hour reminder on iOS
        ),
        androidParams: const AndroidParams(),
      );

      final success = await Add2Calendar.addEvent2Cal(event);
      if (!success) {
        return await _addWebCalendarEvent(
          title: title,
          description: description,
          location: location,
          startDate: adjustedStart,
          endDate: effectiveEndDate,
        );
      }
      return true;
    } catch (e) {
      // Fallback to web link if native calendar invocation fails
      return await _addWebCalendarEvent(
        title: title,
        description: description,
        location: location,
        startDate: adjustedStart,
        endDate: effectiveEndDate,
      );
    }
  }

  static Future<bool> _addWebCalendarEvent({
    required String title,
    required String description,
    required String location,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startStr = _formatUtcDateTime(startDate.toUtc());
    final endStr = _formatUtcDateTime(endDate.toUtc());

    final urlStr =
        'https://calendar.google.com/calendar/render?'
        'action=TEMPLATE'
        '&text=${Uri.encodeComponent(title)}'
        '&dates=$startStr/$endStr'
        '&details=${Uri.encodeComponent(description)}'
        '&location=${Uri.encodeComponent(location)}';

    final uri = Uri.parse(urlStr);
    try {
      if (kIsWeb) {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        return false;
      }
    }
  }

  static String _formatUtcDateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }
}
