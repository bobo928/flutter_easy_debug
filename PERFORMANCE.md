# Log ingestion performance

The benchmark is `test/performance_test.dart`:

```sh
flutter test --no-pub test/performance_test.dart --reporter expanded
```

Each of three consecutive samples writes 100,000 short general-log messages, with a listener attached and retention set to 200. The measured interval contains ingestion only. The test then reads the snapshot, verifies its contents and independence from later changes, and checks one batched notification per burst. Timing is diagnostic; there is no machine-dependent pass/fail threshold.

Observed on this macOS workspace using Flutter 3.44.7 / Dart 3.12.2 in the debug test process:

| Implementation | Sample 1 | Sample 2 | Sample 3 | Median |
| --- | ---: | ---: | ---: | ---: |
| Baseline `031b962` | 151.554 ms | 115.314 ms | 109.887 ms | 115.314 ms |
| Lazy snapshots in this change | 29.580 ms | 14.246 ms | 12.515 ms | 14.246 ms |

The observed median ingestion time was about 8.1 times lower. Both versions retained 200 messages and emitted one notification per burst. These are local samples, not a frame-rate claim or a performance guarantee across devices. JIT, garbage collection, load and message size affect results.

The previous implementation copied the entire retained list on every message. The new path appends/trims the bounded queue and invalidates its cached snapshot; the list is copied only when a consumer reads a changed revision. A listener reading on every write still pays for those reads. Network response updates also reuse already sanitized, unchanged request/response details; configuration changes and caller-mutated stored records force sanitization again.

The console uses lazy slivers for result lists and debounces text search. Whole-list copy/export uses a compute isolate on native platforms; Web compute runs on its current event loop. Captured body and log-count limits continue to apply. Exports do not add persistent disk storage or background uploads.

Real-device profile-mode frame timings, heap allocation traces and long-duration memory curves remain unmeasured. Use Flutter DevTools on the target app to assess those under its actual request rate and payload distribution.
