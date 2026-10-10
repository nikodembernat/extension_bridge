@_exported import ExtensionBridgeKit
import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
  import AppKit
#endif

/// The Flutter plugin behind `ExtensionBridge` on iOS and macOS.
///
/// Apps only interact with it to register features:
///
/// ```swift
/// ExtensionBridgePlugin.register(feature: WidgetsFeature())
/// ```
public final class ExtensionBridgePlugin: NSObject, FlutterPlugin {
  static let channelName = "extension_bridge"

  // MARK: Feature registry

  @MainActor private static var features: [String: ExtensionBridgeFeature] = [:]

  /// Makes `feature` callable from Dart with `bridge.feature(feature.name)`.
  ///
  /// Registering another feature with the same name replaces the previous
  /// one. Features are shared by all Flutter engines of the app.
  @MainActor
  public static func register(feature: ExtensionBridgeFeature) {
    features[feature.name] = feature
  }

  /// Registers a feature called `name` that handles calls with `handler`.
  @MainActor
  public static func register(
    feature name: String,
    handler: @escaping @MainActor (ExtensionBridgeCall) async throws -> Any?
  ) {
    register(feature: ExtensionBridgeClosureFeature(name: name, handler: handler))
  }

  /// Removes the feature called `name`.
  @MainActor
  public static func unregister(feature name: String) {
    features.removeValue(forKey: name)
  }

  /// The feature registered under `name`, if any.
  @MainActor
  public static func feature(named name: String) -> ExtensionBridgeFeature? {
    features[name]
  }

  // MARK: Links

  private static let instances = NSHashTable<ExtensionBridgePlugin>.weakObjects()

  /// Delivers `url` to Dart as an `ExtensionLink`, as if the app had been
  /// opened with it.
  ///
  /// Use it where the system opens the app without a URL, for example in an
  /// App Intent with `openAppWhenRun`:
  ///
  /// ```swift
  /// func perform() async throws -> some IntentResult {
  ///   ExtensionBridgePlugin.deliverLink(URL(string: "myapp://timer")!, source: "intent")
  ///   return .result()
  /// }
  /// ```
  @MainActor
  public static func deliverLink(_ url: URL, source: String? = nil) {
    let link = ExtensionBridgeLink.url(url, source: source)
    for instance in instances.allObjects {
      instance.receive(link)
    }
  }

  // MARK: Registration

  /// Set while plugins are registered with the background engine, which must
  /// not receive app lifecycle events.
  static var isRegisteringBackgroundEngine = false

  private let channel: FlutterMethodChannel
  private var subscriptions: [Int: ExtensionBridgeSubscription] = [:]

