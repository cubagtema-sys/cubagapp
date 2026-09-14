import os
import sys
import uuid
from datetime import datetime
from werkzeug.security import generate_password_hash
from config.db import get_db

DEMO_PROFILES = [
    {
        'name': 'Kofi Mensah (MD)',
        'email': 'sme.cf@cubag.demo',
        'phone': '0244100001',
        'company': 'Apex Freight & Logistics Ltd',
        'company_slug': 'apex_freight',
        'membership_number': 'CUBAG-MEM-SME-001',
        'agency_code': 'AGC-SME-01',
        'location': 'Tema Community 1, Commercial Warehouse Area',
        'digital_address': 'GT-012-3456',
        'tin': 'C0028192011',
        'port_of_operation': 'Tema Port',
        'primary_port': 'Tema Port',
        'member_type': 'Corporate',
        'member_scale': 'sme',
        'fee_category': 'cf_only',
        'consolidation_scope': 'without_consolidation',
        'profile_title': 'SME (1 Branch) — Clearing & Forwarding Only',
        'reg_fee': 1620.00,
    },
    {
        'name': 'Akosua Darko (Operations Director)',
        'email': 'sme.consol@cubag.demo',
        'phone': '0244100002',
        'company': 'Trans-Ghana Groupage Logistics Ltd',
        'company_slug': 'trans_ghana',
        'membership_number': 'CUBAG-MEM-SME-002',
        'agency_code': 'AGC-SME-02',
        'location': 'Heavy Industrial Area, Plot 14, Tema',
        'digital_address': 'GT-045-6789',
        'tin': 'C0028192022',
        'port_of_operation': 'Tema Port',
        'primary_port': 'Tema Port',
        'member_type': 'Corporate',
        'member_scale': 'sme',
        'fee_category': 'consolidation',
        'consolidation_scope': 'with_consolidation',
        'profile_title': 'SME (1 Branch) — Consolidation Only',
        'reg_fee': 1720.00,
    },
    {
        'name': 'Kwame Owusu-Ansah (Managing Director)',
        'email': 'sme.full@cubag.demo',
        'phone': '0244100003',
        'company': 'Meridian Clearing & Consolidation Ltd',
        'company_slug': 'meridian_cc',
        'membership_number': 'CUBAG-MEM-SME-003',
        'agency_code': 'AGC-SME-03',
        'location': 'Airport Residential Area, Accra',
        'digital_address': 'GA-112-9843',
        'tin': 'C0028192033',
        'port_of_operation': 'Kotoka International Airport (KIA)',
        'primary_port': 'Kotoka International Airport (KIA)',
        'member_type': 'Corporate',
        'member_scale': 'sme',
        'fee_category': 'cf_consolidation',
        'consolidation_scope': 'with_consolidation',
        'profile_title': 'SME (1 Branch) — Consolidation, Clearing & Forwarding',
        'reg_fee': 2220.00,
    },
    {
        'name': 'Samuel Osei-Bonsu (CEO)',
        'email': 'corp.cf@cubag.demo',
        'phone': '0244100004',
        'company': 'Global Express Freightways Int. Ltd',
        'company_slug': 'global_express',
        'membership_number': 'CUBAG-MEM-LRG-001',
        'agency_code': 'AGC-LRG-01',
        'location': 'Harbour Road, Tema & Takoradi Port Road',
        'digital_address': 'GT-089-1234',
        'tin': 'C0028192044',
        'port_of_operation': 'Tema Port',
        'primary_port': 'Tema Port',
        'member_type': 'Corporate',
        'member_scale': 'large_corporate',
        'fee_category': 'cf_only',
        'consolidation_scope': 'without_consolidation',
        'profile_title': 'Large Corporate (2+ Branches) — Clearing & Forwarding Only',
        'reg_fee': 2220.00,
    },
    {
        'name': 'Abena Boateng (Executive Director)',
        'email': 'corp.consol@cubag.demo',
        'phone': '0244100005',
        'company': 'West Africa Cargo Consolidators Plc',
        'company_slug': 'w_africa_cargo',
        'membership_number': 'CUBAG-MEM-LRG-002',
        'agency_code': 'AGC-LRG-02',
        'location': 'MPS Terminal Hub, Tema & Aflao Border Facility',
        'digital_address': 'GT-156-7890',
        'tin': 'C0028192055',
        'port_of_operation': 'Tema Port',
        'primary_port': 'Tema Port',
        'member_type': 'Corporate',
        'member_scale': 'large_corporate',
        'fee_category': 'consolidation',
        'consolidation_scope': 'with_consolidation',
        'profile_title': 'Large Corporate (2+ Branches) — Consolidation Only',
        'reg_fee': 2220.00,
    },
    {
        'name': 'Emmanuel Addo-Kufuor (Managing Director)',
        'email': 'corp.full@cubag.demo',
        'phone': '0244100006',
        'company': 'Pan-African Integrated Logistics Ltd',
        'company_slug': 'pan_african',
        'membership_number': 'CUBAG-MEM-LRG-003',
        'agency_code': 'AGC-LRG-03',
        'location': 'Tema Main Port, Takoradi Commercial Hub & KIA Cargo Village',
        'digital_address': 'GA-990-4321',
        'tin': 'C0028192066',
        'port_of_operation': 'Tema Port',
        'primary_port': 'Tema Port',
        'member_type': 'Corporate',
        'member_scale': 'large_corporate',
        'fee_category': 'cf_consolidation',
        'consolidation_scope': 'with_consolidation',
        'profile_title': 'Large Corporate (2+ Branches) — Full Scope (Consolidation & C&F)',
        'reg_fee': 2220.00,
    },
]

