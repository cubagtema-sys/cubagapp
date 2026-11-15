"""Admin group messages: who is in each group."""
from datetime import date

import pytest

import routes.auth as auth
from routes.notifications import MESSAGE_GROUPS, group_members


class _Cur:
    def __init__(self, rows):
        self.rows = rows
        self.sql = None
        self.params = None

    def execute(self, sql, params=None):
        self.sql = ' '.join(sql.split())
        self.params = params

    def fetchall(self):
        return self.rows


def test_renewal_due_leaves_out_members_who_paid(monkeypatch):
    rows = [{'id': 1, 'license_expiry_date': date(2026, 12, 1)}, {'id': 2, 'license_expiry_date': date(2026, 12, 1)}]
    cur = _Cur(rows)
    monkeypatch.setattr(auth, 'renewal_paid_this_cycle', lambda c, mid, exp: mid == 1)
    got = group_members(cur, 'renewal_due', today=date(2026, 11, 15))
    assert [r['id'] for r in got] == [2]
    assert cur.params == (date(2026, 12, 15),)
    assert "COALESCE(role, 'member') = 'member'" in cur.sql


def test_expired_looks_before_today(monkeypatch):
    cur = _Cur([])
    monkeypatch.setattr(auth, 'renewal_paid_this_cycle', lambda *a: False)
    group_members(cur, 'expired', today=date(2026, 11, 15))
    assert cur.params == (date(2026, 11, 14),)


def test_simple_groups_and_unknown():
    cur = _Cur([{'id': 9}])
    assert group_members(cur, 'all_active') == [{'id': 9}] and "status = 'active'" in cur.sql
    assert group_members(cur, 'pending') == [{'id': 9}] and 'pending_review' in cur.sql
    with pytest.raises(ValueError):
        group_members(cur, 'everyone')
    assert set(MESSAGE_GROUPS) == {'renewal_due', 'expired', 'pending', 'all_active'}
