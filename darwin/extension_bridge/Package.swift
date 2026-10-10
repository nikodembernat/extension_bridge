// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "extension_bridge",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0"),
  ],
  products: [
    // The Flutter plugin. Linked into the app by Flutter automatically.
    .library(name: "extension-bridge", targets: ["extension_bridge"]),
    // Flutter-free helpers for app extensions (widgets, Live Activities,
    // share extensions, ...). Add this product to extension targets.
    .library(name: "ExtensionBridgeKit", targets: ["ExtensionBridgeKit"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "ExtensionBridgeKit",
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    ),
    .target(
      name: "extension_bridge",
      dependencies: [
        "ExtensionBridgeKit",
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    ),
  ]
)
