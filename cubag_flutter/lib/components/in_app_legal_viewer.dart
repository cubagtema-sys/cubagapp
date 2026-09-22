import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InAppLegalViewer {
  static void show(BuildContext context, {required String title, required String subtitle, required List<Map<String, String>> sections}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5000).withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Color(0xFFFF5000), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: const Color(0xFF64748b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: sections.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section['heading'] ?? '',
                          style: GoogleFonts.outfit(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A0F0A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          section['body'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.5,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0F0A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Close',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showPrivacyPolicy(BuildContext context) {
    show(
      context,
      title: 'Privacy Policy',
      subtitle: 'Customs Brokers Association of Ghana (CUBAG) • Last Updated 2026',
      sections: [
        {
          'heading': '1. Introduction & Commitment',
          'body': 'The Customs Brokers Association of Ghana ("CUBAG", "we", "our") respects your privacy and is committed to protecting your personal data in strict adherence with international data protection standards and the Data Protection Act. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile and web applications.'
        },
        {
          'heading': '2. Information We Collect',
          'body': '• Personal Identification: Full name, email address, phone number, and company name.\n• Professional & Regulatory Credentials: Customs license numbers, membership numbers, and company classification (SME / Large Corporate).\n• Compliance & Supporting Documents: GRA tax clearance certificates, custom brokerage permits, and identity documents.\n• Transactional & Financial Records: Mobile Money numbers, bank transfer receipts, and payment references processed securely via PCI-DSS compliant gateways.'
        },
        {
          'heading': '3. How We Use Your Information',
          'body': 'We use your information strictly to:\n• Process membership registrations and vet compliance applications.\n• Issue official digital membership cards, cryptographic QR verifications, and annual renewal licenses.\n• Facilitate secure dues payments, CTI course enrollments, and professional development programs.\n• Send real-time push notifications regarding document reviews, payment approvals, and port advisories.'
        },
        {
          'heading': '4. Data Security & PCI-DSS Compliance',
          'body': 'We implement robust technical and organizational security measures—including TLS 1.3 encryption, AES-256 data storage, and secure token authentication—to protect your data from unauthorized access, alteration, or disclosure.'
        },
        {
          'heading': '5. Your Rights',
          'body': 'You have the right to request access to, correction of, or deletion of your personal data by contacting the National Secretariat through your member portal.'
        },
        {
          'heading': '6. Contact Secretariat',
          'body': 'Customs Brokers Association of Ghana (CUBAG)\nNational Secretariat • Tema Port & KIA Chapters • Ghana\nEmail: support@cubag.org'
        },
      ],
    );
  }

  static void showTermsOfService(BuildContext context) {
    show(
      context,
      title: 'Terms of Service',
      subtitle: 'Official CUBAG Platform Usage Agreement',
      sections: [
        {
          'heading': '1. Acceptance of Terms',
          'body': 'By downloading, registering, or accessing the CUBAG Mobile Platform, you agree to be bound by these Terms of Service, all applicable association bylaws, and professional code of conduct regulations.'
        },
        {
          'heading': '2. Membership & Licensing Obligations',
          'body': 'Members must maintain valid customs brokerage credentials, comply with Ghana Revenue Authority (GRA) customs procedures, and keep their professional documentation up to date in the Compliance Centre.'
        },
        {
          'heading': '3. Financial Dues & Payments',
          'body': 'Annual renewal dues, registration fees, and entrance packages must be paid in accordance with official CUBAG tariff schedules. All payments submitted via Mobile Money or Bank Transfer receipts are subject to secretariat verification.'
        },
        {
          'heading': '4. Code of Conduct & Platform Integrity',
          'body': 'Users agree not to misrepresent credentials, upload fraudulent documents, attempt unauthorized access to restricted administrative modules, or disrupt real-time communication channels.'
        },
        {
          'heading': '5. Account Suspension & Termination',
          'body': 'Violation of association bylaws, fraudulent submissions, or lapse in statutory compliance may result in suspension of good standing or revocation of membership privileges.'
        },
        {
          'heading': '6. Secretariat Support',
          'body': 'For inquiries or assistance, please contact the CUBAG Secretariat directly through the member engagement portal.'
        },
      ],
    );
  }
}
