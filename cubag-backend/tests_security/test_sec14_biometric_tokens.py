"""SEC-14: revocable biometric device credentials (fake-DB unit tests).

Stateful behaviour (rotation, revocation on password change, etc.) is proven
against real PostgreSQL in tests_pg/test_sec14_biometric_pg.py; these tests pin
the decision logic and the SQL that each branch issues."""
from datetime import datetime, timedelta

from werkzeug.security import generate_password_hash

from config import biometric_tokens as bio

API = '/api/v1/auth'
DEVICE = 'device-AAAAAAAAAAAAAAAA'
OTHER_DEVICE = 'device-BBBBBBBBBBBBBBBB'
SECRET = 'S' * 43
OLD_SECRET = 'O' * 43
PASSWORD = 'Password123!'
MEMBER = 10


def _member_row(**over):
    row = {'id': MEMBER, 'name': 'Member Ten', 'email': 'm10@example.test', 'company': 'Co',
           'member_type': 'corporate', 'port_of_operation': 'Tema', 'role': 'member', 'status': 'active',
           'email_verified': True, 'token_version': 0, 'password_hash': generate_password_hash(PASSWORD),
           'license_expiry_date': None}
    row.update(over)
    return row


def _token_row(**over):
    row = {'id': 7, 'member_id': MEMBER, 'device_id': DEVICE, 'token_hash': bio.hash_secret(SECRET),
           'prev_token_hash': bio.hash_secret(OLD_SECRET), 'token_version': 0,
           'expires_at': datetime.utcnow() + timedelta(days=30), 'revoked_at': None, 'revoked_reason': None}
    row.update(over)
    return row


def _install(db, token_row=None, member_row=None):
    db.on(r'SELECT \* FROM biometric_tokens WHERE id = %s FOR UPDATE', [token_row] if token_row else [])
    db.on(r'SELECT \* FROM members WHERE id = %s', [member_row] if member_row else [])
    db.on(r'SELECT id, role, status, password_hash', [member_row] if member_row else [])
    db.on(r'SELECT COUNT\(\*\) as cnt FROM payments', [{'cnt': 0}])
    db.on(r'INSERT INTO biometric_tokens', [{'id': 9}])


def _login(client, secret=SECRET, device=DEVICE, row_id=7):
    return client.post(f'{API}/biometric/login', json={'biometric_token': f'{row_id}.{secret}', 'device_id': device})


def _refused(resp):
    return resp.status_code == 401 and resp.get_json()['error_code'] == 'BIOMETRIC_TOKEN_INVALID'


def _revoked_with(db, reason):
    return [p for s, p in db.executed(r'UPDATE biometric_tokens SET revoked_at = NOW\(\)') if p and p[0] == reason]


# ── use ───────────────────────────────────────────────────────────────────────
def test_valid_credential_signs_in_and_is_rotated(client, db):
    _install(db, _token_row(), _member_row())
    r = _login(client)
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body['token'] and body['user']['id'] == MEMBER
    new = body['biometric_token']
    assert new.startswith('7.') and new != f'7.{SECRET}'
    rot = db.executed(r'UPDATE biometric_tokens SET prev_token_hash = %s, token_hash = %s')
    assert len(rot) == 1
    prev_hash, new_hash, row_id = rot[0][1]
    assert prev_hash == bio.hash_secret(SECRET) and new_hash == bio.hash_secret(new.split('.', 1)[1])
    assert not db.executed(r'UPDATE biometric_tokens SET revoked_at')


def test_secret_is_never_written_in_clear(client, db):
    _install(db, _token_row(), _member_row())
    new = _login(client).get_json()['biometric_token'].split('.', 1)[1]
    for sql, params in db.log:
        assert SECRET not in str(params) and new not in str(params) and new not in sql


def test_expired_credential_is_refused_and_revoked(client, db):
    _install(db, _token_row(expires_at=datetime.utcnow() - timedelta(seconds=1)), _member_row())
    assert _refused(_login(client))
    assert _revoked_with(db, 'expired')


def test_revoked_credential_is_refused(client, db):
    _install(db, _token_row(revoked_at=datetime.utcnow(), revoked_reason='user_revoked'), _member_row())
    assert _refused(_login(client))
    assert not db.executed(r'UPDATE biometric_tokens SET prev_token_hash')


def test_reuse_of_rotated_credential_revokes_the_device(client, db):
    _install(db, _token_row(), _member_row())
    assert _refused(_login(client, secret=OLD_SECRET))
    assert _revoked_with(db, 'reuse_detected')
    assert not db.executed(r'UPDATE biometric_tokens SET prev_token_hash')


def test_device_mismatch_is_refused_and_revoked(client, db):
    _install(db, _token_row(), _member_row())
    assert _refused(_login(client, device=OTHER_DEVICE))
    assert _revoked_with(db, 'device_mismatch')


