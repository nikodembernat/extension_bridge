#if os(iOS)
  import Flutter
  import Foundation

  /// Runs the Dart background callback registered with
  /// `ExtensionBridge.registerBackgroundCallback`.
  ///
  /// Use it from code that runs in the app process while Flutter may not be
  /// on screen, typically an App Intent performed by an interactive widget or
  /// Live Activity:
  ///
  /// ```swift
  /// struct IncrementIntent: AppIntent {
  ///   static let title: LocalizedStringResource = "Increment"
  ///
  ///   func perform() async throws -> some IntentResult {
  ///     try await ExtensionBridgeBackground.dispatch("increment")
  ///     return .result()
  ///   }
  /// }
  /// ```
  ///
  /// The first dispatch starts a headless Flutter engine, which is kept for
  /// later dispatches.
  @MainActor
  public enum ExtensionBridgeBackground {
    private static let dispatcherKey = "extension_bridge.background.dispatcher"
    private static let callbackKey = "extension_bridge.background.callback"

    private static var engine: FlutterEngine?
    private static var channel: FlutterMethodChannel?
    private static var isReady = false
    private static var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private static var pluginRegistrant: ((FlutterPluginRegistry) -> Void)?

    /// Sets how plugins are registered with the background engine.
    ///
    /// By default only `extension_bridge` is available in the background
    /// isolate. Pass `GeneratedPluginRegistrant.register(with:)` to make every
    /// plugin of the app available:
    ///
    /// ```swift
    /// ExtensionBridgeBackground.setPluginRegistrant { registry in
    ///   GeneratedPluginRegistrant.register(with: registry)
    /// }
    /// ```
    public static func setPluginRegistrant(_ registrant: @escaping (FlutterPluginRegistry) -> Void)
    {
      pluginRegistrant = registrant
    }

    /// Whether a background callback has been registered from Dart.
    nonisolated public static var hasCallback: Bool {
      UserDefaults.standard.object(forKey: callbackKey) != nil
    }

    /// Calls the Dart background callback with a `BackgroundEvent` named
    /// `name` and returns what the callback returned.
    ///
    /// `arguments` and the result must be supported by the standard message
    /// codec. Errors thrown in Dart are rethrown as `ExtensionBridgeError`.
    @discardableResult
    public static func dispatch(_ name: String, arguments: Any? = nil) async throws -> Any? {
      let defaults = UserDefaults.standard
      guard let callback = (defaults.object(forKey: callbackKey) as? NSNumber)?.int64Value
      else {
        throw ExtensionBridgeError(
          code: "no-background-callback",
          message:
            "No background callback is registered. "
            + "Call ExtensionBridge.registerBackgroundCallback in Dart first.")
      }
      let channel = try startEngine()
      await waitUntilReady()

      let payload: [String: Any] = [
        "callback": NSNumber(value: callback),
        "name": name,
        "arguments": ExtensionBridgePlugin.toFlutter(arguments),
      ]
      return try await withCheckedThrowingContinuation { continuation in
        channel.invokeMethod("dispatch", arguments: payload) { result in
          if let error = result as? FlutterError {
            continuation.resume(
              throwing: ExtensionBridgeError(
                code: error.code, message: error.message, details: error.details))
          } else if (result as AnyObject?) === FlutterMethodNotImplemented {
            continuation.resume(
              throwing: ExtensionBridgeError(
                code: ExtensionBridgeError.notImplementedCode,
                message: "The background isolate is not handling dispatches."))
          } else {
            continuation.resume(returning: result is NSNull ? nil : result)
          }
        }
      }
    }

    nonisolated static func saveHandles(dispatcher: Int64, callback: Int64) {
      let defaults = UserDefaults.standard
      defaults.set(NSNumber(value: dispatcher), forKey: dispatcherKey)
      defaults.set(NSNumber(value: callback), forKey: callbackKey)
    }

    private static func startEngine() throws -> FlutterMethodChannel {
      if let channel { return channel }

      guard
        let dispatcher = (UserDefaults.standard.object(forKey: dispatcherKey) as? NSNumber)?
          .int64Value,
        let information = FlutterCallbackCache.lookupCallbackInformation(dispatcher)
      else {
        throw ExtensionBridgeError(
          code: "no-background-callback",
          message: "The background dispatcher could not be found. Launch the app once.")
      }

      let engine = FlutterEngine(
        name: "extension_bridge_background", project: nil, allowHeadlessExecution: true)
      guard
        engine.run(
          withEntrypoint: information.callbackName,
          libraryURI: information.callbackLibraryPath)
      else {
        throw ExtensionBridgeError(
          code: "background-engine-failed", message: "The background engine did not start.")
      }

      ExtensionBridgePlugin.isRegisteringBackgroundEngine = true
      if let pluginRegistrant {
        pluginRegistrant(engine)
      } else if let registrar = engine.registrar(forPlugin: "ExtensionBridgePlugin") {
        ExtensionBridgePlugin.register(with: registrar)
      }
      ExtensionBridgePlugin.isRegisteringBackgroundEngine = false

      let channel = FlutterMethodChannel(
        name: "extension_bridge/background", binaryMessenger: engine.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "ready" else {
          return result(FlutterMethodNotImplemented)
        }
        MainActor.assumeIsolated { markReady() }
        result(nil)
      }

      self.engine = engine
      self.channel = channel
      return channel
    }

    private static func waitUntilReady() async {
      guard !isReady else { return }
      await withCheckedContinuation { continuation in
        readyWaiters.append(continuation)
      }
    }

    private static func markReady() {
      isReady = true
      let waiters = readyWaiters
      readyWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
  }
#endif
