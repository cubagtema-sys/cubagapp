import os
import sys
import requests
from dotenv import load_dotenv
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

from flask_jwt_extended import create_access_token
from server import app

BASE_URL = "http://127.0.0.1:5005"

def test_dynamic_reg_fee_propagation():
    with app.app_context():
        admin_token = create_access_token(identity=str(1), additional_claims={"role": "admin", "email": "admin@cubag.com"})
        member_token = create_access_token(identity=str(24), additional_claims={"role": "member", "email": "test.member@example.com"})

    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    member_headers = {"Authorization": f"Bearer {member_token}"}

    # 1. Check initial registration fee for member
    res = requests.get(f"{BASE_URL}/api/v1/documents/requirements", headers=member_headers)
    assert res.status_code == 200
    initial_amt = res.json().get('registration_fee_amount')
    print(f"1. Initial Member Registration Fee: GHS {initial_amt}")
    assert float(initial_amt) == 600.0, f"Expected 600.00, got {initial_amt}"

    # 2. Admin edits registration fee to 750.00
    fees_res = requests.get(f"{BASE_URL}/api/v1/admin/fees", headers=admin_headers)
    assert fees_res.status_code == 200
    fees = fees_res.json()
    for f in fees:
        if f.get('id') in ('reg_form_fee', 'new_reg_fee'):
            f['amount'] = '750.00'

    save_res = requests.post(f"{BASE_URL}/api/v1/admin/fees", json=fees, headers=admin_headers)
    assert save_res.status_code == 200
    print("2. Admin updated Registration Fee to GHS 750.00")

    # 3. Check that member requirements immediately reflect 750.00
    res2 = requests.get(f"{BASE_URL}/api/v1/documents/requirements", headers=member_headers)
    assert res2.status_code == 200
    updated_amt = res2.json().get('registration_fee_amount')
    print(f"3. Live Member Registration Fee after Admin edit: GHS {updated_amt}")
    assert float(updated_amt) == 750.0, f"Expected 750.00, got {updated_amt}"

    # 4. Revert back to 600.00
    for f in fees:
        if f.get('id') in ('reg_form_fee', 'new_reg_fee'):
            f['amount'] = '600.00'
    revert_res = requests.post(f"{BASE_URL}/api/v1/admin/fees", json=fees, headers=admin_headers)
    assert revert_res.status_code == 200
    print("4. Reverted Registration Fee back to GHS 600.00 in Admin")

    res3 = requests.get(f"{BASE_URL}/api/v1/documents/requirements", headers=member_headers)
    assert res3.status_code == 200
    reverted_amt = res3.json().get('registration_fee_amount')
    print(f"5. Final Member Registration Fee: GHS {reverted_amt}")
    assert float(reverted_amt) == 600.0, f"Expected 600.00, got {reverted_amt}"

    print("\n✓ FULLY DYNAMIC: Changing the Registration Fee in Admin immediately updates the Member Onboarding Portal live!")

if __name__ == '__main__':
    test_dynamic_reg_fee_propagation()
