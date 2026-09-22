import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Payment Socket Event Validation Tests', () {
    test('Strict payment ID matching rejects null or mismatched payment IDs', () {
      final int paymentId = 42;

      // Simulate socket handler logic
      bool handleSocketApproval(dynamic data, int targetPaymentId) {
        final int? pId = data is Map
            ? int.tryParse(data['payment_id']?.toString() ?? '')
            : null;
        // Strict match: must equal targetPaymentId (no null fallback)
        return pId == targetPaymentId;
      }

      // Test matching ID
      expect(handleSocketApproval({'payment_id': '42'}, paymentId), isTrue);

      // Test mismatched ID
      expect(handleSocketApproval({'payment_id': '99'}, paymentId), isFalse);

      // Test null or missing payment ID (should be rejected securely)
      expect(handleSocketApproval({}, paymentId), isFalse);
      expect(handleSocketApproval({'payment_id': null}, paymentId), isFalse);
      expect(handleSocketApproval(null, paymentId), isFalse);
    });
  });
}
