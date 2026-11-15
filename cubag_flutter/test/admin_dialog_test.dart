import 'package:cubag_flutter/components/admin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget Function(BuildContext) dialog) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog(context: context, builder: dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Widget _form(BuildContext context, {ValueChanged<bool>? onSwitch}) {
  var on = true;
  return StatefulBuilder(
    builder: (context, set) => AdminDialog(
      title: 'New event',
      subtitle: 'Members see it in the app.',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {}, child: const Text('Publish event')),
      ],
      children: [
        const AdminField(label: 'Title', child: TextField()),
        const AdminFieldPair(
          AdminField(label: 'Date', child: TextField()),
          AdminField(label: 'Time', child: TextField()),
        ),
        AdminChoice<String>(options: const [('a', 'Hybrid'), ('b', 'Online')], value: 'a', onChanged: (_) {}),
        for (var i = 0; i < 12; i++) AdminField(label: 'Field $i', child: const TextField()),
        AdminSwitchRow(
          title: 'Tell all members',
          value: on,
          onChanged: (v) {
            set(() => on = v);
            onSwitch?.call(v);
          },
        ),
        const AdminDetailRow('Email', ''),
      ],
    ),
  );
}

void main() {
  for (final size in const [Size(1024, 768), Size(390, 844)]) {
    testWidgets('long form lays out and closes at ${size.width.toInt()}px', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      await t.pumpWidget(_host(_form));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.text('New event'), findsOneWidget);
      expect(find.text('Publish event'), findsOneWidget);
      // Phones get a full-screen dialog, tablets a centred one.
      expect(find.byWidgetPredicate((w) => w is Dialog && w.child is SafeArea), size.width < 600 ? findsOneWidget : findsNothing);

      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(find.text('New event'), findsNothing);
    });
  }

  testWidgets('switch row toggles and empty detail shows a dash', (t) async {
    bool? last;
    await t.pumpWidget(_host((c) => _form(c, onSwitch: (v) => last = v)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Tell all members'), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byType(Switch));
    await t.pump();
    expect(last, isFalse);
    expect(find.text('—'), findsOneWidget);
  });
}
