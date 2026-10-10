/// The platform interface of `extension_bridge`.
///
/// Only needed to implement the bridge for another platform or to replace it
/// with a fake in tests.
library;

export 'src/platform/extension_bridge_platform.dart';
export 'src/platform/method_channel_extension_bridge.dart';
