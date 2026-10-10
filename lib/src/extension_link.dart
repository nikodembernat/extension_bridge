import 'package:meta/meta.dart';

/// A deep link that opened the app from an app extension.
///
/// Native code marks a URL as an extension link by adding the
/// [markerParameter] query parameter to it, optionally with a [source] value.
/// The helpers `ExtensionBridgeLinks` (Kotlin) and `ExtensionBridgeLink`
/// (Swift) do that for you. URLs without the marker are left to the rest of
/// the app (other plugins, Flutter's own deep linking), so the bridge never
/// swallows links it does not own.
@immutable
final class const ExtensionLink({
  /// The link without the [markerParameter].
  required final Uri uri,

  /// Which extension opened the app, for example `widget` or `live_activity`.
  ///
  /// This is the value of the [markerParameter], or `null` when it was empty.
  final String? source,
}) {
  /// Creates an [ExtensionLink].
  this;

  /// Parses a raw link reported by the native side.
  ///
  /// The [markerParameter] is removed from [ExtensionLink.uri] and its value is
  /// exposed as [ExtensionLink.source].
  factory parse(String raw) {
    final uri = Uri.parse(raw);
    final parameters = Map.of(uri.queryParametersAll);
    final marker = parameters.remove(markerParameter);
    final source = marker?.firstWhere((it) => it.isNotEmpty, orElse: () => '');

    return ExtensionLink(
      uri: parameters.isEmpty
          ? _withoutQuery(uri)
          : uri.replace(queryParameters: parameters),
      source: source == null || source.isEmpty ? null : source,
    );
  }

  /// The query parameter that marks a URL as an extension link.
  static const markerParameter = 'extension_bridge';

  static Uri _withoutQuery(Uri uri) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.hasAuthority ? uri.host : null,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    fragment: uri.hasFragment ? uri.fragment : null,
  );

  @override
  bool operator ==(Object other) =>
      other is ExtensionLink && other.uri == uri && other.source == source;

  @override
  int get hashCode => Object.hash(uri, source);

  @override
  String toString() => 'ExtensionLink($uri, source: $source)';
}
