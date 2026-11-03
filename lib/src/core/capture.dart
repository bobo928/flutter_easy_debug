import 'dart:convert';
import 'dart:typed_data';

import 'log_model.dart';

/// Clips at a UTF-8 boundary without encoding an arbitrarily large string.
String boundedText(String text, int maxBytes) {
  if (maxBytes <= 0) return '';
  final prefix = text.length > maxBytes ? text.substring(0, maxBytes) : text;
  final bytes = utf8.encode(prefix);
  if (bytes.length <= maxBytes) return prefix;
  var end = maxBytes;
  while (end > 0 && (bytes[end] & 0xc0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}

Map<String, dynamic> captureHeaders(
  Map<String, dynamic> headers,
  EasyDebugConfig config,
) {
  final hidden = config.sensitiveHeaders.map((e) => e.toLowerCase()).toSet();
  return Map.unmodifiable(
    Map.fromEntries(
      headers.entries.take(100).map((entry) {
        return MapEntry(
          boundedText(entry.key, 256),
          hidden.contains(entry.key.toLowerCase())
              ? '[REDACTED]'
              : boundedText(entry.value.toString(), config.maxMessageLength),
        );
      }),
    ),
  );
}

String captureUrl(String url, EasyDebugConfig config) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasQuery) return boundedText(url, 8192);
  final hidden = config.sensitiveKeys.map((e) => e.toLowerCase()).toSet();
  return boundedText(
    uri
        .replace(
          queryParameters: uri.queryParametersAll.map(
            (key, value) => MapEntry(
              key,
              hidden.contains(key.toLowerCase()) ? ['[REDACTED]'] : value,
            ),
          ),
        )
        .toString(),
    8192,
  );
}

class CapturedBody {
  const CapturedBody(this.text, this.truncated);
  final String? text;
  final bool truncated;
}

/// Visits only a bounded prefix rather than JSON-encoding a complete payload.
CapturedBody captureBody(
  dynamic body,
  EasyDebugConfig config, {
  bool sourceTruncated = false,
}) {
  if (body == null) return const CapturedBody(null, false);
  if (body is Uint8List || body is Stream) {
    return const CapturedBody('<binary or streamed body>', false);
  }
  if (body is String &&
      (sourceTruncated || body.length > config.maxBodyBytes)) {
    final start = body.substring(0, body.length.clamp(0, 64)).trimLeft();
    if (start.startsWith('{') || start.startsWith('[')) {
      return const CapturedBody('<JSON body exceeds capture limit>', true);
    }
  }
  if (body is String && body.length <= config.maxBodyBytes) {
    try {
      body = jsonDecode(body);
    } catch (_) {
      /* Plain text stays plain. */
    }
  }
  final writer = _BodyWriter(config);
  writer.write(body, 0, plainText: body is String);
  return CapturedBody(writer.buffer.toString(), writer.truncated);
}

class _BodyWriter {
  _BodyWriter(this.config);
  final EasyDebugConfig config;
  final buffer = StringBuffer();
  int bytes = 0;
  bool truncated = false;

  void append(String text) {
    final clipped = boundedText(text, config.maxBodyBytes - bytes);
    buffer.write(clipped);
    bytes += utf8.encode(clipped).length;
    if (clipped.length < text.length) truncated = true;
  }

  void write(dynamic value, int depth, {bool plainText = false}) {
    if (bytes >= config.maxBodyBytes) {
      truncated = true;
      return;
    }
    if (depth > 8) {
      append('"<depth limit>"');
      truncated = true;
      return;
    }
    if (value is Map) {
      append('{');
      var first = true;
      for (final entry in value.entries) {
        if (bytes >= config.maxBodyBytes) {
          truncated = true;
          break;
        }
        if (!first) append(', ');
        first = false;
        final key = boundedText(entry.key.toString(), config.maxMessageLength);
        append(jsonEncode(key));
        append(': ');
        write(
          config.sensitiveKeys.any((e) => e.toLowerCase() == key.toLowerCase())
              ? '[REDACTED]'
              : entry.value,
          depth + 1,
        );
      }
      append('}');
    } else if (value is List) {
      append('[');
      for (var i = 0; i < value.length; i++) {
        if (bytes >= config.maxBodyBytes) {
          truncated = true;
          break;
        }
        if (i > 0) append(', ');
        write(value[i], depth + 1);
      }
      append(']');
    } else {
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool) {
        append('"<unsupported body type>"');
        return;
      }
      final text = value?.toString() ?? 'null';
      final prefix = boundedText(text, config.maxBodyBytes - bytes);
      if (prefix.length < text.length) truncated = true;
      append(value is String && !plainText ? jsonEncode(prefix) : prefix);
    }
  }
}
