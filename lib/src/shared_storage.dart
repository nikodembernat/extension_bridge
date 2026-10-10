import 'dart:convert';
import 'dart:typed_data';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';

/// Key-value storage shared between the app and its extensions.
///
/// | Platform      | Backed by                                             |
/// | ------------- | ----------------------------------------------------- |
/// | iOS, macOS    | `UserDefaults(suiteName: appGroup)`                   |
/// | Android       | `SharedPreferences` named after the app group         |
/// | Linux, Windows| A JSON file in the application support directory      |
/// | Web           | `localStorage`                                        |
///
/// Supported values are `bool`, `int`, `double`, `String` and `Uint8List`.
/// Anything else can be stored as JSON with [setJson].
///
/// Native code reads the same values through `ExtensionBridgeStorage`, which
/// exists for Swift (in `ExtensionBridgeKit`) and Kotlin.
final class const SharedStorage(
  /// The app group this storage belongs to, or `null` for the app's own
  /// storage.
  final String? appGroup,
) {
  /// Creates the storage of [appGroup]. Prefer `ExtensionBridge.storage`.
  this;

  ExtensionBridgePlatform get _platform => ExtensionBridgePlatform.instance;

  /// Reads the value stored under [key].
  ///
  /// Returns `null` when nothing is stored. Throws an
  /// [ExtensionBridgeException] with code
  /// [ExtensionBridgeException.typeMismatch] when the stored value is not a
  /// [T].
  Future<T?> get<T extends Object>(String key) async {
    final value = await _platform.getValue(appGroup, key);
    return switch (value) {
      null => null,
      final T value => value,
      // Doubles that hold a whole number may come back as `int` on the web.
      final int value when T == double => value.toDouble() as T,
      _ => throw ExtensionBridgeException(
        ExtensionBridgeException.typeMismatch,
        'Value of "$key" is ${value.runtimeType}, not $T.',
      ),
    };
  }

  /// Reads and decodes a value stored with [setJson].
  Future<Object?> getJson(String key) async {
    final json = await get<String>(key);
    return json == null ? null : jsonDecode(json);
  }

  /// Reads every stored value.
  Future<Map<String, Object>> getAll() => _platform.getAllValues(appGroup);

  /// Whether a value is stored under [key].
  Future<bool> containsKey(String key) async =>
      await _platform.getValue(appGroup, key) != null;

  /// Stores [value] under [key], or removes the key when [value] is `null`.
  ///
  /// Throws an [ArgumentError] for unsupported types.
  Future<void> set(String key, Object? value) {
    _validateKey(key);
    return switch (value) {
      null => remove(key),
      bool() ||
      int() ||
      double() ||
      String() ||
      Uint8List() => _platform.setValue(appGroup, key, value),
      _ => throw ArgumentError.value(
        value,
        'value',
        'Only bool, int, double, String and Uint8List can be stored. '
            'Use setJson for other values',
      ),
    };
  }

  /// Stores [value] encoded as a JSON string, or removes the key when
  /// [value] is `null`.
  ///
  /// Read it back with [getJson]. Native code can decode the string with
  /// `Codable` (Swift) or any JSON library (Kotlin).
  Future<void> setJson(String key, Object? value) =>
      set(key, value == null ? null : jsonEncode(value));

  /// Removes the value stored under [key].
  Future<void> remove(String key) => _platform.removeValue(appGroup, key);

  /// Removes every stored value.
  Future<void> clear() => _platform.clearValues(appGroup);

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Must not be empty');
    }
  }
}