# The official 11 mandatory documents required for full CUBAG licensing
DOCUMENT_REQUIREMENTS = [
    ('application_letter', 'Application Letter on Company Letterhead', 'application_letter.pdf', 1250000),
    ('acceptance_letter', 'Acceptance Letter from CUBAG District', 'district_acceptance_letter.pdf', 980000),
    ('ssnit_clearance', 'SSNIT Clearance Certificate', 'ssnit_clearance_cert_2026.pdf', 1450000),
    ('tax_clearance', 'Tax Clearance Certificate', 'gra_tax_clearance_cert_2026.pdf', 1620000),
    ('proficiency_certificate', 'Proficiency / Exemption Certificate', 'customs_proficiency_cert.pdf', 2100000),
    ('staff_list', 'Staff List', 'certified_staff_roster.pdf', 850000),
    ('data_forms', 'Data Forms (Certificate Holders, Directors & Staff)', 'cubag_director_staff_data_forms.pdf', 2450000),
    ('certificate_commence', 'Certificate to Commence Business / Certificate of Incorporation', 'rgd_commence_business_incorporation.pdf', 3100000),
    ('business_plan', 'Business Plan', 'corporate_logistics_business_plan.pdf', 4200000),
    ('company_regulations', 'Company Regulations', 'company_constitution_and_regulations.pdf', 2800000),
    ('vetting_registration_form', 'Vetting & Registration Form (Provided by the Association)', 'completed_vetting_registration_form.pdf', 1890000),
]

DEFAULT_PASSWORD = 'Password123!'

