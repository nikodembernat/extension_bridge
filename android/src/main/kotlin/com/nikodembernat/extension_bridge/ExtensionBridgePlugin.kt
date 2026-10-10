package com.nikodembernat.extension_bridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The Flutter plugin behind `ExtensionBridge` on Android.
 *
 * Apps only interact with it to register features:
 * ```kotlin
 * ExtensionBridgePlugin.registerFeature(WidgetsFeature())
 * ```
 */
class ExtensionBridgePlugin :
    FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {
  companion object {
    private const val CHANNEL_NAME = "extension_bridge"

    private val features = mutableMapOf<String, ExtensionBridgeFeature>()

    /**
     * Makes [feature] callable from Dart with `bridge.feature(feature.name)`.
     *
     * Registering another feature with the same name replaces the previous one. Features are
     * shared by all Flutter engines of the app.
     */
    @JvmStatic
    fun registerFeature(feature: ExtensionBridgeFeature) {
      synchronized(features) { features[feature.name] = feature }
    }

    /** Registers a feature called [name] that handles calls with [handler]. */
    @JvmStatic
    fun registerFeature(name: String, handler: suspend (ExtensionBridgeCall) -> Any?) {
      registerFeature(
          object : ExtensionBridgeFeature {
            override val name = name

            override suspend fun handle(call: ExtensionBridgeCall): Any? = handler(call)
          }
      )
    }

    /** Removes the feature called [name]. */
    @JvmStatic
    fun unregisterFeature(name: String) {
      synchronized(features) { features.remove(name) }
    }

    /** The feature registered under [name], if any. */
    @JvmStatic
    fun feature(name: String): ExtensionBridgeFeature? = synchronized(features) { features[name] }

    private val instances = mutableSetOf<ExtensionBridgePlugin>()

    /**
     * Delivers [uri] to Dart as an `ExtensionLink`, as if the app had been opened with it.
     *
     * Use it where the app is brought to the front without an intent carrying the link. Must be
     * called on the main thread.
     */
    @JvmStatic
    @JvmOverloads
    fun deliverLink(uri: Uri, source: String? = null) {
      val link = ExtensionBridgeLinks.mark(uri, source).toString()
      instances.toList().forEach { it.receive(link) }
    }
  }

  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var activityBinding: ActivityPluginBinding? = null
  private val subscriptions = mutableMapOf<Int, ExtensionBridgeSubscription>()

  /** Links received while Dart was not listening, oldest first. */
  private val pendingLinks = mutableListOf<String>()
  private var initialLink: String? = null
  private var isInitialLinkResolved = false
  private var isListeningToLinks = false

  private val activity: Activity?
    get() = activityBinding?.activity

  // region Lifecycle

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
    channel.setMethodCallHandler(this)
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    instances.add(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    instances.remove(this)
    channel.setMethodCallHandler(null)
    cancelAllSubscriptions()
    scope.cancel()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    val intent = binding.activity.intent
    if (intent != null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) {
      receive(intent)
    }
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onNewIntent(intent: Intent): Boolean = receive(intent)

  // endregion

  // region Method calls

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val appGroup = call.argument<String>("appGroup")
    try {
      when (call.method) {
        "storage.get" -> result.success(storage(appGroup).get(call.requireArgument("key")))
        "storage.getAll" -> result.success(storage(appGroup).getAll())
        "storage.set" -> {
          storage(appGroup).set(call.requireArgument("key"), call.argument<Any>("value"))
          result.success(null)
        }
        "storage.remove" -> {
          storage(appGroup).remove(call.requireArgument("key"))
          result.success(null)
        }
        "storage.clear" -> {
          storage(appGroup).clear()
          result.success(null)
        }
        "files.directory" -> {
          val directory = ExtensionBridgeFiles(context, appGroup).directory
          if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Could not create $directory.")
          }
          result.success(directory.absolutePath)
        }
        "links.initial" -> {
          resolveInitialLink()
          result.success(initialLink)
        }
        "links.listen" -> {
          resolveInitialLink()
          isListeningToLinks = true
          val links = pendingLinks.toList()
          pendingLinks.clear()
          links.forEach(::sendLink)
          result.success(null)
        }
        "links.cancel" -> {
          isListeningToLinks = false
          result.success(null)
        }
        "feature.invoke" -> invokeFeature(call, result)
        "feature.listen" -> listenToFeature(call, result)
        "feature.cancel" -> {
          subscriptions.remove(call.requireArgument<Int>("id"))?.cancel()
          result.success(null)
        }
        "background.isSupported" -> result.success(true)
        "background.register" -> {
          ExtensionBridgeBackground.saveHandles(
              context,
              dispatcher = call.requireArgument<Number>("dispatcher").toLong(),
              callback = call.requireArgument<Number>("callback").toLong(),
          )
          result.success(null)
        }
        "reset" -> {
          cancelAllSubscriptions()
          isListeningToLinks = false
          result.success(null)
        }
        else -> result.notImplemented()
      }
    } catch (error: Exception) {
      result.error(error)
    }
  }

  private fun storage(appGroup: String?) = ExtensionBridgeStorage(context, appGroup)

  private fun invokeFeature(call: MethodCall, result: MethodChannel.Result) {
    val feature = requireFeature(call.requireArgument("feature"))
    val featureCall =
        ExtensionBridgeCall(
            method = call.requireArgument("method"),
            arguments = call.argument<Any>("arguments"),
            context = context,
            activity = activity,
        )
    scope.launch {
      try {
        result.success(feature.handle(featureCall))
      } catch (error: Exception) {
        result.error(error)
      }
    }
  }

  private fun listenToFeature(call: MethodCall, result: MethodChannel.Result) {
    val id = call.requireArgument<Int>("id")
    val feature = requireFeature(call.requireArgument("feature"))
    val sink =
        ExtensionBridgeEventSink(
            onEvent = { event ->
              channel.invokeMethod("feature.onEvent", mapOf("id" to id, "event" to event))
            },
            onError = { error ->
              channel.invokeMethod(
                  "feature.onError",
                  mapOf(
                      "id" to id,
                      "code" to error.code,
                      "message" to error.message,
                      "details" to error.details,
                  ),
              )
            },
            onEnd = {
              subscriptions.remove(id)
              channel.invokeMethod("feature.onDone", mapOf("id" to id))
            },
        )
    subscriptions[id] =
        feature.listen(
            call.requireArgument("stream"),
            call.argument<Any>("arguments"),
            ExtensionBridgeContext(context, activity),
            sink,
        )
    result.success(null)
  }

  private fun requireFeature(name: String): ExtensionBridgeFeature =
      feature(name)
          ?: throw ExtensionBridgeException(
              "feature-not-found",
              "No feature named \"$name\" is registered. " +
                  "Call ExtensionBridgePlugin.registerFeature before using it from Dart.",
          )

  private fun cancelAllSubscriptions() {
    val all = subscriptions.values.toList()
    subscriptions.clear()
    all.forEach { it.cancel() }
  }

  // endregion

  // region Links

  /** Handles an incoming intent and returns whether it carried an extension link. */
  private fun receive(intent: Intent): Boolean {
    val uri = intent.data
    if (!ExtensionBridgeLinks.isExtensionLink(uri)) return false
    receive(uri.toString())
    return true
  }

  private fun receive(link: String) {
    if (isListeningToLinks) sendLink(link) else pendingLinks.add(link)
  }

  /** The first link that arrived before Dart asked for links is the one that launched the app. */
  private fun resolveInitialLink() {
    if (isInitialLinkResolved) return
    isInitialLinkResolved = true
    initialLink = pendingLinks.removeFirstOrNull()
  }

  private fun sendLink(link: String) {
    channel.invokeMethod("links.onLink", link)
  }

  // endregion
}

private fun <T> MethodCall.requireArgument(key: String): T =
    argument<T>(key)
        ?: throw ExtensionBridgeException(
            ExtensionBridgeException.INVALID_ARGUMENTS,
            "Method \"$method\" requires the argument \"$key\".",
        )

private fun MethodChannel.Result.error(exception: Exception) {
  when (exception) {
    is ExtensionBridgeException -> error(exception.code, exception.message, exception.details)
    is IllegalArgumentException ->
        error(ExtensionBridgeException.INVALID_ARGUMENTS, exception.message, null)
    else -> error("native-error", exception.message ?: exception.toString(), exception.toString())
  }
}
