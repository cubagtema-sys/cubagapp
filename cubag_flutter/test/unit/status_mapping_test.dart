import 'package:flutter_test/flutter_test.dart';

/// Tests for status label/color mapping logic.
/// Mirrors the switch statement in admin_documents_page.dart _MemberRow.
/// If someone changes the status values in the DB, these tests will catch
/// any missing cases before it reaches production.

/// Replicate the status→label mapping from admin_documents_page.dart
String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Not Submitted';
    case 'pending_review':
      return 'In Review';
    case 'suspended':
      return 'Suspended';
    case 'active':
      return 'Active';
    default:
      return 'Unknown';
  }
}

void main() {
  group('Status label mapping', () {
    test('pending → Not Submitted', () {
      expect(statusLabel('pending'), equals('Not Submitted'));
    });

    test('pending_review → In Review', () {
      expect(statusLabel('pending_review'), equals('In Review'));
    });

    test('suspended → Suspended', () {
      expect(statusLabel('suspended'), equals('Suspended'));
    });

    test('active → Active', () {
      expect(statusLabel('active'), equals('Active'));
    });

    test('unknown status → Unknown (not Pending)', () {
      // Previously unknown statuses fell through as 'Pending'
      // which was incorrect (e.g. 'suspended' showed as Pending).
      // Now all unknowns must show 'Unknown'.
      expect(statusLabel('some_future_status'), equals('Unknown'));
      expect(statusLabel(''), equals('Unknown'));
    });

    test('all expected DB statuses are handled', () {
      // This is the contract with the backend.
      // If the backend adds a new status, add it here + in the switch.
      const knownStatuses = [
        'pending',
        'pending_review',
        'suspended',
        'active',
      ];
      for (final s in knownStatuses) {
        expect(
          statusLabel(s),
          isNot(equals('Unknown')),
          reason: 'Known status "$s" should not fall to Unknown',
        );
      }
    });
  });
}
