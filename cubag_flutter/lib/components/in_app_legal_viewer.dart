import 'package:flutter/material.dart';

import '../design/cubag_design.dart';

/// Privacy policy and terms of service, shown as a full reading page.
///
/// A legal text is read, not glanced at: a full screen with one comfortable
/// column (about 65 characters wide), numbered sections because the
/// documents really are ordered clauses, and the date it last changed.
class InAppLegalViewer {
  static const _updated = 'November 2026';
  static const _supportEmail = 'support@cubag.org.gh';

  static void show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Map<String, String>> sections,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _LegalPage(title: title, subtitle: subtitle, sections: sections),
      ),
    );
  }

  static void showPrivacyPolicy(BuildContext context) {
    show(
      context,
      title: 'Privacy policy',
      subtitle: 'How the Customs Brokers Association of Ghana handles your personal information. '
          'Last updated $_updated.',
      sections: const [
        {
          'heading': 'Who we are',
          'body': 'The Customs Brokers Association of Ghana ("CUBAG", "we") runs this app for its members '
              'and applicants. We handle your personal data in line with the Data Protection Act, 2012 '
              '(Act 843). This policy explains what we collect, why, and the choices you have.',
        },
        {
          'heading': 'What we collect',
          'body': '• Who you are: your name, email address, phone number and company.\n'
              '• Your professional details: licence and membership numbers, company classification '
              'and the district you work in.\n'
              '• Documents you upload: for example tax clearance certificates, brokerage permits and '
              'identity documents.\n'
              '• Payments: the amount, purpose, reference and receipt of each payment, and the Mobile '
              'Money number or bank details you pay from.',
        },
        {
          'heading': 'How we use it',
          'body': 'Only to run your membership:\n'
              '• to review your application and your compliance documents;\n'
              '• to issue your membership card, verification code and licence;\n'
              '• to record and confirm your dues and course payments;\n'
              '• to send you notices about your documents, payments and the association.\n'
              'We do not sell your information.',
        },
        {
          'heading': 'Who can see it',
          'body': 'Authorised staff of the CUBAG Secretariat. Payment providers receive only what they need '
              'to process a payment. Your name, company and membership status may appear in the member '
              'directory and when someone scans your verification code.',
        },
        {
          'heading': 'Keeping it safe',
          'body': 'Your data travels over encrypted connections, and access is limited to Secretariat staff '
              'who need it.',
        },
        {
          'heading': 'Your rights',
          'body': 'You can ask to see the information we hold about you, to correct it, or to delete your '
              'account. Use Settings in the app, or email the Secretariat.',
        },
        {
          'heading': 'Contact',
          'body': 'CUBAG National Secretariat, Ghana\nEmail: $_supportEmail',
        },
      ],
    );
  }

  static void showTermsOfService(BuildContext context) {
    show(
      context,
      title: 'Terms of service',
      subtitle: 'The rules for using the CUBAG app. Last updated $_updated.',
      sections: const [
        {
          'heading': 'Agreeing to these terms',
          'body': 'By creating an account or using the CUBAG app you agree to these terms and to the '
              'bylaws of the association.',
        },
        {
          'heading': 'Your membership and licence',
          'body': 'Keep your customs brokerage credentials valid, follow the customs procedures that apply '
              'to your work, and keep your documents in the app up to date.',
        },
        {
          'heading': 'Dues and payments',
          'body': 'Registration fees, membership dues and annual renewal dues are set by CUBAG. Payments '
              'made by Mobile Money or bank transfer count once the Secretariat has confirmed them.',
        },
        {
          'heading': 'Honest information',
          'body': 'Everything you submit must be true and your own. False documents or payment slips can '
              'lead to suspension.',
        },
        {
          'heading': 'Suspension and termination',
          'body': 'Breaking the bylaws, submitting false information, or letting your compliance lapse may '
              'lead to suspension of good standing or loss of membership.',
        },
        {
          'heading': 'Help',
          'body': 'For questions, use Support in the app or email $_supportEmail.',
        },
      ],
    );
  }
}

class _LegalPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Map<String, String>> sections;
  const _LegalPage({required this.title, required this.subtitle, required this.sections});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: CubagColors.paper,
      appBar: AppBar(
        backgroundColor: CubagColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded, color: CubagColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title, style: CubagType.headline),
      ),
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.md, CubagSpace.lg, CubagSpace.xxxl + bottom),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CubagType.display),
                    const SizedBox(height: CubagSpace.sm),
                    Text(subtitle, style: CubagType.body.copyWith(color: CubagColors.muted)),
                    const SizedBox(height: CubagSpace.lg),
                    const Divider(height: 1, color: CubagColors.line),
                    for (var i = 0; i < sections.length; i++) _section(i + 1, sections[i]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(int n, Map<String, String> s) {
    return Padding(
      padding: const EdgeInsets.only(top: CubagSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text('$n.', style: CubagType.title.copyWith(color: CubagColors.action)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['heading'] ?? '', style: CubagType.title),
                const SizedBox(height: CubagSpace.sm),
                Text(
                  s['body'] ?? '',
                  style: CubagType.body.copyWith(color: CubagColors.inkSoft, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