  /// Links received while Dart was not listening, oldest first.
  private var pendingLinks: [String] = []
  private var initialLink: String?
  private var isInitialLinkResolved = false
  private var isListeningToLinks = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = ExtensionBridgePlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)

    guard !isRegisteringBackgroundEngine else { return }
    instances.add(instance)
    registrar.addApplicationDelegate(instance)
    #if os(iOS)
      registrar.addSceneDelegate(instance)
    #endif
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    Self.instances.remove(self)
    cancelAllSubscriptions()
  }

  // MARK: Method calls

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let appGroup = arguments["appGroup"] as? String

    switch call.method {
    case "storage.get":
      let key = arguments["key"] as? String ?? ""
      result(Self.toFlutter(storage(appGroup).value(forKey: key)))
    case "storage.getAll":
      result(Self.toFlutter(storage(appGroup).all()))
    case "storage.set":
      guard let key = arguments["key"] as? String, let value = arguments["value"] else {
        return result(Self.invalidArguments(call))
      }
      storage(appGroup).setValue(Self.fromFlutter(value), forKey: key)
      result(nil)
    case "storage.remove":
      storage(appGroup).removeValue(forKey: arguments["key"] as? String ?? "")
      result(nil)
    case "storage.clear":
      storage(appGroup).removeAll()
      result(nil)
    case "files.directory":
      result(filesDirectory(appGroup))
    case "links.initial":
      resolveInitialLink()
      result(initialLink)
    case "links.listen":
      resolveInitialLink()
      isListeningToLinks = true
      let links = pendingLinks
      pendingLinks.removeAll()
      links.forEach(sendLink)
      result(nil)
    case "links.cancel":
      isListeningToLinks = false
      result(nil)
    case "feature.invoke":
      invokeFeature(arguments, result: result)
    case "feature.listen":
      listenToFeature(arguments, result: result)
    case "feature.cancel":
      if let id = arguments["id"] as? Int {
        subscriptions.removeValue(forKey: id)?.cancel()
      }
      result(nil)
    case "background.isSupported":
      #if os(iOS)
        result(true)
      #else
        result(false)
      #endif
    case "background.register":
      registerBackgroundCallback(arguments, result: result)
    case "reset":
      cancelAllSubscriptions()
      isListeningToLinks = false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func storage(_ appGroup: String?) -> ExtensionBridgeStorage {
    Self.warnIfAppGroupIsUnavailable(appGroup)
    return ExtensionBridgeStorage(appGroup: appGroup)
  }

  private func filesDirectory(_ appGroup: String?) -> Any? {
    guard let directory = ExtensionBridgeFiles(appGroup: appGroup).directory else {
      return FlutterError(
        code: "app-group-unavailable",
        message:
          "The container of app group \"\(appGroup ?? "")\" is not available. "
          + "Add the App Groups capability with this group to the app target.",
        details: nil)
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.path
    } catch {
      return FlutterError(
        code: "io-error", message: error.localizedDescription, details: nil)
    }
  }

  private static var checkedAppGroups: Set<String> = []

  /// Logs a hint when an app group is used without the App Groups
  /// capability, because `UserDefaults` then silently keeps data private.
  private static func warnIfAppGroupIsUnavailable(_ appGroup: String?) {
    guard let appGroup, !checkedAppGroups.contains(appGroup) else { return }
    checkedAppGroups.insert(appGroup)
    if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) == nil {
      NSLog(
        "[extension_bridge] App group \"%@\" is not available, so its data is not shared "
          + "with extensions. Add the App Groups capability with this group to the app target.",
        appGroup)
    }
  }

  // MARK: Features

  private func invokeFeature(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let name = arguments["feature"] as? String,
      let method = arguments["method"] as? String
    else {
      return result(FlutterError(code: "invalid-arguments", message: nil, details: nil))
    }
    let call = ExtensionBridgeCall(method: method, arguments: arguments["arguments"])
    Task { @MainActor in
      guard let feature = Self.features[name] else {
        return result(Self.featureNotFound(name))
      }
      do {
        result(Self.toFlutter(try await feature.handle(call)))
      } catch {
        result(Self.flutterError(error))
      }
    }
  }

  private func listenToFeature(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let id = arguments["id"] as? Int,
      let name = arguments["feature"] as? String,
      let stream = arguments["stream"] as? String
    else {
      return result(FlutterError(code: "invalid-arguments", message: nil, details: nil))
    }
    let streamArguments = arguments["arguments"] is NSNull ? nil : arguments["arguments"]
    Task { @MainActor in
      guard let feature = Self.features[name] else {
        return result(Self.featureNotFound(name))
      }
      let sink = ExtensionBridgeEventSink(
        onEvent: { [weak self] event in
          self?.channel.invokeMethod(
            "feature.onEvent", arguments: ["id": id, "event": Self.toFlutter(event)])
        },
        onError: { [weak self] error in
          self?.channel.invokeMethod(
            "feature.onError",
            arguments: [
              "id": id,
              "code": error.code,
              "message": error.message ?? NSNull(),
              "details": Self.toFlutter(error.details),
            ])
        },
        onEnd: { [weak self] in
          self?.subscriptions.removeValue(forKey: id)
          self?.channel.invokeMethod("feature.onDone", arguments: ["id": id])
        })
      do {
        self.subscriptions[id] = try feature.listen(
          to: stream, arguments: streamArguments, sink: sink)
        result(nil)
      } catch {
        result(Self.flutterError(error))
      }
    }
  }

  private func cancelAllSubscriptions() {
    let all = subscriptions.values
    subscriptions.removeAll()
    all.forEach { $0.cancel() }
  }

  // MARK: Background

  private func registerBackgroundCallback(
    _ arguments: [String: Any], result: @escaping FlutterResult
  ) {
    #if os(iOS)
      guard let dispatcher = (arguments["dispatcher"] as? NSNumber)?.int64Value,
        let callback = (arguments["callback"] as? NSNumber)?.int64Value
      else {
        return result(FlutterError(code: "invalid-arguments", message: nil, details: nil))
      }
      ExtensionBridgeBackground.saveHandles(dispatcher: dispatcher, callback: callback)
      result(nil)
    #else
      result(
        FlutterError(
          code: ExtensionBridgeError.unsupportedCode,
          message: "Background execution is not available on macOS.", details: nil))
    #endif
  }

  // MARK: Links

  /// Handles an incoming URL and returns whether it was an extension link.
  @discardableResult
  func receive(_ url: URL) -> Bool {
    guard ExtensionBridgeLink.isExtensionLink(url) else { return false }
    let link = url.absoluteString
    if isListeningToLinks {
      sendLink(link)
    } else {
      pendingLinks.append(link)
    }
    return true
  }

  /// The first link that arrived before Dart asked for links is the one that
  /// launched the app.
  private func resolveInitialLink() {
    guard !isInitialLinkResolved else { return }
    isInitialLinkResolved = true
    if !pendingLinks.isEmpty {
      initialLink = pendingLinks.removeFirst()
    }
  }

  private func sendLink(_ link: String) {
    channel.invokeMethod("links.onLink", arguments: link)
  }

  // MARK: Codec helpers

  /// Converts native values into values the standard message codec accepts.
  static func toFlutter(_ value: Any?) -> Any {
    switch value {
    case nil, is NSNull:
      return NSNull()
    case let data as Data:
      return FlutterStandardTypedData(bytes: data)
    case let date as Date:
      return ISO8601DateFormatter().string(from: date)
    case let url as URL:
      return url.absoluteString
    case let array as [Any]:
      return array.map { toFlutter($0) }
    case let dictionary as [String: Any]:
      return dictionary.mapValues { toFlutter($0) }
    case let value?:
      return value
    }
  }

  /// Converts values decoded by the standard message codec into property
  /// list compatible values.
  static func fromFlutter(_ value: Any) -> Any? {
    switch value {
    case is NSNull:
      return nil
    case let data as FlutterStandardTypedData:
      return data.data
    default:
      return value
    }
  }

  static func flutterError(_ error: Error) -> FlutterError {
    if let error = error as? ExtensionBridgeError {
      return FlutterError(
        code: error.code, message: error.message, details: toFlutter(error.details))
    }
    return FlutterError(
      code: "native-error", message: error.localizedDescription, details: "\(error)")
  }

  private static func featureNotFound(_ name: String) -> FlutterError {
    FlutterError(
      code: "feature-not-found",
      message:
        "No feature named \"\(name)\" is registered. "
        + "Call ExtensionBridgePlugin.register(feature:) before using it from Dart.",
      details: nil)
  }

  private static func invalidArguments(_ call: FlutterMethodCall) -> FlutterError {
    FlutterError(
      code: "invalid-arguments", message: "Invalid arguments for \(call.method).", details: nil)
  }
}

// MARK: - Lifecycle

#if os(iOS)
  extension ExtensionBridgePlugin: FlutterSceneLifeCycleDelegate {
    public func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
    ) -> Bool {
      if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
        receive(url)
      }
      return true
    }

    public func application(
      _ application: UIApplication,
      open url: URL,
      options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
      receive(url)
    }

    public func scene(
      _ scene: UIScene,
      willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
      var handled = false
      for context in connectionOptions?.urlContexts ?? [] where receive(context.url) {
        handled = true
      }
      return handled
    }

    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool
    {
      var handled = false
      for context in URLContexts where receive(context.url) {
        handled = true
      }
      return handled
    }
  }
#elseif os(macOS)
  extension ExtensionBridgePlugin: FlutterAppLifecycleDelegate {
    @objc(handleOpenURLs:)
    public func handleOpen(_ urls: [URL]) -> Bool {
      var handled = false
      for url in urls where receive(url) {
        handled = true
      }
      return handled
    }
  }
#endif
