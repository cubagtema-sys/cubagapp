"""
Integration tests for public legal pages and data deletion against real PostgreSQL.
"""
import pytest
from conftest import ENABLED

pytestmark = pytest.mark.skipif(not ENABLED, reason="Real PostgreSQL not configured")


def test_public_pages_real_db(client, member, sql):
    """Test that submitting a public deletion request creates a real record in data_deletion_requests."""
    mem_id = member(email='kwame.boateng.test@example.com', name='Kwame Boateng')

    payload = {
        'full_name': 'Kwame Boateng',
        'email': 'kwame.boateng.test@example.com',
        'phone': '0240001122',
        'license_number': 'LCHA-GH-0099',
        'reason': 'retiring',
        'notes': 'Please process my account deletion pursuant to Act 843.',
        'confirm_deletion': True
    }

    res = client.post('/delete-account', json=payload)
    assert res.status_code == 201
    data = res.get_json()
    assert data['success'] is True
    tracking_code = data['tracking_code']
    assert tracking_code.startswith('DEL-')

    # Verify directly in PostgreSQL using sql fixture
    rows = sql("""
        SELECT id, member_id, email, phone, status, tracking_code, request_source
        FROM data_deletion_requests
        WHERE tracking_code = %s
    """, (tracking_code,))
    assert len(rows) == 1
    row = rows[0]
    assert row['member_id'] == mem_id
    assert row['email'] == 'kwame.boateng.test@example.com'
    assert row['status'] == 'pending'
    assert row['request_source'] == 'web'


def test_public_deletion_non_existent_member(client, sql):
    """Test web deletion request from a user not yet in members table still records properly."""
    payload = {
        'full_name': 'Anonymous Requester',
        'email': 'external.user.test@example.com',
        'phone': '0501112233',
        'reason': 'privacy_concerns',
        'confirm_deletion': True
    }

    res = client.post('/delete-account', json=payload)
    assert res.status_code == 201
    data = res.get_json()
    tracking = data['tracking_code']

    rows = sql("""
        SELECT id, member_id, email, status, tracking_code, request_source
        FROM data_deletion_requests
        WHERE tracking_code = %s
    """, (tracking,))
    assert len(rows) == 1
    row = rows[0]
    assert row['member_id'] is None
    assert row['email'] == 'external.user.test@example.com'
    assert row['status'] == 'pending'
    assert row['request_source'] == 'web'
