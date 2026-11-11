"""Regression tests for audit findings SEC-01/02/03/05/06/07/15/16/17/18/19 and BUG-02."""
import datetime
import hashlib
import hmac
import json
import time

API = '/api/v1'


# ── SEC-01 / SEC-02: complaints are admin-only ──────────────────────────────

def test_sec01_list_complaints_requires_admin(client, auth):
    assert client.get(f'{API}/complaints').status_code == 401
    assert client.get(f'{API}/complaints', headers=auth(10)).status_code == 403   # member
    assert client.get(f'{API}/complaints', headers=auth(2)).status_code == 403    # sub-admin, no perm
    assert client.get(f'{API}/complaints', headers=auth(3)).status_code == 200    # sub-admin, perm
    assert client.get(f'{API}/complaints', headers=auth(1)).status_code == 200    # admin


def test_sec01_legacy_prefix_also_protected(client, auth):
    assert client.get('/api/complaints', headers=auth(10)).status_code == 403


def test_sec02_member_cannot_update_complaint(client, auth, db):
    r = client.put(f'{API}/complaints/CMP-2026-12345/status', headers=auth(10),
                   json={'status': 'Resolved', 'resolution_notes': 'fake'})
    assert r.status_code == 403
    assert not db.executed(r'UPDATE complaints')


def test_sec02_admin_can_update_complaint(client, auth, db):
    db.on(r'UPDATE complaints', [{'complaint_id': 'CMP-2026-12345', 'status': 'Resolved',
                                   'resolution_notes': 'ok', 'updated_at': None}])
    r = client.put(f'{API}/complaints/CMP-2026-12345/status', headers=auth(1), json={'status': 'Resolved'})
    assert r.status_code == 200
    assert db.executed(r'INSERT INTO audit_log')


# ── SEC-03: certificate PDF ─────────────────────────────────────────────────

def _member_row(mid, status='active', lic='CUBAG-LIC-2026-0010'):
    return [{'id': mid, 'name': 'Ama Mensah', 'company': 'Mensah Logistics', 'license_number': lic,
             'member_type': 'Corporate', 'port_of_operation': 'Tema Port', 'status': status,
             'license_expiry_date': datetime.date.today() + datetime.timedelta(days=100),
             'good_standing': True, 'package_fee_paid': True}]


def test_sec03_certificate_requires_auth(client):
    assert client.get(f'{API}/members/10/certificate-pdf').status_code == 401


def test_sec03_other_member_forbidden(client, auth):
    assert client.get(f'{API}/members/10/certificate-pdf', headers=auth(11)).status_code == 403


def test_sec03_pending_member_gets_no_certificate_and_no_db_write(client, auth, db):
    db.on(r'FROM members WHERE id = %s', lambda p: _member_row(12, status='pending', lic=None))
    r = client.get(f'{API}/members/12/certificate-pdf', headers=auth(12))
    assert r.status_code == 403
    assert not db.executed(r'UPDATE members SET license_number')


def test_sec03_active_owner_gets_pdf(client, auth, db):
    db.on(r'license_expiry_date, good_standing, package_fee_paid FROM members', lambda p: _member_row(10))
    r = client.get(f'{API}/members/10/certificate-pdf', headers=auth(10))
    assert r.status_code == 200, r.get_data(as_text=True)[:300]
    assert r.mimetype == 'application/pdf'
    assert not db.executed(r'UPDATE members')


def test_sec03_query_token_still_supported_for_pdf_viewer(client, token, db):
    db.on(r'license_expiry_date, good_standing, package_fee_paid FROM members', lambda p: _member_row(10))
    r = client.get(f'{API}/members/10/certificate-pdf?token={token(10)}')
    assert r.status_code == 200


def test_sec03_missing_licence_number_is_not_invented(client, auth, db):
    db.on(r'license_expiry_date, good_standing, package_fee_paid FROM members', lambda p: _member_row(10, lic=None))
    r = client.get(f'{API}/members/10/certificate-pdf', headers=auth(10))
    assert r.status_code == 409
    assert not db.executed(r'UPDATE members')


# ── SEC-05: news image proxy is no longer an open proxy ─────────────────────

def test_sec05_proxy_requires_auth(client):
    assert client.get(f'{API}/news/proxy-image?url=http://169.254.169.254/').status_code == 401


def test_sec05_proxy_rejects_non_allowlisted_hosts(client, auth):
    for url in ('http://169.254.169.254/latest', 'https://evil.example.com/x.html', 'file:///etc/passwd'):
        r = client.get(f'{API}/news/proxy-image', query_string={'url': url}, headers=auth(10))
        assert r.status_code in (400, 403), url


# ── SEC-06: GDPR + fee settings need explicit permissions ───────────────────

