import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Shared Admin Design System Palette ──────────────────────────────────────
const Color kAdminOrange = Color(0xFFFF5000); // Primary CTA Orange
const Color kAdminBrown = Color(0xFF6B3E26); // Primary Brand Brown
const Color kAdminDarkBrown = Color(0xFF3E2418); // Deep Background / Dark Text
const Color kAdminGreen = Color(0xFF10B981); // Success / Active Emerald
const Color kAdminBlue = Color(0xFF2563EB); // Information / Corporate Blue
const Color kAdminPurple = Color(0xFF8B5CF6); // Election / Role Purple
const Color kAdminAmber = Color(0xFFF59E0B); // Pending / Warning Amber
const Color kAdminRed = Color(0xFFEF4444); // Expired / Suspended Red
const Color kAdminBorder = Color(0xFFE2E8F0); // Subtle Slate Border

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
    final hasActions = actions != null && actions!.isNotEmpty;
    final hasLeading = leading != null;

    if (!hasActions && !hasLeading) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 650;
        if (isSmall) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasLeading) leading!,
                if (hasActions) ...actions!,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (hasLeading) leading! else const SizedBox.shrink(),
              if (hasActions)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions!,
                ),
            ],
          ),
        );
      },
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
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF3E2418)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF1A0F0A);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 30 : 6),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(60), width: 1),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF3E2418)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 750;

        final searchField =
            searchWidget ??
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: GoogleFonts.outfit(fontSize: 15, color: textColor),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 15,
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
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            );

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 25 : 5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isSmall
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    if (filters != null && filters!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: filters!,
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(height: 12),
                      trailing!,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 5, child: searchField),
                    if (filters != null && filters!.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: filters!,
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
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
    final unselectedBg = isDark
        ? Colors.white.withAlpha(8)
        : const Color(0xFFF1F5F9);
    final borderColor = isSelected
        ? selectedColor
        : (isDark ? Colors.white12 : const Color(0xFFE2E8F0));
    final textColor = isSelected
        ? Colors.white
        : (isDark ? Colors.white70 : const Color(0xFF64748B));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : unselectedBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.2),
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
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: textColor,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withAlpha(40)
                      : (isDark ? Colors.white12 : Colors.black.withAlpha(15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: textColor,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
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
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
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
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF3E2418)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withAlpha(8)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: subTextColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: textColor,
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
                  fontSize: 15,
                  color: subTextColor,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