def seed_profiles_and_documents():
    conn = get_db()
    pw_hash = generate_password_hash(DEFAULT_PASSWORD, method='pbkdf2:sha256')

    try:
        with conn.cursor() as cursor:
            for p in DEMO_PROFILES:
                # 1. Upsert Member Profile with membership_number ONLY
                cursor.execute("SELECT id FROM members WHERE LOWER(email) = LOWER(%s)", (p['email'],))
                existing = cursor.fetchone()

                if existing:
                    member_id = existing['id']
                    cursor.execute("""
                        UPDATE members SET
                            name = %s,
                            phone = %s,
                            company = %s,
                            license_number = NULL,
                            membership_number = %s,
                            agency_code = %s,
                            location = %s,
                            digital_address = %s,
                            tin = %s,
                            port_of_operation = %s,
                            primary_port = %s,
                            member_type = %s,
                            member_scale = %s,
                            fee_category = %s,
                            consolidation_scope = %s,
                            password_hash = %s,
                            status = 'active',
                            role = 'member',
                            email_verified = TRUE,
                            good_standing = TRUE,
                            compliance_score = 98,
                            star_rating = 5.0,
                            manual_review_score = 10,
                            license_expiry_date = '2027-12-31'
                        WHERE id = %s
                    """, (
                        p['name'], p['phone'], p['company'],
                        p['membership_number'], p['agency_code'],
                        p['location'], p['digital_address'], p['tin'],
                        p['port_of_operation'], p['primary_port'],
                        p['member_type'], p['member_scale'], p['fee_category'], p['consolidation_scope'],
                        pw_hash, member_id
                    ))
                else:
                    cursor.execute("""
                        INSERT INTO members (
                            name, email, phone, company,
                            license_number, membership_number, agency_code,
                            location, digital_address, tin,
                            port_of_operation, primary_port,
                            member_type, member_scale, fee_category, consolidation_scope,
                            password_hash, status, role, email_verified, good_standing,
                            compliance_score, star_rating, manual_review_score, license_expiry_date
                        ) VALUES (
                            %s, %s, %s, %s,
                            NULL, %s, %s,
                            %s, %s, %s,
                            %s, %s,
                            %s, %s, %s, %s,
                            %s, 'active', 'member', TRUE, TRUE,
                            98, 5.0, 10, '2027-12-31'
                        ) RETURNING id
                    """, (
                        p['name'], p['email'].lower(), p['phone'], p['company'],
                        p['membership_number'], p['agency_code'],
                        p['location'], p['digital_address'], p['tin'],
                        p['port_of_operation'], p['primary_port'],
                        p['member_type'], p['member_scale'], p['fee_category'], p['consolidation_scope'],
                        pw_hash
                    ))
                    member_id = cursor.fetchone()['id']

                # 2. Seed all 11 required documents in member_documents
                for req_key, req_label, file_suffix, f_size in DOCUMENT_REQUIREMENTS:
                    file_name = f"{p['company_slug']}_{file_suffix}"
                    mock_url = f"https://jfypczfjycffsmivjjdn.supabase.co/storage/v1/object/public/uploads/member_docs/{member_id}/{req_key}_{uuid.uuid4().hex[:12]}.pdf"

                    cursor.execute("""
                        SELECT id FROM member_documents WHERE member_id = %s AND requirement = %s
                    """, (member_id, req_key))
                    existing_doc = cursor.fetchone()

                    if existing_doc:
                        cursor.execute("""
                            UPDATE member_documents SET
                                label = %s,
                                file_url = %s,
                                file_name = %s,
                                file_size = %s,
                                status = 'approved',
                                admin_note = 'Verified and approved during onboarding vetting.',
                                reviewed_at = NOW(),
                                reviewed_by = 1
                            WHERE id = %s
                        """, (req_label, mock_url, file_name, f_size, existing_doc['id']))
                    else:
                        cursor.execute("""
                            INSERT INTO member_documents (
                                member_id, requirement, label, file_url, file_name, file_size,
                                status, admin_note, uploaded_at, reviewed_at, reviewed_by
                            ) VALUES (
                                %s, %s, %s, %s, %s, %s,
                                'approved', 'Verified and approved during onboarding vetting.', NOW(), NOW(), 1
                            )
                        """, (member_id, req_key, req_label, mock_url, file_name, f_size))

                # 3. Seed Registration Fee Payment Record in payments
                cursor.execute("""
                    SELECT id FROM payments 
                    WHERE member_id = %s AND LOWER(description) LIKE '%%registration%%'
                """, (member_id,))
                if not cursor.fetchone():
                    cursor.execute("""
                        INSERT INTO payments (
                            member_id, amount, description, status, paid_at, payment_ref, created_at
                        ) VALUES (
                            %s, %s, 'New Membership Registration Fee', 'completed', NOW(), %s, NOW()
                        )
                    """, (member_id, p['reg_fee'], f"CUBAG-REG-PAY-{member_id}-{uuid.uuid4().hex[:8].upper()}"))

                print(f"[OK] Profile updated with Membership ID only: {p['company']} ({p['membership_number']})")

            conn.commit()
            print("\n[SUCCESS] All 6 Corporate Profiles updated: Membership Number only (CUBAG-MEM-...) and 11 approved documents.")
    except Exception as e:
        conn.rollback()
        print(f"[ERROR] {e}")
        raise e
    finally:
        conn.close()

if __name__ == '__main__':
    seed_profiles_and_documents()
