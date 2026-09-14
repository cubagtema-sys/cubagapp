import os
import requests
import json
from dotenv import load_dotenv
load_dotenv()

from config.db import get_db

BASE_URL = "http://localhost:5005"

def test_admin_course_broadcast():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, email FROM members WHERE role IN ('admin', 'super_admin') LIMIT 1")
        admin = cur.fetchone()
    conn.close()

    assert admin is not None, "No admin found in DB"
    print(f"Testing with Admin: {admin['id']} - {admin['name']} ({admin['email']})")

    from flask_jwt_extended import create_access_token
    from server import app
    with app.app_context():
        token = create_access_token(identity=str(admin['id']), additional_claims={"role": "admin"})

    headers = {"Authorization": f"Bearer {token}"}

    # 1. Create a test CTI course with notifications
    course_payload = {
        "title": "Automated AfCFTA & Customs Valuation Masterclass",
        "start_date": "05 Nov 2026",
        "duration": "2 Weeks",
        "mode": "Hybrid",
        "fee": "GHS 1,750",
        "description": "Executive training on AfCFTA rules of origin, origin documentation, and electronic dispute settlement.",
        "notify_members": True
    }

    res = requests.post(f"{BASE_URL}/api/v1/events/admin/courses", headers=headers, json=course_payload)
    print("Admin Create Course status:", res.status_code)
    data = res.json()
    print("Response:", data)
    assert res.status_code == 201
    course_id = data['course']['id']

    # 2. Check that announcement was created in DB
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM announcements WHERE title LIKE '%AfCFTA%' ORDER BY id DESC LIMIT 1")
        ann = cur.fetchone()
        print("\nCreated Announcement in DB:", ann['title'] if ann else "None")
        assert ann is not None

        cur.execute("SELECT COUNT(*) as cnt FROM notifications WHERE title LIKE '%AfCFTA%'")
        notif_count = cur.fetchone()['cnt']
        print(f"Total member notifications generated: {notif_count}")
        assert notif_count > 0

    # 3. Clean up test course
    del_res = requests.delete(f"{BASE_URL}/api/v1/events/admin/courses/{course_id}", headers=headers)
    print(f"\nCleaned up test course ({course_id}) status:", del_res.status_code)
    conn.close()
    print("ALL ADMIN CTI BROADCAST TESTS PASSED!")

if __name__ == "__main__":
    test_admin_course_broadcast()
