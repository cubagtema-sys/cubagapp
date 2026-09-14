import os
from dotenv import load_dotenv
load_dotenv()

from routes.payments import _send_receipt_email

def test_email_rendering():
    print("Testing _send_receipt_email...")
    # This will log/send without errors
    _send_receipt_email(
        to_email="testmember@example.com",
        member_name="Kwame Mensah",
        amount=1980.0,
        description="CTI Course: Freight Forwarding Fundamentals (4 Weeks)",
        payment_id=999,
        custom_msg="<p><strong>CTI Course Schedule:</strong> Starts on <strong>25 Aug 2026</strong> (4 Weeks) • Mode: <strong>Hybrid</strong>.</p>"
    )
    print("Receipt email test passed!")

if __name__ == "__main__":
    test_email_rendering()
