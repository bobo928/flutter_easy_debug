import 'dart:convert';

import 'package:easy_debug/easy_debug.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manager = EasyDebugManager();
  setUp(() {
    manager.shutdown();
    manager.updateConfig(const EasyDebugConfig());
  });
  tearDown(manager.shutdown);

  test(
    'sustained ingestion preserves bounded snapshots and batches notifications',
    () async {
      final samples = <int>[];
      for (var sample = 0; sample < 3; sample++) {
        manager.clearLogs();
        await Future<void>.delayed(Duration.zero);
        var notifications = 0;
        void listener() {
          notifications++;
        }

        manager.generalLogsNotifier.addListener(listener);
        final watch = Stopwatch()..start();
        for (var i = 0; i < 100000; i++) {
          EasyDebug.log('event $i');
        }
        watch.stop();
        samples.add(watch.elapsedMicroseconds);
        final snapshot = manager.generalLogsNotifier.value;
        expect(snapshot.length, 200);
        expect(snapshot.last.message, 'event 99999');
        await Future<void>.delayed(Duration.zero);
        expect(notifications, 1);
        manager.generalLogsNotifier.removeListener(listener);
        EasyDebug.log('next event');
        expect(snapshot.last.message, 'event 99999');
        expect(manager.generalLogsNotifier.value.last.message, 'next event');
      }
      final sorted = [...samples]..sort();
      debugPrint(
        'BENCH ${jsonEncode({'case': '100000_general_logs', 'samples_us': samples, 'median_us': sorted[1], 'retained': 200, 'notifications_per_burst': 1})}',
      );
    },
  );
}
