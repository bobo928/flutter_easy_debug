import 'package:flutter/foundation.dart';

/// Resource limits and capture policy for Easy Debug.
class EasyDebugConfig {
  /// Disabled by default in release builds. Controls capture and the overlay.
  final bool enabled;
  final int maxGeneralLogCount;
  final int maxBodyBytes;
  final int maxMessageLength;
  final Set<String> sensitiveHeaders;
  final Set<String> sensitiveKeys;

  /// Whether to clear logs when navigation (push) happens.
  /// Default: false
  final bool clearOnNavigation;

  /// Maximum number of logs to keep in memory.
  /// Default: 50
  final int maxLogCount;

  const EasyDebugConfig({
    this.enabled = !kReleaseMode,
    this.maxGeneralLogCount = 200,
    this.maxBodyBytes = 65536,
    this.maxMessageLength = 4000,
    this.sensitiveHeaders = const {
      'authorization',
      'proxy-authorization',
      'cookie',
      'set-cookie',
      'x-api-key',
    },
    this.sensitiveKeys = const {
      'password',
      'token',
      'access_token',
      'refresh_token',
      'secret',
      'api_key',
    },
    this.clearOnNavigation = false,
    this.maxLogCount = 50,
  }) : assert(maxLogCount >= 0),
       assert(maxGeneralLogCount >= 0),
       assert(maxBodyBytes >= 0),
       assert(maxMessageLength > 0);

  EasyDebugConfig copyWith({bool? enabled}) => EasyDebugConfig(
    enabled: enabled ?? this.enabled,
    clearOnNavigation: clearOnNavigation,
    maxLogCount: maxLogCount,
    maxGeneralLogCount: maxGeneralLogCount,
    maxBodyBytes: maxBodyBytes,
    maxMessageLength: maxMessageLength,
    sensitiveHeaders: sensitiveHeaders,
    sensitiveKeys: sensitiveKeys,
  );
}

/// Represents a single network request/response log
class NetworkLog {
  static int _sequence = 0;
  final String id;
  final DateTime timestamp;
  final String method;
  final String url;

  RequestDetails? request;
  ResponseDetails? response;
  ErrorDetails? error;

  int? durationMs;
  bool isComplete = false;
  bool isCancelled = false;
  bool get isPending => !isComplete && error == null && !isCancelled;

  NetworkLog({
    String? id,
    required this.timestamp,
    required this.method,
    required this.url,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  bool get isError =>
      error != null ||
      (response != null && (response!.statusCode ?? 200) >= 400);

  int get statusCode => response?.statusCode ?? 0;

  NetworkLog copyWith({
    String? id,
    DateTime? timestamp,
    String? method,
    String? url,
    RequestDetails? request,
    ResponseDetails? response,
    ErrorDetails? error,
    int? durationMs,
    bool? isComplete,
    bool? isCancelled,
  }) {
    return NetworkLog(
        id: id ?? this.id,
        timestamp: timestamp ?? this.timestamp,
        method: method ?? this.method,
        url: url ?? this.url,
      )
      ..request = request ?? this.request
      ..response = response ?? this.response
      ..error = error ?? this.error
      ..durationMs = durationMs ?? this.durationMs
      ..isComplete = isComplete ?? this.isComplete
      ..isCancelled = isCancelled ?? this.isCancelled;
  }
}

class RequestDetails {
  final bool bodyTruncated;
  final Map<String, dynamic> headers;
  final dynamic body;
  final String contentType;

  RequestDetails({
    this.headers = const {},
    this.body,
    this.contentType = '',
    this.bodyTruncated = false,
  });
}

class ResponseDetails {
  final bool bodyTruncated;
  final int? statusCode;
  final Map<String, dynamic> headers;
  final dynamic body;
  final DateTime timestamp;

  ResponseDetails({
    this.statusCode,
    this.headers = const {},
    this.body,
    required this.timestamp,
    this.bodyTruncated = false,
  });
}

class ErrorDetails {
  final String errorMessage;
  final String? errorType;
  final dynamic errorObject;
  final String? stackTrace;

  ErrorDetails({
    required this.errorMessage,
    this.errorType,
    this.errorObject,
    this.stackTrace,
  });
}

class GeneralLog {
  final DateTime timestamp;
  final String message;
  final String? level; // e.g., 'INFO', 'ERROR'

  GeneralLog({required this.timestamp, required this.message, this.level});
}
