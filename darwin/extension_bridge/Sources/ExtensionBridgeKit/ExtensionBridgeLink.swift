import Foundation

/// Builds deep links that open the app and reach Dart as `ExtensionLink`s.
///
/// The bridge only handles URLs marked with the `extension_bridge` query
/// parameter, so links meant for other parts of the app are left alone.
///
/// ```swift
/// // In a widget:
/// .widgetURL(ExtensionBridgeLink.url("myapp://counter", source: "widget"))
/// ```
///
/// The URL scheme (`myapp` above) must be registered in the app's
/// `Info.plist` under `CFBundleURLTypes`.
public enum ExtensionBridgeLink {
  /// The query parameter that marks a URL as an extension link.
  public static let markerParameter = "extension_bridge"

  /// Marks `url` as an extension link.
  ///
  /// `source` tells Dart which extension opened the app, for example
  /// `widget` or `live_activity`.
  public static func url(_ url: URL, source: String? = nil) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    var items = (components.queryItems ?? []).filter { $0.name != markerParameter }
    items.append(URLQueryItem(name: markerParameter, value: source ?? ""))
    components.queryItems = items
    return components.url ?? url
  }

  /// Parses `string` and marks it as an extension link.
  public static func url(_ string: String, source: String? = nil) -> URL? {
    URL(string: string).map { url($0, source: source) }
  }

  /// Whether `url` is marked as an extension link.
  public static func isExtensionLink(_ url: URL) -> Bool {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .contains { $0.name == markerParameter } ?? false
  }
}
