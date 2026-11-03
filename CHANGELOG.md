## Unreleased

* Generate list snapshots lazily, retain cached sanitized details on ordinary response updates and add a reproducible ingestion benchmark.
* Add pause/resume without deleting retained logs, method/host/slow/cancelled filters, general-log level/search filters and programmatic query APIs.
* Add sanitized HAR/JSON exports, POSIX cURL templates, background whole-list encoding on native platforms and clipboard feedback.
* Preserve console filter selections across details and tabs, and omit credentials embedded in URLs or redirect locations.
* Bound network/general logs, UTF-8 body/message previews and structured body traversal; coalesce subscriber notifications during bursts.
* Use unique request IDs and constant-time log lookup; remove the unused Dio request map.
* Preserve http stream errors, forward pause/resume/cancellation and capture headers before body consumption without altering caller payloads.
* Make debugPrint initialization idempotent, add shutdown and implement EasyDebug.log.
* Disable capture/UI by default in release builds; add configurable sensitive-header and structured-credential masking.
* Refresh the console with adaptive light/dark cards, search, pending filters, bounded dragging and live details inside the console.
* Replace the stale example test, add network/manager/widget regressions and a verification workflow; update setup and release documentation.

## 0.0.4

* Add standard http client support and a separate general-log view.
* Add debugPrint capture and update the debug console layout.

## 0.0.3

*   **[DOCS] Update README**: Added comprehensive documentation for Environment Switcher feature.
*   **[FIX] UI Polish**: Fixed glassmorphism opacity issue in settings view (was too opaque).

## 0.0.2

*   **[NEW] Environment Switcher**: Added support for managing and switching API environments (e.g., Dev/Prod) at runtime.
    *   New `AppEnvironment` model.
    *   New `EasyDebugManager().init()` method with persistence support via `shared_preferences`.
    *   Reactive Base URL updates via `EasyDebugManager().currentEnvNotifier`.
*   **[FIX] Navigation Fallback**: Fixed navigation issues in projects without global `EasyDebugNavigatorObserver`. Now auto-falls back to `Navigator.of(context, rootNavigator: true)`.

## 0.0.1

*   Initial release of Easy Debug.
*   Pure Dart in-app network debugger for Dio.
*   Features: Floating overlay, glassmorphism UI, log filtering (All/Success/Error), copy to clipboard, and auto-clearing.
