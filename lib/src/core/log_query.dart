import 'log_model.dart';

enum NetworkLogStatus { all, success, error, pending, cancelled }

/// Composable filters shared by the console and programmatic exports.
class NetworkLogQuery {
  const NetworkLogQuery({
    this.search = '',
    this.status = NetworkLogStatus.all,
    this.method,
    this.host,
    this.statusCode,
    this.minDurationMs,
  }) : assert(minDurationMs == null || minDurationMs >= 0);

  final String search;
  final NetworkLogStatus status;
  final String? method;
  final String? host;
  final int? statusCode;
  final int? minDurationMs;

  bool matches(NetworkLog log) {
    if (method != null && log.method.toUpperCase() != method!.toUpperCase()) {
      return false;
    }
    if (host != null &&
        Uri.tryParse(log.url)?.host.toLowerCase() != host!.toLowerCase()) {
      return false;
    }
    if (statusCode != null && log.statusCode != statusCode) return false;
    if (minDurationMs != null &&
        (log.durationMs == null || log.durationMs! < minDurationMs!)) {
      return false;
    }
    final stateMatches = switch (status) {
      NetworkLogStatus.all => true,
      NetworkLogStatus.success =>
        !log.isPending &&
            !log.isCancelled &&
            !log.isError &&
            log.statusCode >= 200 &&
            log.statusCode < 400,
      NetworkLogStatus.error => log.isError && !log.isCancelled,
      NetworkLogStatus.pending => log.isPending,
      NetworkLogStatus.cancelled => log.isCancelled,
    };
    final needle = search.trim().toLowerCase();
    return stateMatches &&
        (needle.isEmpty ||
            log.url.toLowerCase().contains(needle) ||
            log.method.toLowerCase().contains(needle));
  }
}

enum GeneralLogSeverity { debug, info, warning, error }

final _severityCache = Expando<GeneralLogSeverity>();

GeneralLogSeverity severityOf(GeneralLog log) =>
    _severityCache[log] ??= _inferSeverity(log);

GeneralLogSeverity _inferSeverity(GeneralLog log) {
  final level = log.level?.toUpperCase();
  if (level == 'ERROR' || level == 'FATAL') return GeneralLogSeverity.error;
  if (level == 'WARN' || level == 'WARNING') return GeneralLogSeverity.warning;
  if (level == 'DEBUG' || level == 'TRACE') return GeneralLogSeverity.debug;
  if (level == 'INFO') return GeneralLogSeverity.info;
  final message = log.message.toLowerCase();
  if (message.contains('error') ||
      message.contains('exception') ||
      message.contains('fail')) {
    return GeneralLogSeverity.error;
  }
  if (message.contains('warn')) return GeneralLogSeverity.warning;
  if (message.contains('debug')) return GeneralLogSeverity.debug;
  return GeneralLogSeverity.info;
}

class GeneralLogQuery {
  const GeneralLogQuery({this.search = '', this.severity});
  final String search;
  final GeneralLogSeverity? severity;
  bool matches(GeneralLog log) {
    if (severity != null && severityOf(log) != severity) return false;
    final needle = search.trim().toLowerCase();
    return needle.isEmpty || log.message.toLowerCase().contains(needle);
  }
}
