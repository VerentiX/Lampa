import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/remote_button.dart';
import '../lib/screens/lampa/lampa_ui.dart';

void main() {
  testWidgets('opaque card has a visible focus border', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampaInkWell(
            onTap: () {},
            child: const SizedBox(
              width: 200,
              height: 60,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(LampaInkWell),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(box.position, DecorationPosition.foreground);
    expect(
      ((box.decoration as BoxDecoration).border! as Border).top.color,
      const Color(0xffffcc33),
    );
  });
  testWidgets('remote OK, directional navigation and touch activate once', (
    tester,
  ) async {
    var first = 0;
    var second = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RemoteButton(
                autofocus: true,
                onPressed: () => first++,
                child: const SizedBox(
                  width: 200,
                  height: 100,
                  child: Text('VPN'),
                ),
              ),
              RemoteButton(
                onPressed: () => second++,
                child: const SizedBox(
                  width: 200,
                  height: 100,
                  child: Text('Settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(first, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(second, 1);
    await tester.tap(find.text('VPN'));
    expect(first, 2);
  });

  testWidgets('disabled control cannot activate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteButton(autofocus: true, child: Text('Busy')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(tester.takeException(), isNull);
  });

  testWidgets('autofocus is acquired when a busy control becomes enabled', (
    tester,
  ) async {
    final enabled = ValueNotifier(false);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, value, __) => RemoteButton(
            autofocus: true,
            onPressed: value ? () {} : null,
            child: const Text('VPN'),
          ),
        ),
      ),
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('remote-button'),
    );
    enabled.value = true;
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-button');
  });

  testWidgets('subscription overflow menu opens with remote OK', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemotePopupMenuButton<String>(
            label: 'Subscription actions',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) => selected = value,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy link')),
            ],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'copy');
  });
}
