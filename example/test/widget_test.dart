import 'package:easy_debug/easy_debug.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_debug_example/main.dart';

void main() {
  testWidgets('demo exposes the console and switches its views', (
    tester,
  ) async {
    final manager = EasyDebugManager();
    manager.updateConfig(const EasyDebugConfig());
    await tester.pumpWidget(const MyApp());
    expect(find.text('Easy Debug Demo'), findsOneWidget);
    expect(find.text('GET Success (200)'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Easy Debug'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for requests'), findsOneWidget);
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('A little more context'), findsOneWidget);
    await tester.tap(find.byTooltip('Close console'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Easy Debug'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    manager.shutdown();
    await tester.pump();
  });
}
