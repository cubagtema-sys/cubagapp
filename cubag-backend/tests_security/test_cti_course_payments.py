"""Approved CTI course payment policy: no in-app payment for online/hybrid courses on iOS."""
import pytest

API = '/api/v1'
IOS = {'X-Client-Platform': 'ios'}
ANDROID = {'X-Client-Platform': 'android'}

COURSES = {
    101: {'id': 101, 'title': 'Customs Valuation Online', 'mode': 'Online', 'fee': 'GHS 1,500'},
    102: {'id': 102, 'title': 'Tariff Classification Hybrid', 'mode': 'Hybrid', 'fee': 'GHS 1,200'},
    103: {'id': 103, 'title': 'Port Procedures Workshop', 'mode': 'In-Person', 'fee': 'GHS 900'},
}


def _install_courses(db):
    def by_id(p):
        c = COURSES.get(int(p[0]))
        return [c] if c else []

    def by_title(p):
        t = str(p[0]).strip('%').lower()
        return [c for c in COURSES.values() if t and t in c['title'].lower()][:1]

    db.on(r'SELECT id, title, mode FROM cti_courses WHERE id = %s', by_id)
    db.on(r'SELECT id, title, mode FROM cti_courses WHERE deleted_at IS NULL AND LOWER\(title\)', by_title)
    db.on(r'SELECT fee FROM cti_courses', lambda p: [{'fee': next((c['fee'] for c in COURSES.values()
                                                                    if str(p[0]).strip('%').lower() in c['title'].lower()), 'GHS 1')}])
    db.on(r'SELECT email, name FROM members WHERE id', [{'email': 'm@x.com', 'name': 'Member'}])
    db.on(r'INSERT INTO payments', [{'id': 555}])
    db.on(r'INSERT INTO guest_payments', [{'id': 777}])
    db.on(r'FROM cti_courses\s+WHERE deleted_at IS NULL AND is_active = TRUE', list(COURSES.values()))


def _pay(client, auth, headers, course_id, method='momo'):
    c = COURSES[course_id]
    return client.post(f'{API}/payments/', headers={**auth(10), **headers}, json={
        'amount': 1500, 'description': f"CTI Course: {c['title']}", 'method': method,
        'phone': '0240000000', 'network': 'MTN',
        'meta': {'type': 'cti_course', 'course_id': course_id, 'course_title': c['title']},
    })


# 1–3 & 9: viewing courses — details + enrolment status always present; flag per platform
def test_ios_member_course_list_flags(client, auth, db):
    _install_courses(db)
    db.on(r'FROM cti_course_enrollments\s+WHERE member_id', [{'course_id': 101, 'enrollment_id': 9, 'status': 'enrolled',
                                                             'payment_ref': 'X', 'amount': 0, 'payment_confirmed_at': None,
                                                             'created_at': None}])
    r = client.get(f'{API}/events/courses', headers={**auth(10), **IOS})
    assert r.status_code == 200
    items = {c['id']: c for c in r.get_json()['items']}
    assert items[101]['in_app_payment_available'] is False and items[101]['delivery_mode'] == 'online'
    assert items[102]['in_app_payment_available'] is False and items[102]['delivery_mode'] == 'hybrid'
    assert items[103]['in_app_payment_available'] is True and items[103]['delivery_mode'] == 'in_person'
    for c in items.values():                       # details remain visible for every mode
        assert c['title'] and c['fee'] and c['mode']
    assert items[101]['is_enrolled'] is True and items[101]['enrollment_status'] == 'enrolled'   # (9)
    assert items[103]['is_enrolled'] is False


def test_android_course_list_all_payable(client, auth, db):
    _install_courses(db)
    r = client.get(f'{API}/events/courses', headers={**auth(10), **ANDROID})
    assert all(c['in_app_payment_available'] for c in r.get_json()['items'])


