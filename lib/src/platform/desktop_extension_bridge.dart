import 'dart:async';
import 'dart:io';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';
import 'package:extension_bridge/src/platform/stored_value_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The [ExtensionBridgePlatform] used on Linux and Windows.
///
/// These platforms have no app extensions, so everything stays inside the
/// app: values live in a JSON file and shared files in a directory, both under
/// the application support directory. Native features, links and background
/// execution are not available and report
/// [ExtensionBridgeException.unsupported].
class ExtensionBridgeDesktop({
  @visibleForTesting Future<Directory> Function()? rootDirectory,
}) extends ExtensionBridgePlatform {
  /// Creates an [ExtensionBridgeDesktop].
  ///
  /// [rootDirectory] overrides where data is kept, which is useful in tests.
  this;

  /// Registers this class as the default [ExtensionBridgePlatform].
  static void registerWith() {
    ExtensionBridgePlatform.instance = ExtensionBridgeDesktop();
  }

  final Future<Directory> Function() _rootDirectory =
      rootDirectory ?? _defaultRootDirectory;
  final _locks = <String, Future<void>>{};

  static Future<Directory> _defaultRootDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/extension_bridge',
  );

  Future<Directory> _namespaceDirectory(String? appGroup) async =>
      Directory('${(await _rootDirectory()).path}/${appGroup ?? 'default'}');

  Future<File> _storageFile(String? appGroup) async =>
      File('${(await _namespaceDirectory(appGroup)).path}/storage.json');

  Future<Map<String, Object>> _read(String? appGroup) async {
    final file = await _storageFile(appGroup);
    if (!file.existsSync()) {
      return {};
    }
    try {
      return decodeStoredValues(await file.readAsString());
    } on FormatException {
      return {};
    }
  }

  /// Runs [action] after every earlier storage operation of [appGroup].
  ///
  /// Operations of the same group run one after another, so concurrent
  /// writes never lose each other's changes and reads see completed writes.
  Future<T> _synchronized<T>(
    String? appGroup,
    Future<T> Function() action,
  ) async {
    final key = appGroup ?? '';
    final previous = _locks[key];
    final done = Completer<void>();
    _locks[key] = done.future;
    try {
      await previous;
      return await action();
    } finally {
      done.complete();
      if (identical(_locks[key], done.future)) {
        await _locks.remove(key);
      }
    }
  }

  /// Applies [update] to the stored values of [appGroup] and saves them.
  Future<void> _update(
    String? appGroup,
    void Function(Map<String, Object> values) update,
  ) => _synchronized(appGroup, () async {
    final values = await _read(appGroup);
    update(values);
    final file = await _storageFile(appGroup);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encodeStoredValues(values));
    await temporary.rename(file.path);
  });

  @override
  Future<Object?> getValue(String? appGroup, String key) =>
      _synchronized(appGroup, () async => (await _read(appGroup))[key]);

  @override
  Future<Map<String, Object>> getAllValues(String? appGroup) =>
      _synchronized(appGroup, () => _read(appGroup));

  @override
  Future<void> setValue(String? appGroup, String key, Object value) =>
      _update(appGroup, (values) => values[key] = value);

  @override
  Future<void> removeValue(String? appGroup, String key) =>
      _update(appGroup, (values) => values.remove(key));

  @override
  Future<void> clearValues(String? appGroup) =>
      _update(appGroup, (values) => values.clear());

  @override
  Future<String?> getFilesDirectory(String? appGroup) async {
    final directory = Directory(
      '${(await _namespaceDirectory(appGroup)).path}/files',
    );
    await directory.create(recursive: true);
    return directory.path;
  }

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

  ExtensionBridgeException _unsupported(String subject) =>
      ExtensionBridgeException(
        ExtensionBridgeException.unsupported,
        '$subject not available on ${Platform.operatingSystem}.',
      );
}
