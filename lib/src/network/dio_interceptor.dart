import 'package:dio/dio.dart';

import '../core/log_manager.dart';
import '../core/log_model.dart';

class EasyDebugDioInterceptor extends Interceptor {
  static const _idKey = 'easy_debug_id';
  static const _timerKey = 'easy_debug_timer';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final manager = EasyDebugManager();
    if (manager.isRecording && manager.config.maxLogCount > 0) {
      final log =
          NetworkLog(
              timestamp: DateTime.now(),
              method: options.method,
              url: options.uri.toString(),
            )
            ..request = RequestDetails(
              headers: options.headers,
              body: options.data,
              contentType: options.contentType ?? '',
            );
      manager.addLog(log);
      options.extra[_idKey] = log.id;
      options.extra[_timerKey] = Stopwatch()..start();
    }
    super.onRequest(options, handler);
  }

  void _complete(
    RequestOptions options, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    final id = options.extra.remove(_idKey);
    final timer = options.extra.remove(_timerKey);
    if (timer is Stopwatch) timer.stop();
    if (id is! String) return;
    final manager = EasyDebugManager();
    final log = manager.getLog(id);
    if (log == null) return;
    manager.updateLog(
      log.copyWith(
        response: response == null
            ? null
            : ResponseDetails(
                statusCode: response.statusCode,
                headers: response.headers.map,
                body: response.data,
                timestamp: DateTime.now(),
              ),
        error: error == null
            ? null
            : ErrorDetails(
                errorMessage: error.message ?? 'Network request failed',
                errorType: error.type.name,
                stackTrace: error.stackTrace.toString(),
              ),
        durationMs: timer is Stopwatch ? timer.elapsedMilliseconds : null,
        isComplete: true,
        isCancelled: error?.type == DioExceptionType.cancel,
      ),
    );
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _complete(response.requestOptions, response: response);
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _complete(err.requestOptions, response: err.response, error: err);
    super.onError(err, handler);
  }
}
