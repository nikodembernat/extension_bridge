import 'dart:async';
import 'dart:ui';

import 'package:extension_bridge/src/background.dart';
import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/extension_feature.dart';
import 'package:extension_bridge/src/extension_link.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';
import 'package:extension_bridge/src/shared_files.dart';
import 'package:extension_bridge/src/shared_storage.dart';
import 'package:flutter/foundation.dart';

/// The entry point of the bridge between Flutter and native app extensions.
///
/// Home screen widgets, Live Activities, share extensions and App Intents all
/// need the same few things from the Flutter side:
///
/// * [storage] – key-value data the extension can read and write,
/// * [files] – files (images, databases, …) the extension can open,
/// * [links] – deep links the extension uses to open the app,
/// * [registerBackgroundCallback] – Dart code the extension can run without
///   opening the app,
/// * [feature] – any custom native code, such as reloading a widget or
///   starting a Live Activity.
///
/// ```dart
/// const bridge = ExtensionBridge(appGroup: 'group.com.example.app');
///
/// await bridge.storage.set('counter', 42);
/// await bridge.feature('widgets').invoke<void>('reload');
/// ```
///
/// On iOS and macOS the [appGroup] has to be an App Group shared by the app
/// and its extensions. Other platforms use it as a namespace, so the same
/// code works everywhere.
@immutable
final class const ExtensionBridge({
  /// The App Group shared with your extensions, for example
  /// `group.com.example.app`.
  ///
  /// When `null`, data stays private to the app on iOS and macOS, which is
  /// still useful for features that run inside the app process (App Intents,
  /// Android widgets) and in tests.
  final String? appGroup,
}) {
  /// Creates a bridge for [appGroup].
  ///
  /// Instances are cheap and hold no state; keeping one in a top level
  /// `const` is the recommended way to use the bridge.
  this;

  /// Key-value storage shared with extensions.
  SharedStorage get storage => SharedStorage(appGroup);

  /// Files shared with extensions.
  SharedFiles get files => SharedFiles(appGroup);

  /// A handle to the native feature registered under [name].
  ExtensionFeature feature(String name) => ExtensionFeature(name);

  /// The extension link that launched the app, if the app was launched by
  /// one.
  ///
  /// Links that arrive while the app is running are delivered by [links].
  static Future<ExtensionLink?> get initialLink async {
    final link = await ExtensionBridgePlatform.instance.getInitialLink();
    return link == null ? null : ExtensionLink.parse(link);
  }

  /// Extension links that open the app while it is running.
  ///
  /// Only URLs marked with [ExtensionLink.markerParameter] are delivered, so
  /// links meant for other parts of the app are left alone.
  static Stream<ExtensionLink> get links =>
      ExtensionBridgePlatform.instance.links.map(ExtensionLink.parse);

  /// Whether native code can run Dart in the background on this platform.
  ///
  /// This is `true` on Android and iOS.
  static Future<bool> get isBackgroundExecutionSupported =>
      ExtensionBridgePlatform.instance.isBackgroundExecutionSupported();

  /// Registers the [callback] that handles background events dispatched by
  /// native code.
  ///
  /// Native code dispatches events with `ExtensionBridgeBackground.dispatch`
  /// (Swift and Kotlin), for example from an interactive widget or an App
  /// Intent. The callback then runs in a separate, headless isolate that is
  /// started on demand, even when the app is not running.
  ///
  /// The registration is persisted, so call this on every app start to keep
  /// it current. [callback] must be a top level or static function annotated
  /// with `@pragma('vm:entry-point')`:
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// Future<Object?> onBackgroundEvent(BackgroundEvent event) async {
  ///   if (event.name == 'increment') {
  ///     final counter = await bridge.storage.get<int>('counter') ?? 0;
  ///     await bridge.storage.set('counter', counter + 1);
  ///   }
  ///   return null;
  /// }
  /// ```
  ///
  /// Throws an [ExtensionBridgeException] with code
  /// [ExtensionBridgeException.unsupported] where background execution is not
  /// available.
  static Future<void> registerBackgroundCallback(
    BackgroundCallback callback,
  ) async {
    if (kIsWeb) {
      throw const ExtensionBridgeException(
        ExtensionBridgeException.unsupported,
        'Background execution is not available on the web.',
      );
    }
    final dispatcherHandle = PluginUtilities.getCallbackHandle(
      extensionBridgeBackgroundMain,
    );
    final callbackHandle = PluginUtilities.getCallbackHandle(callback);
    if (dispatcherHandle == null || callbackHandle == null) {
      throw ArgumentError.value(
        callback,
        'callback',
        "Must be a top level or static function annotated with @pragma('vm:entry-point')",
      );
    }
    await ExtensionBridgePlatform.instance.registerBackgroundCallback(
      dispatcherHandle: dispatcherHandle.toRawHandle(),
      callbackHandle: callbackHandle.toRawHandle(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExtensionBridge && other.appGroup == appGroup;

  @override
  int get hashCode => appGroup.hashCode;

  @override
  String toString() => 'ExtensionBridge(appGroup: $appGroup)';
}
