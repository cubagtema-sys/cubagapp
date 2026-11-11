"""SEC-20: the member can never choose the price of a fee that unlocks anything.

A completed payment unlocks membership by description keyword, not by total
paid (routes/payments.py _mark_payment_as_paid, routes/auth.py fee status).
So the validator must (a) refuse installments that are not tied to a bill and
(b) refuse unrecognised descriptions that contain an unlocking keyword.
"""
import pytest

from config.payment_validation import (
    INSTALLMENT_NEEDS_BILL,
    validate_member_payment_amount as validate,
)
from fakedb import FakeCursor  # same module instance conftest uses

MEMBER = 10  # active member in conftest.USERS


@pytest.fixture()
def fresh_db(client, db):
    """`client` resets the fake DB's responders."""
    return db


@pytest.fixture()
def cur(fresh_db):
    db = fresh_db
    db.on(r'SELECT member_type FROM members', [{'member_type': 'Corporate'}])
    db.on(r"WHERE key = %s AND is_active", [{'amount': 600}])
    db.on(r'SELECT member_type, member_scale, fee_category FROM members',
          [{'member_type': 'Corporate', 'member_scale': 'sme', 'fee_category': 'cf_only'}])
    db.on(r'SELECT key, amount FROM fee_schedules', [{'key': 'new_cf_only', 'amount': 1620}])
    db.on(r'SELECT fee FROM cti_courses', [{'fee': 900}])
    return FakeCursor()


@pytest.mark.parametrize('desc', [
    'Registration Fee', 'New Membership Dues', 'Membership package', 'CTI Course: Tariff Basics',
])
def test_installment_without_bill_is_refused(cur, desc):
    amount, err = validate(cur, MEMBER, desc, 0.01, is_installment=True)
    assert amount is None and err == INSTALLMENT_NEEDS_BILL


def test_package_installment_is_not_attached_to_renewal_bill(cur, db):
    db.on(r"type = 'renewal'", [{'id': 99}])
    _, err = validate(cur, MEMBER, 'New Membership Dues', 0.01, is_installment=True)
    assert err == INSTALLMENT_NEEDS_BILL


def test_renewal_installment_uses_open_renewal_bill(cur, db):
    db.on(r"type = 'renewal'", [{'id': 99}])
    db.on(r'FROM compliance_applications WHERE id = %s', [{
        'id': 99, 'member_id': MEMBER, 'payment_amount': 1000, 'amount_paid': 0,
        'allow_installments': True, 'min_installment_amount': 250}])
    assert validate(cur, MEMBER, 'Annual Renewal Dues', 300, is_installment=True) == (300, None)
    _, err = validate(cur, MEMBER, 'Annual Renewal Dues', 0.01, is_installment=True)
    assert 'minimum installment' in err


def test_renewal_installment_without_any_bill_is_refused(cur):
    _, err = validate(cur, MEMBER, 'Annual Renewal Dues', 0.01, is_installment=True)
    assert err == INSTALLMENT_NEEDS_BILL


@pytest.mark.parametrize('desc,expected', [
    ('Registration Fee', 600.0),
    ('New Membership Dues', 1620.0),
    ('CTI Course: Tariff Basics', 900.0),
])
def test_full_payment_amount_comes_from_server(cur, desc, expected):
    assert validate(cur, MEMBER, desc, 0.01) == (expected, None)


@pytest.mark.parametrize('desc', [
    'License fee', 'Licence', 'Outstanding bill', 'Onboarding', 'Dossier processing',
    'Reg form', 'Licentiate membership', 'Associate membership', 'Clearing & Forwarding only',
])
def test_unrecognised_unlocking_description_is_refused(fresh_db, desc):
    amount, err = validate(FakeCursor(), MEMBER, desc, 0.01)
    assert amount is None and 'official schedule' in err


@pytest.mark.parametrize('desc', ['Other', 'Association Payment', 'Donation to welfare fund'])
def test_miscellaneous_payment_keeps_member_amount(fresh_db, desc):
    assert validate(FakeCursor(), MEMBER, desc, 50) == (50.0, None)


def test_route_refuses_registration_installment(client, auth, db):
    db.on(r'SELECT email, name FROM members', [{'email': 'a@b.c', 'name': 'A'}])
    r = client.post('/api/v1/payments/', headers=auth(MEMBER), json={
        'amount': 0.01, 'description': 'Registration Fee', 'method': 'momo',
        'phone': '0240000000', 'is_installment': True})
    assert r.status_code == 400
    assert 'bills issued by the Secretariat' in r.get_json()['message']
    assert not db.executed(r'INSERT INTO payments')

