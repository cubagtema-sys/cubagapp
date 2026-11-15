import 'package:flutter/material.dart';

import '../design/cubag_design.dart';

/// The one layout every admin add/edit/detail pop-up uses: a title with a
/// short explanation and a close button, a scrolling body, and the actions
/// in a footer on the right (primary last). Full screen on phones.
class AdminDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxWidth;

  const AdminDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.actions = const [],
    this.maxWidth = 560,
  });

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(CubagSpace.xl, CubagSpace.lg, CubagSpace.sm, CubagSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CubagType.title),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: CubagSpace.xxs),
                      Text(subtitle!, style: CubagType.small),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: CubagColors.muted),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: CubagColors.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(CubagSpace.xl, CubagSpace.lg, CubagSpace.xl, CubagSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const Divider(height: 1, color: CubagColors.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(CubagSpace.xl, CubagSpace.md, CubagSpace.xl, CubagSpace.md),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: CubagSpace.xs,
              runSpacing: CubagSpace.xs,
              children: actions,
            ),
          ),
        ],
      ],
    );

    if (phone) {
      return Dialog.fullscreen(
        backgroundColor: CubagColors.paper,
        child: SafeArea(child: body),
      );
    }
    return Dialog(
      backgroundColor: CubagColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CubagRadius.hero)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: body,
      ),
    );
  }
}

/// A form field with its label above it and optional help text below.
class AdminField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? help;
  const AdminField({super.key, required this.label, required this.child, this.help});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: CubagType.label),
          const SizedBox(height: CubagSpace.xs),
          child,
          if (help != null) ...[
            const SizedBox(height: CubagSpace.xxs),
            Text(help!, style: CubagType.caption),
          ],
        ],
      ),
    );
  }
}

/// Two fields side by side on wide screens, stacked on phones.
class AdminFieldPair extends StatelessWidget {
  final Widget first;
  final Widget second;
  const AdminFieldPair(this.first, this.second, {super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 440) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, second]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: CubagSpace.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// Single-choice pills (cocoa when selected) used inside forms.
class AdminChoice<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const AdminChoice({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CubagSpace.xs,
      runSpacing: CubagSpace.xs,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.$2),
            selected: o.$1 == value,
            showCheckmark: false,
            labelStyle: CubagType.label.copyWith(color: o.$1 == value ? CubagColors.onCocoa : CubagColors.inkSoft),
            selectedColor: CubagColors.cocoa,
            backgroundColor: CubagColors.paper,
            side: BorderSide(color: o.$1 == value ? CubagColors.cocoa : CubagColors.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            onSelected: (_) => onChanged(o.$1),
          ),
      ],
    );
  }
}

/// A switch with a title and one line of explanation, for yes/no settings.
class AdminSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const AdminSwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CubagSpace.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(CubagSpace.md, CubagSpace.sm, CubagSpace.xs, CubagSpace.sm),
        decoration: BoxDecoration(
          color: CubagColors.sand,
          borderRadius: BorderRadius.circular(CubagRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CubagType.label),
                  if (subtitle != null) Text(subtitle!, style: CubagType.caption),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Label / value row for read-only detail pop-ups.
class AdminDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const AdminDetailRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: CubagType.small)),
          Expanded(child: SelectableText(value.isEmpty ? '—' : value, style: CubagType.body.copyWith(color: CubagColors.ink))),
        ],
      ),
    );
  }
}

/// A yes/no question in the shared admin layout. Returns true when the admin
/// confirms. Use [destructive] for archive/delete/reject so the button is red.
Future<bool> showAdminConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AdminDialog(
      title: title,
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: CubagColors.lapsed) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
      children: [if (message != null && message.isNotEmpty) Text(message, style: CubagType.body)],
    ),
  );
  return ok == true;
}
