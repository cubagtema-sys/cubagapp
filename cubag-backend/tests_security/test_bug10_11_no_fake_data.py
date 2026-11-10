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