def test_wrong_secret_is_refused_and_locks_out_after_five(client, db):
    _install(db, _token_row(), _member_row())
    for _ in range(5):
        assert _refused(_login(client, secret='W' * 43))
    assert not _revoked_with(db, 'too_many_attempts')
    assert _refused(_login(client))  # even the right secret is refused now
    assert _revoked_with(db, 'too_many_attempts')


def test_unknown_and_malformed_credentials_are_refused(client, db):
    _install(db, None, _member_row())
    assert _refused(_login(client))
    for bad in ('', 'abc', '7', '7.short', 'x.' + SECRET, None, 12345):
        r = client.post(f'{API}/biometric/login', json={'biometric_token': bad, 'device_id': DEVICE})
        assert _refused(r), bad
    assert _refused(client.post(f'{API}/biometric/login', json={'biometric_token': f'7.{SECRET}', 'device_id': 'x'}))
    assert _refused(client.post(f'{API}/biometric/login', json={}))


def test_all_refusals_look_identical(client, db):
    _install(db, _token_row(), _member_row())
    a = _login(client, secret=OLD_SECRET).get_json()
    _install(db, None, _member_row())
    b = _login(client).get_json()
    _install(db, _token_row(expires_at=datetime.utcnow() - timedelta(days=1)), _member_row())
    c = _login(client).get_json()
    assert a == b == c


# ── account security events ──────────────────────────────────────────────────
def test_credential_from_before_a_password_change_is_refused(client, db):
    _install(db, _token_row(token_version=0), _member_row(token_version=1))
    assert _refused(_login(client))
    assert _revoked_with(db, 'credentials_changed')


def test_deleted_member_is_refused(client, db):
    _install(db, _token_row(), _member_row(status='deleted'))
    assert _refused(_login(client))
    assert _revoked_with(db, 'account_unavailable')


def test_suspended_member_gets_the_normal_suspension_answer_without_rotation(client, db):
    _install(db, _token_row(), _member_row(status='suspended'))
    r = _login(client)
    assert r.status_code == 403 and 'suspended' in r.get_json()['message'].lower()
    assert 'token' not in r.get_json()
    assert not db.executed(r'UPDATE biometric_tokens SET prev_token_hash')


def test_admin_role_cannot_use_a_credential(client, db):
    _install(db, _token_row(), _member_row(role='admin'))
    assert _refused(_login(client))
    assert _revoked_with(db, 'role_not_allowed')


def test_password_change_revokes_all_credentials(client, db, auth):
    db.on(r'SELECT password_hash, role FROM members', [{'password_hash': generate_password_hash(PASSWORD), 'role': 'member'}])
    db.on(r'RETURNING token_version', [{'token_version': 1}])
    r = client.post(f'{API}/change-password', headers=auth(MEMBER, tv=0),
                    json={'current_password': PASSWORD, 'new_password': 'NewPassword456!'})
    assert r.status_code == 200, r.get_json()
    assert _revoked_with(db, 'password_changed')


def test_account_deletion_revokes_all_credentials(client, db, auth):
    r = client.delete(f'{API}/delete-account', headers=auth(MEMBER, tv=0))
    assert r.status_code == 200, r.get_json()
    assert _revoked_with(db, 'account_deleted')


# ── logout ───────────────────────────────────────────────────────────────────
def test_plain_logout_keeps_the_credential(client, db, auth):
    r = client.post(f'{API}/logout', headers=auth(MEMBER, tv=0), json={})
    assert r.status_code == 200
    assert not db.executed(r'UPDATE biometric_tokens')
    assert not db.executed(r'UPDATE members SET token_version')


def test_logout_forget_device_revokes_only_that_device(client, db, auth):
    r = client.post(f'{API}/logout', headers=auth(MEMBER, tv=0), json={'forget_device': True, 'device_id': DEVICE})
    assert r.status_code == 200
    rev = db.executed(r'UPDATE biometric_tokens SET revoked_at = NOW\(\).*member_id = %s AND device_id = %s')
    assert len(rev) == 1 and rev[0][1] == ('signed_out', str(MEMBER), DEVICE)
    assert not db.executed(r'UPDATE members SET token_version')


def test_logout_all_devices_bumps_token_version_and_revokes_everything(client, db, auth):
    r = client.post(f'{API}/logout', headers=auth(MEMBER, tv=0), json={'all_devices': True})
    assert r.status_code == 200
    assert db.executed(r'UPDATE members SET token_version = COALESCE\(token_version, 0\) \+ 1')
    assert _revoked_with(db, 'signed_out_everywhere')


def test_logout_requires_a_session(client):
    assert client.post(f'{API}/logout', json={'all_devices': True}).status_code == 401


# ── enrolment (unauthorised minting / refresh) ───────────────────────────────
def test_enrol_requires_a_session(client, db):
    _install(db, None, _member_row())
    r = client.post(f'{API}/biometric/enroll', json={'device_id': DEVICE, 'password': PASSWORD})
    assert r.status_code == 401
    assert not db.executed(r'INSERT INTO biometric_tokens')


