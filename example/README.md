# extension_bridge example

A counter shared between the app, an Android home screen widget and a Dart
background isolate.

* `lib/main.dart` – the app and its background callback.
* `android/app/src/main/kotlin/.../ExampleFeature.kt`, `ios/Runner/AppDelegate.swift`
  and `macos/Runner/MainFlutterWindow.swift` – the native `example` feature.
* `android/app/src/main/kotlin/.../CounterWidgetProvider.kt` – the home screen
  widget.
* `integration_test/extension_bridge_test.dart` – the tests CI runs on every
  platform.

```sh
flutter run
flutter test integration_test -d <device>
```
