import 'package:cubag_flutter/utils/intelligence_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample flag is read from the server', () {
    final s = ForexSnapshot.fromIntelligence({
      'forex': {'USD': '15.45', 'EUR': '16.80', 'GBP': '19.50', 'CNY': '2.15'},
      'is_sample': true,
      'updated_at': null,
    })!;
    expect(s.isSample, isTrue);
    expect(s.rates['USD'], '15.45');
    expect(s.updatedLabel, '');
  });

  test('admin-published rates are not sample and carry a date', () {
    final s = ForexSnapshot.fromIntelligence({
      'forex': {'USD': 11.1},
      'is_sample': false,
      'updated_at': '2026-11-11T12:00:00',
    })!;
    expect(s.isSample, isFalse);
    expect(s.rates['USD'], '11.1');
    expect(s.rates['EUR'], '—');
    expect(s.updatedLabel, startsWith('Updated 11 Nov 2026'));
  });

  test('older servers without the flag keep previous behaviour', () {
    expect(ForexSnapshot.fromIntelligence({'forex': {}})!.isSample, isFalse);
  });

  test('missing forex section yields null', () {
    expect(ForexSnapshot.fromIntelligence({'ports': []}), isNull);
    expect(ForexSnapshot.fromIntelligence(null), isNull);
  });
}
