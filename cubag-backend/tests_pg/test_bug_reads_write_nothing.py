"""BUG-09 / BUG-08 against real PostgreSQL: reading must not change data."""
from datetime import datetime

API = '/api/v1'


def _snapshot(sql, uid):
    m = sql('SELECT license_number, compliance_score, star_rating, manual_review_score, status '
            'FROM members WHERE id = %s', (uid,))[0]
    counts = {t: sql(f'SELECT COUNT(*) AS n FROM {t}')[0]['n']
              for t in ('member_rating_history', 'notifications', 'compliance_applications', 'compliance_documents')}
    return m, counts


def _ensure_compliance_tables(client, auth, uid):
    # compliance tables are created on first use by routes/compliance.py
    client.get(f'{API}/compliance/my-applications', headers=auth(uid))


def test_profile_reads_write_nothing(member, auth, client, sql):
    uid = member(status='active', license_number=None, compliance_score=None, star_rating=None)
    admin = member(role='admin', email='admin@example.test')
    sql("INSERT INTO payments (member_id, amount, description, status) VALUES (%s, 500, 'Annual renewal', 'paid')", (uid,))
    _ensure_compliance_tables(client, auth, uid)
    before = _snapshot(sql, uid)

    r_owner = client.get(f'{API}/members/{uid}', headers=auth(uid))
    r_admin = client.get(f'{API}/members/{uid}', headers=auth(admin))
    r_me = client.get(f'{API}/auth/me', headers=auth(uid))
    r_hist = client.get(f'{API}/members/license-history', headers=auth(uid))
    for r in (r_owner, r_admin, r_me, r_hist):
        assert r.status_code == 200, (r.request.path, r.get_json())

    assert _snapshot(sql, uid) == before
    # the response still carries a freshly computed rating (not the fallback)
    body = r_owner.get_json()
    assert isinstance(body['compliance_score'], int) and 'breakdown' in body and body['breakdown']
    assert body['license_number'] is None


def test_rating_is_saved_by_write_paths_not_reads(member, auth, client, sql, app):
    uid = member(status='active', compliance_score=None, star_rating=None)
    client.get(f'{API}/members/{uid}', headers=auth(uid))
    assert sql('SELECT compliance_score FROM members WHERE id = %s', (uid,))[0]['compliance_score'] is None
    from config.db import get_db
    from utils import calculate_and_update_member_rating
    conn = get_db()
    try:
        with conn.cursor() as cur:
            calculate_and_update_member_rating(uid, cur)
    finally:
        conn.close()
    row = sql('SELECT compliance_score FROM members WHERE id = %s', (uid,))[0]
    assert row['compliance_score'] is not None
    assert sql('SELECT COUNT(*) AS n FROM member_rating_history WHERE member_id = %s', (uid,))[0]['n'] == 1


def test_licence_backfill_job(member, sql, app):
    active = member(status='active', license_number=None)
    pending_word = member(status='active', license_number='Pending', email='p@example.test')
    keep = member(status='active', license_number='CUBAG-LIC-2025-0999', email='k@example.test')
    waiting = member(status='pending', license_number=None, email='w@example.test')
    admin = member(role='admin', license_number=None, email='a@example.test')
    from config.db import get_db
    from jobs import backfill_missing_licence_numbers
    conn = get_db()
    try:
        with conn.cursor() as cur:
            assert backfill_missing_licence_numbers(cur) == 2
        conn.commit()
        with conn.cursor() as cur:
            assert backfill_missing_licence_numbers(cur) == 0      # idempotent
        conn.commit()
    finally:
        conn.close()
    year = datetime.now().year
    lic = {r['id']: r['license_number'] for r in sql('SELECT id, license_number FROM members')}
    assert lic[active] == f'CUBAG-LIC-{year}-{active:04d}'
    assert lic[pending_word] == f'CUBAG-LIC-{year}-{pending_word:04d}'
    assert lic[keep] == 'CUBAG-LIC-2025-0999'
    assert lic[waiting] is None and lic[admin] is None


