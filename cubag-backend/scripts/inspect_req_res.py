from flask_jwt_extended import create_access_token
from server import app
import requests

with app.app_context():
    member_token = create_access_token(identity=str(19), additional_claims={"role": "member", "email": "corp.full@cubag.demo"})

res = requests.get("http://127.0.0.1:5005/api/v1/documents/requirements", headers={"Authorization": f"Bearer {member_token}"})
print("Keys:", res.json().keys())
print("registration_fee:", res.json().get('registration_fee'))
print("breakdown:", res.json().get('breakdown'))
