"""SEC-14 against real PostgreSQL: the stateful behaviour the fake DB cannot prove
(rotation, single use, row locking, revocation on account security events)."""
import threading

from conftest import PASSWORD

API = '/api/v1/auth'
DEVICE = 'device-AAAAAAAAAAAAAAAA'
DEVICE2 = 'device-BBBBBBBBBBBBBBBB'
BAD = 'BIOMETRIC_TOKEN_INVALID'


def _enrol(client, headers, device=DEVICE, password=PASSWORD, **extra):
    return client.post(f'{API}/biometric/enroll', headers=headers,
                       json={'device_id': device, 'password': password, **extra})


def _bio_login(client, credential, device=DEVICE):
    return client.post(f'{API}/biometric/login', json={'biometric_token': credential, 'device_id': device})


def _refused(r):
    return r.status_code == 401 and r.get_json().get('error_code') == BAD


def _setup(member, auth, client, **kw):
    uid = member(email='bio@example.test', **kw)
    r = _enrol(client, auth(uid), device_name='Test phone', platform='ios')
    assert r.status_code == 201, r.get_json()
    return uid, r.get_json()['biometric_token']


def _row(sql, uid, device=DEVICE):
    return sql('SELECT * FROM biometric_tokens WHERE member_id = %s AND device_id = %s ORDER BY id DESC LIMIT 1',
               (uid, device))[0]


