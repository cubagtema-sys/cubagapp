"""BUG-10/11: simulated or invented data must not be presented as real."""
API = '/api/v1'


def test_vessels_not_simulated_without_ais_key(client, monkeypatch):
    import ais_stream
    monkeypatch.setattr(ais_stream, 'AIS_API_KEY', '')
    r = client.get(f'{API}/vessels')
    body = r.get_json()
    assert r.status_code == 200
    assert body['live'] is False and body['items'] == []


def test_vessel_registry_has_no_stale_schedule_times(client):
    for v in client.get(f'{API}/vessels/registry').get_json():
        assert 'eta' not in v and 'atd' not in v


def test_public_verification_does_not_invent_numbers(client, db):
    db.on(r'FROM members WHERE id = %s AND LOWER\(status\) = .active.', [{
        'id': 10, 'name': 'A', 'company': 'Co', 'member_type': 'Corporate', 'membership_number': None,
        'license_number': None, 'primary_port': 'Tema', 'license_expiry_date': None,
        'good_standing': True, 'status': 'active'}])
    db.on(r'FROM payments', [{'id': 1, 'description': 'Membership package'}])
    body = client.get(f'{API}/members/verify/10').get_json()
    if body.get('verified'):
        assert body['membership_number'] is None
        assert body['license_number'] is None
        assert body['valid_until'] is None


def _intel(client):
    from config.cache import cache
    cache.clear()
    r = client.get(f'{API}/intelligence/')
    assert r.status_code == 200
    return r.get_json()


def test_intelligence_defaults_are_labelled_sample(client, db):
    body = _intel(client)
    assert body['is_sample'] is True
    assert set(body['sample_sections']) == {'ports', 'bunkers', 'alerts', 'forex'}
    assert body['updated_at'] is None


def test_admin_entered_forex_is_not_sample(client, db):
    import datetime as dt
    db.on(r'FROM platform_settings WHERE config_key', [{
        'config_value': {'forex': {'USD': '11.10', 'EUR': '12.00', 'GBP': '14.00', 'CNY': '1.55'}},
        'updated_at': dt.datetime(2026, 11, 11, 9, 0)}])
    body = _intel(client)
    assert body['is_sample'] is False
    assert 'forex' not in body['sample_sections'] and 'ports' in body['sample_sections']
    assert body['forex']['USD'] == '11.10'
    assert body['updated_at'].startswith('2026-11-11T09:00')


def test_defaults_saved_back_unchanged_stay_sample(client, db):
    from routes.intelligence import DEFAULT_DATA
    db.on(r'FROM platform_settings WHERE config_key', [{'config_value': dict(DEFAULT_DATA), 'updated_at': None}])
    assert _intel(client)['is_sample'] is True


def test_meta_fields_are_never_stored(client, db, auth):
    from routes.intelligence import save_data
    save_data({'forex': {'USD': '1'}, 'is_sample': True, 'sample_sections': ['x'], 'updated_at': 'y'})
    stored = [p for s, p in db.executed(r'INSERT INTO platform_settings')]
    assert stored and 'is_sample' not in stored[-1][1] and 'sample_sections' not in stored[-1][1]
