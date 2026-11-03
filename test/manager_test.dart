import 'dart:convert';
import 'package:easy_debug/easy_debug.dart';
import 'package:easy_debug/src/core/capture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final manager = EasyDebugManager();
  setUp(() {
    manager.shutdown();
    manager.updateConfig(const EasyDebugConfig());
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(manager.shutdown);
  NetworkLog log(String path) => NetworkLog(
    timestamp: DateTime.now(),
    method: 'GET',
    url: 'https://test.local/$path',
  );

  test('evicts oldest logs and never resurrects cleared requests', () {
    manager.updateConfig(const EasyDebugConfig(maxLogCount: 2));
    final first = log('first');
    manager.addLog(first);
    manager.addLog(log('second'));
    manager.addLog(log('third'));
    expect(manager.getLog(first.id), isNull);
    expect(manager.logsNotifier.value.map((e) => e.url), [
      'https://test.local/third',
      'https://test.local/second',
    ]);
    manager.clearLogs();
    manager.updateLog(first.copyWith(isComplete: true));
    expect(manager.logsNotifier.value, isEmpty);
  });

  test('body, headers and query credentials are clipped and redacted', () {
    manager.updateConfig(const EasyDebugConfig(maxBodyBytes: 80));
    final entry = log('data?token=secret')
      ..request = RequestDetails(
        headers: {
          'Authorization': 'Bearer secret',
          'Accept': 'application/json',
        },
        body: {
          'password': 'secret',
          'nested': {'token': 'secret'},
          'data': 'x' * 1000,
        },
      );
    manager.addLog(entry);
    final captured = manager.getLog(entry.id)!;
    expect(captured.request!.headers['Authorization'], '[REDACTED]');
    expect(captured.request!.body.toString(), isNot(contains('secret')));
    expect(captured.url, isNot(contains('secret')));
    expect(
      utf8.encode(captured.request!.body.toString()).length,
      lessThanOrEqualTo(80),
    );
    expect(captured.request!.bodyTruncated, isTrue);
  });

  test('unicode is clipped only at a complete UTF-8 character', () {
    for (var limit = 0; limit < 20; limit++) {
      final value = boundedText('你好🌍hello', limit);
      expect(utf8.encode(value).length, lessThanOrEqualTo(limit));
      expect(value, isNot(contains('\uFFFD')));
    }
  });

  test(
    'structured capture stops visiting large collections at the byte cap',
    () {
      final body = List<Object>.generate(100000, (_) => {'value': 'x' * 100});
      final captured = captureBody(
        body,
        const EasyDebugConfig(maxBodyBytes: 128),
      );
      expect(utf8.encode(captured.text!).length, lessThanOrEqualTo(128));
      expect(captured.truncated, isTrue);
    },
  );

  test('zero capacity and disabled capture retain no records', () {
    manager.updateConfig(
      const EasyDebugConfig(maxLogCount: 0, maxGeneralLogCount: 0),
    );
    manager.addLog(log('ignored'));
    EasyDebug.log('ignored');
    expect(manager.logsNotifier.value, isEmpty);
    expect(manager.generalLogsNotifier.value, isEmpty);
    manager.updateConfig(const EasyDebugConfig());
    manager.addLog(log('captured'));
    manager.updateConfig(const EasyDebugConfig(enabled: false));
    manager.addLog(log('ignored'));
    EasyDebug.log('ignored');
    expect(manager.logsNotifier.value, isEmpty);
    expect(manager.generalLogsNotifier.value, isEmpty);
  });

  test('reducing limits immediately trims retained records and previews', () {
    manager.addLog(
      log('body')
        ..response = ResponseDetails(
          timestamp: DateTime.now(),
          body: 'x' * 1000,
        ),
    );
    for (var i = 0; i < 20; i++) {
      EasyDebug.log('long message $i');
    }
    manager.updateConfig(
      const EasyDebugConfig(
        maxBodyBytes: 10,
        maxGeneralLogCount: 3,
        maxMessageLength: 5,
      ),
    );
    expect(
      manager.logsNotifier.value.single.response!.body.toString().length,
      lessThanOrEqualTo(10),
    );
    expect(manager.generalLogsNotifier.value.length, 3);
    expect(manager.generalLogsNotifier.value.last.message.length, 5);
  });

  test('10,000 log burst has bounded retention and one notification', () async {
    await Future<void>.delayed(Duration.zero);
    var notifications = 0;
    void onChanged() {
      notifications++;
    }

    manager.generalLogsNotifier.addListener(onChanged);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      EasyDebug.log('burst $i');
    }
    watch.stop();
    expect(manager.generalLogsNotifier.value.length, 200);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    manager.generalLogsNotifier.removeListener(onChanged);
    debugPrint(
      '10,000 logs: ${watch.elapsedMilliseconds} ms; retained 200; notifications $notifications',
    );
  });

  test(
    'environment selection persists and unknown saved names fall back',
    () async {
      const prod = AppEnvironment(
        name: 'Production',
        baseUrl: 'https://prod.local',
        isDefault: true,
      );
      const dev = AppEnvironment(
        name: 'Development',
        baseUrl: 'https://dev.local',
      );
      await manager.init(environments: [prod, dev]);
      expect(manager.currentBaseUrl, prod.baseUrl);
      await manager.changeEnvironment(dev);
      await manager.init(environments: [prod, dev]);
      expect(manager.currentBaseUrl, dev.baseUrl);
      await manager.init(environments: [prod]);
      expect(manager.currentBaseUrl, prod.baseUrl);
      await expectLater(manager.changeEnvironment(dev), throwsArgumentError);
    },
  );

  test(
    'shutdown restores debugPrint but does not overwrite a later hook',
    () async {
      final original = debugPrint;
      await manager.init();
      manager.shutdown();
      expect(identical(debugPrint, original), isTrue);
      await manager.init();
      void later(String? message, {int? wrapWidth}) {}
      debugPrint = later;
      manager.shutdown();
      expect(identical(debugPrint, later), isTrue);
      debugPrint = original;
    },
  );
}