def test_listing_applications_hides_but_never_deletes_duplicate_drafts(member, auth, client, sql):
    uid = member()
    _ensure_compliance_tables(client, auth, uid)
    old = sql("INSERT INTO compliance_applications (member_id, type, status, created_at) "
              "VALUES (%s, 'renewal', 'draft', NOW() - INTERVAL '2 days') RETURNING id", (uid,))[0]['id']
    new = sql("INSERT INTO compliance_applications (member_id, type, status) VALUES (%s, 'renewal', 'draft') "
              "RETURNING id", (uid,))[0]['id']
    sql("INSERT INTO compliance_documents (application_id, requirement, label, file_url, status) "
        "VALUES (%s, 'ghana_card', 'Ghana Card', '/static/uploads/x.pdf', 'pending')", (old,))
    r = client.get(f'{API}/compliance/my-applications', headers=auth(uid))
    assert r.status_code == 200
    assert [a['id'] for a in r.get_json()['applications']] == [new]
    assert sql('SELECT COUNT(*) AS n FROM compliance_applications WHERE id = %s', (old,))[0]['n'] == 1
    assert sql('SELECT COUNT(*) AS n FROM compliance_documents WHERE application_id = %s', (old,))[0]['n'] == 1


def test_non_owner_compliance_upload_stores_nothing(member, auth, client, sql, tmp_path, monkeypatch):
    """BUG-13 with real rows."""
    import io
    import routes.compliance as compliance
    owner, other = member(), member(email='o@example.test')
    _ensure_compliance_tables(client, auth, owner)
    app_id = sql("INSERT INTO compliance_applications (member_id, type, status) VALUES (%s, 'renewal', 'draft') "
                 "RETURNING id", (owner,))[0]['id']
    stored = []
    monkeypatch.setattr(compliance, '_save_file',
                        lambda b, original_filename, subfolder, prefix='', content_type=None:
                        stored.append(subfolder) or f'/static/uploads/{subfolder}/f.pdf')

    def up(uid):
        return client.post(f'{API}/compliance/applications/{app_id}/upload', headers=auth(uid),
                           data={'requirement': 'ghana_card', 'file': (io.BytesIO(b'%PDF-1.4'), 'c.pdf')},
                           content_type='multipart/form-data')
    assert up(other).status_code == 404
    assert stored == []
    assert up(owner).status_code == 200
    assert stored == [f'compliance_docs/{app_id}']
    assert sql('SELECT COUNT(*) AS n FROM compliance_documents WHERE application_id = %s', (app_id,))[0]['n'] == 1


def test_withdrawn_endpoints_on_real_db(member, auth, client):
    uid = member()
    for path in ('/documents/sign-upload', '/documents/confirm-upload'):
        r = client.post(f'{API}{path}', headers=auth(uid), json={'requirement': 'x', 'public_url': 'https://e.x/a'})
        assert r.status_code == 410 and 'key' not in r.get_data(as_text=True).lower()


def test_me_works_for_member_whose_district_rows_are_missing(member, auth, client, sql):
    """Pre-existing: UNION ALL typed the member id as text; the failing insert aborted
    the transaction and GET /auth/me returned 500."""
    uid = member(port_of_operation='Tema Port, Takoradi Port')
    r = client.get(f'{API}/auth/me', headers=auth(uid))
    assert r.status_code == 200, r.get_json()
    assert set(r.get_json()['districts']) == {'Tema Port', 'Takoradi Port'}


def test_profile_update_with_districts_saves(member, auth, client, sql):
    uid = member(port_of_operation='Tema Port')
    r = client.put(f'{API}/auth/profile', headers=auth(uid), json={'districts': ['Kotoka Airport', 'Aflao']})
    assert r.status_code == 200, r.get_json()
    assert sql('SELECT port_of_operation FROM members WHERE id = %s', (uid,))[0]['port_of_operation'] == 'Kotoka Airport, Aflao'
    names = {x['district_name'] for x in sql('SELECT district_name FROM member_districts WHERE member_id = %s', (uid,))}
    assert names == {'Kotoka Airport', 'Aflao'}


def test_compliance_certificate_with_real_rows(member, auth, client, sql):
    owner = member(status='active', company='Mensah Clearing Ltd', license_number='CUBAG-LIC-2026-0001',
                   license_expiry_date='2027-11-30')
    other = member(email='o@example.test')
    _ensure_compliance_tables(client, auth, owner)
    approved = sql("INSERT INTO compliance_applications (member_id, type, status) VALUES (%s, 'renewal', 'approved') "
                   "RETURNING id", (owner,))[0]['id']
    draft = sql("INSERT INTO compliance_applications (member_id, type, status) VALUES (%s, 'renewal', 'draft') "
                "RETURNING id", (owner,))[0]['id']
    url = f'{API}/compliance/applications/{approved}/certificate'
    assert client.get(url).status_code == 401
    assert client.get(url, headers=auth(other)).status_code == 404
    assert client.get(f'{API}/compliance/applications/{draft}/certificate', headers=auth(owner)).status_code == 409
    r = client.get(url, headers=auth(owner))
    assert r.status_code == 200 and 'MENSAH CLEARING LTD' in r.get_data(as_text=True)
