import json
from config.db import get_db

ALL_FEES = [
    # ── SECTION 1: NEW MEMBERSHIP ──────────────────────────────────────────
    # Independent Initial Onboarding Fee
    {
        'id': 'reg_form_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Registration Fee',
        'amount': '600.00',
        'frequency': 'One-Time',
        'description': 'Mandatory initial registration fee paid separately upon onboarding before document vetting.',
    },

    # Package Summaries (Paid after 11 documents are approved)
    {
        'id': 'new_cf_only',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Clearing & Forwarding Only (SMEs)',
        'amount': '1620.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + C&F Scope (500)',
    },
    {
        'id': 'new_consolidation',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Consolidation Only (SMEs)',
        'amount': '1720.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + Consolidation Scope (600)',
    },
    {
        'id': 'new_cf_consolidation',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Consolidation, Clearing & Forwarding (SMEs)',
        'amount': '2220.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + Consolidation (600) + C&F Scope (500)',
    },
    {
        'id': 'new_large_cf_only',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Clearing & Forwarding Only (Large Corporate)',
        'amount': '2220.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + Corporate Operational Scope (1100)',
    },
    {
        'id': 'new_large_consolidation',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Consolidation Only (Large Corporate)',
        'amount': '2320.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + Corporate Operational Scope (1200)',
    },
    {
        'id': 'new_large_cf_consolidation',
        'section': 'new_membership',
        'is_summary': True,
        'label': 'New Member Package: Consolidation, Clearing & Forwarding (Large Corporate)',
        'amount': '2820.00',
        'frequency': 'One-Time',
        'description': 'Subscription (120) + Vetting (750) + District (250) + Corporate Consolidation & C&F Scope',
    },

    # Individual Breakdown Items (Editable individually)
    {
        'id': 'new_reg_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Registration Fee',
        'amount': '600.00',
        'frequency': 'One-Time',
        'description': 'Initial registration fee taken upfront upon account registration.',
    },
    {
        'id': 'new_sub_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Subscription Fee',
        'amount': '120.00',
        'frequency': 'Annual',
        'description': 'Annual association base subscription fee portion for new entrants.',
    },
    {
        'id': 'new_vetting_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Vetting Fee',
        'amount': '750.00',
        'frequency': 'One-Time',
        'description': 'Secretariat 11 statutory document verification & background vetting fee.',
    },
    {
        'id': 'new_district_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'District',
        'amount': '250.00',
        'frequency': 'One-Time',
        'description': 'CUBAG District chapter onboarding fee (Tema / AIA / Aflao / Takoradi).',
    },
    {
        'id': 'new_consolidation_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Consolidation',
        'amount': '600.00',
        'frequency': 'Annual',
        'description': 'Consolidation operational scope fee for new members.',
    },
    {
        'id': 'new_cf_fee',
        'section': 'new_membership',
        'is_summary': False,
        'label': 'Clearing & Forwarding',
        'amount': '500.00',
        'frequency': 'Annual',
        'description': 'Clearing & Forwarding operational scope fee for new members.',
    },

    # ── SECTION 2: EXISTING MEMBERSHIP RENEWAL ─────────────────────────────

# ── SECTION 3: ASSOCIATE MEMBERSHIP ───────────────────────
{
    'id': 'associate_reg_form_fee',
    'section': 'associate',
    'is_summary': False,
    'label': 'Registration Fee – Associate',
    'amount': '0.00',
    'frequency': 'One-Time',
    'description': 'Mandatory initial onboarding registration fee for Associate members.',
},
{
    'id': 'associate_sub_fee',
    'section': 'associate',
    'is_summary': False,
    'label': 'Subscription Fee – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual base subscription fee for Associate members (Renewed).',
},
{
    'id': 'associate_vetting_fee',
    'section': 'associate',
    'is_summary': False,
    'label': 'Vetting Fee – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual document vetting fee for Associate members (Renewed).',
},
{
    'id': 'associate_district_fee',
    'section': 'associate',
    'is_summary': False,
    'label': 'District – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual district chapter dues for Associate members (Renewed).',
},
{
    'id': 'associate_welfare_dues',
    'section': 'associate',
    'is_summary': False,
    'label': 'Welfare Dues – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual welfare fund dues for Associate members (Renewed).',
},
{
    'id': 'associate_legal_audit_fee',
    'section': 'associate',
    'is_summary': False,
    'label': 'Legal & Audit Fee – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual legal representation & audit retainer for Associate members (Renewed).',
},
{
    'id': 'associate_agm_levy',
    'section': 'associate',
    'is_summary': False,
    'label': 'AGM Levy – Associate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual General Meeting logistics levy for Associate members (Renewed).',
},

# ── SECTION 4: LICENTIATE MEMBERSHIP ───────────────────────
{
    'id': 'licentiate_reg_form_fee',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'Registration Fee – Licentiate',
    'amount': '0.00',
    'frequency': 'One-Time',
    'description': 'Mandatory initial onboarding registration fee for Licentiate members.',
},
{
    'id': 'licentiate_sub_fee',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'Subscription Fee – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual base subscription fee for Licentiate members (Renewed).',
},
{
    'id': 'licentiate_vetting_fee',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'Vetting Fee – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual document vetting fee for Licentiate members (Renewed).',
},
{
    'id': 'licentiate_district_fee',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'District – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual district chapter dues for Licentiate members (Renewed).',
},
{
    'id': 'licentiate_welfare_dues',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'Welfare Dues – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual welfare fund dues for Licentiate members (Renewed).',
},
{
    'id': 'licentiate_legal_audit_fee',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'Legal & Audit Fee – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual legal representation & audit retainer for Licentiate members (Renewed).',
},
{
    'id': 'licentiate_agm_levy',
    'section': 'licentiate',
    'is_summary': False,
    'label': 'AGM Levy – Licentiate',
    'amount': '0.00',
    'frequency': 'Annual',
    'description': 'Annual General Meeting logistics levy for Licentiate members (Renewed).',
},

    # Package Summaries
    {
        'id': 'renewal_sme_without_consolidation',
        'section': 'renewal',
        'is_summary': True,
        'label': 'Annual Renewal Dues: SMEs (Without Consolidation)',
        'amount': '2170.00',
        'frequency': 'Annual',
        'description': 'Sub (120) + Welfare (300) + Admin (200) + Legal/Audit (100) + AGM (500) + Bond (350) + CTI (600)',
    },
    {
        'id': 'renewal_large_corporate_without_consolidation',
        'section': 'renewal',
        'is_summary': True,
        'label': 'Annual Renewal Dues: Large Corporate (Without Consolidation)',
        'amount': '4795.00',
        'frequency': 'Annual',
        'description': 'Sub (1545) + Welfare (400) + Admin (300) + Legal/Audit (500) + AGM (500) + Bond (350) + CTI (1200)',
    },
    {
        'id': 'renewal_sme_with_consolidation',
        'section': 'renewal',
        'is_summary': True,
        'label': 'Annual Renewal Dues: SMEs (Consolidation)',
        'amount': '3456.00',
        'frequency': 'Annual',
        'description': 'Base SME (2,170) + Consolidation Scope (1,286)',
    },
    {
        'id': 'renewal_large_corporate_with_consolidation',
        'section': 'renewal',
        'is_summary': True,
        'label': 'Annual Renewal Dues: Large Corporate (Consolidation)',
        'amount': '6081.00',
        'frequency': 'Annual',
        'description': 'Base Corporate (4,795) + Consolidation Scope (1,286)',
    },

    # Individual Breakdown Items (Editable individually)
    {
        'id': 'renewal_sub_sme',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Subscription Fee — SMEs',
        'amount': '120.00',
        'frequency': 'Annual',
        'description': 'Annual Subscription portion for SME members.',
    },
    {
        'id': 'renewal_sub_large',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Subscription Fee — Large Corporate',
        'amount': '1545.00',
        'frequency': 'Annual',
        'description': 'Annual Subscription portion for Large Corporate members (2+ branches).',
    },
    {
        'id': 'renewal_welfare_sme',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Welfare Dues — SMEs',
        'amount': '300.00',
        'frequency': 'Annual',
        'description': 'Annual member welfare fund dues for SMEs.',
    },
    {
        'id': 'renewal_welfare_large',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Welfare Dues — Large Corporate',
        'amount': '400.00',
        'frequency': 'Annual',
        'description': 'Annual member welfare fund dues for Large Corporates.',
    },
    {
        'id': 'renewal_consolidation_item',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Consolidation — Large Corporate & SMEs',
        'amount': '1286.00',
        'frequency': 'Annual',
        'description': 'Annual Consolidation operational scope tariff.',
    },
    {
        'id': 'renewal_admin_sme',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Administrative Fee — SMEs',
        'amount': '200.00',
        'frequency': 'Annual',
        'description': 'Secretariat annual administrative operational levy for SMEs.',
    },
    {
        'id': 'renewal_admin_large',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Administrative Fee — Large Corporate',
        'amount': '300.00',
        'frequency': 'Annual',
        'description': 'Secretariat annual administrative operational levy for Large Corporates.',
    },
    {
        'id': 'renewal_legal_sme',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Legal & Audit Fee — SMEs',
        'amount': '100.00',
        'frequency': 'Annual',
        'description': 'Legal representation & statutory audit retainer for SMEs.',
    },
    {
        'id': 'renewal_legal_large',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Legal & Audit Fee — Large Corporate',
        'amount': '500.00',
        'frequency': 'Annual',
        'description': 'Legal representation & statutory audit retainer for Large Corporates.',
    },
    {
        'id': 'renewal_agm',
        'section': 'renewal',
        'is_summary': False,
        'label': 'AGM Levy — Large Corporate & SMEs',
        'amount': '500.00',
        'frequency': 'Annual',
        'description': 'Annual General Meeting logistics & venue levy.',
    },
    {
        'id': 'renewal_bond',
        'section': 'renewal',
        'is_summary': False,
        'label': 'Customs Bond Fee (SIC) — Large Corporate & SMEs',
        'amount': '350.00',
        'frequency': 'Annual',
        'description': 'SIC Customs House Agent joint bond indemnity fee.',
    },
    {
        'id': 'renewal_cti_sme',
        'section': 'renewal',
        'is_summary': False,
        'label': '8. CTI Training — SMEs',
        'amount': '600.00',
        'frequency': 'Annual',
        'description': 'Customs Training Institute capacity building levy for SMEs.',
    },
    {
        'id': 'renewal_cti_large',
        'section': 'renewal',
        'is_summary': False,
        'label': '8. CTI Training — Large Corporate',
        'amount': '1200.00',
        'frequency': 'Annual',
        'description': 'Customs Training Institute capacity building levy for Large Corporates.',
    },
]

def seed():
    conn = get_db()
    with conn.cursor() as cur:
        # 1. Update platform_settings
        cur.execute("""
            INSERT INTO platform_settings (config_key, config_value)
            VALUES ('cubag_fees_v2', %s)
            ON CONFLICT (config_key) 
            DO UPDATE SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP
        """, (json.dumps(ALL_FEES),))

        # 2. Update fee_schedules table
        for f in ALL_FEES:
            amt = float(f['amount'])
            key = f['id']
            fee_type = f['section']
            name = f['label']
            desc = f.get('description', '')
            cur.execute("""
                INSERT INTO fee_schedules (key, fee_type, name, amount, description, is_active)
                VALUES (%s, %s, %s, %s, %s, TRUE)
                ON CONFLICT (key) 
                DO UPDATE SET fee_type = EXCLUDED.fee_type, name = EXCLUDED.name, amount = EXCLUDED.amount, description = EXCLUDED.description, is_active = TRUE
            """, (key, fee_type, name, amt, desc))

        conn.commit()
        print(f"Successfully seeded {len(ALL_FEES)} fee items into platform_settings and fee_schedules!")
    conn.close()

if __name__ == '__main__':
    seed()
