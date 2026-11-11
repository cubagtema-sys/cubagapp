import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Shared Admin Design System Palette (Editorial Stone & Ink) ───────────────
const Color kAdminOrange = Color(0xFFFF5000); // Primary Accent Orange
const Color kAdminBrown = Color(0xFF6B3E26); // Primary Brand Brown
const Color kAdminDarkBrown = Color(0xFF3E2418); // Deep Background / Dark Text
const Color kAdminInk = Color(0xFF1F1612); // Deep Espresso Ink
const Color kAdminPaperLight = Color(0xFFFBF8F3); // Warm Ivory Paper
const Color kAdminPaperDark = Color(0xFF22140E); // Dark Paper Tile
const Color kAdminGroundLight = Color(0xFFF4EFEA); // Stone Ground
const Color kAdminGroundDark = Color(0xFF1A0F0A); // Dark Ground
const Color kAdminBorderLight = Color(0xFFE8DED6); // Warm Stone Border
const Color kAdminBorderDark = Color(0xFF3D261C); // Warm Dark Border
const Color kAdminGreen = Color(0xFF10B981); // Emerald Active / Approved
const Color kAdminBlue = Color(0xFF2563EB); // Information Blue
const Color kAdminPurple = Color(0xFF8B5CF6); // Electoral / Compliance Purple
const Color kAdminAmber = Color(0xFFF59E0B); // Pending / Attention Amber
const Color kAdminRed = Color(0xFFEF4444); // Suspended / Delinquent Red
const Color kAdminBorder = Color(0xFFE8DED6); // Default Subtle Border

/// Standardized top header section across all CUBAG Admin pages
class AdminHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;

  const AdminHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : kAdminInk;
    final subtitleColor = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);
    final hasActions = actions != null && actions!.isNotEmpty;
    final hasLeading = leading != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 700;

          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasLeading) ...[
                    leading!,
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: isSmall ? 22 : 26,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: subtitleColor,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          );

          if (isSmall) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                if (hasActions) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions!,
                  ),
                ],
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: titleBlock),
              if (hasActions) ...[
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions!,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Standardized KPI statistic counter card for Admin dashboards & registries
class AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = kAdminOrange,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kAdminPaperDark : kAdminPaperLight;
    final borderColor = isDark ? kAdminBorderDark : kAdminBorderLight;
    final textColor = isDark ? Colors.white : kAdminInk;
    final subTextColor = isDark ? const Color(0xFF9E8F84) : const Color(0xFF7A6B60);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withAlpha(50), width: 1),
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
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        letterSpacing: -0.4,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subTextColor,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Standardized Search and Filter Toolbar Container
class AdminToolbar extends StatelessWidget {
  final Widget? searchWidget;
  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final List<Widget>? filters;
  final Widget? trailing;

  const AdminToolbar({
    super.key,
    this.searchWidget,
    this.searchController,
    this.searchHint = 'Search records by keyword, name, or ID...',
    this.onSearchChanged,
    this.onSearchClear,
    this.filters,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kAdminPaperDark : kAdminPaperLight;
    final borderColor = isDark ? kAdminBorderDark : kAdminBorderLight;
    final textColor = isDark ? Colors.white : kAdminInk;
    final subTextColor = isDark ? const Color(0xFF9E8F84) : const Color(0xFF7A6B60);
    final fieldBg = isDark ? const Color(0xFF170C08) : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 750;

        final searchField =
            searchWidget ??
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: GoogleFonts.inter(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: subTextColor,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: subTextColor,
                  ),
                  suffixIcon:
                      searchController != null &&
                          searchController!.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          color: subTextColor,
                          onPressed: () {
                            searchController!.clear();
                            if (onSearchClear != null) {
                              onSearchClear!();
                            } else if (onSearchChanged != null) {
                              onSearchChanged!('');
                            }
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
              ),
            );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: isSmall
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    if (filters != null && filters!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: filters!,
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(height: 10),
                      trailing!,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 5, child: searchField),
                    if (filters != null && filters!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: filters!,
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// Standardized Filter Chip Pill for Admin Toolbars
class AdminFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final Color selectedColor;

  const AdminFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.count,
    this.selectedColor = kAdminOrange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = isDark ? const Color(0xFF170C08) : Colors.white;
    final borderColor = isSelected
        ? selectedColor
        : (isDark ? kAdminBorderDark : kAdminBorderLight);
    final textColor = isSelected
        ? Colors.white
        : (isDark ? const Color(0xFFD4C8BE) : kAdminInk);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : unselectedBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: textColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withAlpha(40)
                      : (isDark ? Colors.white12 : Colors.black.withAlpha(12)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standardized Status / Classification Badge
class AdminBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isOutlined;

  const AdminBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withAlpha(isOutlined ? 120 : 60),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standardized Section Card for Admin Pages
class AdminSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminSectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kAdminPaperDark : kAdminPaperLight;
    final borderColor = isDark ? kAdminBorderDark : kAdminBorderLight;
    final titleColor = isDark ? Colors.white : kAdminInk;
    final subtitleColor = isDark ? const Color(0xFF9E8F84) : const Color(0xFF7A6B60);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: borderColor),
          ],
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Standardized Empty State View for Admin Pages
class AdminEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  const AdminEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kAdminPaperDark : kAdminPaperLight;
    final borderColor = isDark ? kAdminBorderDark : kAdminBorderLight;
    final textColor = isDark ? Colors.white : kAdminInk;
    final subTextColor = isDark ? const Color(0xFF9E8F84) : const Color(0xFF7A6B60);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF170C08) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Icon(icon, size: 36, color: subTextColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: textColor,
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: subTextColor,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

