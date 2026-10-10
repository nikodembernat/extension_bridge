import Foundation

/// Files shared between the app and its extensions.
///
/// This is the native counterpart of `SharedFiles` in Dart: a file written in
/// Dart with `bridge.files.write('avatar.png', bytes)` is found here under the
/// same name.
///
/// ```swift
/// let files = ExtensionBridgeFiles(appGroup: "group.com.example.app")
/// if let data = files.read("avatar.png"), let image = UIImage(data: data) {
///   ...
/// }
/// ```
///
/// Files live in the `extension_bridge` directory of the app group container.
/// Without an app group the app's own Application Support directory is used,
/// which extensions cannot read.
public struct ExtensionBridgeFiles {
  /// The app group shared with the extensions, or `nil` for app private
  /// files.
  public let appGroup: String?

  /// Creates the files of `appGroup`.
  public init(appGroup: String? = nil) {
    self.appGroup = appGroup
  }

  /// The directory holding the shared files.
  ///
  /// `nil` when the app group container is not available, which usually
  /// means the App Groups capability is missing from the target.
  public var directory: URL? {
    let fileManager = FileManager.default
    if let appGroup {
      return fileManager
        .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
        .appendingPathComponent("extension_bridge", isDirectory: true)
    }
    guard
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { return nil }
    return
      applicationSupport
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "extension_bridge", isDirectory: true)
      .appendingPathComponent("extension_bridge", isDirectory: true)
      .appendingPathComponent("default", isDirectory: true)
  }

  /// The URL of the file called `name`, which does not have to exist.
  public func url(for name: String) -> URL? {
    directory?.appendingPathComponent(name, isDirectory: false)
  }

  /// Reads the file called `name`.
  public func read(_ name: String) -> Data? {
    guard let url = url(for: name) else { return nil }
    return try? Data(contentsOf: url)
  }

  /// Whether the file called `name` exists.
  public func exists(_ name: String) -> Bool {
    guard let url = url(for: name) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  /// Atomically writes `data` to the file called `name` and returns its URL.
  @discardableResult
  public func write(_ data: Data, to name: String) throws -> URL {
    guard let url = url(for: name) else { throw CocoaError(.fileNoSuchFile) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return url
  }

  /// Deletes the file called `name` and returns whether it existed.
  @discardableResult
  public func delete(_ name: String) throws -> Bool {
    guard let url = url(for: name), FileManager.default.fileExists(atPath: url.path) else {
      return false
    }
    try FileManager.default.removeItem(at: url)
    return true
  }
}
