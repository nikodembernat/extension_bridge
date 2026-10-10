import 'dart:async';
import 'dart:convert';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';
import 'package:extension_bridge/src/platform/stored_value_codec.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// The [ExtensionBridgePlatform] used on the web.
///
/// Values are kept in `localStorage`, namespaced by app group. The web has no
/// app extensions, no file system and no background isolates, so files,
/// native features, links and background execution are not available.
class ExtensionBridgeWeb({web.Storage? storage})
    extends ExtensionBridgePlatform {
  /// Creates an [ExtensionBridgeWeb].
  this;

  /// Registers this class as the default [ExtensionBridgePlatform].
  static void registerWith(Registrar registrar) {
    ExtensionBridgePlatform.instance = ExtensionBridgeWeb();
  }

  final web.Storage _storage = storage ?? web.window.localStorage;

  static String _prefix(String? appGroup) =>
      'extension_bridge/${appGroup ?? 'default'}/';

  Iterable<String> _keys(String? appGroup) sync* {
    final prefix = _prefix(appGroup);
    for (var index = 0; index < _storage.length; index++) {
      final key = _storage.key(index);
      if (key != null && key.startsWith(prefix)) {
        yield key;
      }
    }
  }

  static Object? _decode(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      return decodeStoredValue(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<Object?> getValue(String? appGroup, String key) async =>
      _decode(_storage.getItem('${_prefix(appGroup)}$key'));

  @override
  Future<Map<String, Object>> getAllValues(String? appGroup) async {
    final prefix = _prefix(appGroup);
    return {
      for (final key in _keys(appGroup).toList())
        if (_decode(_storage.getItem(key)) case final Object value)
          key.substring(prefix.length): value,
    };
  }

  @override
  Future<void> setValue(String? appGroup, String key, Object value) async {
    _storage.setItem(
      '${_prefix(appGroup)}$key',
      jsonEncode(encodeStoredValue(value)),
    );
  }

  @override
  Future<void> removeValue(String? appGroup, String key) async {
    _storage.removeItem('${_prefix(appGroup)}$key');
  }

  @override
  Future<void> clearValues(String? appGroup) async {
    // Interop members cannot be torn off, hence the closure.
    // ignore: unnecessary_lambdas
    _keys(appGroup).toList().forEach((key) => _storage.removeItem(key));
  }

  @override
  Future<String?> getFilesDirectory(String? appGroup) async => null;

  @override
  Future<String?> getInitialLink() async => null;

  @override
  Stream<String> get links => const Stream.empty();

  @override
  Future<Object?> invokeFeature(
    String feature,
    String method,
    Object? arguments,
  ) => Future.error(_unsupported('Native features are'));

  @override
  Stream<Object?> featureEvents(
    String feature,
    String stream,
    Object? arguments,
  ) => Stream.error(_unsupported('Native features are'));

  @override
  Future<bool> isBackgroundExecutionSupported() async => false;

  @override
  Future<void> registerBackgroundCallback({
    required int dispatcherHandle,
    required int callbackHandle,
  }) => Future.error(_unsupported('Background execution is'));

  static ExtensionBridgeException _unsupported(String subject) =>
      ExtensionBridgeException(
        ExtensionBridgeException.unsupported,
        '$subject not available on the web.',
      );
}
