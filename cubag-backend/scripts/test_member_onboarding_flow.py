import os
import sys
import uuid
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import requests

BASE_URL = "http://127.0.0.1:5005"

def test_registration_and_documents_flow():
    unique_email = f"test.member.{uuid.uuid4().hex[:8]}@example.com"
    payload = {
        'name': 'Kwame Mensah',
        'email': unique_email,
        'phone': '0244123456',
        'company': 'Ghana Maritime Clearing Ltd',
        'location': 'Tema Community 1',
        'digitalAddress': 'GA-183-4902',
        'tin': 'C0012345678',
        'portOfOperation': 'Tema Port',
        'memberType': 'Corporate',
        'memberScale': 'sme',
        'companyScale': 'sme',
        'feeCategory': 'cf_only',
        'password': 'Password123!',
    }

    print(f"1. Registering new member: {unique_email} (SME Clearing & Forwarding Only)...")
    res = requests.post(f"{BASE_URL}/api/v1/auth/register", json=payload)
    print(f"Register status: {res.status_code}")
    data = res.json()
    print(f"Register response keys: {list(data.keys())}")
    assert res.status_code == 201, f"Registration failed: {data}"
    assert 'token' in data, "Token missing from registration response!"
    assert 'user' in data, "User profile missing from registration response!"
    assert data['user']['status'] == 'pending', f"Expected status 'pending', got {data['user']['status']}"
    assert data['user']['feeCategory'] == 'cf_only', f"Expected 'cf_only', got {data['user']['feeCategory']}"
    print(f"✓ Registered member successfully! Member ID: {data['user']['id']}, Token generated.")

    token = data['token']
    member_headers = {"Authorization": f"Bearer {token}"}

    print("\n2. Fetching /documents/requirements for newly registered member...")
    doc_res = requests.get(f"{BASE_URL}/api/v1/documents/requirements", headers=member_headers)
    print(f"Doc req status: {doc_res.status_code}")
    assert doc_res.status_code == 200, f"Failed to get doc requirements: {doc_res.text}"
    doc_data = doc_res.json()

    reqs = doc_data.get('requirements', [])
    print(f"Total required documents returned: {len(reqs)}")
    assert len(reqs) == 11, f"Expected 11 requirements, got {len(reqs)}"
    for idx, r in enumerate(reqs, 1):
        print(f"  [{idx}] {r['label']} (uploaded: {r['uploaded']}, status: {r['status']})")

    reg_fee_amount = doc_data.get('registration_fee_amount')
    package_fee_amount = doc_data.get('package_fee_amount')
    fee_cat_title = doc_data.get('fee_category_title')
    breakdown = doc_data.get('registration_fee_breakdown', [])

    print(f"\nRegistration Fee Amount (Paid upfront upon onboarding): GHS {reg_fee_amount}")
    print(f"Membership Entrance Package Amount (Paid after 11 docs approved): GHS {package_fee_amount}")
    print(f"Fee Category Title: {fee_cat_title}")
    print(f"Breakdown Items: {len(breakdown)}")
    for b in breakdown:
        print(f"  - {b['label']}: GHS {b['amount']} ({b.get('frequency', '')})")

    assert float(reg_fee_amount) == 600.0, f"Expected 600.00 for upfront Registration Fee, got {reg_fee_amount}"
    assert float(package_fee_amount) == 1620.0, f"Expected 1620.00 for SME CF Package, got {package_fee_amount}"
    assert 'CLEARING & FORWARDING ONLY' in fee_cat_title, f"Unexpected category title: {fee_cat_title}"

    print("\n✓ COMPLETE APPLICATION ONBOARDING VERIFICATION SUCCESSFUL 100%!")

if __name__ == '__main__':
    test_registration_and_documents_flow()
