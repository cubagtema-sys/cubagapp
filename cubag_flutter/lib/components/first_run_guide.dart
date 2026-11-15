import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/cubag_design.dart';

/// Three short screens a member sees once, the first time they reach Home:
/// where their licence is, how to pay, and where to get help.
class FirstRunGuide extends StatefulWidget {
  final VoidCallback onDone;
  const FirstRunGuide({super.key, required this.onDone});

  static const _seenKey = 'cubag_first_run_guide_v1';

  /// Shows the guide once per device. Does nothing in design previews.
  static Future<void> showIfNew(BuildContext context) async {
    if (const String.fromEnvironment('DESIGN_START_ROUTE').isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) == true) return;
    if (!context.mounted) return;
    await prefs.setBool(_seenKey, true);
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => FirstRunGuide(onDone: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  static const pages = [
    (
      Icons.badge_outlined,
      'Your licence is on Home',
      'The brown card shows your licence number, when it ends, and what to do next. '
          'When renewal is due, the card tells you.',
    ),
    (
      Icons.payments_outlined,
      'Pay your dues in the app',
      'Tap Pay dues and pay with Mobile Money. Your receipt is saved under Receipts, '
          'and your licence updates once CUBAG approves it.',
    ),
    (
      Icons.support_agent_outlined,
      'Help is one tap away',
      'Use Support to ask CUBAG a question. If something is hard to read, make the '
          'text bigger in your phone settings; the app grows with it.',
    ),
  ];

  @override
  State<FirstRunGuide> createState() => _FirstRunGuideState();
}

class _FirstRunGuideState extends State<FirstRunGuide> {
  final _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == FirstRunGuide.pages.length - 1;
    return Scaffold(
      backgroundColor: CubagColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final p in FirstRunGuide.pages)
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: CubagSpace.xl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          children: [
                            const SizedBox(height: CubagSpace.xxl),
                            Container(
                              width: 112,
                              height: 112,
                              decoration: const BoxDecoration(color: CubagColors.actionTint, shape: BoxShape.circle),
                              child: Icon(p.$1, size: 56, color: CubagColors.action),
                            ),
                            const SizedBox(height: CubagSpace.xl),
                            Text(p.$2, style: CubagType.display.copyWith(fontSize: 30), textAlign: TextAlign.center),
                            const SizedBox(height: CubagSpace.md),
                            Text(
                              p.$3,
                              style: CubagType.body.copyWith(fontSize: 18, height: 1.5, color: CubagColors.inkSoft),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Semantics(
              label: 'Page ${_page + 1} of ${FirstRunGuide.pages.length}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < FirstRunGuide.pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? CubagColors.cocoa : CubagColors.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(CubagSpace.xl),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: last
                      ? widget.onDone
                      : () => _pager.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
                  child: Text(last ? 'Start using CUBAG' : 'Next', style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
