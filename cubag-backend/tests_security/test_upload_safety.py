"""Service-role key leak (new finding, 11 Nov) and BUG-13 (store before ownership check)."""
import io

import pytest

SENTINEL = 'service-role-key-SENTINEL-must-never-leave-the-server'
OWNER, OTHER = 10, 11


@pytest.fixture()
def storage(monkeypatch):
    """Record every attempt to store a file instead of writing anywhere."""
    import routes.compliance as compliance
    calls = []

    def fake_save(file_bytes, original_filename, subfolder, prefix='', content_type=None):
        calls.append(subfolder)
        return f'/static/uploads/{subfolder}/{prefix}x.pdf'
    monkeypatch.setattr(compliance, '_save_file', fake_save)
    return calls


@pytest.fixture(autouse=True)
def configured_supabase(monkeypatch):
    import routes.compliance as compliance
    import routes.documents as documents
    for mod in (compliance, documents):
        monkeypatch.setattr(mod, 'SUPABASE_KEY', SENTINEL, raising=False)
        monkeypatch.setattr(mod, 'SUPABASE_URL', 'https://example.supabase.co', raising=False)


@pytest.mark.parametrize('path, body', [
    ('/api/v1/documents/sign-upload', {'requirement': 'ghana_card', 'ext': 'pdf', 'size': 10}),
    ('/api/v1/documents/confirm-upload', {'requirement': 'ghana_card', 'public_url': 'https://evil.example/x.pdf'}),
    ('/api/v1/compliance/applications/5/sign-upload', {'requirement': 'ghana_card', 'ext': 'pdf', 'size': 10}),
    ('/api/v1/compliance/applications/5/confirm-upload', {'requirement': 'ghana_card', 'public_url': 'https://evil.example/x.pdf'}),
])
def test_withdrawn_direct_upload_endpoints_never_return_a_key_or_write(client, auth, db, path, body):
    db.on(r'SELECT type, status FROM compliance_applications', [{'type': 'renewal', 'status': 'draft'}])
    r = client.post(path, headers=auth(OWNER), json=body)
    assert r.status_code == 410
    text = r.get_data(as_text=True)
    assert SENTINEL not in text and 'supabase_key' not in text
    assert not db.executed(r'INSERT INTO|UPDATE ')


def test_service_key_appears_in_no_response_body_anywhere(app):
    """Static guard: no route may put a SUPABASE key into a JSON response."""
    import pathlib
    import re
    root = pathlib.Path(__file__).resolve().parents[1]
    offenders = []
    for f in list((root / 'routes').glob('*.py')) + [root / 'server.py', root / 'utils.py']:
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if re.search(r"['\"](supabase_key|service_key|service_role)['\"]\s*:", line, re.I):
                offenders.append(f'{f.name}:{n}')
    assert offenders == []


def _upload(client, auth, member, app_id=5):
    data = {'requirement': 'ghana_card', 'file': (io.BytesIO(b'%PDF-1.4 test'), 'card.pdf')}
    return client.post(f'/api/v1/compliance/applications/{app_id}/upload', headers=auth(member),
                       data=data, content_type='multipart/form-data')


def test_bug13_non_owner_upload_stores_nothing(client, auth, db, storage):
    # The ownership query is scoped by member_id, so for a non-owner it returns no row.
    db.on(r'SELECT type, status FROM compliance_applications', [])
    r = _upload(client, auth, OTHER)
    assert r.status_code == 404
    assert storage == []
    assert not db.executed(r'INSERT INTO compliance_documents|UPDATE compliance_documents')


def test_bug13_locked_application_stores_nothing(client, auth, db, storage):
    db.on(r'SELECT type, status FROM compliance_applications', [{'type': 'renewal', 'status': 'approved'}])
    r = _upload(client, auth, OWNER)
    assert r.status_code == 400
    assert storage == []


def test_bug13_owner_upload_still_works(client, auth, db, storage):
    db.on(r'SELECT type, status FROM compliance_applications', [{'type': 'renewal', 'status': 'draft'}])
    r = _upload(client, auth, OWNER)
    assert r.status_code == 200, r.get_json()
    assert storage == ['compliance_docs/5']
    assert db.executed(r'INSERT INTO compliance_documents')
    # ownership is checked before storing AND re-checked under a row lock before the DB write
    assert len(db.executed(r'SELECT type, status FROM compliance_applications WHERE id = %s AND member_id = %s')) == 2
    assert db.executed(r'FOR UPDATE')


# ── compliance certificate (new finding, 11 Nov) ──────────────────────────────
def _cert_row(status='approved', **over):
    row = {'id': 5, 'member_id': OWNER, 'status': status, 'member_name': 'Ama Mensah',
           'member_email': 'ama@example.test', 'member_company': 'Mensah Clearing Ltd',
           'license_number': 'CUBAG-LIC-2026-0010', 'port_of_operation': 'Tema',
           'member_type': 'corporate', 'member_scale': None, 'license_expiry_date': '2027-11-30'}
    row.update(over)
    return row


def test_certificate_requires_sign_in(client, db):
    db.on(r'FROM compliance_applications ca', [_cert_row()])
    r = client.get('/api/v1/compliance/applications/5/certificate')
    assert r.status_code == 401
    assert 'Mensah' not in r.get_data(as_text=True)


def test_certificate_hidden_from_other_members(client, auth, db):
    db.on(r'FROM compliance_applications ca', [_cert_row()])
    r = client.get('/api/v1/compliance/applications/5/certificate', headers=auth(OTHER))
    assert r.status_code == 404 and 'Mensah' not in r.get_data(as_text=True)


@pytest.mark.parametrize('status', ['draft', 'submitted', 'under_review', 'rejected', 'payment_pending'])
def test_certificate_only_for_approved_applications(client, auth, db, status):
    db.on(r'FROM compliance_applications ca', [_cert_row(status=status)])
    assert client.get('/api/v1/compliance/applications/5/certificate', headers=auth(OWNER)).status_code == 409


def test_certificate_owner_and_admin(client, auth, db):
    db.on(r'FROM compliance_applications ca', [_cert_row()])
    for uid in (OWNER, 1):
        r = client.get('/api/v1/compliance/applications/5/certificate', headers=auth(uid))
        assert r.status_code == 200, (uid, r.get_json())
        assert 'MENSAH CLEARING LTD' in r.get_data(as_text=True)


@pytest.mark.parametrize('missing', [
    {'member_company': None, 'member_name': None},
    {'license_number': None}, {'license_number': 'Pending'}, {'license_expiry_date': None},
])
def test_certificate_never_invents_values(client, auth, db, missing):
    db.on(r'FROM compliance_applications ca', [_cert_row(**missing)])
    r = client.get('/api/v1/compliance/applications/5/certificate', headers=auth(OWNER))
    assert r.status_code == 409
    text = r.get_data(as_text=True)
    for invented in ('HART LOGISTICS', 'KIA Air Cargo', 'CUBAG-LIC-'):
        assert invented not in text


def test_certificate_pdf_redirect_keeps_the_token(client, db, token):
    """Regression: SEC-03 made the PDF route require sign-in; the redirect dropped ?token=."""
    db.on(r'FROM compliance_applications ca', [_cert_row()])
    t = token(OWNER)
    r = client.get(f'/api/v1/compliance/applications/5/certificate?token={t}&format=pdf')
    assert r.status_code == 302
    assert r.headers['Location'].endswith(f'/api/v1/members/{OWNER}/certificate-pdf?token={t}')
