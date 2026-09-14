import os

SURVEYS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_surveys_page.dart"

with open(SURVEYS_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add KPI metrics strip right before the Segmented Tabs in build()
old_build_top = """            AdminHeader(
              title: 'Surveys & Association Elections',
              subtitle:
                  'Launch member polls, governance elections, CTI training surveys, and view encrypted balloting results.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (_tab == 'create') {
                      _onTabChanged('active');
                    } else {
                      _onTabChanged('create');
                    }
                  },
                  icon: Icon(
                    _tab == 'create'
                        ? Icons.list_alt_rounded
                        : Icons.add_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _tab == 'create'
                        ? 'View All Polls'
                        : 'Create Poll / Ballot',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: tabs.map((t) {
                  final isActive = _tab == t['id'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onTabChanged(t['id']!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive ? kAdminOrange : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: kAdminOrange.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t['label']!,
                          style: GoogleFonts.outfit(
                            color: isActive ? Colors.white : subTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),"""

new_build_top = """            AdminHeader(
              title: 'Surveys & Association Elections Hub',
              subtitle:
                  'Launch executive elections, governance referendums, member satisfaction surveys, and inspect encrypted real-time balloting results.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(color: borderColor, width: 1.2),
                    backgroundColor: cardBg,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _fetch(refresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: _kOrange),
                  label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (_tab == 'create') {
                      _onTabChanged('active');
                    } else {
                      _onTabChanged('create');
                    }
                  },
                  icon: Icon(
                    _tab == 'create'
                        ? Icons.ballot_outlined
                        : Icons.add_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _tab == 'create'
                        ? 'View Active Polls'
                        : 'New Poll / Ballot',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── KPI METRICS BANNER ───────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                final activeCount = _totalActive > 0 ? _totalActive : _activeSurveys.length;
                final historyCount = _totalHistory > 0 ? _totalHistory : _historySurveys.length;
                final totalCount = activeCount + historyCount;

                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildMetricTile('Active Ballots', '$activeCount', 'Currently open for voting', Icons.how_to_vote_rounded, _kGreen, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Archived History', '$historyCount', 'Closed surveys & ballots', Icons.history_edu_rounded, _kIndigo, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Total Polls Created', '$totalCount', 'Association-wide total', Icons.bar_chart_rounded, _kOrange, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Encrypted Audit', '100% Secure', 'Anonymized cryptographic hash', Icons.verified_user_rounded, _kPurple, cardBg, borderColor, textColor, subTextColor)),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Active Ballots', '$activeCount', 'Currently open', Icons.how_to_vote_rounded, _kGreen, cardBg, borderColor, textColor, subTextColor)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricTile('Archived History', '$historyCount', 'Closed polls', Icons.history_edu_rounded, _kIndigo, cardBg, borderColor, textColor, subTextColor)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Total Polls', '$totalCount', 'Association-wide', Icons.bar_chart_rounded, _kOrange, cardBg, borderColor, textColor, subTextColor)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricTile('Audit Status', 'Verified', 'Cryptographic', Icons.verified_user_rounded, _kPurple, cardBg, borderColor, textColor, subTextColor)),
                            ],
                          ),
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),

            // ── MODERN SEGMENTED TABS WITH COUNTERS ───────────────────────────
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  _buildTabPill('active', 'Active (${_totalActive > 0 ? _totalActive : _activeSurveys.length})', Icons.play_circle_outline_rounded, _kGreen, textColor, subTextColor),
                  const SizedBox(width: 6),
                  _buildTabPill('history', 'History (${_totalHistory > 0 ? _totalHistory : _historySurveys.length})', Icons.archive_outlined, _kIndigo, textColor, subTextColor),
                  const SizedBox(width: 6),
                  _buildTabPill('create', '+ New Poll', Icons.add_chart_rounded, _kOrange, textColor, subTextColor),
                ],
              ),
            ),"""

if old_build_top in content:
    content = content.replace(old_build_top, new_build_top)
    print("Replaced build top successfully")
else:
    print("Could not find exact old_build_top")

# Add helper methods for metric tile and tab pills if not present
helpers = """  Widget _buildMetricTile(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: textColor.withAlpha(200),
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: subTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(
    String id,
    String label,
    IconData icon,
    Color activeColor,
    Color textColor,
    Color subTextColor,
  ) {
    final isActive = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? Colors.white : subTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? Colors.white : textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
"""

if "_buildMetricTile" not in content:
    # insert before _buildSurveyList
    content = content.replace("  // ── Survey Card List ─────────────────────────────────────────", helpers + "\n  // ── Survey Card List ─────────────────────────────────────────")

with open(SURVEYS_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated admin_surveys_page.dart successfully")
