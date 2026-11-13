"""Renewal 'paid so far' must count only the current cycle's payments."""
from datetime import date, datetime

from routes.auth import renewal_cycle_start


def test_cycle_starts_when_renewal_application_opened():
    opened = datetime(2026, 10, 1, 9, 30)
    assert renewal_cycle_start({'id': 7, 'created_at': opened}, '2026-12-05') == opened


def test_without_application_cycle_is_year_before_expiry():
    assert renewal_cycle_start(None, '2026-12-05') == datetime(2025, 12, 5)
    assert renewal_cycle_start({}, date(2026, 12, 5)) == datetime(2025, 12, 5)


def test_without_application_or_expiry_falls_back_to_last_year():
    start = renewal_cycle_start(None, None)
    assert 360 <= (datetime.now() - start).days <= 366


def test_bad_expiry_string_does_not_crash():
    start = renewal_cycle_start(None, 'not-a-date')
    assert isinstance(start, datetime)
