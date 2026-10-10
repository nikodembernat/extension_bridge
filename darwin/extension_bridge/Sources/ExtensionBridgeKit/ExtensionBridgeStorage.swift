import Foundation

/// Key-value storage shared between the app and its extensions.
///
/// This is the native counterpart of `SharedStorage` in Dart: values written
/// in Dart with `bridge.storage.set(...)` can be read here and vice versa.
///
/// ```swift
/// let storage = ExtensionBridgeStorage(appGroup: "group.com.example.app")
/// let counter = storage.integer(forKey: "counter") ?? 0
/// let profile = try storage.decode(Profile.self, forKey: "profile")
/// ```
///
/// Values live in `UserDefaults(suiteName: appGroup)`. Without an app group a
/// private suite of the app is used, which extensions cannot read.
public struct ExtensionBridgeStorage {
  /// The suite used when no app group is given.
  public static let defaultSuiteName = "extension_bridge"

  /// The app group shared with the extensions, or `nil` for app private
  /// storage.
  public let appGroup: String?

  /// Creates the storage of `appGroup`.
  public init(appGroup: String? = nil) {
    self.appGroup = appGroup
  }

  /// The name of the `UserDefaults` suite holding the values.
  public var suiteName: String { appGroup ?? Self.defaultSuiteName }

  /// The underlying `UserDefaults`.
  ///
  /// Falls back to `UserDefaults.standard` only if the suite cannot be
  /// created, which happens when the suite name equals the bundle identifier.
  public var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

  // MARK: Reading

  /// The raw value stored under `key`.
  public func value(forKey key: String) -> Any? {
    defaults.object(forKey: key)
  }

  /// The string stored under `key`.
  public func string(forKey key: String) -> String? {
    value(forKey: key) as? String
  }

  /// The integer stored under `key`.
  public func integer(forKey key: String) -> Int? {
    guard let number = value(forKey: key) as? NSNumber, !number.isBool else { return nil }
    return number.intValue
  }

  /// The floating point number stored under `key`.
  ///
  /// Integers are converted, so a whole number written as `int` in Dart can
  /// still be read as a `Double`.
  public func double(forKey key: String) -> Double? {
    guard let number = value(forKey: key) as? NSNumber, !number.isBool else { return nil }
    return number.doubleValue
  }

  /// The boolean stored under `key`.
  public func bool(forKey key: String) -> Bool? {
    guard let number = value(forKey: key) as? NSNumber, number.isBool else { return nil }
    return number.boolValue
  }

  /// The bytes stored under `key` (a `Uint8List` in Dart).
  public func data(forKey key: String) -> Data? {
    value(forKey: key) as? Data
  }

  /// Decodes the JSON string stored under `key` (written by `setJson` in
  /// Dart).
  ///
  /// Returns `nil` when nothing is stored and throws when the JSON does not
  /// match `type`.
  public func decode<T: Decodable>(
    _ type: T.Type,
    forKey key: String,
    decoder: JSONDecoder = JSONDecoder()
  ) throws -> T? {
    guard let json = string(forKey: key) else { return nil }
    return try decoder.decode(type, from: Data(json.utf8))
  }

  /// Every value stored by the bridge.
  public func all() -> [String: Any] {
    defaults.persistentDomain(forName: suiteName) ?? [:]
  }

  // MARK: Writing

  /// Stores a string.
  public func set(_ value: String, forKey key: String) {
    defaults.set(value, forKey: key)
  }

  /// Stores an integer.
  public func set(_ value: Int, forKey key: String) {
    defaults.set(value, forKey: key)
  }

  /// Stores a floating point number.
  public func set(_ value: Double, forKey key: String) {
    defaults.set(value, forKey: key)
  }

  /// Stores a boolean.
  public func set(_ value: Bool, forKey key: String) {
    defaults.set(value, forKey: key)
  }

  /// Stores bytes, which Dart reads as `Uint8List`.
  public func set(_ value: Data, forKey key: String) {
    defaults.set(value, forKey: key)
  }

  /// Encodes `value` as a JSON string, which Dart reads with `getJson`.
  public func encode<T: Encodable>(
    _ value: T,
    forKey key: String,
    encoder: JSONEncoder = JSONEncoder()
  ) throws {
    let data = try encoder.encode(value)
    defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
  }

  /// Stores any property list value, or removes the key when `value` is
  /// `nil`.
  public func setValue(_ value: Any?, forKey key: String) {
    if let value, !(value is NSNull) {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  /// Removes the value stored under `key`.
  public func removeValue(forKey key: String) {
    defaults.removeObject(forKey: key)
  }

  /// Removes every value stored by the bridge.
  public func removeAll() {
    for key in all().keys {
      defaults.removeObject(forKey: key)
    }
  }
}

extension NSNumber {
  /// Whether this number is a boxed `Bool` rather than an integer.
  fileprivate var isBool: Bool {
    CFGetTypeID(self) == CFBooleanGetTypeID()
  }
}
