"""
Public Web Legal and Compliance Pages for CUBAG.
Provides standalone, responsive web pages and API endpoints for:
- Privacy Policy (/privacy, /api/v1/public/privacy)
- Terms of Service (/terms, /api/v1/public/terms)
- Account Deletion (/delete-account, /api/v1/public/delete-account)

Fulfills:
- Apple App Store Review Guideline 5.1.1(v) (Account Deletion & Privacy Policy URL)
- Google Play Store Policy (Public Privacy Policy & Web-based Account Deletion)
- Republic of Ghana Data Protection Act, 2012 (Act 843)
"""

import os
import uuid
import logging
from datetime import datetime
from flask import Blueprint, request, jsonify, render_template_string, redirect, url_for
from config.db import get_db

logger = logging.getLogger(__name__)

public_pages_bp = Blueprint('public_pages', __name__)

# ── Shared HTML Styling ───────────────────────────────────────────────────────
_BASE_PAGE_HEAD = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }} - Customs Brokers Association Ghana (CUBAG)</title>
    <link rel="icon" type="image/jpeg" href="/logo.jpeg">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Public+Sans:wght@400;600;700&family=Source+Serif+4:opsz,wght@8..60,600&display=swap" rel="stylesheet">
    <style>
        /* CUBAG design tokens (same as the app: lib/design/cubag_design.dart) */
        :root {
            --paper: #ffffff;
            --sand: #F7F3EF;
            --ink: #2A1810;
            --ink-soft: #4A3A31;
            --muted: #6E625B;
            --line: #E8DED6;
            --cocoa: #5C3421;
            --accent: #C2410C;
            --accent-hover: #9A3412;
            --accent-tint: #FFF4ED;
            --danger: #B42318;
            --danger-tint: #FEF3F2;
            --success: #067647;
            --sans: "Public Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            --serif: "Source Serif 4", Georgia, serif;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --paper: #1E120C; --sand: #160D09; --ink: #F5EDE7; --ink-soft: #E2D6CD;
                --muted: #B3A69D; --line: #3A2A20; --accent: #FB8A4C; --accent-hover: #FDA56F;
                --accent-tint: #2B1910; --danger: #F97066; --danger-tint: #2A1414;
            }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: var(--sans);
            background: var(--sand);
            color: var(--ink);
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
            padding-bottom: 64px;
        }
        a { color: var(--accent); }
        a:focus-visible, button:focus-visible, input:focus-visible, textarea:focus-visible {
            outline: 3px solid var(--accent); outline-offset: 2px;
        }
        .header { background: var(--paper); border-bottom: 1px solid var(--line); padding: 14px 16px; }
        .header-content {
            max-width: 720px; margin: 0 auto; display: flex; align-items: center;
            justify-content: space-between; flex-wrap: wrap; gap: 12px;
        }
        .brand { display: flex; align-items: center; gap: 12px; text-decoration: none; color: var(--ink); }
        .brand img { width: 40px; height: 40px; border-radius: 50%; object-fit: cover; }
        .brand-text h1 { font-family: var(--serif); font-size: 17px; font-weight: 600; line-height: 1.2; }
        .brand-text p { font-size: 12.5px; color: var(--muted); }
        .nav-links { display: flex; gap: 4px; flex-wrap: wrap; }
        .nav-links a {
            color: var(--ink-soft); text-decoration: none; font-size: 14px; font-weight: 600;
            padding: 8px 12px; border-radius: 8px;
        }
        .nav-links a:hover { background: var(--sand); }
        .nav-links a.active { color: var(--accent); background: var(--accent-tint); }
        .container { max-width: 720px; margin: 32px auto 0; padding: 0 16px; }
        .card {
            background: var(--paper); border: 1px solid var(--line); border-radius: 14px;
            padding: 40px 40px 32px;
        }
        @media (max-width: 640px) { .card { padding: 24px 18px; } .container { margin-top: 16px; } }
        /* The old uppercase eyebrow label: kept as quiet sentence-case text. */
        .badge { display: block; color: var(--muted); font-size: 14px; font-weight: 600; margin-bottom: 6px; }
        h2.title {
            font-family: var(--serif); font-size: 34px; font-weight: 600; line-height: 1.15;
            color: var(--ink); margin-bottom: 10px;
        }
        .subtitle {
            font-size: 15px; color: var(--muted); margin-bottom: 28px;
            padding-bottom: 24px; border-bottom: 1px solid var(--line);
        }
        .section { margin-bottom: 32px; }
        .section h3 { font-family: var(--serif); font-size: 21px; font-weight: 600; color: var(--ink); margin-bottom: 10px; }
        .section p, .section ul, .section ol { font-size: 16px; color: var(--ink-soft); line-height: 1.7; margin-bottom: 12px; max-width: 66ch; }
        .section ul, .section ol { padding-left: 22px; }
        .section li { margin-bottom: 6px; }
        .section strong { color: var(--ink); }
        .info-box, .danger-box {
            padding: 16px 18px; border-radius: 10px; margin: 16px 0; font-size: 15px;
        }
        .info-box { background: var(--accent-tint); border: 1px solid var(--line); color: var(--ink-soft); }
        .danger-box { background: var(--danger-tint); border: 1px solid var(--danger); color: var(--danger); }
        .footer { margin-top: 32px; text-align: center; font-size: 13px; color: var(--muted); }
        /* Form controls (account deletion) */
        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; font-size: 15px; font-weight: 600; margin-bottom: 6px; color: var(--ink); }
        .form-group .hint { font-size: 13px; color: var(--muted); margin-bottom: 6px; }
        .form-control {
            width: 100%; padding: 12px 14px; border: 1px solid var(--line); border-radius: 10px;
            font-size: 16px; font-family: inherit; background: var(--paper); color: var(--ink);
        }
        .form-control:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-tint); }
        textarea.form-control { resize: vertical; min-height: 96px; }
        .checkbox-label { display: flex; align-items: flex-start; gap: 10px; font-size: 15px; color: var(--ink-soft); cursor: pointer; margin: 16px 0; }
        .checkbox-label input { margin-top: 4px; accent-color: var(--accent); width: 18px; height: 18px; }
        .btn {
            display: inline-block; background: var(--accent); color: #ffffff; font-weight: 700; font-size: 16px;
            padding: 14px 24px; border-radius: 10px; border: none; cursor: pointer; text-decoration: none; text-align: center;
        }
        .btn:hover { background: var(--accent-hover); }
        .btn-danger { background: var(--danger); }
        .btn-danger:hover { filter: brightness(0.92); }
        .btn-block { display: block; width: 100%; }
        @media print { .header, .nav-links, .footer { display: none; } body { background: #fff; } .card { border: 0; } }
    </style>
</head>
<body>
    <header class="header">
        <div class="header-content">
            <a href="/" class="brand">
                <img src="/logo.jpeg" alt="CUBAG Logo" onerror="this.style.display='none'">
                <div class="brand-text">
                    <h1>Customs Brokers Association of Ghana</h1>
                    <p>Honesty and Efficiency</p>
                </div>
            </a>
            <nav class="nav-links">
                <a href="/privacy" class="{% if active_tab == 'privacy' %}active{% endif %}">Privacy</a>
                <a href="/terms" class="{% if active_tab == 'terms' %}active{% endif %}">Terms</a>
                <a href="/delete-account" class="{% if active_tab == 'delete' %}active{% endif %}">Delete account</a>
            </nav>
        </div>
    </header>
    <main class="container">
"""

_BASE_PAGE_FOOT = """
        <div class="footer">
            <p>&copy; {{ current_year }} Customs Brokers Association of Ghana (CUBAG). All rights reserved.</p>
            <p style="margin-top: 4px;">National Secretariat, Accra, Ghana</p>
        </div>
    </main>
</body>
</html>
"""


# ── 1. Privacy Policy Page ────────────────────────────────────────────────────
@public_pages_bp.route('/privacy', methods=['GET'])
@public_pages_bp.route('/api/v1/public/privacy', methods=['GET'])
def serve_privacy_policy():
    """Serves the public CUBAG Privacy Policy."""
    if request.headers.get('Accept') == 'application/json' and request.path.startswith('/api/'):
        return jsonify({
            'title': 'CUBAG Privacy Policy',
            'effective_date': '2026-01-01',
            'last_updated': '2026-11-11',
            'data_controller': 'Customs Brokers Association of Ghana (CUBAG)',
            'jurisdiction': 'Republic of Ghana (Data Protection Act, 2012 - Act 843)',
            'contact_email': 'support@cubag.org',
            'deletion_url': 'https://cubag-api-server.fly.dev/delete-account'
        }), 200

    template = _BASE_PAGE_HEAD + """
        <div class="card">
            <span class="badge">Legal Document</span>
            <h2 class="title">Privacy Policy</h2>
            <div class="subtitle">Effective Date: January 1, 2026 &bull; Last Revised: November 2026</div>

            <div class="section">
                <h3>1. Introduction &amp; Commitment</h3>
                <p>
                    The <strong>Customs Brokers Association of Ghana ("CUBAG", "we", "us", or "our")</strong> operates the CUBAG mobile applications (iOS and Android), web portals, and digital association services.
                </p>
                <p>
                    We are dedicated to safeguarding the privacy, confidentiality, and security of our members, licentiates, customs brokerage staff, and users. This Privacy Policy is formulated in strict accordance with the <strong>Data Protection Act, 2012 (Act 843) of the Republic of Ghana</strong>, African Union cybersecurity frameworks, and relevant international data protection regulations including the EU General Data Protection Regulation (GDPR) where applicable.
                </p>
            </div>

            <div class="section">
                <h3>2. Identity of Data Controller</h3>
                <p>
                    <strong>Data Controller:</strong> Customs Brokers Association of Ghana (CUBAG)<br>
                    <strong>National Secretariat:</strong> Tema Port Commercial Area, Greater Accra, Republic of Ghana<br>
                    <strong>Operating Chapters:</strong> Tema Port, Takoradi Port, Kotoka International Airport (KIA), Aflao, Elubo, Paga<br>
                    <strong>Data Protection Contact:</strong> <a href="mailto:support@cubag.org" style="color: var(--accent);">support@cubag.org</a>
                </p>
            </div>

            <div class="section">
                <h3>3. Categories of Information We Collect</h3>
                <p>We collect and process only the information necessary to fulfill our statutory role as a recognised customs house brokerage association:</p>
                <ul>
                    <li><strong>Personal &amp; Contact Identifiers:</strong> Full legal name, official email address, mobile phone number, digital address (GhanaPost GPS), and corporate business address.</li>
                    <li><strong>Customs &amp; Regulatory Credentials:</strong> Ghana Revenue Authority (GRA) Customs House Agent (CHA) license numbers, CUBAG membership registration codes, company registration numbers (Registrar General's Department), and Tax Identification Numbers (TIN / Ghana Card PIN).</li>
                    <li><strong>Compliance Documentation:</strong> Tax clearance certificates, operating permits, licentiate diplomas, and identity documents submitted for membership vetting.</li>
                    <li><strong>Financial &amp; Transaction Records:</strong> Mobile Money transaction reference IDs, bank transfer audit numbers, and annual dues package receipts. <em>Note: CUBAG does not store raw credit/debit card numbers or Mobile Money PINs.</em></li>
                    <li><strong>Device &amp; Authentication Metadata:</strong> Push notification device tokens (Firebase Cloud Messaging) and cryptographic public hashes of revocable biometric credentials for native device login (Face ID / Touch ID / Android Biometric). Biometric feature data never leaves your personal device.</li>
                </ul>
            </div>

            <div class="section">
                <h3>4. Authorised Processors and Third-Party Sub-processors</h3>
                <p>We work with trusted, industry-certified service providers to deliver secure platform capabilities:</p>
                <ul>
                    <li><strong>Payment Gateways (PCI-DSS Level 1):</strong> Hubtel Ghana Ltd and Paystack Payments Ltd for processing dues, levies, and event registrations.</li>
                    <li><strong>Cloud Infrastructure &amp; Database:</strong> Supabase Inc. / Amazon Web Services (AWS) operating in secure cloud regions with AES-256 data-at-rest encryption.</li>
                    <li><strong>Notification &amp; Messaging Delivery:</strong> Firebase Cloud Messaging (Google LLC) for push alerts, and Termii / Twilio for transactional SMS OTP delivery.</li>
                    <li><strong>Regulatory Reporting:</strong> Ghana Revenue Authority (GRA) and Ghana Ports and Harbours Authority (GPHA) where mandated by customs legislation (Customs Act, 2015, Act 891).</li>
                </ul>
            </div>

            <div class="section">
                <h3>5. Purpose and Legal Basis for Processing</h3>
                <p>Under Ghana Act 843, we process your information under the following legal bases:</p>
                <ul>
                    <li><strong>Contractual Necessity:</strong> To process membership admissions, issue official digital ID cards and cryptographic QR verifications, and maintain the professional roll.</li>
                    <li><strong>Legal &amp; Regulatory Obligation:</strong> To ensure compliance with GRA customs clearance bylaws, verify valid brokerage licenses, and prevent unauthorized brokerage operations.</li>
                    <li><strong>Legitimate Interests:</strong> To deliver educational cohorts (Customs Training Institute - CTI), circulate port tariff advisories, and protect platform security against unauthorized access.</li>
                </ul>
            </div>

            <div class="section">
                <h3>6. Data Retention and Deletion Rights</h3>
                <p>
                    We retain personal data only as long as necessary to serve your membership and satisfy statutory retention obligations:
                </p>
                <ul>
                    <li><strong>Account Deletion:</strong> Any member or user has the absolute right to request the permanent deletion of their account and associated personal data at any time.</li>
                    <li><strong>In-App Deletion:</strong> Accessible inside the CUBAG mobile app under <em>Settings &rarr; Delete Member Account</em>.</li>
                    <li><strong>Web-Based Deletion:</strong> A public, no-install deletion request form is available at <a href="/delete-account" style="color: var(--accent); font-weight: 600;">/delete-account</a>.</li>
                    <li><strong>Statutory Financial Records:</strong> As mandated by Ghana tax and corporate record-keeping laws, transactional payment audit logs are archived in anonymized form for statutory audit periods (up to six years) before being purged.</li>
                </ul>
            </div>

            <div class="section">
                <h3>7. Information Security Measures</h3>
                <p>
                    We deploy multi-layered safeguards including TLS 1.3 encryption in transit, AES-256 encrypted local caching, cryptographic password hashing (Scrypt / PBKDF2), automated rate-limiting, and short-lived signed tokens for private document retrieval.
                </p>
            </div>

            <div class="section">
                <h3>8. Contact the Secretariat</h3>
                <p>
                    For privacy inquiries, data subject access requests (DSAR), or rectification notices, please reach our Data Protection Officer:
                </p>
                <div class="info-box">
                    <strong>Customs Brokers Association of Ghana</strong><br>
                    Attn: Data Protection Officer / Secretariat<br>
                    Email: <a href="mailto:support@cubag.org" style="color: var(--primary); font-weight: bold;">support@cubag.org</a><br>
                    Telephone: +233 (0) 303 206 182 / +233 (0) 50 123 4567<br>
                    Headquarters: Tema Port Commercial District, Greater Accra, Ghana
                </div>
            </div>
        </div>
    """ + _BASE_PAGE_FOOT

    return render_template_string(template, title="Privacy Policy", active_tab="privacy", current_year=datetime.utcnow().year)


# ── 2. Terms of Service Page ──────────────────────────────────────────────────
@public_pages_bp.route('/terms', methods=['GET'])
@public_pages_bp.route('/api/v1/public/terms', methods=['GET'])
def serve_terms_of_service():
    """Serves the official CUBAG Platform Terms of Service."""
    if request.headers.get('Accept') == 'application/json' and request.path.startswith('/api/'):
        return jsonify({
            'title': 'CUBAG Terms of Service',
            'effective_date': '2026-01-01',
            'last_updated': '2026-11-11',
            'association': 'Customs Brokers Association of Ghana (CUBAG)',
            'jurisdiction': 'Republic of Ghana',
            'contact_email': 'support@cubag.org'
        }), 200

    template = _BASE_PAGE_HEAD + """
        <div class="card">
            <span class="badge">Platform Agreement</span>
            <h2 class="title">Terms of Service</h2>
            <div class="subtitle">Effective Date: January 1, 2026 &bull; Last Revised: November 2026</div>

            <div class="section">
                <h3>1. Acceptance of Terms</h3>
                <p>
                    Welcome to the <strong>Customs Brokers Association of Ghana ("CUBAG")</strong> digital ecosystem. By accessing, downloading, installing, or using the CUBAG mobile application or web portal, you agree to be bound by these Terms of Service, the CUBAG Constitution, and all administrative bylaws issued by the National Executive Council.
                </p>
            </div>

            <div class="section">
                <h3>2. Membership Eligibility &amp; Representation</h3>
                <p>
                    Access to authenticated member features requires valid accreditation as a Licensed Customs House Agent (LCHA), individual licentiate broker, or corporate member in good standing pursuant to the <strong>Ghana Customs Act, 2015 (Act 891)</strong>.
                </p>
                <p>
                    You agree that all information, licenses, and statutory clearance certificates submitted during onboarding or renewal are authentic, current, and truthful. Providing fraudulent credentials constitutes ground for immediate revocation and referral to statutory regulatory authorities.
                </p>
            </div>

            <div class="section">
                <h3>3. Account Security &amp; Credentials</h3>
                <p>
                    You are solely responsible for maintaining the confidentiality of your login credentials, password, and biometric enrollment on personal devices. You must promptly report any unauthorized access or compromise of your account to <a href="mailto:support@cubag.org" style="color: var(--accent);">support@cubag.org</a>.
                </p>
            </div>

            <div class="section">
                <h3>4. Dues, Training &amp; Financial Obligations</h3>
                <ul>
                    <li><strong>Annual Dues &amp; Package Fees:</strong> Members are required to satisfy annual dues and renewal fees according to their classified scale (SME / Large Corporate / Licentiate) as stipulated in the official tariff schedule.</li>
                    <li><strong>Customs Training Institute (CTI):</strong> Course registrations and cohort certifications are subject to attendance requirements and completion of statutory curricula.</li>
                    <li><strong>Non-Refundable Dues:</strong> Membership dues, vetting application fees, and examination fees are non-refundable once administrative processing has commenced.</li>
                </ul>
            </div>

            <div class="section">
                <h3>5. Digital ID Card &amp; Public Verification</h3>
                <p>
                    The digital membership credential and associated verification QR codes issued through this application remain the property of CUBAG. They attest to the member's current status and good standing. CUBAG reserves the right to suspend or revoke verification badges upon non-payment of dues, lapse in statutory customs licensing, or disciplinary findings.
                </p>
            </div>

            <div class="section">
                <h3>6. Termination &amp; Account Deletion</h3>
                <p>
                    You may terminate your account at any time either via the in-app deletion feature (Settings &rarr; Delete Member Account) or by submitting an online request via our <a href="/delete-account" style="color: var(--accent); font-weight: 600;">Account Deletion Request Portal</a>. Termination revokes digital verification privileges and deactivates portal access.
                </p>
            </div>

            <div class="section">
                <h3>7. Governing Law &amp; Dispute Resolution</h3>
                <p>
                    These Terms shall be governed by and construed in accordance with the laws of the <strong>Republic of Ghana</strong>. Any disputes arising out of membership conduct or platform usage shall first be submitted to the CUBAG Disciplinary and Ethics Committee, and subsequently to arbitration under the <strong>Alternative Dispute Resolution Act, 2010 (Act 798)</strong> of Ghana.
                </p>
            </div>
        </div>
    """ + _BASE_PAGE_FOOT

    return render_template_string(template, title="Terms of Service", active_tab="terms", current_year=datetime.utcnow().year)


# ── 3. Account Deletion Request Page (GET) ───────────────────────────────────
@public_pages_bp.route('/delete-account', methods=['GET'])
@public_pages_bp.route('/api/v1/public/delete-account', methods=['GET'])
def serve_delete_account_page():
    """
    Public web page for requesting account and data deletion.
    Fulfills Apple Guideline 5.1.1(v) & Google Play Store requirements.
    """
    template = _BASE_PAGE_HEAD + """
        <div class="card">
            <span class="badge" style="background-color: rgba(239, 68, 68, 0.1); color: var(--danger);">Data Subject Rights</span>
            <h2 class="title">Account &amp; Data Deletion Request</h2>
            <div class="subtitle">Ghana Data Protection Act (Act 843) &bull; Apple Guideline 5.1.1(v) &bull; Google Play Data Safety</div>

            <div class="danger-box">
                <strong>Important Information Regarding Account Deletion:</strong><br>
                Deleting your CUBAG member account is permanent. Upon processing, you will immediately lose access to your member portal, digital membership credentials, port circulars, and verified broker badge.
            </div>

            <div class="section">
                <h3>How Account Deletion Works</h3>
                <p>When an account deletion request is processed:</p>
                <ul>
                    <li><strong>Immediately Purged:</strong> Your profile photo, phone number, push notification device tokens, password hashes, biometric device authorization keys, and digital addresses are permanently removed or rendered completely inaccessible.</li>
                    <li><strong>Email Anonymization:</strong> Your registered email is replaced with an anonymous placeholder (<code>deleted_[id]@deleted.invalid</code>) so no further marketing or transactional emails will be dispatched.</li>
                    <li><strong>Regulatory Financial Ledgers:</strong> In strict accordance with the Ghana Revenue Authority (GRA) tax audit requirements, completed transactional receipt amounts and association ledger entries are retained in an anonymized format for statutory audit periods (up to 6 years).</li>
                </ul>
            </div>

            <div class="section" style="margin-top: 32px;">
                <h3>Submit an Online Deletion Request</h3>
                <p>If you have uninstalled the mobile app or wish to submit a web-based deletion request, please complete the form below:</p>

                <form method="POST" action="/delete-account" id="deleteForm">
                    <div class="form-group">
                        <label for="full_name">Full Legal Name *</label>
                        <input type="text" id="full_name" name="full_name" class="form-control" placeholder="e.g. Kwesi Mensah" required>
                    </div>

                    <div class="form-group">
                        <label for="email">Registered Email Address *</label>
                        <div class="hint">The email associated with your CUBAG portal account</div>
                        <input type="email" id="email" name="email" class="form-control" placeholder="broker@example.com" required>
                    </div>

                    <div class="form-group">
                        <label for="phone">Phone Number (Optional)</label>
                        <input type="tel" id="phone" name="phone" class="form-control" placeholder="e.g. +233 24 123 4567">
                    </div>

                    <div class="form-group">
                        <label for="license_number">CUBAG ID or Customs License Number (Optional)</label>
                        <input type="text" id="license_number" name="license_number" class="form-control" placeholder="e.g. CUBAG-2026-0042 or GRA-CHA-8921">
                    </div>

                    <div class="form-group">
                        <label for="reason">Reason for Deletion (Optional)</label>
                        <select id="reason" name="reason" class="form-control">
                            <option value="leaving_profession">Retiring or leaving customs brokerage profession</option>
                            <option value="company_closed">Brokerage company dissolved or restructured</option>
                            <option value="privacy_concerns">Privacy or data collection concerns</option>
                            <option value="duplicate_account">Duplicate or test account</option>
                            <option value="other">Other reason</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label for="notes">Additional Comments (Optional)</label>
                        <textarea id="notes" name="notes" class="form-control" placeholder="Any additional notes for the CUBAG Secretariat..."></textarea>
                    </div>

                    <label class="checkbox-label">
                        <input type="checkbox" name="confirm_deletion" value="yes" required>
                        <span>I understand that this action is permanent and irrevocably cancels my active CUBAG member digital credentials.</span>
                    </label>

                    <button type="submit" class="btn btn-danger btn-block">Submit Permanent Deletion Request</button>
                </form>
            </div>

            <div class="info-box" style="margin-top: 28px;">
                <strong>Alternative Option for Active Mobile Users:</strong><br>
                You can also delete your account instantly from within the CUBAG mobile app without waiting: open the app, go to <strong>Settings &rarr; Delete Member Account</strong>, and confirm your password.
            </div>
        </div>
    """ + _BASE_PAGE_FOOT

    return render_template_string(template, title="Account Deletion Request", active_tab="delete", current_year=datetime.utcnow().year)


# ── 4. Account Deletion Request Handler (POST) ────────────────────────────────
@public_pages_bp.route('/delete-account', methods=['POST'])
@public_pages_bp.route('/api/v1/public/delete-account', methods=['POST'])
def process_delete_account_request():
    """
    Processes a submitted account deletion request from the web form or JSON API.
    Inserts a tracked deletion record into `data_deletion_requests` and provides a receipt.
    """
    is_json = request.is_json
    data = request.get_json(silent=True) or request.form

    email = (data.get('email') or '').strip().lower()
    full_name = (data.get('full_name') or data.get('name') or '').strip()
    phone = (data.get('phone') or '').strip()
    license_no = (data.get('license_number') or '').strip()
    reason = (data.get('reason') or 'Unspecified').strip()
    notes = (data.get('notes') or '').strip()
    confirmed = data.get('confirm_deletion') in ('yes', 'true', True, '1', 1)

    if not email:
        msg = "Email address is required."
        if is_json:
            return jsonify({'success': False, 'message': msg}), 400
        return _render_error_page(msg)

    if not confirmed and not is_json:
        msg = "You must confirm that you understand this action is permanent."
        return _render_error_page(msg)

    tracking_code = f"DEL-{datetime.utcnow().strftime('%Y%m')}-{uuid.uuid4().hex[:6].upper()}"
    full_reason_text = f"Reason: {reason}. Name: {full_name}. License: {license_no}. Notes: {notes}".strip()

    conn = get_db()
    member_id = None
    try:
        with conn.cursor() as cursor:
            # Look up member by email
            cursor.execute("SELECT id, status, name FROM members WHERE LOWER(email) = %s", (email,))
            member = cursor.fetchone()
            if member:
                member_id = member['id']

            # Insert into data_deletion_requests
            cursor.execute("""
                INSERT INTO data_deletion_requests 
                    (member_id, requested_by, status, created_at, email, phone, reason, request_source, tracking_code, notes)
                VALUES 
                    (%s, %s, 'pending', NOW(), %s, %s, %s, 'web', %s, %s)
                RETURNING id
            """, (
                member_id,
                member_id,
                email,
                phone or None,
                full_reason_text,
                tracking_code,
                notes or None
            ))
            res_row = cursor.fetchone() or {}
            request_id = res_row.get('id') if isinstance(res_row, dict) else (res_row[0] if res_row else None)
            conn.commit()

        logger.info(f"[Account Deletion] Web request {request_id} created for {email} with tracking {tracking_code}")

    except Exception as e:
        logger.error(f"[Account Deletion] Error logging deletion request: {e}")
        if is_json:
            return jsonify({'success': False, 'message': 'Internal error processing deletion request.'}), 500
        return _render_error_page("A server error occurred while processing your request. Please email support@cubag.org directly.")
    finally:
        conn.close()

    if is_json:
        return jsonify({
            'success': True,
            'message': 'Account deletion request received successfully.',
            'tracking_code': tracking_code,
            'status': 'pending',
            'estimated_timeline_days': 14,
            'statutory_reference': 'Ghana Data Protection Act, 2012 (Act 843)'
        }), 201

    # Render web success receipt page
    template = _BASE_PAGE_HEAD + """
        <div class="card">
            <span class="badge" style="background-color: rgba(16, 185, 129, 0.1); color: var(--success);">Request Received</span>
            <h2 class="title">Account Deletion Request Logged</h2>
            <div class="subtitle">Reference Tracking Code: <strong>{{ tracking_code }}</strong></div>

            <div class="info-box" style="border-left-color: var(--success); background-color: #ecfdf5;">
                <strong>Your account deletion request has been formally registered with the CUBAG Secretariat.</strong><br>
                A confirmation has been recorded for the account associated with <strong>{{ email }}</strong>.
            </div>

            <div class="section">
                <h3>Next Steps &amp; Processing Timeline</h3>
                <p>
                    Pursuant to the <strong>Data Protection Act, 2012 (Act 843) of Ghana</strong> and platform guidelines:
                </p>
                <ul>
                    <li>Our Data Compliance team will review and process your request within <strong>14 business days</strong>.</li>
                    <li>All personal identifiers, contact numbers, biometric device links, and push tokens will be purged.</li>
                    <li>If you have any active customs clearance filings or pending inquiries, the Secretariat may contact you at {{ email }} to verify your request before finalizing deletion.</li>
                </ul>
            </div>

            <div class="section" style="margin-top: 24px;">
                <p>
                    If you have questions regarding this request or wish to cancel it, please contact our secretariat at <a href="mailto:support@cubag.org" style="color: var(--accent); font-weight: bold;">support@cubag.org</a> quoting reference <strong>{{ tracking_code }}</strong>.
                </p>
            </div>

            <a href="/" class="btn" style="margin-top: 16px;">Return to CUBAG Portal</a>
        </div>
    """ + _BASE_PAGE_FOOT

    return render_template_string(
        template,
        title="Deletion Request Submitted",
        active_tab="delete",
        tracking_code=tracking_code,
        email=email,
        current_year=datetime.utcnow().year
    ), 200


def _render_error_page(message):
    template = _BASE_PAGE_HEAD + """
        <div class="card">
            <span class="badge" style="background-color: rgba(239, 68, 68, 0.1); color: var(--danger);">Request Error</span>
            <h2 class="title">Unable to Process Request</h2>
            <div class="subtitle">Please check the details you entered and try again</div>

            <div class="danger-box">
                {{ message }}
            </div>

            <a href="/delete-account" class="btn" style="margin-top: 16px;">Go Back to Form</a>
        </div>
    """ + _BASE_PAGE_FOOT

    return render_template_string(
        template,
        title="Error Processing Request",
        active_tab="delete",
        message=message,
        current_year=datetime.utcnow().year
    ), 400
