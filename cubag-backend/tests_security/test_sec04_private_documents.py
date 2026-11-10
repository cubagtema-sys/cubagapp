"""SEC-04: sensitive documents are only served to owners/admins via short-lived signed URLs."""
import uuid

import pytest

API = '/api/v1'


@pytest.fixture()
def local_receipt(tmp_path, monkeypatch):
    """A real file under <cwd>/uploads/receipts (serve_uploads checks cwd too).
    Uses a temp directory so the real uploads/ folder is never touched."""
    folder = tmp_path / 'uploads' / 'receipts'
    folder.mkdir(parents=True)
    name = f'test_receipt_{uuid.uuid4().hex}.jpg'
    (folder / name).write_bytes(b'\xff\xd8\xff\xe0testjpeg')
    monkeypatch.chdir(tmp_path)
    yield name


def _receipt_owner(db, owner_id):
    db.on(r'SELECT member_id FROM payments WHERE receipt_url LIKE', [{'member_id': owner_id}])


def test_sensitive_local_file_requires_auth(client, local_receipt, db):
    _receipt_owner(db, 10)
    r = client.get(f'/static/uploads/receipts/{local_receipt}')
    assert r.status_code == 401


def test_other_member_cannot_fetch_receipt(client, auth, local_receipt, db):
    _receipt_owner(db, 10)
    r = client.get(f'/static/uploads/receipts/{local_receipt}', headers=auth(11))
    assert r.status_code == 403


def test_owner_can_fetch_receipt_and_it_is_not_publicly_cached(client, auth, local_receipt, db):
    _receipt_owner(db, 10)
    r = client.get(f'/static/uploads/receipts/{local_receipt}', headers=auth(10))
    assert r.status_code == 200
    assert 'no-store' in r.headers.get('Cache-Control', '')


def test_sign_endpoint_requires_auth(client):
    assert client.get(f'{API}/uploads/sign?url=/static/uploads/receipts/x.jpg').status_code == 401


def test_sign_endpoint_denies_non_owner(client, auth, db):
    _receipt_owner(db, 10)
    r = client.get(f'{API}/uploads/sign', query_string={'url': '/static/uploads/receipts/x.jpg'}, headers=auth(11))
    assert r.status_code == 403


def test_signed_url_round_trip(client, auth, local_receipt, db):
    _receipt_owner(db, 10)
    r = client.get(f'{API}/uploads/sign', query_string={'url': f'/static/uploads/receipts/{local_receipt}'},
                   headers=auth(10))
    assert r.status_code == 200
    signed = r.get_json()['url']
    assert '?t=' in signed
    path = signed.split('/api/v1', 1)[1]
    assert client.get(path).status_code == 200                     # no auth header needed
    tampered = path.replace(local_receipt, 'other.jpg')
    assert client.get(tampered).status_code in (401, 403)         # token bound to one file


def test_admin_with_permission_can_sign(client, auth, db):
    _receipt_owner(db, 10)
    r = client.get(f'{API}/uploads/sign', query_string={'url': '/static/uploads/receipts/x.jpg'}, headers=auth(1))
    assert r.status_code == 200


def test_sub_admin_without_permission_cannot_sign(client, auth, db):
    _receipt_owner(db, 10)
    r = client.get(f'{API}/uploads/sign', query_string={'url': '/static/uploads/receipts/x.jpg'}, headers=auth(2))
    assert r.status_code == 403


def test_member_docs_owner_from_path(client, auth, db):
    url = '/static/uploads/member_docs/10/ghana_card_abc.pdf'
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(10)).status_code == 200
    assert client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(11)).status_code == 403


def test_public_gallery_url_returned_unchanged(client, auth):
    url = 'https://proj.supabase.co/storage/v1/object/public/uploads/gallery/gallery_1.jpg'
    r = client.get(f'{API}/uploads/sign', query_string={'url': url}, headers=auth(11))
    assert r.status_code == 200 and r.get_json()['url'] == url


def test_path_traversal_rejected(client, auth):
    r = client.get('/static/uploads/receipts/../../server.py', headers=auth(10))
    assert r.status_code in (400, 404)
