# extension_bridge

[![CI](https://github.com/nikodembernat/extension_bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/nikodembernat/extension_bridge/actions/workflows/ci.yml)

One bridge between Flutter and native app extensions.

Packages such as [`home_widget`](https://pub.dev/packages/home_widget) and
[`live_activities`](https://pub.dev/packages/live_activities) each reimplement
the same plumbing: an App Group `UserDefaults` suite, a shared container for
images, a URL that opens the app, a headless engine to run Dart in the
background and a method channel for everything else. `extension_bridge` is
that plumbing, done once, so you can build **home screen widgets, Live
Activities, share extensions, App Intents, Control Center controls, watch
complications** – or your own package for any of them – on top of it.

| Capability | Dart | Swift (`ExtensionBridgeKit`) | Kotlin |
| --- | --- | --- | --- |
| Shared key-value storage | `bridge.storage` | `ExtensionBridgeStorage` | `ExtensionBridgeStorage` |
| Shared files | `bridge.files` | `ExtensionBridgeFiles` | `ExtensionBridgeFiles` |
| Deep links into the app | `ExtensionBridge.links` | `ExtensionBridgeLink` | `ExtensionBridgeLinks` |
| Dart in the background | `ExtensionBridge.registerBackgroundCallback` | `ExtensionBridgeBackground` | `ExtensionBridgeBackground` |
| Your own native code | `bridge.feature('name')` | `ExtensionBridgeFeature` | `ExtensionBridgeFeature` |

## Platform support

| | Android | iOS | macOS | Linux | Windows | Web |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Storage | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Files | ✅ | ✅ | ✅ | ✅ | ✅ | – |
| Links | ✅ | ✅ | ✅ | – | – | – |
| Features | ✅ | ✅ | ✅ | – | – | – |
| Background | ✅ | ✅ | – | – | – | – |

Everything marked ✅ is covered by integration tests that run on every
platform in CI. Calls that a platform cannot support fail with an
`ExtensionBridgeException` whose code is `unsupported`, so shared code can
degrade gracefully.

Requirements: Flutter 3.47+, Android 7.0+ (API 24), iOS 15+, macOS 12+. iOS and
macOS use **Swift Package Manager only**; there is no CocoaPods podspec.

## Getting started

```sh
flutter pub add extension_bridge
```

```dart
import 'package:extension_bridge/extension_bridge.dart';

// One constant for the whole app. On iOS and macOS the app group must be
// added to the App Groups capability of the app and of every extension.
const bridge = ExtensionBridge(appGroup: 'group.com.example.app');
```

### Storage

```dart
await bridge.storage.set('counter', 42); // bool, int, double, String, Uint8List
final counter = await bridge.storage.get<int>('counter');

await bridge.storage.setJson('profile', {'name': 'Ada', 'tags': ['admin']});
final profile = await bridge.storage.getJson('profile');

await bridge.storage.remove('counter');
final everything = await bridge.storage.getAll();
```

Read the same values natively:

```swift
let storage = ExtensionBridgeStorage(appGroup: "group.com.example.app")
let counter = storage.integer(forKey: "counter") ?? 0
let profile = try storage.decode(Profile.self, forKey: "profile") // Codable
```

```kotlin
val storage = ExtensionBridgeStorage(context, appGroup = "group.com.example.app")
val counter = storage.getLong("counter") ?: 0
```

### Files

```dart
final path = await bridge.files.write('avatar.png', bytes); // atomic
final data = await bridge.files.read('avatar.png');
final names = await bridge.files.list();
```

```swift
let image = ExtensionBridgeFiles(appGroup: "group.com.example.app")
  .read("avatar.png")
  .flatMap(UIImage.init(data:))
```

```kotlin
val avatar = ExtensionBridgeFiles(context, "group.com.example.app").file("avatar.png")
```

### Links

Extensions open the app with a URL marked by the `extension_bridge` query
parameter. Only marked URLs are handled, so links meant for other packages
(OAuth redirects, `go_router` deep links, …) are never swallowed.

```dart
final initial = await ExtensionBridge.initialLink; // the link that launched the app
ExtensionBridge.links.listen((link) {
  print('${link.source} opened ${link.uri}'); // widget opened myapp://counter
});
```

```swift
// In a SwiftUI widget:
.widgetURL(ExtensionBridgeLink.url("myapp://counter", source: "widget"))

// In an App Intent that brings the app to the front:
await ExtensionBridgePlugin.deliverLink(URL(string: "myapp://timer")!, source: "intent")
```

```kotlin
views.setOnClickPendingIntent(
    R.id.root,
    ExtensionBridgeLinks.pendingIntent(context, Uri.parse("myapp://counter"), source = "widget"),
)
```

On iOS and macOS the URL scheme (`myapp`) must be listed under
`CFBundleURLTypes` in the app's `Info.plist`.

### Background Dart

Native code can run Dart without opening the app – for interactive widgets,
App Intents or Live Activity buttons. The callback runs in a headless isolate
and its return value goes back to native code.

```dart
@pragma('vm:entry-point')
Future<Object?> onBackgroundEvent(BackgroundEvent event) async {
  if (event.name == 'increment') {
    final counter = (await bridge.storage.get<int>('counter') ?? 0) + 1;
    await bridge.storage.set('counter', counter);
    return counter;
  }
  return null;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ExtensionBridge.registerBackgroundCallback(onBackgroundEvent); // on every launch
  runApp(const App());
}
```

```swift
// iOS – e.g. inside AppIntent.perform()
let counter = try await ExtensionBridgeBackground.dispatch("increment")
```

```kotlin
// Android – a widget button, no code needed in a receiver:
views.setOnClickPendingIntent(R.id.plus, ExtensionBridgeBackground.pendingIntent(context, "increment"))
// …or directly from a coroutine:
val counter = ExtensionBridgeBackground.dispatch(context, "increment")
```

Only `extension_bridge` is registered in the background isolate by default. To
use other plugins there, pass your registrant on iOS:

```swift
ExtensionBridgeBackground.setPluginRegistrant { registry in
  GeneratedPluginRegistrant.register(with: registry)
}
```

On Android all plugins are registered automatically.

### Features: your own native code

Anything specific to one kind of extension – reloading WidgetKit timelines,
starting a Live Activity, updating an app widget – is a *feature*: a small
native class that Dart can call and listen to. There is no method channel, event
channel or plugin to write.

```dart
final widgets = bridge.feature('widgets');
await widgets.invoke<void>('reload', {'kind': 'CounterWidget'});
final kinds = await widgets.invokeList<String>('installedKinds');
widgets.events<Map<Object?, Object?>>('changes').listen(print);
```

```swift
import WidgetKit
import extension_bridge

final class WidgetsFeature: ExtensionBridgeFeature {
  let name = "widgets"

  func handle(_ call: ExtensionBridgeCall) async throws -> Any? {
    switch call.method {
    case "reload":
      WidgetCenter.shared.reloadTimelines(ofKind: try call.requireArgument("kind"))
      return nil
    case "installedKinds":
      return try await WidgetCenter.shared.currentConfigurations().map(\.kind)
    default:
      throw ExtensionBridgeError.notImplemented(call)
    }
  }

  // Optional: event streams.
  func listen(to stream: String, arguments: Any?, sink: ExtensionBridgeEventSink) throws
    -> ExtensionBridgeSubscription
  {
    let observer = NotificationCenter.default.addObserver(
      forName: .someChange, object: nil, queue: .main
    ) { _ in sink.send(["changed": true]) }
    return ExtensionBridgeSubscription { NotificationCenter.default.removeObserver(observer) }
  }
}

// AppDelegate.application(_:didFinishLaunchingWithOptions:)
ExtensionBridgePlugin.register(feature: WidgetsFeature())
```

```kotlin
class WidgetsFeature : ExtensionBridgeFeature {
  override val name = "widgets"

  override suspend fun handle(call: ExtensionBridgeCall): Any? =
      when (call.method) {
        "reload" -> CounterWidget.updateAll(call.context)
        else -> throw ExtensionBridgeException.notImplemented(call)
      }
}

// Application.onCreate() – so it is also available to background isolates.
ExtensionBridgePlugin.registerFeature(WidgetsFeature())
```

For one-off calls a closure is enough:

```swift
ExtensionBridgePlugin.register(feature: "widgets") { _ in
  WidgetCenter.shared.reloadAllTimelines()
  return nil
}
```

Errors thrown natively (`ExtensionBridgeError` / `ExtensionBridgeException`)
arrive in Dart as `ExtensionBridgeException` with the same code, message and
details.

## Setup

### iOS

1. Add the **App Groups** capability with your group to the Runner target and
   to every extension target.
2. To use the Swift helpers from an extension (widget, Live Activity, share
   extension, …), add the plugin's Swift package to that target and link
   **only** the `ExtensionBridgeKit` product – it has no Flutter dependency.
   After `flutter build ios` the package is symlinked to
   `ios/Flutter/ephemeral/Packages/.packages/extension_bridge-<version>`
   (*File ▸ Add Package Dependencies… ▸ Add Local…*). Prefer not to? The
   helpers are thin; extensions can use the conventions directly:
   values live in `UserDefaults(suiteName: appGroup)` under the keys used in
   Dart, files in the `extension_bridge` directory of the App Group
   container, and links need the `extension_bridge` query parameter.
3. Register your features in `AppDelegate`:

```swift
import extension_bridge

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ExtensionBridgePlugin.register(feature: WidgetsFeature())
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  // …
}
```

### macOS

Same as iOS, using `macos/`. Sandboxed apps need the App Groups entitlement;
on macOS the group identifier is usually prefixed with your Team ID.

### Android

Nothing to configure. `appGroup` names the `SharedPreferences` file and the
files directory, so the same Dart code works unchanged. The background receiver
is declared by the plugin.

## Recipes

### Home screen widget (iOS)

```swift
struct Provider: TimelineProvider {
  let storage = ExtensionBridgeStorage(appGroup: "group.com.example.app")

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let entry = Entry(date: .now, counter: storage.integer(forKey: "counter") ?? 0)
    completion(Timeline(entries: [entry], policy: .never))
  }
  // …
}

struct CounterView: View {
  let entry: Entry
  var body: some View {
    VStack {
      Text("\(entry.counter)")
      Button(intent: IncrementIntent()) { Text("+") } // iOS 17 interactive widget
    }
    .widgetURL(ExtensionBridgeLink.url("myapp://counter", source: "widget"))
  }
}
```

The intent runs in the app process and calls Dart:

```swift
struct IncrementIntent: AppIntent {
  static let title: LocalizedStringResource = "Increment"

  func perform() async throws -> some IntentResult {
    try await ExtensionBridgeBackground.dispatch("increment")
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}
```

### Home screen widget (Android)

See [`CounterWidgetProvider.kt`](example/android/app/src/main/kotlin/com/nikodembernat/extension_bridge_example/CounterWidgetProvider.kt)
in the example: it reads the counter with `ExtensionBridgeStorage`, opens the
app with `ExtensionBridgeLinks.pendingIntent` and increments in Dart with
`ExtensionBridgeBackground.pendingIntent`.

### Live Activities

Define your `ActivityAttributes` natively and expose start/update/end as a
feature; images go through shared files:

```dart
await bridge.files.write('driver.png', avatarBytes);
final id = await bridge.feature('delivery').invoke<String>('start', {'eta': 15});
bridge.feature('delivery').events<String>('pushToken', {'id': id}).listen(sendToServer);
```

```swift
final class DeliveryFeature: ExtensionBridgeFeature {
  let name = "delivery"

  func handle(_ call: ExtensionBridgeCall) async throws -> Any? {
    switch call.method {
    case "start":
      let activity = try Activity.request(
        attributes: DeliveryAttributes(),
        content: .init(state: .init(eta: try call.requireArgument("eta")), staleDate: nil),
        pushType: .token)
      return activity.id
    default:
      throw ExtensionBridgeError.notImplemented(call)
    }
  }
}
```

### Share extension

The extension saves what was shared into the App Group:

```swift
let files = ExtensionBridgeFiles(appGroup: "group.com.example.app")
try files.write(imageData, to: "shared/\(UUID().uuidString).jpg")
ExtensionBridgeStorage(appGroup: "group.com.example.app").set("Look at this!", forKey: "sharedText")
```

and the app picks it up when it starts or resumes:

```dart
final text = await bridge.storage.get<String>('sharedText');
final images = (await bridge.files.list()).where((it) => it.startsWith('shared/'));
```

Extensions that are allowed to open their app (widgets, Live Activities, App
Intents, action extensions) can additionally use `ExtensionBridgeLink` so the
app reacts immediately through `ExtensionBridge.links`.

## Example

The [example](example) app shares a counter with a real Android home screen
widget, increments it from a background isolate, saves files, and registers an
`example` feature on Android, iOS and macOS. Its
[integration tests](example/integration_test/extension_bridge_test.dart) run on
all six platforms in [CI](.github/workflows/ci.yml).

## Development

```sh
flutter pub get            # resolves the package and the example (pub workspace)
dart analyze               # leancode_lint
flutter test               # unit tests (VM)
flutter test --platform chrome
cd example && flutter test integration_test -d <device>
```
