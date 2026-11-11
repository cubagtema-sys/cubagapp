"""SEC-20 (part 2): pay by fee key, and completed payments unlock only what they paid for.

Installment policy (owner decision, 11 Nov 2026): only renewals can be paid in
parts, against the renewal bill. Registration and package fees gate access to
the app and must be paid in full.
"""
import pytest

from config.payment_validation import (
    INSTALLMENT_NEEDS_BILL, payment_kind, price_fee_key_payment as price,
)
from fakedb import FakeCursor  # same module instance conftest uses

MEMBER = 10  # active member in conftest.USERS


@pytest.fixture()
def cur(client, db):
    """`client` resets the fake DB's responders."""
    db.on(r'SELECT member_type FROM members', [{'member_type': 'Corporate'}])
    db.on(r"WHERE key = %s AND is_active = TRUE LIMIT 1", lambda p: {
        'reg_form_fee': [{'amount': 600}],
        'var_id_card': [{'key': 'var_id_card', 'name': 'ID card', 'amount': 45}],
    }.get(p[0], []))
    db.on(r'SELECT member_type, member_scale, fee_category FROM members',
          [{'member_type': 'Corporate', 'member_scale': 'sme', 'fee_category': 'cf_only'}])
    db.on(r'SELECT key, amount FROM fee_schedules', [{'key': 'new_cf_only', 'amount': 1620}])
    db.on(r'FROM cti_courses WHERE id = %s AND deleted_at', lambda p: (
        [{'id': 3, 'title': 'Tariff Basics', 'fee': 900}] if p[0] == 3 else []))
    return FakeCursor()


@pytest.mark.parametrize('key,amount,desc', [
    ('registration', 600.0, 'Registration Fee'),
    ('package', 1620.0, 'New Membership Dues'),
    ('course:3', 900.0, 'CTI Course: Tariff Basics'),
    ('var_id_card', 45.0, 'ID card'),
])
def test_server_prices_the_fee_key(cur, key, amount, desc):
    plan, err = price(cur, MEMBER, key, 0.01, False)
    assert err is None
    assert (plan['amount'], plan['description'], plan['fee_key']) == (amount, desc, key)
    assert plan['is_installment'] is False


@pytest.mark.parametrize('key', ['nope', 'course:999', 'course:x', 'x' * 101, ''])
def test_unknown_fee_key_is_refused(cur, key):
    plan, err = price(cur, MEMBER, key, 10, False)
    assert plan is None and err


@pytest.mark.parametrize('key', ['registration', 'package', 'course:3', 'var_id_card'])
def test_only_renewals_can_be_paid_in_parts(cur, key):
    assert price(cur, MEMBER, key, 10, True) == (None, INSTALLMENT_NEEDS_BILL)


def test_renewal_installment_goes_on_the_renewal_bill(cur, db):
    db.on(r"type = 'renewal'", [{'id': 99}])
    db.on(r'FROM compliance_applications WHERE id = %s', [{
        'id': 99, 'member_id': MEMBER, 'payment_amount': 1000, 'amount_paid': 0,
        'allow_installments': True, 'min_installment_amount': 250}])
    plan, err = price(cur, MEMBER, 'renewal', 300, True)
    assert err is None and plan['comp_app_id'] == 99 and plan['amount'] == 300 and plan['is_installment']


def test_route_charges_schedule_amount_and_stores_fee_key(client, auth, db):
    db.on(r'SELECT email, name FROM members', [{'email': 'a@b.c', 'name': 'A'}])
    db.on(r"WHERE key = %s AND is_active = TRUE LIMIT 1",
          [{'key': 'var_id_card', 'name': 'ID card', 'amount': 45}])
    db.on(r'INSERT INTO payments', [{'id': 501}])
    client.post('/api/v1/payments/', headers=auth(MEMBER), json={
        'amount': 1, 'description': 'anything', 'fee_key': 'var_id_card', 'method': 'bank'})
    inserts = db.executed(r'INSERT INTO payments')
    assert inserts, 'payment row not created'
    params = inserts[-1][1]
    assert params[1] == 45.0 and params[2] == 'ID card' and params[-1] == 'var_id_card'


