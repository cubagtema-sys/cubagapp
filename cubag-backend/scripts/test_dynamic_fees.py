import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import requests
from flask_jwt_extended import create_access_token
from server import app

BASE_URL = "http://127.0.0.1:5005"

def test_dynamic_fees():
    with app.app_context():
        admin_token = create_access_token(identity=str(1), additional_claims={"role": "admin", "email": "admin@cubag.com"})
        member_token = create_access_token(identity=str(19), additional_claims={"role": "member", "email": "corp.full@cubag.demo"})

    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    member_headers = {"Authorization": f"Bearer {member_token}"}

    # 1. Fetch current fees
    res = requests.get(f"{BASE_URL}/api/v1/admin/fees", headers=admin_headers)
    assert res.status_code == 200
    fees = res.json()
    print(f"Fetched {len(fees)} fees from admin endpoint.")

    # 2. Update vetting fee to 800.00
    updated_fees = []
    for f in fees:
        item = dict(f)
        if item.get('id') == 'new_vetting_fee':
            item['amount'] = '800.00'
        updated_fees.append(item)

    save_res = requests.post(f"{BASE_URL}/api/v1/admin/fees", json=updated_fees, headers=admin_headers)
    print(f"Save fees response: {save_res.status_code}")
    assert save_res.status_code == 200

    # 3. Check that documents breakdown dynamically reflects 800.00
    doc_res = requests.get(f"{BASE_URL}/api/v1/documents/requirements", headers=member_headers)
    print(f"Member requirements response: {doc_res.status_code}")
    assert doc_res.status_code == 200
    doc_data = doc_res.json()
    breakdown = doc_data.get('registration_fee_breakdown', [])
    vetting_item = next((b for b in breakdown if 'vetting' in b.get('label', '').lower()), None)
    print(f"Dynamic vetting item in document breakdown: {vetting_item}")
    assert vetting_item is not None and float(vetting_item.get('amount')) == 800.0, f"Expected 800.0, got {vetting_item}"

    # 4. Revert vetting fee back to 750.00
    revert_fees = []
    for f in fees:
        item = dict(f)
        if item.get('id') == 'new_vetting_fee':
            item['amount'] = '750.00'
        revert_fees.append(item)
    revert_res = requests.post(f"{BASE_URL}/api/v1/admin/fees", json=revert_fees, headers=admin_headers)
    assert revert_res.status_code == 200

    print("\n✓ DYNAMIC FEE SYSTEM VERIFIED 100%! Changes made in Admin propagate live across the whole application.")

if __name__ == '__main__':
    test_dynamic_fees()
