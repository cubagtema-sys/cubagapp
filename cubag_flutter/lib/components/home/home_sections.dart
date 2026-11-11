import 'package:flutter/material.dart';

import '../../design/cubag_design.dart';

/// Section heading on Home: sentence case, with an optional link on the right.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? linkLabel;
  final VoidCallback? onLink;
  const HomeSectionHeader(this.title, {super.key, this.linkLabel, this.onLink});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.xs),
      child: Row(
        children: [
          Expanded(child: Text(title, style: CubagType.headline)),
          if (linkLabel != null)
            TextButton(onPressed: onLink, child: Text(linkLabel!)),
        ],
      ),
    );
  }
}

/// White grouped list with hairline separators (rows, not separate cards).
class HomeGroup extends StatelessWidget {
  final List<Widget> children;
  const HomeGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: CubagSpace.md),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One to-do item: what to do, when it is due, and where it leads.
class TaskRow extends StatelessWidget {
  final String title;
  final String? due;
  final bool overdue;
  final VoidCallback onTap;
  const TaskRow({
    super.key,
    required this.title,
    required this.onTap,
    this.due,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: overdue ? CubagColors.lapsed : CubagColors.seal,
              ),
            ),
            const SizedBox(width: CubagSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CubagType.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (due != null)
                    Text(
                      due!,
                      style: CubagType.small.copyWith(
                        color: overdue ? CubagColors.lapsed : CubagColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CubagColors.muted),
          ],
        ),
      ),
    );
  }
}

/// A calm single line used when a section has nothing to show.
class QuietRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const QuietRow({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: CubagColors.valid, size: 20),
          const SizedBox(width: CubagSpace.sm),
          Expanded(child: Text(text, style: CubagType.body)),
        ],
      ),
    );
  }
}

class Shortcut {
  final IconData icon;
  final String label;
  final String route;
  const Shortcut(this.icon, this.label, this.route);
}

/// Services as a plain icon row (three per line), not a grid of boxed cards.
class ShortcutGrid extends StatelessWidget {
  final List<Shortcut> items;
  final ValueChanged<String> onOpen;
  const ShortcutGrid({super.key, required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 520 ? 6 : 3;
        final w = c.maxWidth / perRow;
        return Wrap(
          children: [
            for (final s in items)
              SizedBox(
                width: w,
                child: Semantics(
                  button: true,
                  label: s.label,
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CubagRadius.card),
                    onTap: () => onOpen(s.route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: CubagColors.actionTint,
                              borderRadius: BorderRadius.circular(CubagRadius.card),
                            ),
                            child: Icon(s.icon, color: CubagColors.action, size: 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.label,
                            style: CubagType.caption.copyWith(color: CubagColors.ink),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One exchange rate: currency, then the cedi value in even figures.
class RateRow extends StatelessWidget {
  final String code;
  final String name;
  final String value;
  const RateRow({super.key, required this.code, required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CubagSpace.md, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(code, style: CubagType.label)),
          Expanded(child: Text(name, style: CubagType.small)),
          Text(value == '—' ? '—' : 'GH₵ $value', style: CubagType.figure),
        ],
      ),
    );
  }
}
