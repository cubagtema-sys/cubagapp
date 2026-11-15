import 'package:cubag_flutter/components/feedback_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<(String, String)>> pump(WidgetTester t, {bool ok = true}) async {
    final sent = <(String, String)>[];
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeedbackSheet(send: (s, m) async {
          sent.add((s, m));
          return ok;
        }),
      ),
    ));
    return sent;
  }

  testWidgets('empty note asks for words and sends nothing', (t) async {
    final sent = await pump(t);
    await t.tap(find.text('Send to CUBAG'));
    await t.pump();
    expect(find.textContaining('Write a few words'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('quick reason and area go to the Secretariat as a ticket', (t) async {
    final sent = await pump(t);
    await t.tap(find.text('Documents'));
    await t.tap(find.text('The text is too small'));
    await t.pump();
    await t.tap(find.text('Send to CUBAG'));
    await t.pumpAndSettle();
    expect(sent, [('App feedback: Documents', 'The text is too small.')]);
    expect(find.text('Thank you'), findsOneWidget);
  });

  testWidgets('failed send keeps the note and says so', (t) async {
    await pump(t, ok: false);
    await t.enterText(find.byType(TextField), 'Cannot find receipts');
    await t.tap(find.text('Send to CUBAG'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not send'), findsOneWidget);
    expect(find.text('Cannot find receipts'), findsOneWidget);
  });
}
