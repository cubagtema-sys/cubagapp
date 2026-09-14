import os

SURVEYS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_surveys_page.dart"

with open(SURVEYS_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add _kIndigo at top
if "const _kIndigo = Color(0xFF6366F1);" not in content:
    content = content.replace("const _kAmber = Color(0xFFf59e0b);", "const _kAmber = Color(0xFFf59e0b);\nconst _kIndigo = Color(0xFF6366F1);")

# 2. Add _buildMetricTile and _buildTabPill right before the closing brace of _State
methods = """  Widget _buildMetricTile(
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
}"""

content = content.replace("    focusedBorder: OutlineInputBorder(\n      borderRadius: BorderRadius.circular(12),\n      borderSide: const BorderSide(color: _kOrange, width: 2),\n    ),\n  );\n}", "    focusedBorder: OutlineInputBorder(\n      borderRadius: BorderRadius.circular(12),\n      borderSide: const BorderSide(color: _kOrange, width: 2),\n    ),\n  );\n\n" + methods)

with open(SURVEYS_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Inserted methods successfully")
