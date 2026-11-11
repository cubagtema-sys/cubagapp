import 'package:cubag_flutter/components/home/licence_status.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 11, 15, 0);
DateTime _in(int days) => DateTime(2026, 11, 11 + days); // calendar days, DST-safe

LicenceStatus _s({bool paid = true, DateTime? expiry, int tasks = 0}) =>
    licenceStatus(packagePaid: paid, expiry: expiry, pendingTasks: tasks, now: _now);

void main() {
  test('package unpaid: activation pending, pay the package', () {
    final s = _s(paid: false, expiry: _in(200));
    expect(s.stage, LicenceStage.activationPending);
    expect(s.actionLabel, 'Pay package fee');
    expect(s.actionRoute, contains('/payments'));
  });

  test('package unpaid with open steps: go to the steps first', () {
    final s = _s(paid: false, tasks: 2);
    expect(s.actionLabel, 'View steps (2)');
    expect(s.actionRoute, '/tasks');
  });

  test('expired', () {
    final s = _s(expiry: _in(-3));
    expect(s.stage, LicenceStage.expired);
    expect(s.pill, 'Expired');
    expect(s.actionLabel, 'Renew licence');
    expect(s.yearRemaining, 0);
  });

  test('last 30 days: renew now, with the day count', () {
    expect(_s(expiry: _in(24)).pill, 'Renew in 24 days');
    expect(_s(expiry: _in(1)).pill, 'Renew in 1 day');
    expect(_s(expiry: _in(0)).pill, 'Expires today');
    expect(_s(expiry: _in(30)).actionRoute, '/compliance');
  });

  test('31-60 days: no action yet, says when renewal opens (server 30-day rule)', () {
    final s = _s(expiry: _in(45));
    expect(s.stage, LicenceStage.renewalSoon);
    expect(s.actionLabel, isNull);
    expect(s.message, contains('Renewal opens on 26 Nov 2026'));
  });

  test('more than 60 days: valid, no action', () {
    final s = _s(expiry: _in(200));
    expect(s.stage, LicenceStage.valid);
    expect(s.actionLabel, isNull);
    expect(s.yearRemaining, closeTo(200 / 365, 0.001));
  });

  test('no expiry on record: active, nothing invented', () {
    final s = _s(expiry: null);
    expect(s.pill, 'Active');
    expect(s.yearRemaining, isNull);
  });

  test('time of day greeting', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 19)), 'Good evening');
  });

  test('day count is not shortened by a daylight-saving change', () {
    // 11 Nov -> 30 May crosses the March clock change in most of Europe/US.
    expect(_s(expiry: DateTime(2027, 5, 30)).daysLeft, 200);
  });

  test('expiry parsing ignores placeholders', () {
    expect(parseExpiry('None'), isNull);
    expect(parseExpiry(''), isNull);
    expect(parseExpiry('2026-12-05'), DateTime(2026, 12, 5));
  });
}
