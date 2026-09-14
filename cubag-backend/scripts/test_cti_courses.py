import os
import requests
import json
from dotenv import load_dotenv
load_dotenv()

from config.db import get_db
from jobs import check_upcoming_cti_courses

BASE_URL = "http://localhost:5005"

def test_cti_flow():
    # 1. Get a test member
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, email FROM members WHERE role = 'member' LIMIT 1")
        member = cur.fetchone()
    conn.close()

    assert member is not None, "No member found in DB"
    print(f"Testing with member: {member['id']} - {member['name']} ({member['email']})")

    # 2. Login to get JWT
    res = requests.post(f"{BASE_URL}/api/v1/auth/login", json={
        "email": member['email'],
        "password": "Password123!"  # or mock login
    })

    # If password is encrypted, create a temporary test token
    from flask_jwt_extended import create_access_token
    from server import app
    with app.app_context():
        token = create_access_token(identity=str(member['id']))

    headers = {"Authorization": f"Bearer {token}"}

    # 3. Test GET /api/v1/events/courses
    res = requests.get(f"{BASE_URL}/api/v1/events/courses", headers=headers)
    print("GET /api/v1/events/courses status:", res.status_code)
    courses_data = res.json()
    print(f"Total courses returned: {courses_data['total']}")
    for c in courses_data['items']:
        print(f" - [{c['id']}] {c['title']} | {c['start_date']} | {c['mode']} | {c['fee']} | Enrolled: {c.get('is_enrolled')}")

    # 4. Test POST /api/v1/events/courses/1/enroll
    enroll_res = requests.post(f"{BASE_URL}/api/v1/events/courses/1/enroll", headers=headers, json={
        "payment_method": "momo",
        "phone": "0241234567"
    })
    print("\nPOST /api/v1/events/courses/1/enroll status:", enroll_res.status_code)
    print("Enroll response:", enroll_res.json())

    # 5. Test GET /api/v1/events/courses/my-enrollments
    my_res = requests.get(f"{BASE_URL}/api/v1/events/courses/my-enrollments", headers=headers)
    print("\nGET /api/v1/events/courses/my-enrollments status:", my_res.status_code)
    my_data = my_res.json()
    print(f"Total enrolled courses: {my_data['total']}")
    for e in my_data['items']:
        print(f" - Enrolled in: {e['title']} | Ref: {e['payment_ref']} | Status: {e['enrollment_status']} | Start Date: {e['start_date']}")

    # 6. Test background reminder job
    print("\nTesting background job: check_upcoming_cti_courses()...")
    check_upcoming_cti_courses()
    print("Background job executed cleanly!")

if __name__ == "__main__":
    test_cti_flow()
