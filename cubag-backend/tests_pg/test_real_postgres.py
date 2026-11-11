"""Security flows executed against a real PostgreSQL server (see conftest.py)."""
from conftest import PASSWORD

API = '/api/v1'
IOS = {'X-Client-Platform': 'ios'}
ANDROID = {'X-Client-Platform': 'android'}


# ── schema ────────────────────────────────────────────────────────────────────
def test_fresh_database_has_expected_schema(sql):
    tables = {r['table_name'] for r in sql(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}
    for t in ('members', 'payments', 'messages', 'otp_codes', 'cti_courses', 'tasks',
              'task_submissions', 'task_submission_files', 'sub_admin_permissions', 'notifications'):
        assert t in tables, f'missing table {t}'
    cols = {r['column_name'] for r in sql(
        "SELECT column_name FROM information_schema.columns WHERE table_name = 'members'")}
    assert {'token_version', 'pending_email', 'password_hash', 'status'} <= cols


def test_init_db_is_idempotent(app, sql):
    from config.db import init_db
    before = sql("SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = 'public'")[0]['n']
    init_db()
    after = sql("SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = 'public'")[0]['n']
    assert before == after and after > 30


# ── login / session revocation ───────────────────────────────────────────────
def test_login_returns_token_with_token_version(member, login, client):
    uid = member(email='a@example.test')
    r = login('a@example.test')
    assert r.status_code == 200, r.get_json()
    tok = r.get_json().get('token') or r.get_json().get('access_token')
    assert tok
    assert client.get(f'{API}/notifications/', headers={'Authorization': f'Bearer {tok}'}).status_code == 200
    assert uid == 1


def test_wrong_password_and_deleted_account_cannot_login(member, login):
    member(email='a@example.test')
    member(email='gone@example.test', status='deleted')
    assert login('a@example.test', 'wrong-password').status_code == 401
    assert login('gone@example.test').status_code == 401


def test_login_email_is_case_insensitive(member, login):
    member(email='MixedCase@example.test')
    assert login('mixedcase@EXAMPLE.test').status_code == 200


def test_password_change_revokes_old_tokens(member, auth, client, sql, login):
    uid = member(email='a@example.test')
    old = auth(uid)
    r = client.post(f'{API}/auth/change-password', headers=old,
                    json={'current_password': PASSWORD, 'new_password': 'NewPassword456!'})
    assert r.status_code == 200, r.get_json()
    fresh = r.get_json()['token']
    assert sql('SELECT token_version FROM members WHERE id = %s', (uid,))[0]['token_version'] == 1
    assert client.get(f'{API}/notifications/', headers=old).status_code == 401
    assert client.get(f'{API}/notifications/', headers={'Authorization': f'Bearer {fresh}'}).status_code == 200
    assert login('a@example.test').status_code == 401
    assert login('a@example.test', 'NewPassword456!').status_code == 200


def test_wrong_current_password_changes_nothing(member, auth, client, sql):
    uid = member()
    r = client.post(f'{API}/auth/change-password', headers=auth(uid),
                    json={'current_password': 'nope', 'new_password': 'NewPassword456!'})
    assert r.status_code == 400
    assert sql('SELECT token_version FROM members WHERE id = %s', (uid,))[0]['token_version'] in (0, None)


def test_delete_account_clears_credentials_and_data(member, auth, client, sql, login):
    uid = member(email='a@example.test', license_number='CUBAG-LIC-1')
    other = member()
    sql('INSERT INTO messages (sender_id, receiver_id, message) VALUES (%s, %s, %s)', (uid, other, 'hello'))
    sql("INSERT INTO notifications (member_id, title, body) VALUES (%s, 't', 'm')", (uid,))
    old = auth(uid)
    r = client.delete(f'{API}/auth/delete-account', headers=old)
    assert r.status_code == 200, r.get_json()
    row = sql('SELECT status, password_hash, license_number, token_version FROM members WHERE id = %s', (uid,))[0]
    assert row['status'] == 'deleted' and row['password_hash'] == '!deleted' and row['license_number'] is None
    assert row['token_version'] >= 1
    assert [m['message'] for m in sql('SELECT message FROM messages WHERE sender_id = %s', (uid,))] == ['[deleted]']
    assert sql('SELECT COUNT(*) AS n FROM notifications WHERE member_id = %s', (uid,))[0]['n'] == 0
    assert client.get(f'{API}/notifications/', headers=old).status_code in (401, 403)
    assert login('a@example.test').status_code == 401
    assert login('CUBAG-LIC-1').status_code == 401


def test_suspended_member_token_is_refused(member, auth, client, sql):
    uid = member()
    h = auth(uid)
    assert client.get(f'{API}/notifications/', headers=h).status_code == 200
    sql("UPDATE members SET status = 'suspended' WHERE id = %s", (uid,))
    from config.cache import cache
    cache.clear()
    assert client.get(f'{API}/notifications/', headers=h).status_code == 403


# ── authorisation with real permission rows ──────────────────────────────────
def test_complaints_list_permissions(member, auth, client, sql):
    admin = member(role='admin')
    plain = member()
    sub_no = member(role='sub_admin')
    sub_yes = member(role='sub_admin')
    sql("INSERT INTO sub_admin_permissions (sub_admin_id, permission_key) VALUES (%s, 'complaints')", (sub_yes,))
    assert client.get(f'{API}/complaints/').status_code == 401
    assert client.get(f'{API}/complaints/', headers=auth(plain)).status_code == 403
    assert client.get(f'{API}/complaints/', headers=auth(sub_no)).status_code == 403
    assert client.get(f'{API}/complaints/', headers=auth(sub_yes)).status_code == 200
    assert client.get(f'{API}/complaints/', headers=auth(admin)).status_code == 200


# ── email change needs a code sent to the new address ────────────────────────
def test_email_change_requires_code(member, auth, client, sql):
    uid = member(email='old@example.test')
    h = auth(uid)
    r = client.put(f'{API}/auth/profile', headers=h, json={'email': 'new@example.test'})
    assert r.status_code == 202 and r.get_json()['email_verification_required'] is True
    assert sql('SELECT email, pending_email FROM members WHERE id = %s', (uid,))[0] == {
        'email': 'old@example.test', 'pending_email': 'new@example.test'}
    code = sql("SELECT code FROM otp_codes WHERE email = 'new@example.test' AND type = 'email_change'")[0]['code']
    wrong = '000000' if code != '000000' else '111111'
    assert client.put(f'{API}/auth/profile', headers=h,
                      json={'email': 'new@example.test', 'email_otp': wrong}).status_code == 400
    assert sql('SELECT email FROM members WHERE id = %s', (uid,))[0]['email'] == 'old@example.test'
    r = client.put(f'{API}/auth/profile', headers=h, json={'email': 'new@example.test', 'email_otp': code})
    assert r.status_code == 200, r.get_json()
    assert sql('SELECT email, pending_email FROM members WHERE id = %s', (uid,))[0] == {
        'email': 'new@example.test', 'pending_email': None}
    assert sql("SELECT COUNT(*) AS n FROM otp_codes WHERE type = 'email_change'")[0]['n'] == 0


def test_email_change_to_existing_address_is_refused(member, auth, client, sql):
    uid = member(email='old@example.test')
    member(email='taken@example.test')
    r = client.put(f'{API}/auth/profile', headers=auth(uid), json={'email': 'taken@example.test'})
    assert r.status_code in (400, 409)
    assert sql('SELECT email FROM members WHERE id = %s', (uid,))[0]['email'] == 'old@example.test'


# ── messaging safety ─────────────────────────────────────────────────────────
def test_message_block_and_report(member, auth, client, sql):
    a, b = member(), member()
    assert client.post(f'{API}/messages/{b}', headers=auth(a), json={'text': 'hello'}).status_code in (200, 201)
    assert sql('SELECT COUNT(*) AS n FROM messages')[0]['n'] == 1
    assert client.post(f'{API}/messages/{a}/block', headers=auth(b)).status_code == 200
    r = client.post(f'{API}/messages/{b}', headers=auth(a), json={'text': 'again'})
    assert r.status_code == 403
    assert sql('SELECT COUNT(*) AS n FROM messages')[0]['n'] == 1
    assert client.delete(f'{API}/messages/{a}/block', headers=auth(b)).status_code == 200
    assert client.post(f'{API}/messages/{b}', headers=auth(a), json={'text': 'again'}).status_code in (200, 201)
    r = client.post(f'{API}/messages/{a}/report', headers=auth(b), json={'reason': 'spam', 'details': 'x'})
    assert r.status_code in (200, 201), r.get_json()
    rep = sql('SELECT reporter_id, reported_member_id, reason, status FROM message_reports')
    assert len(rep) == 1 and rep[0]['reporter_id'] == b and rep[0]['reported_member_id'] == a
    assert sql('SELECT COUNT(*) AS n FROM member_blocks WHERE blocker_id = %s AND blocked_id = %s', (b, a))[0]['n'] == 1


def test_cannot_message_deleted_or_missing_member(member, auth, client):
    a = member()
    gone = member(status='deleted')
    assert client.post(f'{API}/messages/{gone}', headers=auth(a), json={'text': 'hi'}).status_code == 404
    assert client.post(f'{API}/messages/9999', headers=auth(a), json={'text': 'hi'}).status_code == 404


# ── CTI course payment policy with real course rows ──────────────────────────
def _course(sql, title, mode):
    return sql("INSERT INTO cti_courses (title, mode, fee) VALUES (%s, %s, 'GHS 1,500') RETURNING id",
               (title, mode))[0]['id']


def _pay(client, headers, cid, title):
    return client.post(f'{API}/payments/', headers=headers, json={
        'amount': 1500, 'description': f'CTI Course: {title}', 'method': 'momo',
        'phone': '0240000000', 'network': 'MTN',
        'meta': {'type': 'cti_course', 'course_id': cid, 'course_title': title}})


def test_ios_blocked_for_online_and_hybrid_courses_only(member, auth, client, sql):
    uid = member()
    online = _course(sql, 'Online Customs Law', 'Online')
    hybrid = _course(sql, 'Hybrid Valuation', 'Hybrid')
    inperson = _course(sql, 'Classroom Tariff', 'In-Person')
    for cid, title in ((online, 'Online Customs Law'), (hybrid, 'Hybrid Valuation')):
        r = _pay(client, {**auth(uid), **IOS}, cid, title)
        assert r.status_code == 403
        assert r.get_json()['error_code'] == 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'
    assert sql('SELECT COUNT(*) AS n FROM payments')[0]['n'] == 0
    r = _pay(client, {**auth(uid), **IOS}, inperson, 'Classroom Tariff')
    assert (r.get_json() or {}).get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'
    r = _pay(client, {**auth(uid), **ANDROID}, online, 'Online Customs Law')
    assert (r.get_json() or {}).get('error_code') != 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'


def test_ios_block_cannot_be_bypassed_by_omitting_course_id(member, auth, client, sql):
    uid = member()
    _course(sql, 'Online Customs Law', 'Online')
    r = client.post(f'{API}/payments/', headers={**auth(uid), **IOS}, json={
        'amount': 1500, 'description': 'CTI Course: Online Customs Law', 'method': 'momo',
        'phone': '0240000000', 'network': 'MTN'})
    assert r.status_code == 403
    assert sql('SELECT COUNT(*) AS n FROM payments')[0]['n'] == 0


def test_course_list_flags_per_platform(member, auth, client, sql):
    uid = member()
    _course(sql, 'Online Customs Law', 'Online')
    _course(sql, 'Classroom Tariff', 'In-Person')
    def flags(platform):
        body = client.get(f'{API}/events/courses', headers={**auth(uid), **platform}).get_json()
        items = body if isinstance(body, list) else body.get('courses') or body.get('items')
        return {c['title']: (c['delivery_mode'], c['in_app_payment_available']) for c in items}
    assert flags(IOS) == {'Online Customs Law': ('online', False), 'Classroom Tariff': ('in_person', True)}
    assert flags(ANDROID) == {'Online Customs Law': ('online', True), 'Classroom Tariff': ('in_person', True)}


# ── signed document access uses real ownership rows ──────────────────────────
def test_receipt_signing_checks_real_owner(member, auth, client, sql):
    owner, other, admin = member(), member(), member(role='admin')
    url = '/static/uploads/receipts/r1.jpg'
    sql("INSERT INTO payments (member_id, amount, description, status, receipt_url) VALUES (%s, 10, 'x', 'pending', %s)",
        (owner, url))
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}).status_code == 401
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(other)).status_code == 403
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(owner)).status_code == 200
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(admin)).status_code == 200


# ── transactions ─────────────────────────────────────────────────────────────
def test_failed_statement_rolls_back_and_pool_recovers(app, sql, member):
    from config.db import get_db
    uid = member(email='dup@example.test')
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE members SET name = 'changed' WHERE id = %s", (uid,))
            try:
                cur.execute("INSERT INTO members (name, email) VALUES ('x', 'dup@example.test')")
                raised = False
            except Exception:
                raised = True
        assert raised
        conn.rollback()
    finally:
        conn.close()
    assert sql('SELECT name FROM members WHERE id = %s', (uid,))[0]['name'] != 'changed'
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT 1 AS ok')
            assert cur.fetchone()['ok'] == 1
    finally:
        conn.close()
