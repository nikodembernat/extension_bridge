import 'dart:async';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';

/// A handle to a native feature registered with the bridge.
///
/// Features are how you add your own native code, for example reloading
/// WidgetKit timelines, starting a Live Activity or donating an App Intent,
/// without writing a plugin, method channel or event channel yourself.
///
/// Register the native side once (Swift shown, Kotlin works the same way):
///
/// ```swift
/// ExtensionBridgePlugin.register(feature: WidgetsFeature())
/// ```
///
/// and talk to it from Dart:
///
/// ```dart
/// final widgets = bridge.feature('widgets');
/// await widgets.invoke<void>('reload', {'kind': 'CounterWidget'});
/// widgets.events('installed').listen(print);
/// ```
///
/// Native errors arrive as [ExtensionBridgeException]s. Calling a feature
/// that was never registered fails with
/// [ExtensionBridgeException.featureNotFound].
final class const ExtensionFeature(
  /// The name the native feature was registered with.
  final String name,
) {
  /// Creates a handle to the native feature called [name].
  this;

  /// Calls [method] on the native feature and returns its result.
  ///
  /// [arguments] and the result can be anything the standard message codec
  /// supports: `null`, `bool`, `int`, `double`, `String`, typed data, and
  /// lists and maps of those.
  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    final result = await ExtensionBridgePlatform.instance.invokeFeature(
      name,
      method,
      arguments,
    );
    return result as T?;
  }

  /// Calls [method] and casts the resulting list to `List<T>`.
  Future<List<T>?> invokeList<T>(String method, [Object? arguments]) async =>
      (await invoke<List<Object?>>(method, arguments))?.cast<T>();

  /// Calls [method] and casts the resulting map to `Map<K, V>`.
  Future<Map<K, V>?> invokeMap<K, V>(
    String method, [
    Object? arguments,
  ]) async =>
      (await invoke<Map<Object?, Object?>>(method, arguments))?.cast<K, V>();

  /// Listens to the native event [stream] of this feature.
  ///
  /// The native side starts producing events when the returned stream is
  /// listened to and stops when the subscription is cancelled. Every call
  /// creates an independent subscription.
  Stream<T> events<T>(String stream, [Object? arguments]) =>
      ExtensionBridgePlatform.instance
          .featureEvents(name, stream, arguments)
          .cast<T>();

  @override
  String toString() => 'ExtensionFeature($name)';
}