def test_schema_stores_hashes_only(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    secret = cred.split('.', 1)[1]
    row = _row(sql, uid)
    assert len(row['token_hash'].strip()) == 64 and row['prev_token_hash'] is None
    dump = str(sql('SELECT * FROM biometric_tokens'))
    assert secret not in dump and PASSWORD not in dump
    assert row['device_name'] == 'Test phone' and row['platform'] == 'ios' and row['revoked_at'] is None
    days = sql("SELECT EXTRACT(EPOCH FROM (expires_at - created_at)) / 86400 AS d FROM biometric_tokens")[0]['d']
    assert 89 < float(days) < 91


def test_valid_credential_signs_in_rotates_and_new_one_works(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    r = _bio_login(client, cred)
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body['user']['id'] == uid and body['user']['email'] == 'bio@example.test'
    assert client.get('/api/v1/notifications/', headers={'Authorization': f"Bearer {body['token']}"}).status_code == 200
    second = body['biometric_token']
    assert second != cred
    assert _row(sql, uid)['last_used_at'] is not None
    r2 = _bio_login(client, second)
    assert r2.status_code == 200 and r2.get_json()['biometric_token'] not in (cred, second)


def test_reuse_of_a_rotated_credential_kills_the_device(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    second = _bio_login(client, cred).get_json()['biometric_token']
    assert _refused(_bio_login(client, cred))          # replay of the old one
    assert _row(sql, uid)['revoked_reason'] == 'reuse_detected'
    assert _refused(_bio_login(client, second))        # the legitimate one is cut off too


def test_expired_credential(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    sql("UPDATE biometric_tokens SET expires_at = NOW() - INTERVAL '1 minute' WHERE member_id = %s", (uid,))
    assert _refused(_bio_login(client, cred))
    assert _row(sql, uid)['revoked_reason'] == 'expired'


def test_revoked_credential(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    assert client.post(f'{API}/biometric/revoke', headers=auth(uid), json={'device_id': DEVICE}).status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'user_revoked'
    assert _refused(_bio_login(client, cred))


def test_device_mismatch_revokes(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    assert _refused(_bio_login(client, cred, device=DEVICE2))
    assert _row(sql, uid)['revoked_reason'] == 'device_mismatch'
    assert _refused(_bio_login(client, cred))


def test_credential_of_one_member_cannot_be_used_as_another(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    other = member(email='other@example.test')
    other_cred = _enrol(client, auth(other), device=DEVICE2).get_json()['biometric_token']
    row_a, secret_a = cred.split('.', 1)
    row_b, secret_b = other_cred.split('.', 1)
    assert _refused(_bio_login(client, f'{row_b}.{secret_a}', device=DEVICE2))   # A's secret on B's row
    assert _refused(_bio_login(client, f'{row_a}.{secret_b}'))                   # B's secret on A's row
    assert _bio_login(client, cred).get_json()['user']['id'] == uid


def test_wrong_secret_five_times_revokes(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    row_id = cred.split('.', 1)[0]
    for _ in range(5):
        assert _refused(_bio_login(client, f'{row_id}.' + 'W' * 43))
    assert _row(sql, uid)['revoked_at'] is None
    assert _refused(_bio_login(client, cred))
    assert _row(sql, uid)['revoked_reason'] == 'too_many_attempts'


def test_password_change_revokes_and_reenrolment_works(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    r = client.post(f'{API}/change-password', headers=auth(uid),
                    json={'current_password': PASSWORD, 'new_password': 'NewPassword456!'})
    assert r.status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'password_changed'
    assert _refused(_bio_login(client, cred))
    fresh = {'Authorization': f"Bearer {r.get_json()['token']}"}
    assert _enrol(client, fresh, password=PASSWORD).status_code == 400          # old password no longer enrols
    r2 = _enrol(client, fresh, password='NewPassword456!')
    assert r2.status_code == 201
    assert _bio_login(client, r2.get_json()['biometric_token']).status_code == 200


def test_token_version_bump_alone_invalidates(member, auth, client, sql):
    """Even if a revocation were missed, a credential issued under an older token_version is dead."""
    uid, cred = _setup(member, auth, client)
    sql('UPDATE members SET token_version = COALESCE(token_version, 0) + 1 WHERE id = %s', (uid,))
    assert _refused(_bio_login(client, cred))
    assert _row(sql, uid)['revoked_reason'] == 'credentials_changed'


def test_password_reset_revokes(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    sql("INSERT INTO otp_codes (email, code, type) VALUES ('bio@example.test', '123456', 'password_reset')")
    r = client.post(f'{API}/reset-password', json={'email': 'bio@example.test', 'code': '123456',
                                                   'new_password': 'ResetPassword789!'})
    assert r.status_code == 200, r.get_json()
    assert _row(sql, uid)['revoked_reason'] == 'password_reset'
    assert _refused(_bio_login(client, cred))


def test_email_change_revokes(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    h = auth(uid)
    assert client.put(f'{API}/profile', headers=h, json={'email': 'new@example.test'}).status_code == 202
    assert _row(sql, uid)['revoked_at'] is None            # not until the change is confirmed
    code = sql("SELECT code FROM otp_codes WHERE type = 'email_change'")[0]['code']
    assert client.put(f'{API}/profile', headers=h, json={'email': 'new@example.test', 'email_otp': code}).status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'email_changed'
    assert _refused(_bio_login(client, cred))


def test_profile_edit_without_email_change_keeps_credential(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    assert client.put(f'{API}/profile', headers=auth(uid), json={'phone': '0249999999'}).status_code == 200
    assert _row(sql, uid)['revoked_at'] is None
    assert _bio_login(client, cred).status_code == 200


def test_account_deletion_revokes(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    assert client.delete(f'{API}/delete-account', headers=auth(uid)).status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'account_deleted'
    assert _refused(_bio_login(client, cred))


def test_suspended_member_cannot_use_credential_and_it_is_not_consumed(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    sql("UPDATE members SET status = 'suspended' WHERE id = %s", (uid,))
    r = _bio_login(client, cred)
    assert r.status_code == 403 and 'token' not in r.get_json()
    row = _row(sql, uid)
    assert row['prev_token_hash'] is None and row['revoked_at'] is None
    sql("UPDATE members SET status = 'active' WHERE id = %s", (uid,))
    from config.cache import cache
    cache.clear()
    assert _bio_login(client, cred).status_code == 200      # reinstated: same credential still good


def test_logout_variants(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    cred2 = _enrol(client, auth(uid), device=DEVICE2).get_json()['biometric_token']
    h = auth(uid)
    # plain logout: credential stays (that is what lets Face ID sign back in)
    assert client.post(f'{API}/logout', headers=h, json={}).status_code == 200
    cred = _bio_login(client, cred).get_json()['biometric_token']
    # forget this device only
    assert client.post(f'{API}/logout', headers=h, json={'forget_device': True, 'device_id': DEVICE}).status_code == 200
    assert _refused(_bio_login(client, cred))
    cred2 = _bio_login(client, cred2, device=DEVICE2).get_json()['biometric_token']
    # sign out everywhere
    assert client.post(f'{API}/logout', headers=h, json={'all_devices': True}).status_code == 200
    assert client.get('/api/v1/notifications/', headers=h).status_code == 401
    assert _refused(_bio_login(client, cred2, device=DEVICE2))
    assert _row(sql, uid, DEVICE2)['revoked_reason'] == 'signed_out_everywhere'


def test_member_cannot_revoke_another_members_device(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    other = member(email='other@example.test')
    assert client.post(f'{API}/biometric/revoke', headers=auth(other), json={'device_id': DEVICE}).status_code == 200
    assert client.post(f'{API}/biometric/revoke', headers=auth(other), json={'all': True}).status_code == 200
    assert _row(sql, uid)['revoked_at'] is None
    assert _bio_login(client, cred).status_code == 200


def test_enrolment_rules(member, auth, client, sql):
    uid = member(email='bio@example.test')
    admin = member(role='admin', email='admin@example.test')
    assert _enrol(client, {}).status_code == 401
    assert _enrol(client, auth(uid), password='wrong').status_code == 400
    assert _enrol(client, auth(admin)).status_code == 403
    assert sql('SELECT COUNT(*) AS n FROM biometric_tokens')[0]['n'] == 0
    first = _enrol(client, auth(uid)).get_json()['biometric_token']
    second = _enrol(client, auth(uid)).get_json()['biometric_token']      # same device again
    assert _refused(_bio_login(client, first))
    assert _bio_login(client, second).status_code == 200
    assert sql('SELECT COUNT(*) AS n FROM biometric_tokens WHERE revoked_at IS NULL')[0]['n'] == 1


def test_device_cap_revokes_the_oldest(member, auth, client, sql):
    uid = member(email='bio@example.test')
    creds = {}
    for i in range(6):
        dev = f'device-{i:016d}'
        creds[dev] = _enrol(client, auth(uid), device=dev).get_json()['biometric_token']
    assert sql('SELECT COUNT(*) AS n FROM biometric_tokens WHERE revoked_at IS NULL')[0]['n'] == 5
    oldest = 'device-' + '0' * 16
    assert _row(sql, uid, oldest)['revoked_reason'] == 'device_limit'
    assert _refused(_bio_login(client, creds[oldest], device=oldest))
    r = client.get(f'{API}/biometric/devices', headers=auth(uid))
    assert len(r.get_json()['devices']) == 5 and 'hash' not in str(r.get_json())


def test_admin_promoted_after_enrolment_cannot_use_credential(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    sql("UPDATE members SET role = 'admin' WHERE id = %s", (uid,))
    assert _refused(_bio_login(client, cred))
    assert _row(sql, uid)['revoked_reason'] == 'role_not_allowed'


def test_two_simultaneous_uses_cannot_both_succeed(app, member, auth, sql):
    """Row lock: the same credential presented twice at once yields at most one session."""
    uid = member(email='bio@example.test')
    c0 = app.test_client()
    cred = _enrol(c0, auth(uid)).get_json()['biometric_token']
    results = []
    barrier = threading.Barrier(2)

    def use():
        c = app.test_client()
        barrier.wait()
        results.append(_bio_login(c, cred).status_code)

    threads = [threading.Thread(target=use) for _ in range(2)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(results) == [200, 401], results
    # the loser presented a rotated credential -> reuse detected -> device revoked
    assert _row(sql, uid)['revoked_reason'] == 'reuse_detected'


def test_deleting_the_member_row_cascades(member, auth, client, sql):
    uid, _ = _setup(member, auth, client)
    sql('DELETE FROM members WHERE id = %s', (uid,))
    assert sql('SELECT COUNT(*) AS n FROM biometric_tokens')[0]['n'] == 0


def test_presented_credential_is_revoked_even_when_someone_else_is_signed_in(member, auth, client, sql):
    """Shared phone: member B signs in and turns biometrics off; A's credential held by the phone dies too."""
    uid, cred = _setup(member, auth, client)
    other = member(email='other@example.test')
    r = client.post(f'{API}/biometric/revoke', headers=auth(other), json={'device_id': DEVICE, 'biometric_token': cred})
    assert r.status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'user_revoked'
    assert _refused(_bio_login(client, cred))


def test_signed_out_device_revokes_itself_but_a_guess_revokes_nothing(member, auth, client, sql):
    uid, cred = _setup(member, auth, client)
    row_id = cred.split('.', 1)[0]
    assert client.post(f'{API}/biometric/revoke', json={'device_id': DEVICE, 'biometric_token': f'{row_id}.' + 'W' * 43}).status_code == 200
    assert _row(sql, uid)['revoked_at'] is None
    assert client.post(f'{API}/biometric/revoke', json={'device_id': DEVICE, 'biometric_token': cred}).status_code == 200
    assert _row(sql, uid)['revoked_reason'] == 'user_revoked'
