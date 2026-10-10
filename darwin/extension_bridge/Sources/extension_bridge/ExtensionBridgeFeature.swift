import Foundation

/// Native code that Dart can call through `bridge.feature(name)`.
///
/// Implement this protocol for anything the bridge does not do by itself,
/// such as reloading WidgetKit timelines or starting a Live Activity, and
/// register it once, for example in `AppDelegate`:
///
/// ```swift
/// final class WidgetsFeature: ExtensionBridgeFeature {
///   let name = "widgets"
///
///   func handle(_ call: ExtensionBridgeCall) async throws -> Any? {
///     switch call.method {
///     case "reload":
///       WidgetCenter.shared.reloadAllTimelines()
///       return nil
///     default:
///       throw ExtensionBridgeError.notImplemented(call)
///     }
///   }
/// }
///
/// ExtensionBridgePlugin.register(feature: WidgetsFeature())
/// ```
///
/// Features are isolated to the main actor.
@MainActor
public protocol ExtensionBridgeFeature: AnyObject {
  /// The name Dart uses to reach this feature.
  var name: String { get }

  /// Handles a call made with `ExtensionFeature.invoke` in Dart.
  ///
  /// The returned value is sent back to Dart and must be supported by the
  /// standard message codec. Throw an `ExtensionBridgeError` to fail the call
  /// with a specific code.
  func handle(_ call: ExtensionBridgeCall) async throws -> Any?

  /// Starts the event stream `stream`, requested with
  /// `ExtensionFeature.events` in Dart.
  ///
  /// Send events through `sink` until the returned subscription is cancelled,
  /// which happens when Dart stops listening. The default implementation
  /// throws `ExtensionBridgeError.notImplemented`.
  func listen(
    to stream: String,
    arguments: Any?,
    sink: ExtensionBridgeEventSink
  ) throws -> ExtensionBridgeSubscription
}

extension ExtensionBridgeFeature {
  public func listen(
    to stream: String,
    arguments: Any?,
    sink: ExtensionBridgeEventSink
  ) throws -> ExtensionBridgeSubscription {
    throw ExtensionBridgeError(
      code: ExtensionBridgeError.notImplementedCode,
      message: "Feature \"\(name)\" has no stream \"\(stream)\".")
  }
}

/// A feature implemented with closures, for when a class is overkill.
///
/// ```swift
/// ExtensionBridgePlugin.register(feature: "widgets") { call in
///   WidgetCenter.shared.reloadAllTimelines()
///   return nil
/// }
/// ```
public final class ExtensionBridgeClosureFeature: ExtensionBridgeFeature {
  public let name: String
  private let handler: @MainActor (ExtensionBridgeCall) async throws -> Any?

  /// Creates a feature called `name` that handles calls with `handler`.
  public init(
    name: String,
    handler: @escaping @MainActor (ExtensionBridgeCall) async throws -> Any?
  ) {
    self.name = name
    self.handler = handler
  }

  public func handle(_ call: ExtensionBridgeCall) async throws -> Any? {
    try await handler(call)
  }
}

/// A method call coming from Dart.
public struct ExtensionBridgeCall {
  /// The name of the called method.
  public let method: String

  /// The arguments passed from Dart, or `nil`.
  public let arguments: Any?

  /// Creates a call. Only needed in tests.
  public init(method: String, arguments: Any?) {
    self.method = method
    self.arguments = arguments is NSNull ? nil : arguments
  }

  /// The argument called `key` when the arguments are a map.
  public func argument<T>(_ key: String) -> T? {
    (arguments as? [String: Any])?[key] as? T
  }

  /// The argument called `key`, or an `invalid-arguments` error when it is
  /// missing or has another type.
  public func requireArgument<T>(_ key: String) throws -> T {
    guard let value: T = argument(key) else {
      throw ExtensionBridgeError(
        code: ExtensionBridgeError.invalidArgumentsCode,
        message: "Method \"\(method)\" requires a \(T.self) argument \"\(key)\".")
    }
    return value
  }
}

/// An error sent back to Dart, where it becomes an `ExtensionBridgeException`
/// with the same code, message and details.
public struct ExtensionBridgeError: Error, CustomStringConvertible {
  /// The code used when a feature does not implement a method or stream.
  public static let notImplementedCode = "not-implemented"
  /// The code used when the arguments of a call are invalid.
  public static let invalidArgumentsCode = "invalid-arguments"
  /// The code used when a feature is not available on this platform.
  public static let unsupportedCode = "unsupported"

  /// A machine readable error code.
  public let code: String
  /// A human readable description.
  public let message: String?
  /// Additional, codec compatible details.
  public let details: Any?

  /// Creates an error.
  public init(code: String, message: String? = nil, details: Any? = nil) {
    self.code = code
    self.message = message
    self.details = details
  }

  /// The error for a method a feature does not implement.
  public static func notImplemented(_ call: ExtensionBridgeCall) -> ExtensionBridgeError {
    ExtensionBridgeError(
      code: notImplementedCode, message: "Method \"\(call.method)\" is not implemented.")
  }

  public var description: String {
    "ExtensionBridgeError(\(code)\(message.map { ", \($0)" } ?? ""))"
  }
}

/// Sends events of one stream to Dart. Safe to use from any thread.
public final class ExtensionBridgeEventSink {
  private let onEvent: (Any?) -> Void
  private let onError: (ExtensionBridgeError) -> Void
  private let onEnd: () -> Void

  /// Creates a sink. Only needed in tests.
  public init(
    onEvent: @escaping (Any?) -> Void,
    onError: @escaping (ExtensionBridgeError) -> Void,
    onEnd: @escaping () -> Void
  ) {
    self.onEvent = onEvent
    self.onError = onError
    self.onEnd = onEnd
  }

  /// Sends a codec compatible event.
  public func send(_ event: Any?) {
    onMain { self.onEvent(event) }
  }

  /// Sends an error, which Dart receives as an `ExtensionBridgeException`.
  public func fail(_ error: ExtensionBridgeError) {
    onMain { self.onError(error) }
  }

  /// Closes the stream.
  public func end() {
    onMain { self.onEnd() }
  }

  private func onMain(_ action: @escaping () -> Void) {
    if Thread.isMainThread {
      action()
    } else {
      DispatchQueue.main.async(execute: action)
    }
  }
}

/// A running event stream, cancelled when Dart stops listening.
public final class ExtensionBridgeSubscription {
  private var onCancel: (() -> Void)?

  /// Creates a subscription that calls `onCancel` once when cancelled.
  public init(onCancel: @escaping () -> Void = {}) {
    self.onCancel = onCancel
  }

  /// Stops the stream. Calling this more than once has no effect.
  public func cancel() {
    let action = onCancel
    onCancel = nil
    action?()
  }
}
