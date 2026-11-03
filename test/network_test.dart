import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:easy_debug/easy_debug.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'regression_test.dart' show TestClient;

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.status);
  final int status;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"ok":true}',
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  final manager = EasyDebugManager();
  setUp(() {
    manager.shutdown();
    manager.updateConfig(
      const EasyDebugConfig(maxLogCount: 500, maxBodyBytes: 128),
    );
  });
  tearDown(manager.shutdown);

  for (final status in [200, 404]) {
    test(
      'Dio captures response $status without changing caller behavior',
      () async {
        final dio = Dio()..httpClientAdapter = StubAdapter(status);
        dio.interceptors.add(EasyDebugDioInterceptor());
        if (status == 200) {
          expect(
            (await dio.get<dynamic>('https://test.local/data')).statusCode,
            200,
          );
        } else {
          await expectLater(
            dio.get<dynamic>('https://test.local/data'),
            throwsA(isA<DioException>()),
          );
        }
        final log = manager.logsNotifier.value.single;
        expect(log.statusCode, status);
        expect(log.isError, status == 404);
        expect(log.isPending, isFalse);
        expect(log.durationMs, isNotNull);
        dio.close();
      },
    );
  }

  test(
    'concurrent http responses remain associated with their own requests',
    () async {
      final client = EasyDebugHttpClient(
        TestClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return http.StreamedResponse(
            Stream.value(utf8.encode(request.url.path)),
            200,
          );
        }),
      );
      await Future.wait(
        List.generate(200, (i) => client.get(Uri.https('test.local', '/$i'))),
      );
      final logs = manager.logsNotifier.value;
      expect(logs.length, 200);
      expect(logs.map((log) => log.id).toSet().length, 200);
      for (final log in logs) {
        expect(log.response!.body, Uri.parse(log.url).path);
        expect(log.isPending, isFalse);
      }
      client.close();
    },
  );

  test(
    'large http body reaches caller intact while preview stays bounded',
    () async {
      final body = 'x' * 100000;
      final client = EasyDebugHttpClient(
        TestClient(
          (_) async => http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(body.substring(0, 50000)),
              utf8.encode(body.substring(50000)),
            ]),
            200,
          ),
        ),
      );
      final response = await client.get(Uri.https('test.local', '/large'));
      expect(response.body, body);
      final log = manager.logsNotifier.value.single;
      expect(
        utf8.encode(log.response!.body.toString()).length,
        lessThanOrEqualTo(128),
      );
      expect(log.response!.bodyTruncated, isTrue);
      client.close();
    },
  );

  test('cancellation reaches source and marks log as cancelled', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final client = EasyDebugHttpClient(
      TestClient((_) async => http.StreamedResponse(source.stream, 200)),
    );
    final response = await client.send(
      http.Request('GET', Uri.https('test.local', '/stream')),
    );
    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
    expect(cancelled, isTrue);
    expect(manager.logsNotifier.value.single.isCancelled, isTrue);
    expect(manager.logsNotifier.value.single.isPending, isFalse);
    await source.close();
    client.close();
  });

  test('headers are visible before the response body is consumed', () async {
    final client = EasyDebugHttpClient(
      TestClient((_) async => http.StreamedResponse(const Stream.empty(), 202)),
    );
    final response = await client.send(
      http.Request('GET', Uri.https('test.local', '/delayed')),
    );
    expect(manager.logsNotifier.value.single.statusCode, 202);
    expect(manager.logsNotifier.value.single.isPending, isTrue);
    await response.stream.drain<void>();
    expect(manager.logsNotifier.value.single.isPending, isFalse);
    client.close();
  });

  test('http pause and resume preserve source backpressure', () async {
    var paused = false;
    final source = StreamController<List<int>>(
      onPause: () {
        paused = true;
      },
      onResume: () {
        paused = false;
      },
    );
    final client = EasyDebugHttpClient(
      TestClient((_) async => http.StreamedResponse(source.stream, 200)),
    );
    final response = await client.send(
      http.Request('GET', Uri.https('test.local', '/pause')),
    );
    final subscription = response.stream.listen((_) {});
    subscription.pause();
    expect(paused, isTrue);
    subscription.resume();
    expect(paused, isFalse);
    await subscription.cancel();
    await source.close();
    client.close();
  });

  test(
    'transport errors propagate; late responses cannot restore cleared logs',
    () async {
      final client = EasyDebugHttpClient(
        TestClient((_) async => throw StateError('offline')),
      );
      await expectLater(
        client.get(Uri.https('test.local', '/offline')),
        throwsStateError,
      );
      expect(manager.logsNotifier.value.single.isError, isTrue);
      final source = StreamController<List<int>>();
      final delayed = EasyDebugHttpClient(
        TestClient((_) async => http.StreamedResponse(source.stream, 200)),
      );
      final response = await delayed.send(
        http.Request('GET', Uri.https('test.local', '/cleared')),
      );
      final finished = response.stream.drain<void>();
      manager.clearLogs();
      source.add(utf8.encode('late'));
      await source.close();
      await finished;
      expect(manager.logsNotifier.value, isEmpty);
      client.close();
      delayed.close();
    },
  );

  test('disabled http capture is a transparent pass-through', () async {
    manager.updateConfig(const EasyDebugConfig(enabled: false));
    final client = EasyDebugHttpClient(
      TestClient((_) async => http.StreamedResponse(Stream.value([65]), 200)),
    );
    expect((await client.get(Uri.https('test.local', '/data'))).body, 'A');
    expect(manager.logsNotifier.value, isEmpty);
    client.close();
  });

  test(
    'binary request bytes reach the inner client without decoder failures',
    () async {
      final client = EasyDebugHttpClient(
        TestClient((request) async {
          expect((request as http.Request).bodyBytes, [255, 254, 253]);
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
      );
      final request = http.Request('POST', Uri.https('test.local', '/binary'))
        ..bodyBytes = [255, 254, 253];
      final response = await client.send(request);
      await response.stream.drain<void>();
      expect(manager.logsNotifier.value.single.statusCode, 200);
      client.close();
    },
  );

  test('truncated JSON does not expose a credential in a raw prefix', () async {
    final body = '{"password":"private-credential","padding":"${'x' * 2000}"}';
    final client = EasyDebugHttpClient(
      TestClient(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode(body)), 200),
      ),
    );
    expect(
      (await client.get(Uri.https('test.local', '/large-json'))).body,
      body,
    );
    final log = manager.logsNotifier.value.single;
    expect(
      log.response!.body.toString(),
      isNot(contains('private-credential')),
    );
    expect(log.response!.bodyTruncated, isTrue);
    client.close();
  });
}
