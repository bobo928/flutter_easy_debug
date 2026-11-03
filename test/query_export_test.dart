import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:easy_debug/easy_debug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manager = EasyDebugManager();
  setUp(() {
    manager.shutdown();
    manager.updateConfig(const EasyDebugConfig());
  });
  tearDown(manager.shutdown);
  NetworkLog request(
    String path, {
    String method = 'GET',
    int code = 200,
    int duration = 120,
  }) =>
      NetworkLog(
          timestamp: DateTime.utc(2026, 11, 3, 12),
          method: method,
          url: 'https://api.test.local$path',
        )
        ..request = RequestDetails(
          headers: {'Content-Type': 'application/json'},
          body: '{"ok":true}',
          contentType: 'application/json',
        )
        ..response = ResponseDetails(
          statusCode: code,
          headers: {'content-type': 'application/json'},
          body: '{"ok":true}',
          timestamp: DateTime.now(),
        )
        ..isComplete = true
        ..durationMs = duration;

  test(
    'combined network queries filter method, host, status and slow requests',
    () {
      manager.addLog(
        request('/orders', method: 'POST', code: 201, duration: 1200),
      );
      manager.addLog(request('/orders', duration: 10));
      manager.addLog(request('/missing', code: 404, duration: 1500));
      final query = NetworkLogQuery(
        search: 'ORDERS',
        method: 'post',
        host: 'API.TEST.LOCAL',
        statusCode: 201,
        minDurationMs: 1000,
        status: NetworkLogStatus.success,
      );
      expect(manager.queryNetworkLogs(query).length, 1);
      expect(
        manager
            .queryNetworkLogs(
              const NetworkLogQuery(status: NetworkLogStatus.error),
            )
            .single
            .statusCode,
        404,
      );
      expect(
        manager.queryNetworkLogs(
          const NetworkLogQuery(host: 'different.local'),
        ),
        isEmpty,
      );
      expect(
        manager.queryNetworkLogs(const NetworkLogQuery(method: 'DELETE')),
        isEmpty,
      );
    },
  );

  test('pending and cancelled requests have independent filters', () {
    final pending = NetworkLog(
      timestamp: DateTime.now(),
      method: 'GET',
      url: 'https://test.local',
    );
    manager.addLog(pending);
    manager.addLog(
      request('/cancelled')
        ..isCancelled = true
        ..error = ErrorDetails(errorMessage: 'cancelled'),
    );
    expect(
      manager
          .queryNetworkLogs(
            const NetworkLogQuery(status: NetworkLogStatus.pending),
          )
          .single
          .id,
      pending.id,
    );
    expect(
      manager
          .queryNetworkLogs(
            const NetworkLogQuery(status: NetworkLogStatus.cancelled),
          )
          .length,
      1,
    );
    expect(
      manager.queryNetworkLogs(
        const NetworkLogQuery(status: NetworkLogStatus.error),
      ),
      isEmpty,
    );
    expect(
      manager.queryNetworkLogs(const NetworkLogQuery(minDurationMs: 1000)),
      isEmpty,
    );
  });

  test(
    'HAR exports chronological, sanitized previews with required fields',
    () {
      final first = request(
        '/data?tag=a&tag=b&token=query-secret',
        method: 'POST',
      );
      first.request = RequestDetails(
        contentType: 'application/json',
        headers: {'Authorization': 'header-secret'},
        body: {'password': 'body-secret'},
      );
      manager.addLog(first);
      manager.addLog(
        request(
          '/later',
        ).copyWith(timestamp: first.timestamp.add(const Duration(seconds: 1))),
      );
      final text = manager.exportHar();
      final fixture = Platform.environment['EASY_DEBUG_EXPORT_FIXTURE'];
      if (fixture != null) {
        final file = File(fixture);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }
      expect(text, isNot(contains('query-secret')));
      expect(text, isNot(contains('header-secret')));
      expect(text, isNot(contains('body-secret')));
      final har = jsonDecode(text) as Map<String, dynamic>;
      expect(har['log']['version'], '1.2');
      final entries = har['log']['entries'] as List;
      expect(
        entries.first['startedDateTime'],
        first.timestamp.toIso8601String(),
      );
      expect(
        entries.first['request']['queryString']
            .where((dynamic pair) => pair['name'] == 'tag')
            .length,
        2,
      );
      expect(entries.first['request']['headersSize'], -1);
      expect(entries.first['response']['bodySize'], -1);
      expect(
        entries.first['response']['content']['mimeType'],
        'application/json',
      );
      expect(entries.first['timings']['wait'], entries.first['time']);
      for (final entry in entries) {
        for (final key in [
          'startedDateTime',
          'time',
          'request',
          'response',
          'cache',
          'timings',
        ]) {
          expect((entry as Map).containsKey(key), isTrue, reason: key);
        }
      }
    },
  );

  test(
    'exports reapply masking to caller-supplied records and URL credentials',
    () {
      final raw = request('/private').copyWith(
        url: 'https://user:password-secret@test.local/path?token=query-secret',
      );
      raw.request = RequestDetails(
        headers: {'Authorization': 'header-secret'},
        body: {'token': 'body-secret'},
      );
      final har = EasyDebugExport.har([raw]);
      final curl = EasyDebugExport.curl(raw);
      for (final secret in [
        'password-secret',
        'query-secret',
        'header-secret',
        'body-secret',
      ]) {
        expect(har, isNot(contains(secret)));
        expect(curl, isNot(contains(secret)));
      }
    },
  );

  test(
    'HAR preserves pending, cancellation and truncated preview metadata',
    () {
      manager.updateConfig(const EasyDebugConfig(maxBodyBytes: 16));
      manager.addLog(
        request('/long')
          ..response = ResponseDetails(
            body: 'x' * 1000,
            timestamp: DateTime.now(),
            statusCode: 200,
          ),
      );
      final har = jsonDecode(manager.exportHar());
      expect(
        har['log']['entries'].single['_easyDebug']['responseBodyTruncated'],
        isTrue,
      );
      expect(
        har['log']['entries'].single['response']['content']['text'].length,
        lessThanOrEqualTo(16),
      );
      final pending = NetworkLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: 'https://test.local/pending',
      );
      final encoded = jsonDecode(EasyDebugExport.har([pending]));
      expect(encoded['log']['entries'].single['_easyDebug']['pending'], isTrue);
      expect(encoded['log']['entries'].single['response']['status'], 0);
      expect(jsonDecode(EasyDebugExport.har([]))['log']['entries'], isEmpty);
    },
  );

  test(
    'cURL safely preserves literal shell metacharacters without executing them',
    () async {
      final raw = request('/data', method: 'POST');
      final body =
          r"O'Reilly $(printf INJECTED)"
          '\nsecond line';
      raw.request = RequestDetails(
        body: body,
        headers: {'X-Trace': r"value' $(printf INJECTED)"},
      );
      final command = EasyDebugExport.curl(raw);
      // Replace curl with a local function; no network request is sent.
      final result = await Process.run('/bin/sh', [
        '-c',
        r'''curl() { printf '%s\0' "$@"; }
''' +
            command,
      ]);
      expect(result.exitCode, 0);
      final args = (result.stdout as String).split('\u0000');
      expect(args, contains(body));
      expect(args, contains(r"X-Trace: value' $(printf INJECTED)"));
      expect(args, contains('https://api.test.local/data'));
    },
    skip: Platform.isWindows,
  );

  test(
    'cURL omits truncated payloads instead of pretending they are complete',
    () {
      manager.updateConfig(const EasyDebugConfig(maxBodyBytes: 16));
      manager.addLog(
        request('/data', method: 'POST')
          ..request = RequestDetails(body: 'x' * 100),
      );
      final command = EasyDebugExport.curl(
        manager.logsNotifier.value.single,
        config: manager.config,
      );
      expect(command, contains('Body omitted'));
      expect(command, isNot(contains('--data-raw')));
    },
  );

  test('async HAR export has the same content as synchronous export', () async {
    manager.addLog(request('/data'));
    expect(
      jsonDecode(
        await EasyDebugExport.harAsync(
          manager.logsNotifier.value,
          config: manager.config,
        ),
      ),
      jsonDecode(manager.exportHar()),
    );
  });

  test(
    'async export sanitizes native error objects before crossing isolates',
    () async {
      final port = ReceivePort();
      try {
        final raw = request('/native')
          ..error = ErrorDetails(errorMessage: 'offline', errorObject: port);
        final asyncHar = await EasyDebugExport.harAsync([raw]);
        expect(jsonDecode(asyncHar), jsonDecode(EasyDebugExport.har([raw])));
      } finally {
        port.close();
      }
    },
  );

  test('headers use canonical values and redirect credentials are masked', () {
    manager.addLog(
      request('/redirect')
        ..response = ResponseDetails(
          timestamp: DateTime.now(),
          statusCode: 302,
          headers: {
            'content-type': ['application/json'],
            'Location': [
              'https://user:password-secret@next.local/path?token=query-secret',
            ],
          },
        ),
    );
    final har = jsonDecode(manager.exportHar());
    final response = har['log']['entries'].single['response'];
    expect(response['content']['mimeType'], 'application/json');
    expect(response['redirectURL'], isNot(contains('password-secret')));
    expect(response['redirectURL'], isNot(contains('query-secret')));
  });

  test('mutating a stored record cannot bypass masking on update', () {
    final raw = request('/data');
    manager.addLog(raw);
    final stored = manager.getLog(raw.id)!;
    stored.response = ResponseDetails(
      timestamp: DateTime.now(),
      headers: {'Set-Cookie': 'cookie-secret'},
    );
    manager.updateLog(stored);
    expect(
      manager.getLog(raw.id)!.response!.headers['Set-Cookie'],
      '[REDACTED]',
    );
  });

  test('cURL drops stale framing headers and unavailable bodies', () {
    final raw = request('/data', method: 'POST')
      ..request = RequestDetails(
        headers: {'Content-Length': '99999', 'Host': 'old.local'},
        body: '<streamed request body>',
      );
    final command = EasyDebugExport.curl(raw);
    expect(command, isNot(contains('Content-Length')));
    expect(command, isNot(contains('old.local')));
    expect(command, isNot(contains('--data-raw')));
    expect(command, contains('Body omitted'));
  });

  test(
    'general severity and search combine; explicit levels take precedence',
    () {
      EasyDebug.log('an error counter at zero', level: 'INFO');
      EasyDebug.log('offline error');
      EasyDebug.log('retry warning', level: 'WARN');
      expect(
        manager
            .queryGeneralLogs(
              const GeneralLogQuery(severity: GeneralLogSeverity.error),
            )
            .length,
        1,
      );
      expect(
        manager
            .queryGeneralLogs(
              const GeneralLogQuery(
                search: 'RETRY',
                severity: GeneralLogSeverity.warning,
              ),
            )
            .length,
        1,
      );
      final records = jsonDecode(
        manager.exportGeneralJson(
          query: const GeneralLogQuery(severity: GeneralLogSeverity.info),
        ),
      );
      expect(records.single['level'], 'INFO');
      expect(jsonDecode(manager.exportNetworkJson()), isEmpty);
    },
  );

  test(
    'pause retains prior logs, ignores new captures, and allows existing updates',
    () {
      final first = request('/before');
      manager.addLog(first);
      EasyDebug.log('before');
      manager.pauseRecording();
      manager.addLog(request('/during'));
      EasyDebug.log('during');
      manager.updateLog(manager.getLog(first.id)!.copyWith(durationMs: 999));
      expect(manager.logsNotifier.value.length, 1);
      expect(manager.logsNotifier.value.single.durationMs, 999);
      expect(manager.generalLogsNotifier.value.single.message, 'before');
      manager.resumeRecording();
      manager.addLog(request('/after'));
      EasyDebug.log('after');
      expect(manager.logsNotifier.value.length, 2);
      expect(manager.generalLogsNotifier.value.length, 2);
      manager.shutdown();
      expect(manager.isPaused, isFalse);
      expect(manager.isRecording, isFalse);
    },
  );
}
