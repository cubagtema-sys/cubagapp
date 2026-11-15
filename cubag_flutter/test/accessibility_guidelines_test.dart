import 'package:cubag_flutter/components/feedback_sheet.dart';
import 'package:cubag_flutter/components/first_run_guide.dart';
import 'package:cubag_flutter/components/home/home_sections.dart';
import 'package:flutter/material.dart';
import 'package:cubag_flutter/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Platform accessibility rules for the screens older members use most:
/// tap targets at least 48x48 (Android) / 44x44 (iOS), every button has a
/// spoken label, and text meets contrast guidelines.
Future<void> expectAccessible(WidgetTester t, Widget child) async {
  final handle = t.ensureSemantics();
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: SingleChildScrollView(child: child))));
  await t.pumpAndSettle();
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

void main() {
  testWidgets('Home services', (t) async {
    await expectAccessible(
      t,
      ShortcutGrid(
        items: const [
          Shortcut(Icons.payments_outlined, 'Pay dues', '/payments'),
          Shortcut(Icons.receipt_long_outlined, 'Receipts', '/payment-history'),
          Shortcut(Icons.school_outlined, 'Courses', '/courses'),
          Shortcut(Icons.groups_outlined, 'Member network', '/networking'),
        ],
        onOpen: (_) {},
      ),
    );
  });

  testWidgets('Feedback sheet', (t) async {
    await expectAccessible(t, FeedbackSheet(send: (_, _) async => true));
  });

  testWidgets('First-run guide', (t) async {
    final handle = t.ensureSemantics();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: FirstRunGuide(onDone: () {})));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
