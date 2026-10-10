// File access for platforms without `dart:io`.
//
// It is never reached at runtime: those platforms report no files directory,
// so `SharedFiles` fails before touching the file system.

import 'dart:typed_data';

/// See the `dart:io` implementation.
Future<String> writeFile(String path, Uint8List bytes) =>
    throw UnsupportedError('Files are not supported on this platform.');

/// See the `dart:io` implementation.
Future<Uint8List?> readFile(String path) =>
    throw UnsupportedError('Files are not supported on this platform.');

/// See the `dart:io` implementation.
Future<bool> fileExists(String path) =>
    throw UnsupportedError('Files are not supported on this platform.');

/// See the `dart:io` implementation.
Future<bool> deleteFile(String path) =>
    throw UnsupportedError('Files are not supported on this platform.');

/// See the `dart:io` implementation.
Future<List<String>> listFiles(String directory) =>
    throw UnsupportedError('Files are not supported on this platform.');

/// See the `dart:io` implementation.
Future<void> clearDirectory(String directory) =>
    throw UnsupportedError('Files are not supported on this platform.');
