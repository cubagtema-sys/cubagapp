import 'package:cubag_flutter/utils/payment_statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final payments = [
    {'status': 'paid', 'created_at': '2026-03-02T10:00:00', 'description': 'Renewal dues', 'payment_ref': 'A1', 'amount': '1200.00'},
    {'status': 'Paid', 'created_at': '2026-01-15T09:00:00', 'description': '', 'payment_ref': 'A0', 'amount': 80},
    {'status': 'pending', 'created_at': '2026-05-01T09:00:00', 'amount': '500'},
    {'status': 'failed', 'created_at': '2026-06-01T09:00:00', 'amount': '500'},
    {'status': 'paid', 'created_at': '2025-11-20T09:00:00', 'amount': '300'},
    {'status': 'paid', 'created_at': 'not a date', 'amount': '300'},
  ];

  test('only paid payments of that year, oldest first', () {
    final lines = statementLines(payments, 2026);
    expect(lines.map((l) => l.reference), ['A0', 'A1']);
    expect(lines.first.description, 'CUBAG payment');
    expect(lines.fold<double>(0, (s, l) => s + l.amount), 1280);
  });

  test('years with paid payments, newest first', () {
    expect(statementYears(payments), [2026, 2025]);
    expect(statementYears([{'status': 'pending', 'created_at': '2026-01-01'}]), isEmpty);
  });

  test('PDF builds, including with no lines', () async {
    final pdf = await buildYearStatement(
      year: 2026,
      lines: statementLines(payments, 2026),
      name: 'Kwame Owusu',
      company: 'Owusu Clearing',
      licenceNumber: 'CUBAG-0142',
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    final empty = await buildYearStatement(year: 2024, lines: const [], name: '', company: '', licenceNumber: '');
    expect(String.fromCharCodes(empty.take(4)), '%PDF');
  });
}
