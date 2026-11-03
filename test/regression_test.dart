import 'dart:async';

import 'package:easy_debug/easy_debug.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class TestClient extends http.BaseClient {
  TestClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  final manager = EasyDebugManager();
  final originalDebugPrint = debugPrint;
  setUp(() {
    manager.shutdown();
    debugPrint = originalDebugPrint;
    manager.updateConfig(const EasyDebugConfig());
    manager.clearLogs();
  });
  tearDown(() {
    manager.shutdown();
    debugPrint = originalDebugPrint;
    manager.clearLogs();
  });

  test('general logs stay bounded during sustained output', () {
    for (var i = 0; i < 1000; i++) {
      manager.addGeneralLog('entry $i');
    }
    expect(manager.generalLogsNotifier.value.length, lessThanOrEqualTo(200));
    expect(manager.generalLogsNotifier.value.last.message, 'entry 999');
  });

  test('initializing twice captures debugPrint once', () async {
    await manager.init(environments: []);
    await manager.init(environments: []);
    debugPrint('one message');
    expect(manager.generalLogsNotifier.value.length, 1);
  });

  test('http stream error survives the subsequent done event', () async {
    final source = StreamController<List<int>>();
    final client = EasyDebugHttpClient(
      TestClient((_) async {
        return http.StreamedResponse(source.stream, 200);
      }),
    );
    final response = await client.send(
      http.Request('GET', Uri.https('test.local', '/stream')),
    );
    final finished = Completer<void>();
    response.stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: finished.complete,
    );
    source.add([65]);
    source.addError(StateError('stream failed'));
    await source.close();
    await finished.future;
    expect(manager.logsNotifier.value.single.error, isNotNull);
    expect(manager.logsNotifier.value.single.isError, isTrue);
    client.close();
  });
}