def test_public_course_list_annotated(client, db):
    _install_courses(db)
    r = client.get(f'{API}/events/public/courses', headers=IOS)
    items = {c['id']: c for c in r.get_json()['items']}
    assert items[101]['in_app_payment_available'] is False
    assert items[103]['in_app_payment_available'] is True


# 4, 5, 7: iOS payment attempts for online/hybrid are refused server-side
@pytest.mark.parametrize('course_id', [101, 102])
@pytest.mark.parametrize('method', ['momo', 'bank'])
def test_ios_online_hybrid_payment_refused(client, auth, db, course_id, method):
    _install_courses(db)
    r = _pay(client, auth, IOS, course_id, method)
    assert r.status_code == 403
    body = r.get_json()
    assert body['error_code'] == 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'
    # anti-steering: no URL / website / alternative-payment wording
    msg = body['message'].lower()
    for word in ('http', 'www', 'website', 'secretariat', 'visit', 'online at', 'bank', 'momo'):
        assert word not in msg
    assert not db.executed(r'INSERT INTO payments')


def test_ios_unmatched_course_payment_refused(client, auth, db):
    _install_courses(db)
    r = client.post(f'{API}/payments/', headers={**auth(10), **IOS}, json={
        'amount': 100, 'description': 'CTI Course: Something Unknown', 'method': 'momo', 'phone': '0240000000'})
    assert r.status_code == 403


def test_ios_guest_public_momo_for_online_course_refused(client, db):
    _install_courses(db)
    r = client.post(f'{API}/payments/public/initiate-momo', headers=IOS, json={
        'name': 'Guest', 'phone': '0240000000', 'course_name': 'Customs Valuation Online', 'service_type': 'cti_training'})
    assert r.status_code == 403
    assert not db.executed(r'INSERT INTO guest_payments')


# 6: in-person courses still pay in-app on iOS
def test_ios_in_person_course_payment_allowed(client, auth, db):
    _install_courses(db)
    r = _pay(client, auth, IOS, 103)
    assert r.status_code != 403, r.get_json()
    assert r.get_json().get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'


def test_ios_guest_in_person_course_allowed(client, db):
    _install_courses(db)
    r = client.post(f'{API}/payments/public/initiate-momo', headers=IOS, json={
        'name': 'Guest', 'phone': '0240000000', 'course_name': 'Port Procedures Workshop', 'service_type': 'cti_training'})
    assert r.status_code == 200, r.get_json()
    assert db.executed(r'INSERT INTO guest_payments')


# Android is not restricted by the iOS rule
@pytest.mark.parametrize('course_id', [101, 102, 103])
def test_android_course_payments_not_blocked(client, auth, db, course_id):
    _install_courses(db)
    r = _pay(client, auth, ANDROID, course_id)
    assert r.get_json().get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'


def test_no_platform_header_not_blocked(client, auth, db):
    _install_courses(db)
    r = _pay(client, auth, {}, 101)
    assert r.get_json().get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'


# 8: unrelated payments unaffected on iOS
@pytest.mark.parametrize('description', ['Annual Membership Dues 2026', 'Registration Fee', 'Customs Licence Renewal 2027'])
def test_ios_non_course_payments_not_blocked(client, auth, db, description):
    _install_courses(db)
    r = client.post(f'{API}/payments/', headers={**auth(10), **IOS}, json={
        'amount': 500, 'description': description, 'method': 'momo', 'phone': '0240000000'})
    assert r.get_json().get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'


def test_mode_normalisation():
    from config.course_payment_policy import normalize_mode
    assert normalize_mode('Online') == 'online'
    assert normalize_mode('Virtual (Zoom)') == 'online'
    assert normalize_mode('Hybrid') == 'hybrid'
    assert normalize_mode('In-Person') == 'in_person'
    assert normalize_mode('in person') == 'in_person'
    assert normalize_mode('Physical / Classroom') == 'in_person'
    assert normalize_mode('') == 'unknown'
