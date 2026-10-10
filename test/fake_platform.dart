import 'dart:async';

import 'package:extension_bridge/extension_bridge_platform_interface.dart';

/// An in-memory [ExtensionBridgePlatform] for tests.
class FakeExtensionBridgePlatform() extends ExtensionBridgePlatform {
  /// Values per app group.
  final values = <String?, Map<String, Object>>{};

  /// The directory reported for shared files.
  String? filesDirectory;

  /// The link reported as initial link.
  String? initialLink;

  /// Pushes links to [links].
  final linkController = StreamController<String>.broadcast();

  /// The last registered background handles.
  (int, int)? backgroundHandles;

  @override
  Future<Object?> getValue(String? appGroup, String key) async =>
      values[appGroup]?[key];

  @override
  Future<Map<String, Object>> getAllValues(String? appGroup) async =>
      Map.of(values[appGroup] ?? {});

  @override
  Future<void> setValue(String? appGroup, String key, Object value) async =>
      (values[appGroup] ??= {})[key] = value;

  @override
  Future<void> removeValue(String? appGroup, String key) async =>
      values[appGroup]?.remove(key);

  @override
  Future<void> clearValues(String? appGroup) async => values.remove(appGroup);

  @override
  Future<String?> getFilesDirectory(String? appGroup) async => filesDirectory;

  @override
  Future<String?> getInitialLink() async => initialLink;

  @override
  Stream<String> get links => linkController.stream;

  @override
  Future<Object?> invokeFeature(
    String feature,
    String method,
    Object? arguments,
  ) async => [feature, method, arguments];

  @override
  Stream<Object?> featureEvents(
    String feature,
    String stream,
    Object? arguments,
  ) => Stream.fromIterable([feature, stream, arguments]);

  @override
  Future<bool> isBackgroundExecutionSupported() async => true;

  @override
  Future<void> registerBackgroundCallback({
    required int dispatcherHandle,
    required int callbackHandle,
  }) async => backgroundHandles = (dispatcherHandle, callbackHandle);
}
