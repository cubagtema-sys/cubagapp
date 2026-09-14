import os

CTI_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/cti_courses_page.dart"

with open(CTI_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update _buildMiniBadge definition to accept isDark
old_mini_badge = """  Widget _buildMiniBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }"""

new_mini_badge = """  Widget _buildMiniBadge(IconData icon, String text, Color color, {bool isDark = false}) {
    final effectiveColor = isDark ? Colors.white : color;
    final effectiveBg = isDark ? Colors.white.withAlpha(20) : color.withAlpha(18);
    final effectiveBorder = isDark ? Colors.white.withAlpha(45) : color.withAlpha(45);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: effectiveBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: effectiveColor),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w700, color: effectiveColor)),
        ],
      ),
    );
  }"""

content = content.replace(old_mini_badge, new_mini_badge)

# 2. Update usages of _buildMiniBadge in the file to pass isDark: isDark
# In _openEnrollmentSheet:
content = content.replace(
    "_buildMiniBadge(Icons.calendar_today_rounded, startDate, _kBlue),",
    "_buildMiniBadge(Icons.calendar_today_rounded, startDate, isDark ? Colors.white : _kBlue, isDark: isDark),"
)
content = content.replace(
    "_buildMiniBadge(Icons.timelapse_rounded, duration, _kIndigo),",
    "_buildMiniBadge(Icons.timelapse_rounded, duration, isDark ? Colors.white : _kIndigo, isDark: isDark),"
)
content = content.replace(
    "_buildMiniBadge(Icons.location_on_outlined, mode, _kPurple),",
    "_buildMiniBadge(Icons.location_on_outlined, mode, isDark ? Colors.white : _kPurple, isDark: isDark),"
)

# In _buildHeroStat:
content = content.replace(
    "_buildHeroStat('FCM Alerts', Icons.notifications_active_rounded, _kBlue),",
    "_buildHeroStat('FCM Alerts', Icons.notifications_active_rounded, Colors.white),"
)

with open(CTI_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated cti_courses_page.dart dark mode colors to crisp white")
