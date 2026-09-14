import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import requests
from flask_jwt_extended import create_access_token
from server import app

BASE_URL = "http://127.0.0.1:5005"

def test_admin_documents_flow():
    with app.app_context():
        # Member 1 is Admin
        token = create_access_token(identity=str(1), additional_claims={"role": "admin", "email": "admin@cubag.com"})
    
    headers = {"Authorization": f"Bearer {token}"}
    print("Generated JWT successfully")

    # 1. Test pending applicants endpoint
    pending_res = requests.get(f"{BASE_URL}/api/v1/documents/admin/pending", headers=headers)
    print(f"Pending applicants status: {pending_res.status_code}")
    assert pending_res.status_code == 200, f"Failed pending: {pending_res.text}"
    members = pending_res.json().get("members", [])
    print(f"Total pending/registered members returned: {len(members)}")
    for m in members[:3]:
        print(f" - ID={m.get('id')} | Company='{m.get('company')}' | Scale={m.get('member_scale')} | Scope={m.get('fee_category')} | Docs={m.get('docs_uploaded')}/11 | Status={m.get('status')}")

    # 2. Test active applicants endpoint
    active_res = requests.get(f"{BASE_URL}/api/v1/documents/admin/pending?status=active", headers=headers)
    print(f"Active applicants status: {active_res.status_code}")
    assert active_res.status_code == 200, f"Failed active: {active_res.text}"
    active_members = active_res.json().get("members", [])
    print(f"Total active/approved members returned: {len(active_members)}")
    for m in active_members[:3]:
        print(f" - ID={m.get('id')} | Company='{m.get('company')}' | MembershipNo={m.get('membership_number')} | Docs={m.get('docs_uploaded')}/11")

    # 3. Test member dossier details endpoint
    target_id = (members[0] if members else active_members[0])['id']
    member_doc_res = requests.get(f"{BASE_URL}/api/v1/documents/admin/member/{target_id}", headers=headers)
    print(f"\nMember {target_id} dossier status: {member_doc_res.status_code}")
    assert member_doc_res.status_code == 200, f"Failed member docs: {member_doc_res.text}"
    data = member_doc_res.json()
    member_info = data.get("member", {})
    docs_list = data.get("documents", [])
    print(f"Member details: company='{member_info.get('company')}', scale='{member_info.get('member_scale')}', reg_fee_paid={member_info.get('registration_fee_paid')}")
    print(f"Total required documents returned: {len(docs_list)}")
    print("Sample 3 documents:")
    for d in docs_list[:3]:
        print(f" - [{d.get('key')}] {d.get('label')}: uploaded={d.get('uploaded')}, status={d.get('status')}")

    # 4. Test requirements endpoint
    req_res = requests.get(f"{BASE_URL}/api/v1/documents/admin/requirements", headers=headers)
    print(f"\nRequirements endpoint status: {req_res.status_code}")
    assert req_res.status_code == 200, f"Failed requirements: {req_res.text}"
    reqs = req_res.json().get("requirements", [])
    print(f"Total requirements configured: {len(reqs)}")
    print("\n✓ ALL ADMIN DOCUMENTS HUB ENDPOINTS VERIFIED & WORKING 100%!")

if __name__ == "__main__":
    test_admin_documents_flow()
