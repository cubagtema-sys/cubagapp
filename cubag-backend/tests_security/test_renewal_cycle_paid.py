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


# ── renewal_paid_this_cycle: a renewal counts only for the current licence ──
from routes.auth import renewal_paid_this_cycle  # noqa: E402


class _Cur:
    """Records the 'since' bound and answers from a list of payment dates."""

    def __init__(self, paid_on):
        self.paid_on = paid_on
        self.since = None

    def execute(self, sql, params):
        self.since = params[1]

    def fetchone(self):
        return {'cnt': sum(1 for d in self.paid_on if d >= self.since)}


def test_last_years_renewal_does_not_count():
    cur = _Cur([date(2025, 11, 20)])
    assert renewal_paid_this_cycle(cur, 1, '2026-12-05') is False
    assert cur.since == date(2026, 11, 4)


def test_renewal_paid_in_the_window_counts():
    assert renewal_paid_this_cycle(_Cur([date(2026, 11, 11)]), 1, date(2026, 12, 5)) is True


def test_renewal_paid_after_expiry_counts():
    assert renewal_paid_this_cycle(_Cur([date(2026, 12, 20)]), 1, '2026-12-05') is True


def test_unknown_expiry_keeps_old_behaviour():
    assert renewal_paid_this_cycle(_Cur([date(2020, 1, 1)]), 1, None) is True
