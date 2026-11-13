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
      sections = [
        _buildSection(context, 'Core management', [
          _MenuItem('Dashboard', Icons.grid_view_rounded, '/admin/dashboard'),
          _MenuItem('Members', Icons.people_alt_rounded, '/admin/members'),
          _MenuItem(
            'Registration',
            Icons.folder_copy_rounded,
            '/admin/documents',
          ),
          _MenuItem(
            'Document Rules',
            Icons.rule_folder_rounded,
            '/admin/document-rules',
          ),
          _MenuItem(
            'Renewal',
            Icons.verified_user_rounded,
            '/admin/compliance',
          ),
          _MenuItem(
            'Announcements',
            Icons.campaign_rounded,
            '/admin/announcements',
          ),
        ]),
        _buildSection(context, 'Operations & support', [
          _MenuItem(
            'Port Operational News',
            Icons.feed_rounded,
            '/admin/port-news',
          ),
          _MenuItem(
            'Insights',
            Icons.cell_tower_rounded,
            '/admin/intelligence',
          ),
          _MenuItem(
            'Support Tickets',
            Icons.support_agent_rounded,
            '/admin/tickets',
          ),
          _MenuItem(
            'Complaints',
            Icons.gavel_rounded,
            '/admin/complaints',
          ),
          _MenuItem(
            'Messages',
            Icons.chat_rounded,
            '/admin/messages',
          ),
          _MenuItem(
            'Reported Messages',
            Icons.flag_rounded,
            '/admin/message-reports',
          ),
        ]),
        _buildSection(context, 'Financials & records', [
          _MenuItem(
            'Financial Center',
            Icons.account_balance_wallet_rounded,
            '/admin/payments',
          ),
          _MenuItem(
            'Platform Analytics',
            Icons.analytics_rounded,
            '/admin/analytics',
          ),
          _MenuItem(
            'Payment Settings',
            Icons.payment_rounded,
            '/admin/payment-settings',
          ),
          _MenuItem('Platform Fees', Icons.receipt_rounded, '/admin/fees'),
        ]),
        _buildSection(context, 'Engagement & events', [
          _MenuItem('Events & Meetings', Icons.event_rounded, '/admin/events'),
          _MenuItem(
            'CTI Short Courses',
            Icons.school_rounded,
            '/admin/cti-courses',
          ),
          _MenuItem(
            'Photo Gallery',
            Icons.photo_library_rounded,
            '/admin/gallery',
          ),
          _MenuItem(
            'Surveys',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ]),
        _buildSection(context, 'Administration', [
          _MenuItem(
            'Sub-Admins',
            Icons.admin_panel_settings_rounded,
            '/admin/sub-admins',
          ),
          _MenuItem('Ports of Operation', Icons.anchor_rounded, '/admin/ports'),
          _MenuItem('Audit Log', Icons.history_rounded, '/admin/audit-log'),
        ]),
      ];
    } else if (role == 'sub_admin') {
      final allAdminItems = <String, List<_MenuItem>>{
        'members': [
          _MenuItem('Members', Icons.people_alt_rounded, '/admin/members'),
        ],
        'compliance': [
          _MenuItem(
            'Renewal',
            Icons.verified_user_rounded,
            '/admin/compliance',
          ),
        ],
        'documents': [
          _MenuItem(
            'Registration',
            Icons.folder_shared_rounded,
            '/admin/documents',
          ),
          _MenuItem(
            'Document Rules',
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
            'Port Operational News',
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
            'Support Tickets',
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
          _MenuItem('Reported Messages', Icons.flag_rounded, '/admin/message-reports'),
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
            'Financial Center',
            Icons.account_balance_wallet_rounded,
            '/admin/payments',
          ),
        ],
        'analytics': [
          _MenuItem(
            'Platform Analytics',
            Icons.analytics_rounded,
            '/admin/analytics',
          ),
        ],
        'fees': [
          _MenuItem('Platform Fees', Icons.receipt_rounded, '/admin/fees'),
        ],
        'events': [
          _MenuItem('Events & Meetings', Icons.event_rounded, '/admin/events'),
          _MenuItem(
            'CTI Short Courses',
            Icons.school_rounded,
            '/admin/cti-courses',
          ),
          _MenuItem(
            'Photo Gallery',
            Icons.photo_library_rounded,
            '/admin/gallery',
          ),
        ],
        'surveys': [
          _MenuItem(
            'Surveys',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ],
        'audit_log': [
          _MenuItem('Audit Log', Icons.history_rounded, '/admin/audit-log'),
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
          _buildSection(context, 'My modules', permittedItems),
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

class _MenuItem {
  final String title;
  final IconData icon;
  final String route;
  final String? subtitle;
  final bool isLogout;
  _MenuItem(this.title, this.icon, this.route, {this.subtitle, this.isLogout = false});
}
