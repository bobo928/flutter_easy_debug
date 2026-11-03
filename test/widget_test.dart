import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_debug/easy_debug.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = EasyDebugManager();
  final captureDir = Platform.environment['EASY_DEBUG_CAPTURE_DIR'];
  setUpAll(() async {
    final sdk = Platform.environment['EASY_DEBUG_FLUTTER_ROOT'];
    if (captureDir != null && sdk != null) {
      final font = FontLoader('Roboto');
      font.addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      font.addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await font.load();
      final mono = FontLoader('monospace');
      mono.addFont(
        File(
          Platform.environment['EASY_DEBUG_MONOSPACE_FONT'] ??
              '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await mono.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await icons.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager.shutdown();
    manager.updateConfig(const EasyDebugConfig());
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(manager.shutdown);

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureDir == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('easy_debug_panel')),
    );
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(captureDir).create(recursive: true);
      await File(
        '$captureDir/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> showApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        builder: (_, child) => EasyDebugWidget(child: child!),
        home: const Scaffold(body: Center(child: Text('Host application'))),
      ),
    );
    await tester.tap(find.byTooltip('Open Easy Debug'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      manager.clearLogs();
      await tester.pump();
    });
  }

  NetworkLog sample(String path, {int? code = 200}) =>
      NetworkLog(
          timestamp: DateTime(2026, 11, 3, 14, 32, 8),
          method: 'GET',
          url: 'https://api.example.com$path',
        )
        ..request = RequestDetails(headers: {'Accept': 'application/json'})
        ..response = code == null
            ? null
            : ResponseDetails(
                statusCode: code,
                timestamp: DateTime.now(),
                body: {'status': 'ready'},
              )
        ..durationMs = code == null ? null : 124
        ..isComplete = code != null;

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1100, 800),
  ]) {
    testWidgets('console opens, searches and filters at $size', (tester) async {
      manager.addLog(sample('/v1/orders/42'));
      manager.addLog(sample('/v1/orders/missing', code: 404));
      manager.addLog(sample('/v1/events', code: null));
      await showApp(tester, size: size);
      expect(find.text('Easy Debug'), findsOneWidget);
      if (size.width == 390) await capture(tester, 'network_light');
      await tester.tap(find.text('Error'));
      await tester.pumpAndSettle();
      expect(find.text('/v1/orders/missing'), findsOneWidget);
      expect(find.text('/v1/orders/42'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.enterText(find.byType(TextField), 'events');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('/v1/events'), findsOneWidget);
      expect(find.text('/v1/orders/missing'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'details update after opening and retain error when response exists',
    (tester) async {
      final pending = sample('/v1/orders/42', code: null);
      manager.addLog(pending);
      await showApp(tester);
      await tester.tap(find.text('/v1/orders/42'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for response…'), findsOneWidget);
      manager.updateLog(
        manager
            .getLog(pending.id)!
            .copyWith(
              response: ResponseDetails(
                statusCode: 500,
                body: '{"message":"service unavailable"}',
                timestamp: DateTime.now(),
              ),
              error: ErrorDetails(errorMessage: 'Connection interrupted'),
              isComplete: true,
              durationMs: 846,
            ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Waiting for response…'), findsNothing);
      expect(find.textContaining('Connection interrupted'), findsOneWidget);
      expect(find.textContaining('service unavailable'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Request details')).dy, lessThan(80));
      await capture(tester, 'request_details');
      await tester.tap(find.byTooltip('Back to requests'));
      await tester.pumpAndSettle();
      expect(find.text('Easy Debug'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dark mode logs, settings, clear and close work', (tester) async {
    await manager.init(
      environments: const [
        AppEnvironment(
          name: 'Production',
          baseUrl: 'https://api.example.com',
          isDefault: true,
        ),
        AppEnvironment(name: 'Development', baseUrl: 'https://dev.example.com'),
      ],
    );
    EasyDebug.log('Session started. Ready to inspect requests.', level: 'INFO');
    EasyDebug.log('Network retry scheduled in 2 seconds.', level: 'WARN');
    EasyDebug.log('Could not load the product catalogue.', level: 'ERROR');
    await showApp(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Session started'), findsOneWidget);
    await capture(tester, 'logs_dark');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsWidgets);
    await capture(tester, 'settings_dark');
    await tester.tap(find.byTooltip('Clear logs'));
    await tester.pumpAndSettle();
    expect(manager.generalLogsNotifier.value, isEmpty);
    await tester.tap(find.byTooltip('Close console'));
    await tester.pumpAndSettle();
    expect(find.text('Host application'), findsOneWidget);
    manager.shutdown();
    await tester.pump();
  });

  testWidgets('disabled config hides overlay and stops collection', (
    tester,
  ) async {
    await showApp(tester);
    await capture(tester, 'empty_state');
    manager.updateConfig(const EasyDebugConfig(enabled: false));
    await tester.pumpAndSettle();
    expect(find.text('Easy Debug'), findsNothing);
    expect(find.byTooltip('Open Easy Debug'), findsNothing);
    expect(find.text('Host application'), findsOneWidget);
  });

  testWidgets(
    'console handles keyboard insets and enlarged text on a narrow screen',
    (tester) async {
      await showApp(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tooltips and long press have an overlay in MaterialApp builder',
    (tester) async {
      await showApp(tester);
      await tester.longPress(find.byTooltip('Clear logs'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating button remains reachable after dragging beyond screen',
    (tester) async {
      await showApp(tester);
      await tester.tap(find.byTooltip('Close console'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byTooltip('Open Easy Debug'),
        const Offset(3000, 3000),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byTooltip('Open Easy Debug'));
      expect(rect.right, lessThanOrEqualTo(390));
      expect(rect.bottom, lessThanOrEqualTo(844));
      await tester.tap(find.byTooltip('Open Easy Debug'));
      await tester.pumpAndSettle();
      expect(find.text('Easy Debug'), findsOneWidget);
    },
  );
}
