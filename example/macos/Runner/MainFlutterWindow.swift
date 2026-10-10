import Cocoa
import FlutterMacOS
import extension_bridge

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    ExtensionBridgePlugin.register(feature: ExampleFeature())
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// The native side of `bridge.feature('example')`.
final class ExampleFeature: ExtensionBridgeFeature {
  let name = "example"

  func handle(_ call: ExtensionBridgeCall) async throws -> Any? {
    switch call.method {
    case "platform":
      return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    case "echo":
      return call.arguments
    case "fail":
      throw ExtensionBridgeError(
        code: "example-error", message: "Failure requested from Dart.", details: ["answer": 42])
    case "reloadWidgets":
      // A WidgetKit extension would call WidgetCenter.shared.reloadAllTimelines() here.
      return nil
    case "readStorage":
      let storage = ExtensionBridgeStorage(appGroup: call.argument("appGroup"))
      return storage.value(forKey: try call.requireArgument("key"))
    case "writeStorage":
      let storage = ExtensionBridgeStorage(appGroup: call.argument("appGroup"))
      storage.set("native", forKey: "native.string")
      storage.set(7, forKey: "native.int")
      storage.set(2.5, forKey: "native.double")
      storage.set(true, forKey: "native.bool")
      storage.set(Data([1, 2, 3]), forKey: "native.bytes")
      return nil
    case "readFile":
      let files = ExtensionBridgeFiles(appGroup: call.argument("appGroup"))
      return files.read(try call.requireArgument("name"))
    case "openLink":
      let uri: String = try call.requireArgument("uri")
      guard let url = URL(string: uri) else { throw ExtensionBridgeError.notImplemented(call) }
      ExtensionBridgePlugin.deliverLink(url, source: call.argument("source"))
      return nil
    default:
      throw ExtensionBridgeError.notImplemented(call)
    }
  }

  func listen(to stream: String, arguments: Any?, sink: ExtensionBridgeEventSink) throws
    -> ExtensionBridgeSubscription
  {
    guard stream == "ticks" else {
      throw ExtensionBridgeError(code: ExtensionBridgeError.notImplementedCode)
    }
    let count = (arguments as? [String: Any])?["count"] as? Int ?? 3
    let task = Task { @MainActor in
      for tick in 0..<count {
        try await Task.sleep(nanoseconds: 10_000_000)
        sink.send(tick)
      }
      sink.end()
    }
    return ExtensionBridgeSubscription { task.cancel() }
  }
}
