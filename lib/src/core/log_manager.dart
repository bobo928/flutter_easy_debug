import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capture.dart';
import 'config_model.dart';
import 'log_model.dart';
import 'log_export.dart';
import 'log_query.dart';

/// Immutable snapshots are materialized on demand, once per observed revision.
class _SnapshotNotifier<T> extends ValueNotifier<List<T>> {
  _SnapshotNotifier(this._read) : super(const []);
  final Iterable<T> Function() _read;
  List<T>? _snapshot;
  Timer? _notification;

  @override
  List<T> get value => _snapshot ??= List<T>.unmodifiable(_read());

  @override
  set value(List<T> value) {
    _snapshot = List<T>.unmodifiable(value);
    notifyListeners();
  }

  void invalidate() {
    _snapshot = null;
    notifyListeners();
  }

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
  final pausedNotifier = ValueNotifier(false);
  bool get isPaused => pausedNotifier.value;
  bool get isRecording => enabled && !isPaused;

  /// Stops new captures without deleting records. In-flight requests still finish.
  void pauseRecording() {
    if (enabled) pausedNotifier.value = true;
  }

  void resumeRecording() => pausedNotifier.value = false;

  final _logs = <String, NetworkLog>{};
  final _generalLogs = ListQueue<GeneralLog>();
  late final _networkNotifier = _SnapshotNotifier<NetworkLog>(
    () => _logs.values.toList().reversed,
  );
  late final _generalNotifier = _SnapshotNotifier<GeneralLog>(
    () => _generalLogs,
  );
  ValueNotifier<List<NetworkLog>> get logsNotifier => _networkNotifier;
  ValueNotifier<List<GeneralLog>> get generalLogsNotifier => _generalNotifier;
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

  List<NetworkLog> queryNetworkLogs(NetworkLogQuery query) =>
      List.unmodifiable(logsNotifier.value.where(query.matches));
  List<GeneralLog> queryGeneralLogs(GeneralLogQuery query) =>
      List.unmodifiable(generalLogsNotifier.value.where(query.matches));

  String exportHar({NetworkLogQuery query = const NetworkLogQuery()}) =>
      EasyDebugExport.har(queryNetworkLogs(query), config: config);
  String exportNetworkJson({NetworkLogQuery query = const NetworkLogQuery()}) =>
      EasyDebugExport.networkJson(queryNetworkLogs(query), config: config);
  String exportGeneralJson({GeneralLogQuery query = const GeneralLogQuery()}) =>
      EasyDebugExport.generalJson(queryGeneralLogs(query));

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
      pausedNotifier.value = false;
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
    if (!isRecording || config.maxLogCount == 0) return;
    _logs[log.id] = _capture(log);
    _trim();
    _publishNetwork();
  }

  void updateLog(NetworkLog updatedLog) {
    if (!enabled || !_logs.containsKey(updatedLog.id)) return;
    _logs[updatedLog.id] = captureNetworkLog(
      updatedLog,
      config,
      previous: _logs[updatedLog.id],
    );
    _publishNetwork();
  }

  NetworkLog _capture(NetworkLog log) => captureNetworkLog(log, config);

  void addGeneralLog(String message, {String? level}) {
    if (!isRecording || config.maxGeneralLogCount == 0) return;
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

  void _publishNetwork() => _networkNotifier.invalidate();
  void _publishGeneral() => _generalNotifier.invalidate();
}

/// Explicit application logging without a global print hook.
class EasyDebug {
  static void log(String message, {String? level}) =>
      EasyDebugManager().addGeneralLog(message, level: level);
}
