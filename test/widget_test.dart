// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_samples_module/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('Flutter route stack and counters restore together', (
    tester,
  ) async {
    const channel = MethodChannel('android_samples/bridge/v1/control');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ready') return true;
      expect(call.method, 'openRoute');
      return call.arguments;
    });

    await tester.pumpWidget(const MyApp(initialRoute: 'samples://flutter/tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increment'));
    await tester.tap(find.text('在 Tab 内打开 Flutter 详情'));
    await tester.pumpAndSettle();
    expect(find.text('ID 42：Tab 内详情'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    expect(find.text('ID 42：Tab 内详情'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Flutter 首页'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
