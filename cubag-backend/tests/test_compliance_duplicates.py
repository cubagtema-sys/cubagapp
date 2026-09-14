import os
from flask_jwt_extended import create_access_token
from server import app
from config.db import get_db


def test_duplicate_active_compliance_applications_are_not_created(client):
    """A member should not be able to create multiple active compliance applications of the same type."""
    member_id = 1
    with app.app_context():
        token = create_access_token(identity=str(member_id), additional_claims={'role': 'member'})

    headers = {'Authorization': f'Bearer {token}'}

    resp1 = client.post('/api/v1/compliance/applications', headers=headers, json={'type': 'renewal'})
    assert resp1.status_code in (200, 201)

    resp2 = client.post('/api/v1/compliance/applications', headers=headers, json={'type': 'renewal'})
    assert resp2.status_code == 200
    body = resp2.get_json()
    assert body['existing'] is True

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT COUNT(*) AS cnt FROM compliance_applications WHERE member_id = %s AND type = %s AND status IN ('draft', 'submitted', 'payment_pending', 'payment_confirmed', 'under_review', 'revision_requested')",
                (member_id, 'renewal'),
            )
            count = cursor.fetchone()['cnt']
    finally:
        conn.close()

    assert count == 1
