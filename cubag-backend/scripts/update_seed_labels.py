import re
import json

SEED_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag-backend/scripts/seed_official_fees.py"

with open(SEED_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Replace numbered labels and Registration Form Fee (Upfront Onboarding)
content = content.replace("'Registration Form Fee (Upfront Onboarding)'", "'Registration Fee'")
content = content.replace("'1. Registration Fee'", "'Registration Fee'")
content = content.replace("'2. Subscription Fee'", "'Subscription Fee'")
content = content.replace("'3. Vetting Fee'", "'Vetting Fee'")
content = content.replace("'4. District'", "'District'")
content = content.replace("'5. Consolidation'", "'Consolidation'")
content = content.replace("'6. Clearing & Forwarding'", "'Clearing & Forwarding'")

content = content.replace("'1. Subscription Fee — SMEs'", "'Subscription Fee — SMEs'")
content = content.replace("'1. Subscription Fee — Large Corporate'", "'Subscription Fee — Large Corporate'")
content = content.replace("'2. Welfare Dues — SMEs'", "'Welfare Dues — SMEs'")
content = content.replace("'2. Welfare Dues — Large Corporate'", "'Welfare Dues — Large Corporate'")
content = content.replace("'3. Consolidation — Large Corporate & SMEs'", "'Consolidation — Large Corporate & SMEs'")
content = content.replace("'4. Administrative Fee — SMEs'", "'Administrative Fee — SMEs'")
content = content.replace("'4. Administrative Fee — Large Corporate'", "'Administrative Fee — Large Corporate'")
content = content.replace("'5. Legal & Audit Fee — SMEs'", "'Legal & Audit Fee — SMEs'")
content = content.replace("'5. Legal & Audit Fee — Large Corporate'", "'Legal & Audit Fee — Large Corporate'")
content = content.replace("'6. AGM Levy — Large Corporate & SMEs'", "'AGM Levy — Large Corporate & SMEs'")
content = content.replace("'7. Customs Bond Fee (SIC) — Large Corporate & SMEs'", "'Customs Bond Fee (SIC) — Large Corporate & SMEs'")
content = content.replace("'8. CTI Courses & Training Levy — SMEs'", "'CTI Courses & Training Levy — SMEs'")
content = content.replace("'8. CTI Courses & Training Levy — Large Corporate'", "'CTI Courses & Training Levy — Large Corporate'")

with open(SEED_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated seed_official_fees.py successfully")
