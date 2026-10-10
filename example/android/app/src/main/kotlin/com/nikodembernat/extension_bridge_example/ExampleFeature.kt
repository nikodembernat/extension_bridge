package com.nikodembernat.extension_bridge_example

import android.content.Intent
import android.net.Uri
import android.os.Build
import com.nikodembernat.extension_bridge.ExtensionBridgeBackground
import com.nikodembernat.extension_bridge.ExtensionBridgeCall
import com.nikodembernat.extension_bridge.ExtensionBridgeContext
import com.nikodembernat.extension_bridge.ExtensionBridgeEventSink
import com.nikodembernat.extension_bridge.ExtensionBridgeException
import com.nikodembernat.extension_bridge.ExtensionBridgeFeature
import com.nikodembernat.extension_bridge.ExtensionBridgeFiles
import com.nikodembernat.extension_bridge.ExtensionBridgeLinks
import com.nikodembernat.extension_bridge.ExtensionBridgeStorage
import com.nikodembernat.extension_bridge.ExtensionBridgeSubscription
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The native side of `bridge.feature('example')`. */
class ExampleFeature : ExtensionBridgeFeature {
  override val name = "example"

  override suspend fun handle(call: ExtensionBridgeCall): Any? =
      when (call.method) {
        "platform" -> "Android ${Build.VERSION.RELEASE}"
        "echo" -> call.arguments
        "fail" ->
            throw ExtensionBridgeException(
                "example-error",
                "Failure requested from Dart.",
                mapOf("answer" to 42),
            )
        "reloadWidgets" -> CounterWidgetProvider.updateAll(call.context)
        "readStorage" ->
            ExtensionBridgeStorage(call.context, call.argument("appGroup"))
                .get(call.requireArgument("key"))
        "writeStorage" -> {
          val storage = ExtensionBridgeStorage(call.context, call.argument("appGroup"))
          storage.set("native.string", "native")
          storage.set("native.int", 7L)
          storage.set("native.double", 2.5)
          storage.set("native.bool", true)
          storage.set("native.bytes", byteArrayOf(1, 2, 3))
          null
        }
        "readFile" ->
            ExtensionBridgeFiles(call.context, call.argument("appGroup"))
                .read(call.requireArgument("name"))
        "dispatchBackground" ->
            ExtensionBridgeBackground.dispatch(
                call.context,
                call.requireArgument("name"),
                call.argument<Any>("arguments"),
            )
        "openLink" -> {
          val intent =
              ExtensionBridgeLinks.intent(
                  call.context,
                  Uri.parse(call.requireArgument<String>("uri")),
                  call.argument("source"),
              )
          (call.activity ?: call.context).startActivity(intent)
          null
        }
        else -> throw ExtensionBridgeException.notImplemented(call)
      }

  override fun listen(
      stream: String,
      arguments: Any?,
      context: ExtensionBridgeContext,
      sink: ExtensionBridgeEventSink,
  ): ExtensionBridgeSubscription {
    if (stream != "ticks") return super.listen(stream, arguments, context, sink)

    val count = (arguments as? Map<*, *>)?.get("count") as? Int ?: 3
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    scope.launch {
      for (tick in 0 until count) {
        delay(10)
        sink.send(tick)
      }
      sink.end()
    }
    return ExtensionBridgeSubscription { scope.cancel() }
  }
}
