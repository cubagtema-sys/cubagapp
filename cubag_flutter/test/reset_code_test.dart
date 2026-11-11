import 'package:cubag_flutter/pages/forgot_password_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed 8-digit code', () => expect(extractResetCode('12345678'), '12345678'));
  test('code with spaces', () => expect(extractResetCode(' 1234 5678 '), '12345678'));
  test('pasted reset link', () {
    expect(
      extractResetCode('https://cubag-api-server.fly.dev/#/reset-password?token=87654321&email=a%40b.com'),
      '87654321',
    );
  });
  test('anything else is left for the server to reject', () {
    expect(extractResetCode('abc'), 'abc');
  });
}
