import os

DASHBOARD_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/dashboard_page.dart"

with open(DASHBOARD_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Replace _buildQuickActionsGrid and _quickAction
old_grid_block = """  Widget _buildQuickActionsGrid(bool isMobile) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      padding: EdgeInsets.zero,
      children: [
        _quickAction(
          context,
          Icons.school_rounded,
          'CTI Courses',
          '/courses',
          color: const Color(0xFFFF5000),
          subtext: 'Certifications & ICUMS',
        ),
        _quickAction(
          context,
          Icons.payments_outlined,
          'Pay Dues',
          '/payments',
          color: const Color(0xFF10b981),
          subtext: 'Renew annual membership',
        ),
        _quickAction(
          context,
          Icons.how_to_vote_rounded,
          'Surveys & Polls',
          '/surveys',
          color: const Color(0xFF8b5cf6),
          subtext: 'Vote in elections',
        ),
        _quickAction(
          context,
          Icons.receipt_long_outlined,
          'Statement',
          '/payment-history',
          color: const Color(0xFFef4444),
          subtext: 'View transactions',
        ),
        _quickAction(
          context,
          Icons.bar_chart_rounded,
          'Live Data',
          '/live-data',
          color: const Color(0xFF10b981),
          subtext: 'Platform stats',
        ),
        _quickAction(
          context,
          Icons.support_agent_rounded,
          'Support Hub',
          '/engagement',
          color: const Color(0xFF0284c7),
          subtext: 'Create a ticket',
        ),
        _quickAction(
          context,
          Icons.language_rounded,
          'Networking',
          '/networking',
          color: const Color(0xFF0d9488),
          subtext: 'Member directory',
        ),
      ],
    );
  }"""

new_grid_block = """  Widget _buildQuickActionsGrid(bool isMobile) {
    return Column(
      children: [
        // Row 1: CTI Courses (Featured warm accent) & Pay Dues (Emerald badge)
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _quickAction(
                context,
                Icons.school_rounded,
                'CTI Courses',
                '/courses',
                color: const Color(0xFFFF5000),
                badgeText: 'ACCREDITED',
                subtext: 'Certifications & ICUMS 2.0',
                isFeatured: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: _quickAction(
                context,
                Icons.payments_outlined,
                'Pay Dues',
                '/payments',
                color: const Color(0xFF10b981),
                badgeText: 'ANNUAL',
                subtext: 'Membership renewal dues',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 2: Surveys & Polls & Statement Receipts
        Row(
          children: [
            Expanded(
              child: _quickAction(
                context,
                Icons.how_to_vote_rounded,
                'Surveys & Polls',
                '/surveys',
                color: const Color(0xFF8b5cf6),
                badgeText: 'ELECTIONS',
                subtext: 'Cast your ballot',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickAction(
                context,
                Icons.receipt_long_outlined,
                'Statement',
                '/payment-history',
                color: const Color(0xFFef4444),
                badgeText: 'RECEIPTS',
                subtext: 'Audit transaction log',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 3: Support Hub & Networking Directory
        Row(
          children: [
            Expanded(
              child: _quickAction(
                context,
                Icons.support_agent_rounded,
                'Support Hub',
                '/engagement',
                color: const Color(0xFF0284c7),
                badgeText: '24/7 HELPDESK',
                subtext: 'Submit inquiry ticket',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickAction(
                context,
                Icons.hub_rounded,
                'Networking',
                '/networking',
                color: const Color(0xFF0d9488),
                badgeText: 'DIRECTORY',
                subtext: 'Find broker members',
              ),
            ),
          ],
        ),
      ],
    );
  }"""

if old_grid_block in content:
    content = content.replace(old_grid_block, new_grid_block)
    print("Replaced _buildQuickActionsGrid successfully")
else:
    print("Could not match old_grid_block")

old_quick_action = """  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String label,
    String route, {
    required Color color,
    String? subtext,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF64748b);

    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 25 : 12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withAlpha(isDark ? 60 : 40),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtext != null) ...[
              const SizedBox(height: 2),
              Text(
                subtext,
                style: GoogleFonts.inter(fontSize: 10, color: subTextColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }"""

new_quick_action = """  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String label,
    String route, {
    required Color color,
    String? badgeText,
    String? subtext,
    bool isFeatured = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFf8fafc) : const Color(0xFF1A0F0A);
    final subTextColor = isDark ? const Color(0xFF94a3b8) : const Color(0xFF64748b);
    final cardBg = isDark
        ? Color.lerp(const Color(0xFF181C28), color, 0.12)!
        : Color.lerp(Colors.white, color, 0.05)!;

    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withAlpha(isDark ? 90 : 50),
            width: isFeatured ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(isDark ? 25 : 12),
              blurRadius: isFeatured ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 35 : 22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withAlpha(60)),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withAlpha(isDark ? 35 : 20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withAlpha(70)),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.outfit(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtext != null) ...[
              const SizedBox(height: 2),
              Text(
                subtext,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: subTextColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }"""

if old_quick_action in content:
    content = content.replace(old_quick_action, new_quick_action)
    print("Replaced _quickAction successfully")
else:
    print("Could not match old_quick_action")

with open(DASHBOARD_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated dashboard_page.dart successfully")