def test_enrol_requires_the_current_password(client, db, auth):
    _install(db, None, _member_row())
    h = auth(MEMBER, tv=0)
    assert client.post(f'{API}/biometric/enroll', headers=h, json={'device_id': DEVICE}).status_code == 400
    r = client.post(f'{API}/biometric/enroll', headers=h, json={'device_id': DEVICE, 'password': 'wrong'})
    assert r.status_code == 400  # not 401: must not sign the user out
    assert not db.executed(r'INSERT INTO biometric_tokens')


def test_enrol_wrong_password_locks_out(client, db, auth):
    _install(db, None, _member_row())
    h = auth(MEMBER, tv=0)
    for _ in range(5):
        assert client.post(f'{API}/biometric/enroll', headers=h,
                           json={'device_id': DEVICE, 'password': 'wrong'}).status_code == 400
    r = client.post(f'{API}/biometric/enroll', headers=h, json={'device_id': DEVICE, 'password': PASSWORD})
    assert r.status_code == 429
    assert not db.executed(r'INSERT INTO biometric_tokens')


def test_enrol_rejects_bad_device_id(client, db, auth):
    _install(db, None, _member_row())
    for bad in (None, '', 'short', 'has spaces in it......', 'x' * 65):
        r = client.post(f'{API}/biometric/enroll', headers=auth(MEMBER, tv=0),
                        json={'device_id': bad, 'password': PASSWORD})
        assert r.status_code == 400, bad


def test_admin_cannot_enrol(client, db, auth):
    _install(db, None, _member_row(id=1, role='admin'))
    r = client.post(f'{API}/biometric/enroll', headers=auth(1, tv=0), json={'device_id': DEVICE, 'password': PASSWORD})
    assert r.status_code == 403
    assert not db.executed(r'INSERT INTO biometric_tokens')


def test_enrol_stores_only_a_hash_and_replaces_this_device(client, db, auth):
    _install(db, None, _member_row())
    r = client.post(f'{API}/biometric/enroll', headers=auth(MEMBER, tv=0),
                    json={'device_id': DEVICE, 'password': PASSWORD, 'device_name': 'Pixel\x00 9', 'platform': 'android'})
    assert r.status_code == 201, r.get_json()
    body = r.get_json()
    row_id, secret = body['biometric_token'].split('.', 1)
    assert row_id == '9' and len(secret) >= 43 and body['device_id'] == DEVICE
    ins = db.executed(r'INSERT INTO biometric_tokens')
    assert len(ins) == 1
    params = ins[0][1]
    assert bio.hash_secret(secret) in params and secret not in params and PASSWORD not in str(params)
    assert 'Pixel 9' in params
    assert db.executed(r"UPDATE biometric_tokens SET revoked_at = NOW\(\), revoked_reason = 'replaced'")


# ── revoke endpoint ──────────────────────────────────────────────────────────
def test_signed_in_member_can_revoke_one_device_or_all(client, db, auth):
    h = auth(MEMBER, tv=0)
    assert client.post(f'{API}/biometric/revoke', headers=h, json={'device_id': DEVICE}).status_code == 200
    assert db.executed(r'member_id = %s AND device_id = %s AND revoked_at IS NULL')[-1][1] == ('user_revoked', str(MEMBER), DEVICE)
    assert client.post(f'{API}/biometric/revoke', headers=h, json={'all': True}).status_code == 200
    assert _revoked_with(db, 'user_revoked_all')
    assert client.post(f'{API}/biometric/revoke', headers=h, json={}).status_code == 400


def test_signed_out_device_can_revoke_itself_only_with_its_credential(client, db):
    _install(db, _token_row(), _member_row())
    r = client.post(f'{API}/biometric/revoke', json={'device_id': DEVICE, 'biometric_token': f'7.{SECRET}'})
    assert r.status_code == 200 and _revoked_with(db, 'user_revoked')
    _install(db, _token_row(), _member_row())
    before = len(db.executed(r'UPDATE biometric_tokens'))
    r = client.post(f'{API}/biometric/revoke', json={'device_id': DEVICE, 'biometric_token': '7.' + 'W' * 43})
    assert r.status_code == 200  # same answer, nothing revoked
    assert len(db.executed(r'UPDATE biometric_tokens')) == before


def test_devices_list_requires_session_and_exposes_no_hashes(client, db, auth):
    assert client.get(f'{API}/biometric/devices').status_code == 401
    db.on(r'SELECT id, device_id, device_name, platform', [
        {'id': 7, 'device_id': DEVICE, 'device_name': 'iPhone', 'platform': 'ios',
         'created_at': datetime(2026, 11, 1), 'last_used_at': None, 'expires_at': datetime(2027, 1, 30)}])
    r = client.get(f'{API}/biometric/devices', headers=auth(MEMBER, tv=0))
    assert r.status_code == 200
    assert 'hash' not in str(r.get_json()).lower() and r.get_json()['devices'][0]['device_id'] == DEVICE
