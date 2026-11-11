"""SEC-12: administrators need an emailed one-time code after their password."""
import re
from datetime import timedelta

import pytest
from werkzeug.security import generate_password_hash

API = '/api/v1/auth'
PW = 'Correct-horse-9'
PW_HASH = generate_password_hash(PW)


def _member(role='admin', **kw):
    m = {
        'id': 1 if role != 'member' else 10, 'role': role, 'status': 'active', 'email_verified': True,
        'email': 'chief@cubag.example', 'name': 'Chief', 'company': 'CUBAG', 'member_type': 'Corporate',
        'port_of_operation': 'Tema', 'license_expiry_date': None, 'password_hash': PW_HASH,
        'token_version': 0,
    }
    m.update(kw)
    return m


@pytest.fixture()
def mfa(client, db, monkeypatch):
    """Login wiring + an in-memory admin_mfa_challenges table + captured emails."""
    import routes.auth as auth_routes
    from config import admin_mfa

    sent = []
    monkeypatch.setattr(auth_routes, '_send_email', lambda to, subj, body, html=None: sent.append((to, body)) or True)
    row = {}

    def insert(p):
        row.clear()
        row.update(id=5, member_id=p[0], token_hash=p[1], code_hash=p[2], expires_at=p[3], attempts=0, used_at=None)
        return [{'id': 5}]

    db.on(r'INSERT INTO admin_mfa_challenges', insert)
    db.on(r'UPDATE admin_mfa_challenges SET code_hash', lambda p: row.update(code_hash=p[0]) or [])
    db.on(r'FROM admin_mfa_challenges WHERE id', lambda p: [dict(row)] if row else [])
    db.on(r'UPDATE admin_mfa_challenges SET attempts', lambda p: row.update(attempts=p[0], used_at=p[1]) or [])
    db.on(r'UPDATE admin_mfa_challenges SET used_at = %s WHERE id', lambda p: row.update(used_at=p[0]) or [])

    class Ctx:
        pass
    c = Ctx()
    c.sent, c.row, c.client, c.db, c.mod = sent, row, client, db, admin_mfa

    def as_user(member):
        db.on(r'SELECT \* FROM members WHERE LOWER\(email\)', [member])
        db.on(r'SELECT \* FROM members WHERE id = %s', [member])
    c.as_user = as_user

    def login():
        return client.post(f'{API}/login', json={'email': 'chief@cubag.example', 'password': PW})
    c.login = login

    def code():
        return re.search(r'\b(\d{6})\b', sent[-1][1]).group(1)
    c.code = code
    return c


def test_admin_password_alone_gets_no_token(mfa):
    mfa.as_user(_member())
    r = mfa.login()
    body = r.get_json()
    assert r.status_code == 202 and body['mfa_required'] is True
    assert 'token' not in body and body['mfa_token']
    assert body['email_hint'] == 'c***@cubag.example'
    assert mfa.sent and mfa.sent[-1][0] == 'chief@cubag.example'


@pytest.mark.parametrize('role', ['admin', 'sub_admin', 'super_admin'])
def test_correct_code_completes_sign_in_once(mfa, role):
    mfa.as_user(_member(role=role))
    challenge = mfa.login().get_json()['mfa_token']
    r = mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': mfa.code()})
    assert r.status_code == 200 and r.get_json()['token']
    assert r.get_json()['user']['role'] == role
    again = mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': mfa.code()})
    assert again.status_code == 401


def test_wrong_codes_burn_the_challenge(mfa):
    mfa.as_user(_member())
    challenge = mfa.login().get_json()['mfa_token']
    good = mfa.code()
    bad = '000000' if good != '000000' else '111111'
    for _ in range(mfa.mod.MAX_WRONG_ATTEMPTS - 1):
        r = mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': bad})
        assert r.status_code == 400
    assert mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': bad}).status_code == 401
    assert mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': good}).status_code == 401


def test_expired_challenge_is_refused(mfa):
    mfa.as_user(_member())
    challenge = mfa.login().get_json()['mfa_token']
    mfa.row['expires_at'] = mfa.mod._utcnow() - timedelta(seconds=1)
    r = mfa.client.post(f'{API}/login/mfa', json={'mfa_token': challenge, 'code': mfa.code()})
    assert r.status_code == 401


def test_forged_challenge_secret_is_refused(mfa):
    mfa.as_user(_member())
    mfa.login()
    r = mfa.client.post(f'{API}/login/mfa', json={'mfa_token': '5.' + 'A' * 43, 'code': mfa.code()})
    assert r.status_code == 401


def test_member_sign_in_is_unchanged(mfa):
    mfa.as_user(_member(role='member'))
    r = mfa.login()
    assert r.status_code == 200 and r.get_json()['token']
    assert not mfa.sent


def test_suspended_admin_gets_no_code(mfa):
    mfa.as_user(_member(status='suspended'))
    r = mfa.login()
    assert r.status_code == 403 and not mfa.sent and 'token' not in r.get_json()


def test_email_failure_issues_nothing(mfa, monkeypatch):
    import routes.auth as auth_routes
    monkeypatch.setattr(auth_routes, '_send_email', lambda *a, **k: False)
    mfa.as_user(_member())
    r = mfa.login()
    assert r.status_code == 503 and 'token' not in r.get_json() and 'mfa_token' not in r.get_json()


def test_emergency_switch_off(mfa, monkeypatch):
    monkeypatch.setenv('ADMIN_MFA_REQUIRED', 'false')
    mfa.as_user(_member())
    r = mfa.login()
    assert r.status_code == 200 and r.get_json()['token']
