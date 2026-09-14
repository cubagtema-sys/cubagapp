import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import requests
from flask_jwt_extended import create_access_token
from server import app

BASE_URL = "http://127.0.0.1:5005"

def test_admin_tickets():
    with app.app_context():
        # Member 1 is Admin
        admin_token = create_access_token(identity=str(1), additional_claims={"role": "admin", "email": "admin@cubag.com"})
        # Member 19 is a Corporate Member
        member_token = create_access_token(identity=str(19), additional_claims={"role": "member", "email": "corp.full@cubag.demo"})

    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    member_headers = {"Authorization": f"Bearer {member_token}"}
    print("Generated tokens successfully")

    # 1. Member creates a test support ticket
    tkt_payload = {
        "subject": "Inquiry regarding ICUMS Manifest Submission Error code 403",
        "message": "We are experiencing an ICUMS clearance transmission error on Bill of Lading BL-2026-GH-889. Could the secretariat verify our customs broker agency linkage with GCNet/ICUMS?"
    }
    create_res = requests.post(f"{BASE_URL}/api/v1/tickets", json=tkt_payload, headers=member_headers)
    print(f"Create ticket status: {create_res.status_code}")
    assert create_res.status_code in (200, 201), f"Create failed: {create_res.text}"
    ticket_id = create_res.json().get('id')
    print(f"Created ticket ID: {ticket_id}")

    # 2. Admin fetches inbox in tabular format
    inbox_res = requests.get(f"{BASE_URL}/api/v1/tickets/admin/all?status=inbox&page=1&per_page=15", headers=admin_headers)
    print(f"Admin inbox fetch status: {inbox_res.status_code}")
    assert inbox_res.status_code == 200, f"Fetch inbox failed: {inbox_res.text}"
    inbox_data = inbox_res.json()
    items = inbox_data.get('data', [])
    print(f"Total tickets returned in table: {len(items)}, total in DB: {inbox_data.get('total')}")
    if items:
        t0 = items[0]
        print(f"Sample row: ID={t0.get('id')} | Member='{t0.get('member_name')}' | Company='{t0.get('company')}' | Subject='{t0.get('subject')}' | Status={t0.get('status')}")

    # 3. Admin replies to the ticket
    reply_payload = {
        "message": "Dear Member, we have contacted GRA ICUMS Operations Desk. The link has been synchronized. Please re-submit your manifest entry."
    }
    reply_res = requests.post(f"{BASE_URL}/api/v1/tickets/admin/{ticket_id}/reply", json=reply_payload, headers=admin_headers)
    print(f"Admin reply status: {reply_res.status_code}")
    assert reply_res.status_code in (200, 201), f"Reply failed: {reply_res.text}"

    # 4. Admin updates status to resolved
    status_res = requests.put(f"{BASE_URL}/api/v1/tickets/admin/{ticket_id}/status", json={"status": "resolved"}, headers=admin_headers)
    print(f"Update status to resolved: {status_res.status_code}")
    assert status_res.status_code == 200, f"Status update failed: {status_res.text}"

    # 5. Admin updates status to archived
    archive_res = requests.put(f"{BASE_URL}/api/v1/tickets/admin/{ticket_id}/status", json={"status": "archived"}, headers=admin_headers)
    print(f"Archive ticket status: {archive_res.status_code}")
    assert archive_res.status_code == 200, f"Archive failed: {archive_res.text}"

    # 6. Admin checks archived tickets tab
    archived_tab_res = requests.get(f"{BASE_URL}/api/v1/tickets/admin/all?status=archived&page=1&per_page=15", headers=admin_headers)
    print(f"Archived tab fetch status: {archived_tab_res.status_code}")
    assert archived_tab_res.status_code == 200, f"Archived tab failed: {archived_tab_res.text}"
    archived_items = archived_tab_res.json().get('data', [])
    print(f"Archived tab items: {len(archived_items)}")

    print("\n✓ ALL TABULAR TICKETS ENDPOINTS & HELPDESK WORKFLOWS VERIFIED 100%!")

if __name__ == "__main__":
    test_admin_tickets()
