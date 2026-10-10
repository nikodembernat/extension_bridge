import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Something native code asked Dart to do while the app may be in the
/// background, for example a button tap in an interactive widget or an App
/// Intent being performed.
@immutable
final class const BackgroundEvent({
  /// The name native code dispatched, for example `increment`.
  required final String name,

  /// Codec compatible arguments sent with the event.
  final Object? arguments,
}) {
  /// Creates a [BackgroundEvent].
  this;

  @override
  bool operator ==(Object other) =>
      other is BackgroundEvent &&
      other.name == name &&
      other.arguments == arguments;

  @override
  int get hashCode => Object.hash(name, arguments);

  @override
  String toString() => 'BackgroundEvent($name, $arguments)';
}

/// Handles [BackgroundEvent]s in a background isolate.
///
/// The returned value is sent back to native code, so an App Intent can, for
/// example, read a result computed in Dart. It must be codec compatible.
///
/// The function must be a top level or static function annotated with
/// `@pragma('vm:entry-point')`, because it is looked up by a callback handle
/// from a fresh isolate.
typedef BackgroundCallback = FutureOr<Object?> Function(BackgroundEvent event);

/// The channel between the background isolate and the native plugin.
@internal
const backgroundChannel = MethodChannel('extension_bridge/background');

/// The entry point of the background isolate started by native code.
@internal
@pragma('vm:entry-point')
Future<void> extensionBridgeBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  backgroundChannel.setMethodCallHandler((call) async {
    if (call.method != 'dispatch') {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    final arguments = call.arguments as Map<Object?, Object?>;
    final handle = CallbackHandle.fromRawHandle(arguments['callback']! as int);
    final callback = PluginUtilities.getCallbackFromHandle(handle);
    if (callback is! BackgroundCallback) {
      throw PlatformException(
        code: 'no-background-callback',
        message:
            'The registered background callback could not be found. '
            'Is it a top level or static function annotated with '
            "@pragma('vm:entry-point')?",
      );
    }
    return await callback(
      BackgroundEvent(
        name: arguments['name']! as String,
        arguments: arguments['arguments'],
      ),
    );
  });

  await backgroundChannel.invokeMethod<void>('ready');
}
