"""The daily licence reminder must not nag members who already paid this year's renewal."""
from datetime import date, timedelta

import jobs


class _Cur:
    def __init__(self, members):
        self.members = members
        self.inserted = []
        self._rows = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = ' '.join(sql.split())
        if s.startswith('SELECT id, name, fcm_token, license_expiry_date'):
            self._rows = self.members
        elif s.startswith('SELECT COUNT(*) as cnt FROM notifications'):
            self._rows = [{'cnt': 0}]
        elif s.startswith('INSERT INTO notifications'):
            self.inserted.append(params[0])
        else:
            self._rows = []

    def fetchall(self):
        return self._rows

    def fetchone(self):
        return self._rows[0]


class _Conn:
    def __init__(self, cur):
        self.cur = cur

    def cursor(self):
        return self.cur

    def commit(self):
        pass

    def rollback(self):
        pass

    def close(self):
        pass


def test_paid_member_gets_no_reminder_unpaid_member_does(monkeypatch):
    soon = date.today() + timedelta(days=10)
    cur = _Cur([
        {'id': 1, 'name': 'Paid', 'fcm_token': None, 'license_expiry_date': soon},
        {'id': 2, 'name': 'Unpaid', 'fcm_token': None, 'license_expiry_date': soon},
    ])
    monkeypatch.setattr(jobs, 'get_db', lambda: _Conn(cur))
    monkeypatch.setattr(jobs, 'renewal_paid_this_cycle', lambda c, mid, exp: mid == 1)
    jobs.check_expired_licenses()
    assert cur.inserted == [2]
