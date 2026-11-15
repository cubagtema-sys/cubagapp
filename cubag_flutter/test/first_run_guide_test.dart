import 'package:cubag_flutter/components/first_run_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('guide pages through to the end and finishes', (t) async {
    var done = 0;
    await t.pumpWidget(MaterialApp(home: FirstRunGuide(onDone: () => done++)));
    expect(find.text('Your licence is on Home'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Pay your dues in the app'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start using CUBAG'));
    expect(done, 1);
  });

  testWidgets('shows once per device', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(onPressed: () => FirstRunGuide.showIfNew(c), child: const Text('home')),
      ),
    ));
    await t.tap(find.text('home'));
    await t.pumpAndSettle();
    expect(find.text('Your licence is on Home'), findsOneWidget);
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    await t.tap(find.text('home'));
    await t.pumpAndSettle();
    expect(find.text('Your licence is on Home'), findsNothing);
  });
}
