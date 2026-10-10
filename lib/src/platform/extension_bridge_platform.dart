import 'package:extension_bridge/src/platform/method_channel_extension_bridge.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that every platform implementation of the bridge extends.
///
/// App code uses `ExtensionBridge` instead. This class is public so platform
/// implementations and tests can replace [instance].
///
/// Values crossing this interface are limited to what the standard message
/// codec supports. Storage values are additionally limited to `bool`, `int`,
/// `double`, `String` and `Uint8List`.
abstract class ExtensionBridgePlatform() extends PlatformInterface {
  /// Constructs an [ExtensionBridgePlatform].
  this : super(token: _token);

  static final Object _token = Object();

  static ExtensionBridgePlatform _instance = MethodChannelExtensionBridge();

  /// The implementation used by `ExtensionBridge`.
  ///
  /// Defaults to [MethodChannelExtensionBridge], which talks to the Android,
  /// iOS and macOS plugins. Linux, Windows and web register their own.
  static ExtensionBridgePlatform get instance => _instance;

  static set instance(ExtensionBridgePlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Reads the value stored under [key], or `null` if there is none.
  Future<Object?> getValue(String? appGroup, String key);

  /// Reads every stored value.
  Future<Map<String, Object>> getAllValues(String? appGroup);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> setValue(String? appGroup, String key, Object value);

  /// Removes the value stored under [key].
  Future<void> removeValue(String? appGroup, String key);

  /// Removes every stored value.
  Future<void> clearValues(String? appGroup);

  /// The absolute path of the directory shared with app extensions.
  ///
  /// Returns `null` when the platform has no file system.
  Future<String?> getFilesDirectory(String? appGroup);

  /// The extension link that launched the app, if any.
  Future<String?> getInitialLink();

  /// Extension links received while the app is running.
  Stream<String> get links;

  /// Calls [method] on the native feature registered under [feature].
  Future<Object?> invokeFeature(
    String feature,
    String method,
    Object? arguments,
  );

  /// Listens to the [stream] of the native feature registered under
  /// [feature].
  Stream<Object?> featureEvents(
    String feature,
    String stream,
    Object? arguments,
  );

  /// Whether native code can run Dart in the background on this platform.
  Future<bool> isBackgroundExecutionSupported();

  /// Persists the raw callback handles used to start a background isolate.
  Future<void> registerBackgroundCallback({
    required int dispatcherHandle,
    required int callbackHandle,
  });
}
