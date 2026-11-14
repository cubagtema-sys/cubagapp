import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cubag_design.dart';

/// A row of pill tabs (cocoa when selected) used to filter a list.
/// Values are (key, label) pairs; scrolls sideways when it does not fit.
class FilterTabs extends StatelessWidget {
  final List<(String, String)> tabs;
  final String selected;
  final ValueChanged<String> onSelected;
  const FilterTabs({super.key, required this.tabs, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: CubagSpace.xs),
              child: ChoiceChip(
                label: Text(t.$2),
                selected: selected == t.$1,
                showCheckmark: false,
                labelStyle: CubagType.label.copyWith(
                  color: selected == t.$1 ? CubagColors.onCocoa : CubagColors.inkSoft,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                selectedColor: CubagColors.cocoa,
                backgroundColor: CubagColors.paper,
                side: BorderSide(color: selected == t.$1 ? CubagColors.cocoa : CubagColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  onSelected(t.$1);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Centred empty or no-results message with an optional action.
class EmptyMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyMessage({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CubagSpace.xxl, horizontal: CubagSpace.lg),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: CubagColors.paper, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: CubagColors.cocoa),
          ),
          const SizedBox(height: CubagSpace.md),
          Text(title, style: CubagType.headline, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: CubagSpace.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(message!, style: CubagType.small, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: CubagSpace.lg), action!],
        ],
      ),
    );
  }
}
