import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'capture.dart';
import 'log_model.dart';

/// Exports sanitized, bounded previews. It never sends network requests.
class EasyDebugExport {
  static const _encoder = JsonEncoder.withIndent('  ');

  static Future<String> harAsync(
    Iterable<NetworkLog> logs, {
    EasyDebugConfig config = const EasyDebugConfig(),
  }) => compute(
    _encodeHar,
    logs.map((log) => captureNetworkLog(log, config)).toList(),
    debugLabel: 'EasyDebug HAR export',
  );

  static Future<String> generalJsonAsync(Iterable<GeneralLog> logs) => compute(
    _encodeGeneral,
    logs.toList(),
    debugLabel: 'EasyDebug log export',
  );

  static String har(
    Iterable<NetworkLog> logs, {
    EasyDebugConfig config = const EasyDebugConfig(),
  }) =>
      _capturedHar(logs.map((log) => captureNetworkLog(log, config)).toList());

  static String _capturedHar(List<NetworkLog> entries) {
    entries.sort((a, b) {
      final time = a.timestamp.compareTo(b.timestamp);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return _encoder.convert({
      'log': {
        'version': '1.2',
        'creator': {'name': 'easy_debug', 'version': '0.0.4'},
        'comment':
            'Sanitized captured previews. Wire sizes and transport phases are not recorded.',
        'entries': entries.map(_harEntry).toList(),
      },
    });
  }

  static String networkJson(
    Iterable<NetworkLog> logs, {
    EasyDebugConfig config = const EasyDebugConfig(),
  }) => _encoder.convert(
    logs.map((entry) {
      final log = captureNetworkLog(entry, config);
      return {
        'id': log.id,
        'timestamp': log.timestamp.toUtc().toIso8601String(),
        'method': log.method,
        'url': log.url,
        'statusCode': log.statusCode,
        'durationMs': log.durationMs,
        'pending': log.isPending,
        'cancelled': log.isCancelled,
        'request': {
          'headers': log.request?.headers,
          'body': log.request?.body,
          'truncated': log.request?.bodyTruncated ?? false,
        },
        'response': {
          'headers': log.response?.headers,
          'body': log.response?.body,
          'truncated': log.response?.bodyTruncated ?? false,
        },
        if (log.error != null) 'error': log.error!.errorMessage,
      };
    }).toList(),
  );

  static String generalJson(Iterable<GeneralLog> logs) => _encoder.convert(
    logs
        .map(
          (log) => {
            'timestamp': log.timestamp.toUtc().toIso8601String(),
            'level': log.level,
            'message': log.message,
          },
        )
        .toList(),
  );

  /// A POSIX-shell reproduction template, with retained credentials masked.
  static String curl(
    NetworkLog entry, {
    EasyDebugConfig config = const EasyDebugConfig(),
  }) {
    final log = captureNetworkLog(entry, config);
    final args = [
      'curl',
      '--request',
      _quote(log.method),
      '--url',
      _quote(log.url),
    ];
    for (final header
        in log.request?.headers.entries ??
            const <MapEntry<String, dynamic>>[]) {
      if (const {
        'host',
        'content-length',
        'transfer-encoding',
        'connection',
        'accept-encoding',
      }.contains(header.key.toLowerCase())) {
        continue;
      }
      args.addAll(['--header', _quote('${header.key}: ${header.value}')]);
    }
    final body = log.request?.body;
    final truncated = log.request?.bodyTruncated ?? false;
    final unavailable = const {
      '<binary or streamed body>',
      '<streamed request body>',
      '<binary request body>',
      '"<unsupported body type>"',
    }.contains(body);
    if (body != null &&
        body.toString().isNotEmpty &&
        !truncated &&
        !unavailable) {
      args.addAll(['--data-raw', _quote(body.toString())]);
    }
    return '# Captured preview; replace redacted credentials before use.\n${truncated || unavailable ? '# Body omitted because the captured preview is truncated or unavailable.\n' : ''}${args.join(' ')}';
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  static List<Map<String, String>> _headers(Map<String, dynamic>? headers) =>
      headers?.entries
          .map((e) => {'name': e.key, 'value': e.value.toString()})
          .toList() ??
      [];

  static String _header(Map<String, dynamic>? headers, String name) {
    for (final entry
        in headers?.entries ?? const <MapEntry<String, dynamic>>[]) {
      if (entry.key.toLowerCase() == name) return entry.value.toString();
    }
    return '';
  }

  static Map<String, dynamic> _harEntry(NetworkLog log) {
    final uri = Uri.tryParse(log.url);
    final request = log.request;
    final response = log.response;
    final body = response?.body?.toString();
    final duration = math.max(0, log.durationMs ?? 0);
    return {
      'startedDateTime': log.timestamp.toUtc().toIso8601String(),
      'time': duration,
      'request': {
        'method': log.method,
        'url': log.url,
        'httpVersion': '',
        'cookies': <Object>[],
        'headers': _headers(request?.headers),
        'queryString': [
          for (final entry
              in uri?.queryParametersAll.entries ??
                  const <MapEntry<String, List<String>>>[])
            for (final value in entry.value)
              {'name': entry.key, 'value': value},
        ],
        if (request?.body != null)
          'postData': {
            'mimeType': request!.contentType,
            'text': request.body.toString(),
          },
        'headersSize': -1,
        'bodySize': -1,
      },
      'response': {
        'status': log.statusCode,
        'statusText': '',
        'httpVersion': '',
        'cookies': <Object>[],
        'headers': _headers(response?.headers),
        'content': {
          'size': body == null ? 0 : utf8.encode(body).length,
          'mimeType': _header(response?.headers, 'content-type'),
          'text': ?body,
          'comment':
              'Size is the exported preview size, not the original wire size.',
        },
        'redirectURL': _header(response?.headers, 'location'),
        'headersSize': -1,
        'bodySize': -1,
      },
      'cache': <String, dynamic>{},
      'timings': {
        'send': 0,
        'wait': duration,
        'receive': 0,
        'comment':
            'Only total elapsed time is recorded; wait holds that aggregate.',
      },
      '_easyDebug': {
        'id': log.id,
        'pending': log.isPending,
        'cancelled': log.isCancelled,
        'requestBodyTruncated': request?.bodyTruncated ?? false,
        'responseBodyTruncated': response?.bodyTruncated ?? false,
        if (log.error != null) 'error': log.error!.errorMessage,
      },
    };
  }
}

String _encodeHar(List<NetworkLog> input) =>
    EasyDebugExport._capturedHar(input);
String _encodeGeneral(List<GeneralLog> logs) =>
    EasyDebugExport.generalJson(logs);
