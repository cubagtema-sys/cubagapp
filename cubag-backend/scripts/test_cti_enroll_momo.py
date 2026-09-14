import os
import jwt
import datetime
import requests
from dotenv import load_dotenv
load_dotenv()

from config.db import get_db

BASE_URL = "http://localhost:5005"
JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "cubag_secret_key_2026")

def make_token(member_id, role="member"):
    payload = {
        "sub": str(member_id),
        "role": role,
        "type": "access",
        "iat": datetime.datetime.utcnow(),
        "exp": datetime.datetime.utcnow() + datetime.timedelta(hours=2)
    }
    return jwt.encode(payload, JWT_SECRET_KEY, algorithm="HS256")

def test_cti_enroll_momo():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, email FROM members WHERE role = 'member' LIMIT 1")
        member = cur.fetchone()
    conn.close()

    assert member is not None, "No member found in DB"
    print(f"Testing with Member: {member['id']} - {member['name']} ({member['email']})")

    token = make_token(member['id'], "member")
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Fetch available courses
    res = requests.get(f"{BASE_URL}/api/v1/events/courses", headers=headers)
    courses = res.json().get('items', [])
    assert len(courses) > 0, "No courses found"
    target_course = courses[0]
    print(f"Target Course: ID {target_course['id']} - {target_course['title']} ({target_course['fee']})")

    # Clean previous enrollment and test payments if any
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM cti_course_enrollments WHERE course_id = %s AND member_id = %s", (target_course['id'], member['id']))
        cur.execute("DELETE FROM payments WHERE member_id = %s AND description LIKE %s", (member['id'], f"%{target_course['title']}%"))
        conn.commit()
    conn.close()

    # 2. Initiate MoMo Payment
    pay_payload = {
        "amount": 1980.0,
        "description": f"CTI Course: {target_course['title']}",
        "method": "momo",
        "network": "MTN",
        "phone": "0244123456",
        "meta": {
            "type": "cti_course",
            "course_id": target_course['id'],
            "course_title": target_course['title'],
        }
    }

    pay_res = requests.post(f"{BASE_URL}/api/v1/payments", headers=headers, json=pay_payload)
    print("Initiate Payment response:", pay_res.status_code, pay_res.json())
    assert pay_res.status_code in (200, 201)
    pay_data = pay_res.json()
    payment_id = pay_data.get('payment_id')
    tx_ref = pay_data.get('transaction_ref') or pay_data.get('whitsun_ref')
    assert payment_id is not None
    assert tx_ref is not None

    # 3. Verify user is NOT enrolled yet
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM cti_course_enrollments WHERE course_id = %s AND member_id = %s", (target_course['id'], member['id']))
        enrolled_row = cur.fetchone()
        print("Enrollment before payment confirmation:", enrolled_row)
        assert enrolled_row is None, "Member should NOT be enrolled while payment is pending!"

    # 4. Confirm payment (simulate successful MoMo authorization)
    with conn.cursor() as cur:
        from routes.payments import _mark_payment_as_paid
        _mark_payment_as_paid(payment_id)

    # 5. Verify user is now enrolled!
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM cti_course_enrollments WHERE course_id = %s AND member_id = %s", (target_course['id'], member['id']))
        enrolled_row = cur.fetchone()
        print("Enrollment after payment confirmation:", enrolled_row)
        assert enrolled_row is not None
        assert enrolled_row['status'] == 'enrolled'
    conn.close()

    print("\nALL CTI MOMO ENROLLMENT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_cti_enroll_momo()
