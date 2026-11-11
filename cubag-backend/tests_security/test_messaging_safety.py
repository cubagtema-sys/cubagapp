"""Messaging safety (Apple 1.2 / Google Play UGC) and BUG-12."""
API = '/api/v1'


def _recipient(db, status='active'):
    db.on(r'SELECT status, role FROM members WHERE id = %s', [{'status': status, 'role': 'member'}])
    db.on(r'INSERT INTO messages', [{'id': 1, 'created_at': None}])


def test_message_length_limited(client, auth, db):
    _recipient(db)
    r = client.post(f'{API}/messages/11', headers=auth(10), json={'text': 'x' * 2001})
    assert r.status_code == 400
    assert not db.executed(r'INSERT INTO messages')


def test_cannot_message_deleted_or_unknown_member(client, auth, db):
    _recipient(db, status='deleted')
    assert client.post(f'{API}/messages/11', headers=auth(10), json={'text': 'hi'}).status_code == 404


def test_blocked_member_cannot_send(client, auth, db):
    _recipient(db)
    db.on(r'FROM member_blocks WHERE \(blocker_id', [{'?column?': 1}])
    r = client.post(f'{API}/messages/11', headers=auth(10), json={'text': 'hi'})
    assert r.status_code == 403
    assert not db.executed(r'INSERT INTO messages')


def test_normal_message_sent(client, auth, db):
    _recipient(db)
    r = client.post(f'{API}/messages/11', headers=auth(10), json={'text': 'hello'})
    assert r.status_code == 201
    assert db.executed(r'INSERT INTO messages')


def test_block_and_unblock(client, auth, db):
    assert client.post(f'{API}/messages/11/block', headers=auth(10)).status_code == 200
    assert db.executed(r'INSERT INTO member_blocks')
    assert client.delete(f'{API}/messages/11/block', headers=auth(10)).status_code == 200
    assert db.executed(r'DELETE FROM member_blocks')


def test_report_creates_report_and_blocks(client, auth, db):
    db.on(r'INSERT INTO message_reports', [{'id': 7}])
    r = client.post(f'{API}/messages/11/report', headers=auth(10),
                    json={'reason': 'harassment', 'details': 'abusive', 'message_id': 3})
    assert r.status_code == 201 and r.get_json()['report_id'] == 7
    assert db.executed(r'INSERT INTO member_blocks')


def test_admin_report_queue_permissions(client, auth):
    assert client.get(f'{API}/messages/admin/reports', headers=auth(10)).status_code == 403
    assert client.get(f'{API}/messages/admin/reports', headers=auth(2)).status_code == 403
    assert client.get(f'{API}/messages/admin/reports', headers=auth(1)).status_code == 200


def test_resolving_a_report_needs_messaging_permission(client, auth, db):
    url = f'{API}/messages/admin/reports/5'
    assert client.put(url, headers=auth(10), json={'status': 'resolved'}).status_code == 403
    assert client.put(url, headers=auth(2), json={'status': 'resolved'}).status_code == 403


def test_admin_report_status_changes(client, auth, db):
    url = f'{API}/messages/admin/reports/5'
    assert client.put(url, headers=auth(1), json={'status': 'deleted'}).status_code == 400
    assert client.put(url, headers=auth(1), json={'status': 'resolved'}).status_code == 404
    db.on(r'UPDATE message_reports SET status', [{'id': 5}])
    for status in ('resolved', 'dismissed', 'open'):
        r = client.put(url, headers=auth(1), json={'status': status})
        assert r.status_code == 200 and r.get_json()['status'] == status
    sql, params = db.executed(r'UPDATE message_reports SET status')[-1]
    assert params[0] == 'open' and str(params[1]) == '1' and params[2] == 5
