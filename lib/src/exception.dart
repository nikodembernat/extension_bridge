import 'package:flutter/services.dart';

/// An error reported by the native side of the bridge or by a feature.
///
/// Every platform reports failures with this single type, so callers can catch
/// it without depending on [PlatformException] or a platform specific error.
class const ExtensionBridgeException(
  /// A machine readable error code.
  ///
  /// The bridge itself uses the constants defined on this class. Features may
  /// use any code they like.
  final String code, [

  /// A human readable description of the error.
  final String? message,

  /// Additional, codec compatible details about the error.
  final Object? details,
]) implements Exception {
  /// Creates an [ExtensionBridgeException].
  this;

  /// Converts a [PlatformException] coming from a method channel.
  factory fromPlatformException(PlatformException exception) =>
      ExtensionBridgeException(
        exception.code,
        exception.message,
        exception.details,
      );

  /// The feature or method is not available on the current platform.
  static const unsupported = 'unsupported';

  /// The arguments passed to a call were invalid.
  static const invalidArguments = 'invalid-arguments';

  /// No native feature with the requested name was registered.
  static const featureNotFound = 'feature-not-found';

  /// A native feature does not implement the requested method or stream.
  static const notImplemented = 'not-implemented';

  /// A stored value does not have the requested type.
  static const typeMismatch = 'type-mismatch';

  /// A background callback was dispatched before one was registered.
  static const noBackgroundCallback = 'no-background-callback';

  @override
  String toString() => [
    'ExtensionBridgeException($code',
    if (message != null) ', $message',
    if (details != null) ', $details',
    ')',
  ].join();
}
