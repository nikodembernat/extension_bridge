import 'dart:async';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The [ExtensionBridgePlatform] used on Android, iOS and macOS.
///
/// Everything goes through a single [MethodChannel]. Streams (links and
/// feature events) are multiplexed over it: Dart asks native code to start a
/// stream with an id, and native code calls back with events tagged with that
/// id. This lets features expose any number of streams without registering an
/// `EventChannel` for each of them.
class MethodChannelExtensionBridge({
  @visibleForTesting
  final MethodChannel _channel = const MethodChannel(channelName),
}) extends ExtensionBridgePlatform {
  /// Creates a [MethodChannelExtensionBridge].
  this;

  /// The name of the method channel shared with the native plugins.
  static const channelName = 'extension_bridge';

  final _subscriptions = <int, StreamController<Object?>>{};
  var _nextSubscriptionId = 0;
  StreamController<String>? _links;
  Future<void>? _handlerInstalled;

  @override
  Future<Object?> getValue(String? appGroup, String key) =>
      _invoke('storage.get', {'appGroup': appGroup, 'key': key});

  @override
  Future<Map<String, Object>> getAllValues(String? appGroup) async {
    final values = await _invoke('storage.getAll', {'appGroup': appGroup});
    return {
      for (final MapEntry(:key, :value) in (values! as Map).entries)
        if (value != null) key as String: value as Object,
    };
  }

  @override
  Future<void> setValue(String? appGroup, String key, Object value) => _invoke(
    'storage.set',
    {'appGroup': appGroup, 'key': key, 'value': value},
  );

  @override
  Future<void> removeValue(String? appGroup, String key) =>
      _invoke('storage.remove', {'appGroup': appGroup, 'key': key});

  @override
  Future<void> clearValues(String? appGroup) =>
      _invoke('storage.clear', {'appGroup': appGroup});

  @override
  Future<String?> getFilesDirectory(String? appGroup) async =>
      await _invoke('files.directory', {'appGroup': appGroup}) as String?;

  @override
  Future<String?> getInitialLink() async =>
      await _invoke('links.initial') as String?;

  @override
  Stream<String> get links {
    return (_links ??= StreamController<String>.broadcast(
      onListen: () async {
        await _ensureHandlerInstalled();
        await _invoke('links.listen');
      },
      onCancel: () => _invoke('links.cancel'),
    )).stream;
  }

  @override
  Future<Object?> invokeFeature(
    String feature,
    String method,
    Object? arguments,
  ) => _invoke('feature.invoke', {
    'feature': feature,
    'method': method,
    'arguments': arguments,
  });

  @override
  Stream<Object?> featureEvents(
    String feature,
    String stream,
    Object? arguments,
  ) {
    final id = _nextSubscriptionId++;
    late final StreamController<Object?> controller;
    controller = StreamController<Object?>(
      onListen: () async {
        _subscriptions[id] = controller;
        try {
          await _ensureHandlerInstalled();
          await _invoke('feature.listen', {
            'id': id,
            'feature': feature,
            'stream': stream,
            'arguments': arguments,
          });
        } on ExtensionBridgeException catch (error, st) {
          _subscriptions.remove(id);
          controller.addError(error, st);
          await controller.close();
        }
      },
      onCancel: () async {
        if (_subscriptions.remove(id) != null) {
          await _invoke('feature.cancel', {'id': id});
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<bool> isBackgroundExecutionSupported() async =>
      await _invoke('background.isSupported') as bool? ?? false;

  @override
  Future<void> registerBackgroundCallback({
    required int dispatcherHandle,
    required int callbackHandle,
  }) => _invoke('background.register', {
    'dispatcher': dispatcherHandle,
    'callback': callbackHandle,
  });

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (exception) {
      throw ExtensionBridgeException.fromPlatformException(exception);
    } on MissingPluginException catch (exception) {
      throw ExtensionBridgeException(
        ExtensionBridgeException.unsupported,
        exception.message ?? 'The extension_bridge plugin is not registered.',
      );
    }
  }

  /// Installs the handler for calls coming from native code.
  ///
  /// The first installation also resets the native state of this engine, so
  /// subscriptions left behind by a hot restart are dropped.
  Future<void> _ensureHandlerInstalled() {
    return _handlerInstalled ??= () async {
      _channel.setMethodCallHandler(_handleNativeCall);
      await _invoke('reset');
    }();
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments;
    switch (call.method) {
      case 'links.onLink':
        _links?.add(arguments! as String);
      case 'feature.onEvent':
        final map = arguments! as Map;
        _subscriptions[map['id']! as int]?.add(map['event']);
      case 'feature.onError':
        final map = arguments! as Map;
        _subscriptions[map['id']! as int]?.addError(
          ExtensionBridgeException(
            map['code']! as String,
            map['message'] as String?,
            map['details'],
          ),
        );
      case 'feature.onDone':
        final map = arguments! as Map;
        await _subscriptions.remove(map['id']! as int)?.close();
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
    return null;
  }
}
