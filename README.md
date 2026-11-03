# Easy Debug

An in-app Flutter console for inspecting **Dio**, **http** and application logs.
Open the floating button to see requests, inspect responses, copy details and switch API environments.

<p align="center">
  <img src="screenshots/1.png" width="30%" alt="Network inspector" />
  <img src="screenshots/2.png" width="30%" alt="Dark application logs" />
  <img src="screenshots/3.png" width="30%" alt="Live request details" />
</p>

## Features

- Dio interceptor and an http client wrapper; existing caller responses and errors pass through.
- Request cards, URL/method search, success/error/pending filters and live details.
- Light and dark themes, adaptive panel width, draggable button with screen bounds, keyboard-aware layout.
- Request/response headers and body previews, duration, errors and clipboard copy.
- Bounded network/general logs and body previews; burst notifications are coalesced.
- Environment selection persisted with shared_preferences.
- Capture and UI disabled by default in release builds.

The package implementation is Dart/Flutter. Environment persistence uses the shared_preferences platform plugin. This repository includes Android/iOS example projects; platform support also depends on those dependencies and your host application.

## Installation

Use the Git checkout while evaluating these changes:

```yaml
dependencies:
  easy_debug:
    git:
      url: https://github.com/bobo928/flutter_easy_debug.git
      ref: main
```

Dart 3.10.1 or newer (below 4.0) is required, together with a compatible Flutter SDK.
The verification workflow currently uses Flutter 3.44.7 / Dart 3.12.2.

## Initialize and display the console

```dart
import 'package:easy_debug/easy_debug.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyDebugManager().init(); // Enables debugPrint capture; idempotent.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => EasyDebugWidget(child: child!),
    navigatorObservers: [EasyDebugNavigatorObserver()],
    home: const Scaffold(body: Center(child: Text('My app'))),
  );
}
```

Tap the bug button to open the console. Details stay inside the console and update when a request finishes, without pushing a host application route. Escape or the close button dismisses the console. The observer is needed only if you want automatic clearing when host routes are pushed.

## Connect the clients you actually use

```dart
final dio = Dio()..interceptors.add(EasyDebugDioInterceptor());

final client = EasyDebugHttpClient(http.Client());
final response = await client.get(Uri.parse('https://example.com/data'));
// Close the wrapper when the owning component is disposed.
client.close();
```

Import http as usual: `import 'package:http/http.dart' as http;`.

Requests from other client instances are not captured. Multipart/streamed request bodies are represented by a placeholder. Binary bodies are not rendered as JSON.

The http wrapper retains at most a bounded response prefix, forwards chunks and pause/resume to the source, and records cancellation. Headers are available before body consumption; a response is pending until its stream completes. Duration includes time spent consuming that stream. A stream that is never listened to remains pending.

## Application logs

```dart
debugPrint('A message captured after init()');
EasyDebug.log('Cache refreshed', level: 'INFO');
EasyDebugManager().addGeneralLog('Explicit log entry');
```

Ordinary `print()` and other isolates are not intercepted. Levels are optional. Tap a log card to copy the complete retained message.

Call `EasyDebugManager().shutdown()` to stop recording, clear retained logs and restore the debugPrint hook installed by this package. It does not overwrite a replacement hook installed later by another component. Re-enable configuration and call `init()` to start a new session.

## Resource limits and capture policy

```dart
EasyDebugManager().updateConfig(const EasyDebugConfig(
  // Defaults to false in release builds; omit to keep that default.
  enabled: true,
  maxLogCount: 50,
  maxGeneralLogCount: 200,
  maxBodyBytes: 65536,
  maxMessageLength: 4000,
  clearOnNavigation: false,
));
```

Zero record capacity disables retention of that log type. Limits must be non-negative and message length must be positive. Reducing a limit trims retained data. Disabling capture clears records, hides the overlay and bypasses instrumentation for new requests.

- Each request/response body preview is bounded in UTF-8 bytes. Truncated previews are labeled in details and copied output. Large structured bodies are traversed only up to the preview budget, with a nesting-depth limit.
- Incomplete or oversized JSON text is omitted when it cannot be safely parsed within the budget; caller data remains intact.
- General message length is also a UTF-8 byte budget. Headers are limited to 100 entries, with bounded names and values.
- Sensitive headers (Authorization, Cookie, Set-Cookie, Proxy-Authorization, X-API-Key) are masked by default. Common credential keys are masked in structured JSON and URL queries. Customize `sensitiveHeaders` and `sensitiveKeys` if your API uses other names.
- Plain-text bodies, error text and application log messages are not automatically scrubbed. Avoid logging secrets in those channels.
- Stored log values update immediately. Subscriber notifications are batched once per event-loop turn, so a burst does not cause a notification for every log entry.
- Logs are held in memory only; environment selection is the only persisted data.

Keep debug capture disabled for normal release distribution. If you explicitly enable it, apply the policies appropriate to that build.

## Environment switching

```dart
await EasyDebugManager().init(environments: const [
  AppEnvironment(
    name: 'Production',
    baseUrl: 'https://api.example.com',
    isDefault: true,
  ),
  AppEnvironment(
    name: 'Development',
    baseUrl: 'https://dev.example.com',
  ),
]);
```

The manager restores a saved environment name, then falls back to the default or first entry. Names should be unique. The host must update its clients:

```dart
void onEnvironmentChanged() {
  dio.options.baseUrl = EasyDebugManager().currentBaseUrl;
}

onEnvironmentChanged();
EasyDebugManager().currentEnvNotifier.addListener(onEnvironmentChanged);
// Remove the listener when its owner is disposed.
EasyDebugManager().currentEnvNotifier.removeListener(onEnvironmentChanged);
```

For http, construct new request URIs from the current base URL. Switching environments does not rewrite requests already in flight.

## Development

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test example/lib example/test
flutter analyze --no-pub
flutter test --no-pub
cd example
flutter test --no-pub
```

Tests use local adapters and streams, not public API endpoints. They cover retention, redaction, repeated initialization, concurrent HTTP requests, stream errors/cancellation/backpressure, and console interaction at phone and desktop sizes.

See [CHANGELOG.md](CHANGELOG.md) for changes and [PUBLISHING.md](PUBLISHING.md) for release checks.

## License

MIT. Original project by JasonBoolean.
