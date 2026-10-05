import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/lampa/tv_url_keyboard.dart';

void main() {
  testWidgets('remote pad appends a character and backspace removes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TvSubscriptionEntry())),
    );

    await tester.tap(find.byKey(const ValueKey('tv-key-h')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-url-preview'))).data,
      'h',
    );

    await tester.tap(find.byKey(const ValueKey('tv-key-Стереть')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-url-preview'))).data,
      'Вставьте ссылку подписки Хаттабыч',
    );
  });
}
