import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/log_manager.dart';
import '../core/log_model.dart';

/// Passes through response chunks, pause/resume, errors and cancellation.
/// Only a bounded body prefix is retained for inspection.
class EasyDebugHttpClient extends http.BaseClient {
  EasyDebugHttpClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final manager = EasyDebugManager();
    if (!manager.isRecording || manager.config.maxLogCount == 0) {
      return _inner.send(request);
    }
    final timer = Stopwatch()..start();
    Object? requestBody;
    var requestBodyTruncated = false;
    if (request is http.Request) {
      final bytes = request.bodyBytes;
      final limit = manager.config.maxBodyBytes;
      requestBodyTruncated = bytes.length > limit;
      final prefix = bytes.take(limit).toList(growable: false);
      try {
        requestBody = request.encoding.name == 'utf-8'
            ? utf8.decode(prefix, allowMalformed: true)
            : request.encoding.decode(prefix);
      } catch (_) {
        requestBody = '<binary request body>';
      }
    } else {
      requestBody = '<streamed request body>';
    }
    final log =
        NetworkLog(
            timestamp: DateTime.now(),
            method: request.method,
            url: request.url.toString(),
          )
          ..request = RequestDetails(
            headers: request.headers,
            body: requestBody,
            bodyTruncated: requestBodyTruncated,
            contentType: request.headers['content-type'] ?? '',
          );
    manager.addLog(log);
    final id = log.id;
    void update({
      ResponseDetails? response,
      ErrorDetails? error,
      bool complete = false,
      bool cancelled = false,
    }) {
      final current = manager.getLog(id);
      if (current == null) return;
      manager.updateLog(
        current.copyWith(
          response: response,
          error: error,
          durationMs: timer.elapsedMilliseconds,
          isComplete: complete,
          isCancelled: cancelled,
        ),
      );
    }

    try {
      final response = await _inner.send(request);
      update(
        response: ResponseDetails(
          statusCode: response.statusCode,
          headers: response.headers,
          timestamp: DateTime.now(),
        ),
      );
      final bytes = <int>[];
      // Freeze the cap for this request; later config reductions also apply below.
      final limit = manager.config.maxBodyBytes;
      var truncated = false;
      var ended = false;
      final stream = Stream<List<int>>.multi((controller) {
        final subscription = response.stream.listen(
          (chunk) {
            if (manager.getLog(id) == null || !manager.enabled) {
              bytes.clear();
            } else {
              final remaining = math.max(
                0,
                math.min(limit, manager.config.maxBodyBytes) - bytes.length,
              );
              if (chunk.length > remaining) truncated = true;
              bytes.addAll(chunk.take(remaining));
            }
            controller.addSync(chunk);
          },
          onError: (Object error, StackTrace stack) {
            update(
              error: ErrorDetails(
                errorMessage: error.toString(),
                stackTrace: stack.toString(),
              ),
              complete: true,
            );
            controller.addErrorSync(error, stack);
          },
          onDone: () {
            ended = true;
            timer.stop();
            update(
              response: ResponseDetails(
                statusCode: response.statusCode,
                headers: response.headers,
                timestamp: DateTime.now(),
                body: utf8.decode(bytes, allowMalformed: true),
                bodyTruncated: truncated,
              ),
              complete: true,
            );
            bytes.clear();
            controller.closeSync();
          },
        );
        controller.onPause = subscription.pause;
        controller.onResume = subscription.resume;
        controller.onCancel = () {
          if (!ended) {
            timer.stop();
            final current = manager.getLog(id);
            if (current?.error == null) update(complete: true, cancelled: true);
          }
          bytes.clear();
          return subscription.cancel();
        };
      });
      return http.StreamedResponse(
        stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error, stack) {
      timer.stop();
      update(
        error: ErrorDetails(
          errorMessage: error.toString(),
          stackTrace: stack.toString(),
        ),
        complete: true,
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
