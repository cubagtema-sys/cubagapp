import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cubag_design.dart';

/// Building blocks for admin list pages, matching the hand-redesigned
/// Members and Applications pages: a clickable figure strip, a plain search
/// field, and one grouped container of rows.

/// One figure in an [AdminFigureStrip].
class AdminFigure {
  final String label;
  final String value;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  const AdminFigure(this.label, this.value, {this.color, this.selected = false, this.onTap});
}

/// A row of figures in one bordered strip. Figures with [AdminFigure.onTap]
/// act as filters; the selected one is shaded. Wraps to two rows on phones.
class AdminFigureStrip extends StatelessWidget {
  final List<AdminFigure> figures;
  const AdminFigureStrip({super.key, required this.figures});

  Widget _cell(AdminFigure f) {
    final body = Container(
      padding: const EdgeInsets.all(CubagSpace.md),
      color: f.selected ? CubagColors.sand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(f.label, style: CubagType.small, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              f.value,
              style: CubagType.title.copyWith(
                color: f.color ?? CubagColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (f.onTap == null) return body;
    return Semantics(
      button: true,
      selected: f.selected,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          f.onTap!();
        },
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth < 520 && figures.length > 2 ? 2 : figures.length;
        final rows = <List<AdminFigure>>[];
        for (var i = 0; i < figures.length; i += perRow) {
          rows.add(figures.sublist(i, (i + perRow).clamp(0, figures.length)));
        }
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CubagColors.paper,
            borderRadius: BorderRadius.circular(CubagRadius.card),
            border: Border.all(color: CubagColors.line),
          ),
          child: Column(
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const Divider(height: 1, color: CubagColors.line),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < perRow; i++) ...[
                        if (i > 0) const VerticalDivider(width: 1, color: CubagColors.line),
                        Expanded(child: i < rows[r].length ? _cell(rows[r][i]) : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Plain search field used above admin lists.
class AdminSearchField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  const AdminSearchField({super.key, required this.hint, this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CubagRadius.control),
      borderSide: const BorderSide(color: CubagColors.line),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: CubagColors.muted),
        isDense: true,
        filled: true,
        fillColor: CubagColors.paper,
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

/// One bordered, white container holding rows separated by hairlines.
class AdminRowGroup extends StatelessWidget {
  final List<Widget> children;
  final double dividerIndent;
  const AdminRowGroup({super.key, required this.children, this.dividerIndent = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: dividerIndent, color: CubagColors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Round leading mark for an [AdminListRow]: an icon or initials on sand.
class AdminRowMark extends StatelessWidget {
  final IconData? icon;
  final String? initials;
  final Color color;
  final Color background;
  const AdminRowMark({
    super.key,
    this.icon,
    this.initials,
    this.color = CubagColors.cocoa,
    this.background = CubagColors.sand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, size: 20, color: color)
          : Text(initials ?? '', style: CubagType.label.copyWith(color: color)),
    );
  }
}

/// Initials for a person's or company's name ("Kwame Owusu" -> "KO").
String adminInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final s = parts.map((w) => w[0].toUpperCase()).join();
  return s.isEmpty ? '?' : s;
}

/// A list row: mark, title, one line of detail, a meta line, status on the
/// right, and a chevron when it opens something.
class AdminListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? status;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? background;
  final int subtitleLines;

  const AdminListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.status,
    this.trailing,
    this.onTap,
    this.background,
    this.subtitleLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? CubagColors.paper,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(CubagSpace.md, 12, CubagSpace.sm, 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: CubagSpace.sm)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CubagType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: CubagType.small.copyWith(color: CubagColors.inkSoft),
                        maxLines: subtitleLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta!,
                        style: CubagType.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null) ...[const SizedBox(width: CubagSpace.sm), status!],
              if (trailing != null)
                trailing!
              else if (onTap != null) ...[
                const SizedBox(width: CubagSpace.xxs),
                const Icon(Icons.chevron_right_rounded, color: CubagColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small section heading above a group on admin pages.
class AdminGroupLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AdminGroupLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.xs, top: CubagSpace.xs),
      child: Row(
        children: [
          Expanded(child: Text(text, style: CubagType.headline)),
          ?trailing,
        ],
      ),
    );
  }
}
