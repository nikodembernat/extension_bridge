import 'dart:typed_data';

import 'package:extension_bridge/src/exception.dart';
import 'package:extension_bridge/src/platform/extension_bridge_platform.dart';
import 'package:extension_bridge/src/platform/files/file_access.dart';

/// Files shared between the app and its extensions.
///
/// | Platform      | Directory                                                |
/// | ------------- | -------------------------------------------------------- |
/// | iOS, macOS    | `extension_bridge` in the app group container            |
/// | Android       | `extension_bridge/<app group>` in the app's files dir    |
/// | Linux, Windows| `extension_bridge/<app group>/files` in app support dir  |
/// | Web           | Not supported                                            |
///
/// Without an app group the app's own directories are used on iOS and macOS,
/// which extensions cannot read. Names are relative paths such as
/// `avatar.png` or `images/avatar.png`.
///
/// Native code resolves the same names through `ExtensionBridgeFiles`, which
/// exists for Swift (in `ExtensionBridgeKit`) and Kotlin.
final class const SharedFiles(
  /// The app group these files belong to, or `null` for the app's own files.
  final String? appGroup,
) {
  /// Creates the files of [appGroup]. Prefer `ExtensionBridge.files`.
  this;

  /// The absolute path of the shared directory.
  ///
  /// Throws an [ExtensionBridgeException] with code
  /// [ExtensionBridgeException.unsupported] on the web.
  Future<String> get directory async {
    final directory = await ExtensionBridgePlatform.instance.getFilesDirectory(
      appGroup,
    );
    if (directory == null) {
      throw const ExtensionBridgeException(
        ExtensionBridgeException.unsupported,
        'Shared files are not available on this platform.',
      );
    }
    return directory;
  }

  /// The absolute path of the file called [name].
  ///
  /// The file does not have to exist. This is the path native code gets for
  /// the same name, so it can be stored and handed to an extension.
  Future<String> pathOf(String name) async =>
      '${await directory}/${_validateName(name)}';

  /// Writes [bytes] to the file called [name] and returns its absolute path.
  ///
  /// The file is replaced atomically, so an extension never reads a partially
  /// written file.
  Future<String> write(String name, Uint8List bytes) async =>
      await writeFile(await pathOf(name), bytes);

  /// Reads the file called [name], or returns `null` if it does not exist.
  Future<Uint8List?> read(String name) async =>
      await readFile(await pathOf(name));

  /// Whether the file called [name] exists.
  Future<bool> exists(String name) async =>
      await fileExists(await pathOf(name));

  /// Deletes the file called [name] and returns whether it existed.
  Future<bool> delete(String name) async =>
      await deleteFile(await pathOf(name));

  /// The names of all shared files, sorted.
  Future<List<String>> list() async => await listFiles(await directory);

  /// Deletes all shared files.
  Future<void> clear() async => await clearDirectory(await directory);

  static String _validateName(String name) {
    final segments = name.split(RegExp(r'[/\\]'));
    if (name.isEmpty ||
        name.startsWith('/') ||
        segments.any((it) => it.isEmpty || it == '.' || it == '..')) {
      throw ArgumentError.value(
        name,
        'name',
        'Must be a relative path without empty, "." or ".." segments',
      );
    }
    return segments.join('/');
  }
}
