import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../components/app_layout.dart';

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
        _buildSection(context, 'CORE MANAGEMENT', [
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
        _buildSection(context, 'OPERATIONS & SUPPORT', [
          _MenuItem(
            'Port Operational News',
            Icons.feed_rounded,
            '/admin/port-news',
          ),
          _MenuItem(
            'Intelligence Hub',
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
            'Messaging',
            Icons.chat_rounded,
            '/admin/messages',
          ),
        ]),
        _buildSection(context, 'FINANCIALS & RECORDS', [
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
        _buildSection(context, 'ENGAGEMENT & EVENTS', [
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
            'Surveys & Elections',
            Icons.how_to_vote_rounded,
            '/admin/surveys',
          ),
        ]),
        _buildSection(context, 'ADMINISTRATION', [
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
            'Intelligence Hub',
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
        'messaging': [_MenuItem('Messaging', Icons.chat_rounded, '/admin/messages')],
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
            'Surveys & Elections',
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
          _buildSection(context, 'OVERVIEW', [
            _MenuItem('Dashboard', Icons.grid_view_rounded, '/admin/dashboard'),
          ]),
        if (permittedItems.isNotEmpty)
          _buildSection(context, 'MY MODULES', permittedItems),
      ];
    } else {
      final status = auth.membershipStatus.toLowerCase().trim();
      final isPending = status != 'active' && status != 'approved';

      if (isPending) {
        sections = [
          _buildSection(context, 'APPLICATION ONBOARDING', [
            _MenuItem(
              'Complete Application',
              Icons.assignment_turned_in_rounded,
              '/application-documents',
            ),
            _MenuItem(
              'Payment & Checkout',
              Icons.payment_rounded,
              '/payments',
            ),
          ]),
        ];
      } else {
        sections = [
          _buildSection(context, 'MAIN', [
            _MenuItem('Dashboard', Icons.home_rounded, '/dashboard'),
          ]),
          _buildSection(context, 'SERVICES', [
            _MenuItem(
              'Membership Hub',
              Icons.card_membership_rounded,
              '/membership-services',
            ),
            _MenuItem(
              'Compliance Centre',
              Icons.verified_user_rounded,
              '/compliance',
            ),
            _MenuItem(
              'CTI Courses',
              Icons.school_rounded,
              '/courses',
            ),
            _MenuItem(
              'Payment Records',
              Icons.receipt_long_rounded,
              '/payment-history',
            ),
            _MenuItem('Tasks & Compliance', Icons.task_alt_rounded, '/tasks'),
            _MenuItem(
              'Member Directory',
              Icons.people_alt_rounded,
              '/networking',
            ),
            _MenuItem(
              'Messaging',
              Icons.chat_bubble_outline_rounded,
              '/messaging',
            ),
            _MenuItem('Events', Icons.event_rounded, '/events'),
            _MenuItem(
              'Surveys & Elections',
              Icons.how_to_vote_rounded,
              '/surveys',
            ),
            _MenuItem(
              'Support & Inquiries',
              Icons.support_agent_rounded,
              '/engagement',
            ),
          ]),
          _buildSection(context, 'RESOURCES', [
            _MenuItem('Live Logistics', Icons.analytics_rounded, '/live-data'),
            _MenuItem(
              'Vessel Movements',
              Icons.directions_boat_rounded,
              '/vessel-movements',
            ),
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
              _buildSection(context, 'ACCOUNT', [
                if (!isPending)
                  _MenuItem(
                    'Settings',
                    Icons.settings_rounded,
                    (isAdmin || role == 'sub_admin')
                        ? '/admin/settings'
                        : '/settings',
                  ),
                _MenuItem(
                  'Sign Out',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? const Color(0xFF9ca3af) : const Color(0xFF64748b),
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF4D2D20)
                  : const Color(0xFFcbd5e1).withValues(alpha: 0.5),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Column(
                  children: [
                    _navTile(context, item),
                    if (index != items.length - 1)
                      Divider(
                        height: 1,
                        indent: 64,
                        endIndent: 0,
                        color: isDark
                            ? const Color(0xFF4D2D20)
                            : const Color(0xFFf1f5f9),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _navTile(BuildContext context, _MenuItem item) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Normal vs Logout styling
    final Color iconColor = item.isLogout ? const Color(0xFFef4444) : primary;
    final Color badgeBgColor = item.isLogout
        ? const Color(0xFFef4444).withValues(alpha: 0.1)
        : primary.withValues(alpha: 0.1);
    final Color textColor = item.isLogout
        ? const Color(0xFFef4444)
        : (isDark ? Colors.white : const Color(0xFF281710));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (item.isLogout) {
            await Provider.of<AuthService>(context, listen: false).logout();
          }
          if (context.mounted) {
            context.go(item.route);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(item.icon, color: iconColor, size: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.title,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? const Color(0xFF4b5563)
                    : const Color(0xFFcbd5e1),
                size: 20,
              ),
            ],
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
  final bool isLogout;
  _MenuItem(this.title, this.icon, this.route, {this.isLogout = false});
}