@pytest.mark.parametrize('fee_key,desc,kind', [
    (None, 'Annual Renewal Dues', 'renewal'),      # used to fail: 'renewal' contains 'new'
    (None, 'License Renewal', 'renewal'),
    (None, 'Annual Dues', 'renewal'),
    (None, 'New Membership Dues', 'package'),
    (None, 'Registration Fee', 'registration'),
    (None, 'Clearing & Forwarding only', 'package'),
    (None, 'CTI Course: Tariff Basics', 'course'),
    (None, 'Other', 'fee'),
    (None, 'Association Payment', 'fee'),
    (None, 'Consolidation fee', 'fee'),
    ('var_consolidation', 'Consolidation fee', 'fee'),
    ('registration', 'Registration Fee', 'registration'),
    ('course:3', 'CTI Course: X', 'course'),
])
def test_payment_kind(fee_key, desc, kind):
    assert payment_kind(fee_key, desc) == kind


# ── completion: what a paid payment unlocks ─────────────────────────────────

def _complete(db, description, fee_key=None, application_id=None):
    from routes.payments import _mark_payment_as_paid
    db.on(r'FROM payments WHERE id = %s FOR UPDATE', [{
        'status': 'pending', 'member_id': MEMBER, 'description': description, 'amount': 100,
        'payment_ref': 'R1', 'application_id': application_id, 'is_installment': False,
        'fee_key': fee_key}])
    db.on(r'SELECT license_number, license_expiry_date FROM members', [{
        'license_number': 'CUBAG-LIC-1', 'license_expiry_date': None}])
    db.log.clear()
    _mark_payment_as_paid(501)


def _sets(db, column):
    return [s for s, _ in db.executed(r'UPDATE members') if column in s]


@pytest.mark.parametrize('desc,fee_key', [
    ('Other', None), ('Association Payment', None), ('ID card', 'var_id_card'),
    ('Consolidation fee', 'var_consolidation'),
])
def test_plain_payment_unlocks_nothing(client, db, desc, fee_key):
    _complete(db, desc, fee_key)
    assert db.executed(r"UPDATE payments SET status = 'paid'")
    assert not _sets(db, 'registration_fee_paid')
    assert not _sets(db, 'package_fee_paid')
    assert not db.executed(r'INSERT INTO license_history')
    assert not db.executed(r'INSERT INTO cti_course_enrollments')


def test_registration_payment_sets_registration_only(client, db):
    _complete(db, 'Registration Fee', 'registration')
    assert _sets(db, 'registration_fee_paid') and not _sets(db, 'package_fee_paid')


def test_package_payment_sets_package(client, db):
    _complete(db, 'New Membership Dues', 'package')
    assert _sets(db, 'package_fee_paid')


def test_renewal_without_bill_now_renews_the_licence(client, db):
    _complete(db, 'Annual Renewal Dues')
    assert db.executed(r'INSERT INTO license_history')
    assert not _sets(db, 'registration_fee_paid')


def test_course_paid_by_id_enrols_in_that_course_only(client, db):
    db.on(r'SELECT id, title, start_date FROM cti_courses WHERE id = %s',
          lambda p: [{'id': 3, 'title': 'Tariff Basics', 'start_date': None}] if p[0] == 3 else [])
    _complete(db, 'CTI Course: Tariff Basics', 'course:3')
    enrol = db.executed(r'INSERT INTO cti_course_enrollments')
    assert enrol and enrol[-1][1][0] == 3


def test_unmatched_course_description_enrols_nobody(client, db):
    db.on(r'SELECT id, title, start_date FROM cti_courses\s+WHERE deleted_at',
          [{'id': 1, 'title': 'First Course', 'start_date': None}])
    _complete(db, 'Training materials')
    assert not db.executed(r'INSERT INTO cti_course_enrollments')