def test_sec06_sub_admin_without_permission_blocked(client, auth):
    h = auth(2)
    assert client.get(f'{API}/gdpr/export/member/10', headers=h).status_code == 403
    assert client.post(f'{API}/gdpr/deletion/approve/1', headers=h).status_code == 403
    assert client.post(f'{API}/gdpr/deletion/request', headers=h, json={'member_id': 10}).status_code == 403
    assert client.get(f'{API}/gdpr/deletion/requests', headers=h).status_code == 403
    assert client.put(f'{API}/compliance-settings/', headers=h, json={'renewal_fee': 1}).status_code == 403


def test_sec06_members_blocked(client, auth):
    assert client.get(f'{API}/gdpr/export/member/11', headers=auth(10)).status_code == 403


# ── SEC-07 / BUG-02 / SEC-16: session & account status ─────────────────────

def test_bug02_expired_token_gives_401_not_503(client, auth):
    h = auth(10, expires=datetime.timedelta(seconds=-60))
    r = client.get(f'{API}/notifications/', headers=h)
    assert r.status_code == 401


def test_bug02_garbage_token_on_public_route_is_ignored(client, db):
    r = client.get(f'{API}/members/public/fees', headers={'Authorization': 'Bearer not-a-jwt'})
    assert r.status_code != 503


def test_sec07_deleted_account_token_rejected(client, auth):
    r = client.get(f'{API}/notifications/', headers=auth(13))
    assert r.status_code == 401


def test_sec07_deleted_account_cannot_use_auth_me(client, auth):
    assert client.get(f'{API}/auth/me', headers=auth(13)).status_code == 401


def test_sec07_suspended_account_blocked(client, auth):
    assert client.get(f'{API}/notifications/', headers=auth(14)).status_code == 403


def test_sec07_deleted_account_cannot_login_by_licence_number(client, db):
    from werkzeug.security import generate_password_hash
    row = {'id': 13, 'name': 'X', 'email': 'deleted_13@deleted.invalid', 'status': 'deleted', 'role': 'member',
           'password_hash': generate_password_hash('Password123'), 'email_verified': True}
    db.on(r'LOWER\(agency_code\) = LOWER\(%s\) OR LOWER\(license_number\)', [row])
    r = client.post(f'{API}/auth/login', json={'identifier': 'CUBAG-LIC-2026-0013', 'password': 'Password123'})
    assert r.status_code == 401


def test_sec07_delete_account_clears_credentials_and_bumps_token_version(client, auth, db):
    r = client.delete(f'{API}/auth/delete-account', headers=auth(10))
    assert r.status_code == 200
    upd = db.executed(r"UPDATE members SET status = 'deleted'")
    assert upd, 'deletion UPDATE not executed'
    sql = upd[0][0]
    for col in ("password_hash = '!deleted'", 'agency_code = NULL', 'license_number = NULL', 'token_version'):
        assert col in sql


def test_sec16_old_token_rejected_after_token_version_bump(client, auth):
    from conftest import USERS
    USERS[11]['tv'] = 2
    try:
        assert client.get(f'{API}/notifications/', headers=auth(11, tv=1)).status_code == 401
        assert client.get(f'{API}/notifications/', headers=auth(11)).status_code == 401   # legacy token, no tv
        assert client.get(f'{API}/notifications/', headers=auth(11, tv=2)).status_code == 200
    finally:
        USERS[11].pop('tv', None)


def test_sec16_password_reset_bumps_token_version(client, db):
    db.on(r"type = 'password_reset'", [{'email': 'a@b.com', 'code': '12345678'}])
    db.on(r'SELECT id FROM members WHERE LOWER\(email\)', [{'id': 10}])
    r = client.post(f'{API}/auth/reset-password', json={'email': 'a@b.com', 'code': '12345678', 'new_password': 'NewPassword1'})
    assert r.status_code == 200
    assert db.executed(r'token_version = COALESCE\(token_version, 0\) \+ 1')


def test_change_password_wrong_current_is_400_not_401(client, auth, db):
    from werkzeug.security import generate_password_hash
    db.on(r'SELECT password_hash, role FROM members', [{'password_hash': generate_password_hash('right-pass'), 'role': 'member'}])
    r = client.post(f'{API}/auth/change-password', headers=auth(10),
                    json={'current_password': 'wrong-pass', 'new_password': 'NewPassword1'})
    assert r.status_code == 400


def test_change_password_returns_fresh_token(client, auth, db):
    from werkzeug.security import generate_password_hash
    db.on(r'SELECT password_hash, role FROM members', [{'password_hash': generate_password_hash('right-pass'), 'role': 'member'}])
    db.on(r'RETURNING token_version', [{'token_version': 1}])
    r = client.post(f'{API}/auth/change-password', headers=auth(10),
                    json={'current_password': 'right-pass', 'new_password': 'NewPassword1'})
    assert r.status_code == 200
    assert r.get_json().get('token')


# ── SEC-15: email change needs verification ─────────────────────────────────

