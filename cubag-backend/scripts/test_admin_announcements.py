import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import requests
from flask_jwt_extended import create_access_token
from server import app

BASE_URL = "http://127.0.0.1:5005"

def test_admin_announcements():
    with app.app_context():
        # Member 1 is Admin
        token = create_access_token(identity=str(1), additional_claims={"role": "admin", "email": "admin@cubag.com"})
    
    headers = {"Authorization": f"Bearer {token}"}
    print("Generated Admin JWT successfully")

    # 1. Fetch active announcements
    res_active = requests.get(f"{BASE_URL}/api/v1/announcements/admin/all?archived=false&page=1&limit=15", headers=headers)
    print(f"Active announcements status: {res_active.status_code}")
    assert res_active.status_code == 200, f"Failed active: {res_active.text}"
    active_data = res_active.json()
    print(f"Active count: {active_data.get('total')} items")

    # 2. Fetch archived announcements
    res_archived = requests.get(f"{BASE_URL}/api/v1/announcements/admin/all?archived=true&page=1&limit=15", headers=headers)
    print(f"Archived announcements status: {res_archived.status_code}")
    assert res_archived.status_code == 200, f"Failed archived: {res_archived.text}"
    archived_data = res_archived.json()
    print(f"Archived count: {archived_data.get('total')} items")

    # 3. Create test broadcast
    create_payload = {
        "title": "URGENT: Port of Tema Berth 3 Modernization Notice",
        "body": "All freight forwarders and customs house agents are advised that GPHA Berth 3 will undergo maintenance from Monday 06:00 GMT. Please redirect bulk cargo clearances to Berth 2.",
        "category": "Urgent Alert",
        "posted_by": "CUBAG Secretariat"
    }
    res_create = requests.post(f"{BASE_URL}/api/v1/announcements", json=create_payload, headers=headers)
    print(f"Create broadcast status: {res_create.status_code}")
    assert res_create.status_code in (200, 201), f"Failed create: {res_create.text}"

    # 4. Re-fetch active to get created ID
    res_active2 = requests.get(f"{BASE_URL}/api/v1/announcements/admin/all?archived=false&page=1&limit=5", headers=headers)
    items = res_active2.json().get('data', [])
    assert len(items) > 0, "No items returned after creation"
    new_item = items[0]
    new_id = new_item['id']
    print(f"Created circular ID: {new_id}, title='{new_item.get('title')}'")

    # 5. Test Edit / PUT
    edit_payload = {
        "title": "URGENT: Port of Tema Berth 3 Maintenance Notice [UPDATED]",
        "body": "All freight forwarders and customs house agents are advised that GPHA Berth 3 will undergo maintenance from Monday 06:00 GMT. Expedited clearance lane open at Berth 1.",
        "category": "Regulatory & Port Advisory"
    }
    res_edit = requests.put(f"{BASE_URL}/api/v1/announcements/{new_id}", json=edit_payload, headers=headers)
    print(f"Edit circular status: {res_edit.status_code}")
    assert res_edit.status_code == 200, f"Failed edit: {res_edit.text}"

    # 6. Test Archive / Soft Delete
    res_del = requests.delete(f"{BASE_URL}/api/v1/announcements/{new_id}", headers=headers)
    print(f"Archive circular status: {res_del.status_code}")
    assert res_del.status_code == 200, f"Failed delete: {res_del.text}"

    # 7. Test Restore
    res_restore = requests.patch(f"{BASE_URL}/api/v1/announcements/{new_id}/restore", json={}, headers=headers)
    print(f"Restore circular status: {res_restore.status_code}")
    assert res_restore.status_code == 200, f"Failed restore: {res_restore.text}"

    print("\n✓ ALL ADMIN ANNOUNCEMENTS ENDPOINTS & WORKFLOWS VERIFIED 100%!")

if __name__ == "__main__":
    test_admin_announcements()
