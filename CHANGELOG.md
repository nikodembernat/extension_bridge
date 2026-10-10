## 0.1.0

* Initial release.
* Shared key-value storage (`bridge.storage`) backed by App Group `UserDefaults`
  (iOS, macOS), `SharedPreferences` (Android), a JSON file (Linux, Windows) and
  `localStorage` (web), with matching Swift and Kotlin readers.
* Shared files (`bridge.files`) in the App Group container.
* Extension links (`ExtensionBridge.initialLink`, `ExtensionBridge.links`)
  that never swallow URLs meant for other packages.
* Background Dart callbacks dispatched from native code on Android and iOS.
* Custom native features with methods and event streams, without writing
  channels.
* `ExtensionBridgeKit`, a Flutter-free Swift library for app extensions.
* Swift Package Manager only, no CocoaPods.
