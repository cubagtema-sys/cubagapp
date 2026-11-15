import '../components/feedback_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../components/app_layout.dart';
import '../design/cubag_design.dart';

class MobileMenuPage extends StatelessWidget {
  const MobileMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final role = auth.userRole;
    final isAdmin = role == 'admin' || role == 'super_admin';
    final isPending = role == 'member' && auth.membershipStatus.toLowerCase().trim() != 'active';

    // Same logic as AppLayout's _buildNavItems
    List<Widget> sections = [];
    if (isAdmin) {
      // Same groups and names as the admin sidebar.
      sections = [
        _buildSection(context, 'Overview', [
          _MenuItem('Dashboard', Icons.grid_view_rounded, '/admin/dashboard'),
        ]),
        _buildSection(context, 'Members', [
          _MenuItem('Members', Icons.people_alt_outlined, '/admin/members'),
          _MenuItem('Applications', Icons.folder_shared_outlined, '/admin/documents'),
          _MenuItem('Compliance', Icons.verified_user_outlined, '/admin/compliance'),
        ]),
        _buildSection(context, 'Money', [
          _MenuItem('Payments', Icons.payments_outlined, '/admin/payments'),
          _MenuItem('Revenue', Icons.trending_up_rounded, '/admin/analytics'),
          _MenuItem('Fees', Icons.receipt_long_outlined, '/admin/fees'),
          _MenuItem('Bank accounts', Icons.account_balance_outlined, '/admin/payment-settings'),
        ]),
        _buildSection(context, 'Communication', [
          _MenuItem('Announcements', Icons.campaign_outlined, '/admin/announcements'),
          _MenuItem('Messages', Icons.chat_bubble_outline_rounded, '/admin/messages'),
          _MenuItem('Reports', Icons.flag_outlined, '/admin/message-reports'),
          _MenuItem('Tickets', Icons.support_agent_outlined, '/admin/tickets'),
          _MenuItem('Complaints', Icons.gavel_rounded, '/admin/complaints'),
        ]),
        _buildSection(context, 'Events and content', [
          _MenuItem('Events', Icons.event_outlined, '/admin/events'),
          _MenuItem('Courses', Icons.school_outlined, '/admin/cti-courses'),
          _MenuItem('Polls', Icons.how_to_vote_outlined, '/admin/surveys'),
          _MenuItem('Gallery', Icons.photo_library_outlined, '/admin/gallery'),
          _MenuItem('News', Icons.newspaper_outlined, '/admin/port-news'),
          _MenuItem('Insights', Icons.insights_outlined, '/admin/intelligence'),
        ]),
        _buildSection(context, 'Setup', [
          _MenuItem('Requirements', Icons.rule_folder_outlined, '/admin/document-rules'),
          _MenuItem('Ports', Icons.anchor_rounded, '/admin/ports'),
          _MenuItem('Admins', Icons.admin_panel_settings_outlined, '/admin/sub-admins'),
          _MenuItem('Audit', Icons.history_rounded, '/admin/audit-log'),
        ]),
      ];
    } else if (role == 'sub_admin') {
      final allAdminItems = <String, List<_MenuItem>>{
        'members': [
          _MenuItem('Members', Icons.people_alt_rounded, '/admin/members'),
        ],
        'compliance': [
          _MenuItem(
            'Compliance',
            Icons.verified_user_rounded,
            '/admin/compliance',
          ),
        ],
        'documents': [
          _MenuItem(
            'Applications',
            Icons.folder_shared_rounded,
            '/admin/documents',
          ),
          _MenuItem(
            'Requirements',
            Icons.rule_folder_rounded,
            '/admin/document-rules',
          ),
        ],
        'announcements': [
          _MenuItem(
            'Announcements',
            Icons.campaign_rounded,
            '/admin/announcements',
          ),
          _MenuItem(
            'News',
            Icons.feed_rounded,
            '/admin/port-news',
          ),
        ],
        'intelligence': [
          _MenuItem(
            'Insights',
            Icons.cell_tower_rounded,
            '/admin/intelligence',
          ),
        ],
        'tickets': [
          _MenuItem(
            'Tickets',
            Icons.support_agent_rounded,
            '/admin/tickets',
          ),
          _MenuItem(
            'Complaints',
            Icons.gavel_rounded,
            '/admin/complaints',
          ),
        ],
        'messaging': [
          _MenuItem('Messages', Icons.chat_rounded, '/admin/messages'),
          _MenuItem('Reports', Icons.flag_rounded, '/admin/message-reports'),
        ],
        'notifications': [
          _MenuItem(
            'Notifications',
            Icons.notifications_rounded,
            '/admin/notifications',
          ),
        ],
        'payments': [
          _MenuItem(
            'Payments',
            Icons.account_balance_wallet_rounded,
            '/admin/payments',
          ),
        ],
        'analytics': [
          _MenuItem(
            'Revenue',
            Icons.analytics_rounded,
            '/admin/analytics',
          ),
        ],
        'fees': [
          _MenuItem('Fees', Icons.receipt_rounded, '/admin/fees'),
        ],
        'events': [
          _MenuItem('Events', Icons.event_rounded, '/admin/events'),
          _MenuItem(
            'Courses',
            Icons.school_rounded,
            '/admin/cti-courses',
          ),
          _MenuItem(
            'Gallery',
            Icons.photo_library_rounded,
            '/admin/gallery',
          ),
        ],
        'surveys': [
          _MenuItem(
            'Polls',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ],
        'audit_log': [
          _MenuItem('Audit', Icons.history_rounded, '/admin/audit-log'),
        ],
      };

      final permittedItems = <_MenuItem>[];
      final orderedKeys = [
        'members',
        'compliance',
        'documents',
        'announcements',
        'schedules',
        'intelligence',
        'tickets',
        'messaging',
        'notifications',
        'payments',
        'fees',
        'events',
        'surveys',
        'audit_log',
      ];
      for (final key in orderedKeys) {
        if (auth.hasPermission(key)) {
          permittedItems.addAll(allAdminItems[key] ?? []);
        }
      }

      final showDashboard = auth.hasPermission('dashboard');

      sections = [
        if (showDashboard)
          _buildSection(context, 'Overview', [
            _MenuItem('Dashboard', Icons.grid_view_rounded, '/admin/dashboard'),
          ]),
        if (permittedItems.isNotEmpty)
          _buildSection(context, 'Your sections', permittedItems),
      ];
    } else {
      final status = auth.membershipStatus.toLowerCase().trim();
      final isPending = status != 'active' && status != 'approved';

      if (isPending) {
        sections = [
          _buildSection(context, 'Your application', [
            _MenuItem(
              'Complete your application',
              Icons.assignment_turned_in_outlined,
              '/application-documents',
              subtitle: 'Upload your documents',
            ),
            _MenuItem(
              'Pay fees',
              Icons.payments_outlined,
              '/payments',
              subtitle: 'Registration and membership fees',
            ),
          ]),
        ];
      } else {
        // Grouped by what members come to do. Home, Network and Compliance
        // are already in the bottom bar, so they are not repeated here.
        sections = [
          _buildSection(context, 'Dues and licence', [
            _MenuItem('Pay dues', Icons.payments_outlined, '/payments',
                subtitle: 'Renewal dues and other fees'),
            _MenuItem('Licence and certificate', Icons.badge_outlined, '/license-renewal',
                subtitle: 'Your licence, certificate and renewal'),
            _MenuItem('Payment history', Icons.receipt_long_outlined, '/payment-history',
                subtitle: 'Receipts for everything you have paid'),
            _MenuItem('Membership services', Icons.card_membership_outlined, '/membership-services',
                subtitle: 'Letters, records and requests'),
          ]),
          _buildSection(context, 'Learn and meet', [
            _MenuItem('Events', Icons.event_outlined, '/events',
                subtitle: 'Meetings and seminars'),
            _MenuItem('CTI courses', Icons.school_outlined, '/courses',
                subtitle: 'Training and enrolment'),
            _MenuItem('Announcements', Icons.campaign_outlined, '/announcements',
                subtitle: 'News from CUBAG'),
            _MenuItem('Polls', Icons.how_to_vote_outlined, '/surveys',
                subtitle: 'Have your say on CUBAG decisions'),
          ]),
          _buildSection(context, 'Work tools', [
            _MenuItem('Messages', Icons.chat_bubble_outline_rounded, '/messaging'),
            _MenuItem('Tasks', Icons.task_alt_rounded, '/tasks'),
            _MenuItem('Vessel movements', Icons.directions_boat_outlined, '/vessel-movements'),
            _MenuItem('Cargo schedules', Icons.inventory_2_outlined, '/cargo-schedules'),
            _MenuItem('Port insights', Icons.insights_outlined, '/live-data'),
          ]),
          _buildSection(context, 'Help', [
            _MenuItem('Support', Icons.support_agent_outlined, '/engagement',
                subtitle: 'Ask CUBAG or report a problem'),
            _MenuItem('Tell us what is hard', Icons.rate_review_outlined, _feedbackRoute,
                subtitle: 'Something confusing or hard to read in the app'),
          ]),
        ];
      }
    }

    return AppLayout(
      title: 'Menu',
      scrollable: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...sections,
              _buildSection(context, 'Account', [
                if (!isPending)
                  _MenuItem(
                    'Settings',
                    Icons.settings_rounded,
                    (isAdmin || role == 'sub_admin')
                        ? '/admin/settings'
                        : '/settings',
                  ),
                _MenuItem(
                  'Sign out',
                  Icons.logout_rounded,
                  '/login',
                  isLogout: true,
                ),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_MenuItem> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(CubagSpace.xxs, CubagSpace.xl, CubagSpace.xxs, CubagSpace.xs),
          child: Semantics(header: true, child: Text(title, style: CubagType.label.copyWith(color: CubagColors.muted))),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 60, color: CubagColors.line),
                _navTile(context, items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _navTile(BuildContext context, _MenuItem item) {
    final fg = item.isLogout ? CubagColors.lapsed : CubagColors.cocoa;
    return Material(
      color: CubagColors.paper,
      child: InkWell(
        onTap: () async {
          if (item.isLogout) {
            await Provider.of<AuthService>(context, listen: false).logout();
          }
          if (item.route == _feedbackRoute) {
            if (context.mounted) FeedbackSheet.show(context);
            return;
          }
          if (context.mounted) {
            context.go(item.route);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, color: fg, size: 22),
                const SizedBox(width: CubagSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: CubagType.bodyStrong.copyWith(color: item.isLogout ? CubagColors.lapsed : CubagColors.ink),
                      ),
                      if (item.subtitle != null)
                        Text(item.subtitle!, style: CubagType.small),
                    ],
                  ),
                ),
                if (!item.isLogout)
                  const Icon(Icons.chevron_right_rounded, color: CubagColors.lineStrong, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Not a page: opens the feedback sheet.
const _feedbackRoute = '#feedback';

class _MenuItem {
  final String title;
  final IconData icon;
  final String route;
  final String? subtitle;
  final bool isLogout;
  _MenuItem(this.title, this.icon, this.route, {this.subtitle, this.isLogout = false});
}
