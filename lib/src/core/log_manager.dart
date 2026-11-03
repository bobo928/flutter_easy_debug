import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capture.dart';
import 'config_model.dart';
import 'log_model.dart';

/// Values update synchronously; burst notifications coalesce per event loop.
class _BatchedNotifier<T> extends ValueNotifier<T> {
  _BatchedNotifier(super.value);
  Timer? _notification;
  @override
  void notifyListeners() {
    if (!hasListeners) return;
    _notification ??= Timer(Duration.zero, () {
      _notification = null;
      super.notifyListeners();
    });
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _notification?.cancel();
      _notification = null;
    }
  }

  @override
  void dispose() {
    _notification?.cancel();
    super.dispose();
  }
}

class EasyDebugManager {
  static final EasyDebugManager _instance = EasyDebugManager._internal();
  static const String _prefKeyEnvName = 'easy_debug_env_name';
  factory EasyDebugManager() => _instance;
  EasyDebugManager._internal();

  final configNotifier = ValueNotifier(const EasyDebugConfig());
  EasyDebugConfig get config => configNotifier.value;
  set config(EasyDebugConfig value) => updateConfig(value);
  bool get enabled => config.enabled;

  final _logs = <String, NetworkLog>{};
  final _generalLogs = ListQueue<GeneralLog>();
  final ValueNotifier<List<NetworkLog>> logsNotifier = _BatchedNotifier([]);
  final ValueNotifier<List<GeneralLog>> generalLogsNotifier = _BatchedNotifier(
    [],
  );
  final currentEnvNotifier = ValueNotifier<AppEnvironment?>(null);
  List<AppEnvironment> _availableEnvironments = const [];
  List<AppEnvironment> get availableEnvironments => _availableEnvironments;
  DebugPrintCallback? _originalDebugPrint;
  DebugPrintCallback? _captureDebugPrint;

  /// Installs output capture once. Environments are optional for log-only usage.
  Future<void> init({List<AppEnvironment> environments = const []}) async {
    if (_captureDebugPrint == null) {
      final original = debugPrint;
      _originalDebugPrint = original;
      _captureDebugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) addGeneralLog(message);
        original(message, wrapWidth: wrapWidth);
      };
      debugPrint = _captureDebugPrint!;
    }
    _availableEnvironments = List.unmodifiable(environments);
    if (environments.isEmpty) {
      currentEnvNotifier.value = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_prefKeyEnvName);
    currentEnvNotifier.value = environments.firstWhere(
      (e) => e.name == savedName,
      orElse: () => environments.firstWhere(
        (e) => e.isDefault,
        orElse: () => environments.first,
      ),
    );
  }

  /// Stops capture, releases retained logs and restores the hook we installed.
  void shutdown() {
    if (identical(debugPrint, _captureDebugPrint) &&
        _originalDebugPrint != null) {
      debugPrint = _originalDebugPrint!;
    }
    _captureDebugPrint = null;
    _originalDebugPrint = null;
    updateConfig(config.copyWith(enabled: false));
  }

  Future<void> changeEnvironment(AppEnvironment env) async {
    if (!_availableEnvironments.contains(env)) {
      throw ArgumentError.value(env, 'env');
    }
    if (currentEnvNotifier.value == env) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyEnvName, env.name);
    currentEnvNotifier.value = env;
  }

  String get currentBaseUrl => currentEnvNotifier.value?.baseUrl ?? '';
  NetworkLog? getLog(String id) => _logs[id];

  void updateConfig(EasyDebugConfig newConfig) {
    if (newConfig.maxLogCount < 0 ||
        newConfig.maxGeneralLogCount < 0 ||
        newConfig.maxBodyBytes < 0 ||
        newConfig.maxMessageLength <= 0) {
      throw ArgumentError(
        'Log limits must be non-negative; message length must be positive.',
      );
    }
    configNotifier.value = newConfig;
    if (!enabled) {
      clearLogs();
      return;
    }
    _trim();
    _logs.updateAll((_, log) => _capture(log));
    final messages = _generalLogs.toList();
    _generalLogs.clear();
    for (final log in messages) {
      _generalLogs.add(
        GeneralLog(
          timestamp: log.timestamp,
          message: boundedText(log.message, config.maxMessageLength),
          level: log.level,
        ),
      );
    }
    _publishNetwork();
    _publishGeneral();
  }

  void addLog(NetworkLog log) {
    if (!enabled || config.maxLogCount == 0) return;
    _logs[log.id] = _capture(log);
    _trim();
    _publishNetwork();
  }

  void updateLog(NetworkLog updatedLog) {
    if (!enabled || !_logs.containsKey(updatedLog.id)) return;
    _logs[updatedLog.id] = _capture(updatedLog);
    _publishNetwork();
  }

  NetworkLog _capture(NetworkLog log) {
    final request = log.request;
    final response = log.response;
    final requestBody = captureBody(
      request?.body,
      config,
      sourceTruncated: request?.bodyTruncated ?? false,
    );
    final responseBody = captureBody(
      response?.body,
      config,
      sourceTruncated: response?.bodyTruncated ?? false,
    );
    final error = log.error;
    return log.copyWith(
      method: boundedText(log.method, 32),
      url: captureUrl(log.url, config),
      request: request == null
          ? null
          : RequestDetails(
              headers: captureHeaders(request.headers, config),
              body: requestBody.text,
              contentType: boundedText(request.contentType, 256),
              bodyTruncated: request.bodyTruncated || requestBody.truncated,
            ),
      response: response == null
          ? null
          : ResponseDetails(
              statusCode: response.statusCode,
              headers: captureHeaders(response.headers, config),
              body: responseBody.text,
              timestamp: response.timestamp,
              bodyTruncated: response.bodyTruncated || responseBody.truncated,
            ),
      error: error == null
          ? null
          : ErrorDetails(
              errorMessage: boundedText(
                error.errorMessage,
                config.maxMessageLength,
              ),
              errorType: error.errorType == null
                  ? null
                  : boundedText(error.errorType!, 128),
              stackTrace: error.stackTrace == null
                  ? null
                  : boundedText(error.stackTrace!, config.maxMessageLength),
            ),
    );
  }

  void addGeneralLog(String message, {String? level}) {
    if (!enabled || config.maxGeneralLogCount == 0) return;
    _generalLogs.add(
      GeneralLog(
        timestamp: DateTime.now(),
        message: boundedText(message, config.maxMessageLength),
        level: level == null ? null : boundedText(level, 32),
      ),
    );
    _trim();
    _publishGeneral();
  }

  void clearLogs() {
    _logs.clear();
    _generalLogs.clear();
    _publishNetwork();
    _publishGeneral();
  }

  void _trim() {
    while (_logs.length > config.maxLogCount) {
      _logs.remove(_logs.keys.first);
    }
    while (_generalLogs.length > config.maxGeneralLogCount) {
      _generalLogs.removeFirst();
    }
  }

  void _publishNetwork() =>
      logsNotifier.value = List.unmodifiable(_logs.values.toList().reversed);
  void _publishGeneral() =>
      generalLogsNotifier.value = List.unmodifiable(_generalLogs);
}

/// Explicit application logging without a global print hook.
class EasyDebug {
  static void log(String message, {String? level}) =>
      EasyDebugManager().addGeneralLog(message, level: level);
}
