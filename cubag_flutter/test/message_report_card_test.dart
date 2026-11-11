import 'package:cubag_flutter/components/message_report_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _report({String status = 'open', String? message = 'Send me your PIN'}) => {
      'id': 7,
      'reason': 'fraud',
      'status': status,
      'reporter_name': 'Ama Mensah',
      'reported_name': 'Kofi Asante',
      'reported_member_id': 42,
      'message_text': message,
      'details': 'Asked for my MoMo PIN',
      'created_at': '2026-11-11T09:30:00',
    };

Future<List<String>> _pump(WidgetTester t, Map<String, dynamic> r,
    {bool busy = false, VoidCallback? onOpen}) async {
  final calls = <String>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MessageReportCard(
          report: r,
          busy: busy,
          onStatus: calls.add,
          onOpenMember: onOpen ?? () {},
        ),
      ),
    ),
  ));
  return calls;
}

void main() {
  testWidgets('shows reason, people, quoted message and note', (t) async {
    await _pump(t, _report());
    expect(find.text('Fraud or scam'), findsOneWidget);
    expect(find.textContaining('Ama Mensah reported Kofi Asante'), findsOneWidget);
    expect(find.text('“Send me your PIN”'), findsOneWidget);
    expect(find.text("Reporter's note: Asked for my MoMo PIN"), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('open report: resolve and dismiss call back with the status', (t) async {
    final calls = await _pump(t, _report());
    expect(find.text('Reopen'), findsNothing);
    await t.tap(find.text('Mark resolved'));
    await t.tap(find.text('Dismiss'));
    expect(calls, ['resolved', 'dismissed']);
  });

  testWidgets('closed report can only be reopened', (t) async {
    final calls = await _pump(t, _report(status: 'resolved'));
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Mark resolved'), findsNothing);
    await t.tap(find.text('Reopen'));
    expect(calls, ['open']);
  });

  testWidgets('busy hides actions', (t) async {
    await _pump(t, _report(), busy: true);
    expect(find.text('Mark resolved'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('view member button opens the reported member', (t) async {
    var opened = false;
    await _pump(t, _report(), onOpen: () => opened = true);
    await t.tap(find.text('View Kofi Asante'));
    expect(opened, isTrue);
  });

  testWidgets('report without a message or unknown reason still renders', (t) async {
    await _pump(t, {..._report(message: null), 'reason': 'weird', 'reporter_name': null});
    expect(find.text('Other'), findsOneWidget);
    expect(find.textContaining('Unknown member reported'), findsOneWidget);
  });
}
