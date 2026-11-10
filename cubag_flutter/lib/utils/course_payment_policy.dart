import 'platform_info.dart';

/// Approved CTI course payment policy (Nov 2026):
/// on the iOS app, ONLINE and HYBRID courses show details and enrolment status
/// only — no payment button, form, link or instructions. IN-PERSON courses keep
/// in-app payment. Android and web are unaffected. The backend enforces the same
/// rule; this class only drives what the UI shows.
enum CourseDeliveryMode { online, hybrid, inPerson, unknown }

class CoursePaymentPolicy {
  CoursePaymentPolicy._();

  static CourseDeliveryMode parseMode(Object? raw) {
    final m = (raw ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ' ').trim();
    if (m.isEmpty) return CourseDeliveryMode.unknown;
    if (m.contains('hybrid') || m.contains('blended')) return CourseDeliveryMode.hybrid;
    const online = ['online', 'virtual', 'remote', 'e learning', 'elearning', 'zoom', 'webinar'];
    if (online.any(m.contains)) return CourseDeliveryMode.online;
    const inPerson = ['in person', 'inperson', 'physical', 'on site', 'onsite', 'classroom', 'face to face'];
    if (inPerson.any(m.contains)) return CourseDeliveryMode.inPerson;
    if (m == 'in_person') return CourseDeliveryMode.inPerson;
    return CourseDeliveryMode.unknown;
  }

  static CourseDeliveryMode modeOf(Map<String, dynamic> course) =>
      parseMode(course['delivery_mode'] ?? course['mode']);

  static String label(CourseDeliveryMode mode) {
    switch (mode) {
      case CourseDeliveryMode.online:
        return 'Online';
      case CourseDeliveryMode.hybrid:
        return 'Hybrid';
      case CourseDeliveryMode.inPerson:
        return 'In-person';
      case CourseDeliveryMode.unknown:
        return 'Mode to be confirmed';
    }
  }

  /// Whether this course may be paid for inside the app on this platform.
  /// [isIOSApp] is injectable for tests.
  static bool canPayInApp(Map<String, dynamic> course, {bool? isIOSApp}) {
    final ios = isIOSApp ?? PlatformInfo.isIOSApp;
    if (!ios) return true;
    // On iOS the local rule always applies; the server flag can only make it stricter.
    final serverFlag = course['in_app_payment_available'];
    final localOk = modeOf(course) == CourseDeliveryMode.inPerson;
    return localOk && serverFlag != false;
  }

  /// Error code the backend returns when it refuses a course payment.
  static const blockedErrorCode = 'COURSE_PAYMENT_UNAVAILABLE_IN_APP';
}