def test_sec15_email_change_without_code_is_not_applied(client, auth, db):
    db.on(r'SELECT email FROM members WHERE id', [{'email': 'old@x.com'}])
    r = client.put(f'{API}/auth/profile', headers=auth(10), json={'email': 'attacker@evil.com'})
    assert r.status_code == 202
    assert r.get_json().get('email_verification_required') is True
    assert not db.executed(r'UPDATE members SET email = %s')


def test_sec15_email_change_with_wrong_code_rejected(client, auth, db):
    db.on(r'SELECT email FROM members WHERE id', [{'email': 'old@x.com'}])
    r = client.put(f'{API}/auth/profile', headers=auth(10), json={'email': 'new@x.com', 'email_otp': '000000'})
    assert r.status_code == 400
    assert not db.executed(r'UPDATE members SET email = %s')


def test_sec15_email_change_with_valid_code_applied(client, auth, db):
    db.on(r'SELECT email FROM members WHERE id', [{'email': 'old@x.com'}])
    db.on(r"o.type = 'email_change'", [{'?column?': 1}])
    r = client.put(f'{API}/auth/profile', headers=auth(10), json={'email': 'new@x.com', 'email_otp': '123456'})
    assert r.status_code == 200, r.get_json()
    assert db.executed(r'UPDATE members SET email = %s')


def test_sec15_phone_update_unaffected(client, auth, db):
    r = client.put(f'{API}/auth/profile', headers=auth(10), json={'phone': '0240000000'})
    assert r.status_code == 200
    assert db.executed(r'UPDATE members SET phone = %s')


# ── SEC-17: login lockout + IP header trust ─────────────────────────────────

def test_sec17_per_account_lockout(client, db):
    for i in range(10):
        client.post(f'{API}/auth/login', json={'identifier': 'victim@x.com', 'password': 'bad'},
                    headers={'Fly-Client-IP': f'10.0.0.{i}'})
    r = client.post(f'{API}/auth/login', json={'identifier': 'victim@x.com', 'password': 'bad'},
                    headers={'Fly-Client-IP': '10.0.1.1'})
    assert r.status_code == 429


def test_sec17_spoofed_cf_header_does_not_reset_ip_limit(client):
    statuses = []
    for i in range(14):
        r = client.post(f'{API}/auth/login', json={'identifier': f'u{i}@x.com', 'password': 'bad'},
                        headers={'Fly-Client-IP': '203.0.113.9', 'CF-Connecting-IP': f'1.2.3.{i}'})
        statuses.append(r.status_code)
    assert 429 in statuses


# ── SEC-18: no internals in 5xx responses ───────────────────────────────────

def test_sec18_5xx_bodies_are_scrubbed(client, auth, db):
    def boom(params):
        raise Exception('relation "notifications" does not exist at /app/routes/notifications.py')
    db.on(r'SELECT id FROM notifications', boom)
    r = client.delete(f'{API}/notifications/5', headers=auth(10))
    body = r.get_json()
    assert r.status_code == 500
    assert 'relation' not in json.dumps(body) and '/app/' not in json.dumps(body)
    assert body.get('error_id')


# ── SEC-19: compliance webhook fails closed ─────────────────────────────────

def _signed(body: bytes, secret='whsec-test', ts=None):
    ts = str(int(time.time()) if ts is None else ts)
    sig = 'sha256=' + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return {'X-Whitsun-Signature': sig, 'X-Whitsun-Timestamp': ts, 'Content-Type': 'application/json'}


def test_sec19_unsigned_webhook_rejected(client, db):
    body = json.dumps({'transactionReference': 'REF1', 'status': 'successful', 'amount': 1}).encode()
    r = client.post(f'{API}/compliance/payment-webhook', data=body, headers={'Content-Type': 'application/json'})
    assert r.status_code == 401
    assert not db.executed(r'UPDATE compliance_applications')


def test_sec19_stale_signed_webhook_rejected(client):
    body = json.dumps({'transactionReference': 'REF1', 'status': 'successful'}).encode()
    r = client.post(f'{API}/compliance/payment-webhook', data=body, headers=_signed(body, ts=int(time.time()) - 3600))
    assert r.status_code == 401


def test_sec19_valid_signed_webhook_accepted(client):
    body = json.dumps({'transactionReference': 'NOPE', 'status': 'successful'}).encode()
    r = client.post(f'{API}/compliance/payment-webhook', data=body, headers=_signed(body))
    assert r.status_code == 200


def test_reset_email_leads_with_code_not_in_subject(monkeypatch):
    import routes.auth as auth_routes
    sent = {}
    monkeypatch.setattr(auth_routes, '_send_email',
                        lambda to, subj, txt, html=None: sent.update(subj=subj, txt=txt, html=html) or True)
    auth_routes.send_reset_email('ama+cubag@example.com', '12345678')
    assert '12345678' not in sent['subj']
    assert '1234 5678' in sent['txt'] and '1234 5678' in sent['html']
    assert 'email=ama%2Bcubag%40example.com' in sent['txt']
