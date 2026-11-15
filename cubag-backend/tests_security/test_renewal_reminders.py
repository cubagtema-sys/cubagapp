"""Renewal reminders: set days only, plain words, email as well as push."""
from datetime import date, timedelta

import jobs
from jobs import reminder_due, renewal_reminder_message
from tests_security.test_reminder_skips_paid import _Conn, _Cur


def test_reminders_only_on_set_days():
    assert [d for d in range(0, 40) if reminder_due(d)] == [1, 3, 7, 14, 30]


def test_message_is_plain_and_correct():
    title, body, html = renewal_reminder_message('Kwame Owusu', 1, date(2026, 12, 5))
    assert title == 'Your CUBAG licence ends in 1 day'
    assert 'Hello Kwame' in body and '5 December 2026' in body and 'Pay dues' in body
    assert '<strong>5 December 2026</strong>' in html
    assert renewal_reminder_message(None, 14, date(2026, 12, 5))[0].endswith('14 days')


def _run(monkeypatch, days_left, email='k@x.gh'):
    cur = _Cur([{'id': 2, 'name': 'Kwame', 'email': email, 'fcm_token': None,
                 'license_expiry_date': date.today() + timedelta(days=days_left)}])
    sent = []
    monkeypatch.setattr(jobs, 'get_db', lambda: _Conn(cur))
    monkeypatch.setattr(jobs, 'renewal_paid_this_cycle', lambda c, mid, exp: False)
    monkeypatch.setattr(jobs, '_send_email', lambda to, subj, *a: sent.append((to, subj)))
    jobs.check_expired_licenses()
    return cur, sent


def test_reminder_day_sends_notification_and_email(monkeypatch):
    cur, sent = _run(monkeypatch, 7)
    assert cur.inserted == [2]
    assert sent == [('k@x.gh', 'Your CUBAG licence ends in 7 days')]


def test_other_days_send_nothing(monkeypatch):
    cur, sent = _run(monkeypatch, 8)
    assert cur.inserted == [] and sent == []


def test_no_email_address_still_notifies_in_app(monkeypatch):
    cur, sent = _run(monkeypatch, 3, email=None)
    assert cur.inserted == [2] and sent == []


class _ExpiredCur(_Cur):
    """Serves the expired-members query and records suspensions."""

    def __init__(self, expired):
        super().__init__([])
        self.expired = expired
        self.suspended = []

    def execute(self, sql, params=None):
        s = ' '.join(sql.split())
        if s.startswith('SELECT id, name, email, fcm_token, license_expiry_date FROM members') and 'license_expiry_date < %s' in s:
            self._rows = self.expired
        elif s.startswith("UPDATE members SET status = 'suspended'"):
            self.suspended.append(params[0])
        else:
            super().execute(sql, params)


def test_paid_but_unapproved_member_stays_active(monkeypatch):
    ended = date.today() - timedelta(days=2)
    cur = _ExpiredCur([
        {'id': 5, 'name': 'Paid', 'email': None, 'fcm_token': None, 'license_expiry_date': ended},
        {'id': 6, 'name': 'Unpaid', 'email': None, 'fcm_token': None, 'license_expiry_date': ended},
    ])
    monkeypatch.setattr(jobs, 'get_db', lambda: _Conn(cur))
    monkeypatch.setattr(jobs, 'renewal_paid_this_cycle', lambda c, mid, exp: mid == 5)
    monkeypatch.setattr(jobs, '_send_email', lambda *a: True)
    jobs.check_expired_licenses()
    assert cur.suspended == [6]
