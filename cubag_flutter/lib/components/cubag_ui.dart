import 'package:flutter/material.dart';

import '../design/cubag_design.dart';

/// Shared building blocks for redesigned member screens.

/// Screen title (serif) with an optional one-line explanation.
class PageIntro extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageIntro(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: CubagType.display),
        if (subtitle != null) ...[
          const SizedBox(height: CubagSpace.xs),
          Text(subtitle!, style: CubagType.body),
        ],
      ],
    );
  }
}

enum StatusKind { neutral, pending, good, bad }

/// Small status label. Colour carries meaning, the word carries it too.
class StatusChip extends StatelessWidget {
  final String label;
  final StatusKind kind;
  const StatusChip(this.label, {super.key, this.kind = StatusKind.neutral});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (kind) {
      StatusKind.good => (CubagColors.valid, CubagColors.validTint),
      StatusKind.bad => (CubagColors.lapsed, CubagColors.lapsedTint),
      StatusKind.pending => (CubagColors.due, CubagColors.dueTint),
      StatusKind.neutral => (CubagColors.muted, CubagColors.sand),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: CubagType.caption.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

/// Centred, width-limited scrolling page body with standard gutters and
/// pull-to-refresh. Wider limit on tablets.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.onRefresh, this.maxWidth = 720});

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        CubagSpace.lg,
        CubagSpace.lg,
        CubagSpace.lg,
        CubagSpace.xxxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, color: CubagColors.action, child: list);
  }
}

enum ChecklistState { done, current, upcoming }

class ChecklistStep {
  final String title;
  final String? detail;
  final ChecklistState state;

  /// Shown only on the current step.
  final Widget? action;
  const ChecklistStep(this.title, {this.detail, required this.state, this.action});
}

/// A real sequence (so numbered): each step done, current or still to come.
class StepChecklist extends StatelessWidget {
  final List<ChecklistStep> steps;
  const StepChecklist({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      padding: const EdgeInsets.symmetric(vertical: CubagSpace.xs),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) _row(i, steps[i], i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _row(int i, ChecklistStep s, bool last) {
    final (circleBg, circleFg) = switch (s.state) {
      ChecklistState.done => (CubagColors.valid, Colors.white),
      ChecklistState.current => (CubagColors.action, Colors.white),
      ChecklistState.upcoming => (CubagColors.sand, CubagColors.muted),
    };
    return Semantics(
      label: '${s.title}. ${switch (s.state) {
        ChecklistState.done => 'Done',
        ChecklistState.current => 'Current step',
        ChecklistState.upcoming => 'Not started',
      }}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 56,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
                    child: s.state == ChecklistState.done
                        ? Icon(Icons.check_rounded, size: 18, color: circleFg)
                        : Text('${i + 1}', style: CubagType.label.copyWith(color: circleFg)),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: s.state == ChecklistState.done ? CubagColors.valid : CubagColors.line,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, CubagSpace.md, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      style: CubagType.bodyStrong.copyWith(
                        color: s.state == ChecklistState.upcoming ? CubagColors.muted : CubagColors.ink,
                      ),
                    ),
                    if (s.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(s.detail!, style: CubagType.small),
                    ],
                    if (s.state == ChecklistState.current && s.action != null) ...[
                      const SizedBox(height: CubagSpace.sm),
                      s.action!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
