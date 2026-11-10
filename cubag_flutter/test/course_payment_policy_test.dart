// Approved CTI course payment policy — UI decision logic.
// Run: flutter test test/course_payment_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cubag_flutter/utils/course_payment_policy.dart';

Map<String, dynamic> course(String mode, {bool? serverFlag}) => {
      'id': 1,
      'title': 'Course',
      'mode': mode,
      'fee': 'GHS 1,500',
      if (serverFlag != null) 'in_app_payment_available': serverFlag,
    };

void main() {
  group('iOS app', () {
    test('online course: details only, no in-app payment', () {
      expect(CoursePaymentPolicy.canPayInApp(course('Online'), isIOSApp: true), isFalse);
    });
    test('hybrid course: details only, no in-app payment', () {
      expect(CoursePaymentPolicy.canPayInApp(course('Hybrid'), isIOSApp: true), isFalse);
    });
    test('in-person course keeps in-app payment', () {
      expect(CoursePaymentPolicy.canPayInApp(course('In-Person'), isIOSApp: true), isTrue);
    });
    test('unknown mode is treated as not payable (conservative)', () {
      expect(CoursePaymentPolicy.canPayInApp(course(''), isIOSApp: true), isFalse);
    });
    test('server can only make it stricter, never looser', () {
      expect(CoursePaymentPolicy.canPayInApp(course('Online', serverFlag: true), isIOSApp: true), isFalse);
      expect(CoursePaymentPolicy.canPayInApp(course('In-Person', serverFlag: false), isIOSApp: true), isFalse);
    });
  });

  group('Android / web', () {
    for (final m in ['Online', 'Hybrid', 'In-Person', '']) {
      test('"$m" course remains payable', () {
        expect(CoursePaymentPolicy.canPayInApp(course(m), isIOSApp: false), isTrue);
      });
    }
  });

  test('mode parsing and labels', () {
    expect(CoursePaymentPolicy.parseMode('Virtual (Zoom)'), CourseDeliveryMode.online);
    expect(CoursePaymentPolicy.parseMode('in person'), CourseDeliveryMode.inPerson);
    expect(CoursePaymentPolicy.parseMode('in_person'), CourseDeliveryMode.inPerson);
    expect(CoursePaymentPolicy.parseMode('Blended'), CourseDeliveryMode.hybrid);
    expect(CoursePaymentPolicy.label(CourseDeliveryMode.inPerson), 'In-person');
    expect(CoursePaymentPolicy.modeOf({'delivery_mode': 'in_person', 'mode': 'x'}), CourseDeliveryMode.inPerson);
  });
}
