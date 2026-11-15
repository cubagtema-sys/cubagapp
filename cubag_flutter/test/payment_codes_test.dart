import 'package:cubag_flutter/utils/payment_codes.dart';
import 'package:flutter_test/flutter_test.dart';

// Must match cubag-backend/tests_security/test_payment_codes.py.
void main() {
  test('defaults follow the bank, like the server', () {
    expect(defaultPaymentCode('national', 'Zenith Bank'), 'CUB-SUB');
    expect(defaultPaymentCode('national', 'GCB'), 'CUB-ADM');
    expect(defaultPaymentCode('district', 'Ecobank'), 'CUB-DST');
    expect(defaultPaymentCode('national', 'NIB'), 'CUB-CPD');
    expect(defaultPaymentCode('new_membership', 'GCB'), 'CUB-REG');
  });

  test('typed code wins and is upper case', () {
    expect(paymentCodeFor({'section': 'national', 'bank_name': 'GCB', 'payment_code': ' cub-legal '}), 'CUB-LEGAL');
    expect(paymentCodeFor({'section': 'variable', 'bank_name': 'GCB'}), 'CUB-ADM');
  });
}
