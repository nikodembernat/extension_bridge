package com.nikodembernat.extension_bridge

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Runs the Dart background callback registered with `ExtensionBridge.registerBackgroundCallback`.
 *
 * Use it from code that may run while Flutter is not on screen, such as an app widget, a service
 * or a broadcast receiver:
 * ```kotlin
 * val result = ExtensionBridgeBackground.dispatch(context, "increment")
 * ```
 *
 * App widgets usually do not call it directly but use [pendingIntent], which dispatches through
 * [ExtensionBridgeBackgroundReceiver] when tapped.
 *
 * The first dispatch starts a headless Flutter engine, which is kept for later dispatches.
 */
object ExtensionBridgeBackground {
  private const val TAG = "ExtensionBridge"
  private const val PREFERENCES = "extension_bridge.background"
  private const val DISPATCHER_KEY = "dispatcher"
  private const val CALLBACK_KEY = "callback"
  internal const val EXTRA_NAME = "com.nikodembernat.extension_bridge.extra.NAME"
  internal const val EXTRA_ARGUMENTS = "com.nikodembernat.extension_bridge.extra.ARGUMENTS"

  private var engine: FlutterEngine? = null
  private var channel: MethodChannel? = null
  private var isReady = false
  private val readyWaiters = mutableListOf<() -> Unit>()

  /** Whether a background callback has been registered from Dart. */
  @JvmStatic
  fun hasCallback(context: Context): Boolean =
      preferences(context).getLong(CALLBACK_KEY, 0L) != 0L

  /**
   * Calls the Dart background callback with a `BackgroundEvent` named [name] and returns what the
   * callback returned.
   *
   * [arguments] and the result must be supported by the standard message codec.
   *
   * @throws ExtensionBridgeException when no callback is registered or the callback failed.
   */
  suspend fun dispatch(context: Context, name: String, arguments: Any? = null): Any? =
      withContext(Dispatchers.Main) {
        val applicationContext = context.applicationContext
        val callback = preferences(applicationContext).getLong(CALLBACK_KEY, 0L)
        if (callback == 0L) {
          throw ExtensionBridgeException(
              "no-background-callback",
              "No background callback is registered. " +
                  "Call ExtensionBridge.registerBackgroundCallback in Dart first.",
          )
        }
        val channel = startEngine(applicationContext)
        awaitReady()
        suspendCancellableCoroutine { continuation ->
          channel.invokeMethod(
              "dispatch",
              mapOf("callback" to callback, "name" to name, "arguments" to arguments),
              object : MethodChannel.Result {
                override fun success(result: Any?) = continuation.resume(result)

                override fun error(code: String, message: String?, details: Any?) =
                    continuation.resumeWithException(
                        ExtensionBridgeException(code, message, details)
                    )

                override fun notImplemented() =
                    continuation.resumeWithException(
                        ExtensionBridgeException(
                            ExtensionBridgeException.NOT_IMPLEMENTED,
                            "The background isolate is not handling dispatches.",
                        )
                    )
              },
          )
        }
      }

  /**
   * Like [dispatch], but reports the result to [onResult] instead of suspending, for Java callers
   * and code without coroutines.
   */
  @JvmStatic
  @JvmOverloads
  fun dispatchAsync(
      context: Context,
      name: String,
      arguments: Any? = null,
      onResult: (Result<Any?>) -> Unit = {},
  ) {
    CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
      onResult(runCatching { dispatch(context, name, arguments) })
    }
  }

  /**
   * A [PendingIntent] that dispatches [name] in the background when sent, for example when an app
   * widget button is tapped.
   *
   * [arguments] may contain strings, numbers and booleans and reach Dart as a map.
   */
  @JvmStatic
  @JvmOverloads
  fun pendingIntent(
      context: Context,
      name: String,
      arguments: Map<String, Any?> = emptyMap(),
  ): PendingIntent {
    val bundle = Bundle()
    for ((key, value) in arguments) {
      when (value) {
        null -> bundle.putString(key, null)
        is String -> bundle.putString(key, value)
        is Int -> bundle.putInt(key, value)
        is Long -> bundle.putLong(key, value)
        is Double -> bundle.putDouble(key, value)
        is Float -> bundle.putFloat(key, value)
        is Boolean -> bundle.putBoolean(key, value)
        else -> throw IllegalArgumentException("Unsupported argument type for \"$key\".")
      }
    }
    val intent =
        Intent(context, ExtensionBridgeBackgroundReceiver::class.java)
            .putExtra(EXTRA_NAME, name)
            .putExtra(EXTRA_ARGUMENTS, bundle)
    return PendingIntent.getBroadcast(
        context,
        (name + arguments.toSortedMap()).hashCode(),
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  internal fun saveHandles(context: Context, dispatcher: Long, callback: Long) {
    preferences(context)
        .edit()
        .putLong(DISPATCHER_KEY, dispatcher)
        .putLong(CALLBACK_KEY, callback)
        .apply()
  }

  private fun preferences(context: Context) =
      context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

  private fun startEngine(context: Context): MethodChannel {
    channel?.let {
      return it
    }

    val loader = FlutterInjector.instance().flutterLoader()
    if (!loader.initialized()) {
      loader.startInitialization(context)
    }
    loader.ensureInitializationComplete(context, null)

    val dispatcher = preferences(context).getLong(DISPATCHER_KEY, 0L)
    val information =
        FlutterCallbackInformation.lookupCallbackInformation(dispatcher)
            ?: throw ExtensionBridgeException(
                "no-background-callback",
                "The background dispatcher could not be found. Launch the app once.",
            )

    val engine = FlutterEngine(context)
    val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "extension_bridge/background")
    channel.setMethodCallHandler { call, result ->
      if (call.method == "ready") {
        markReady()
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
    engine.dartExecutor.executeDartCallback(
        DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), information)
    )

    this.engine = engine
    this.channel = channel
    return channel
  }

  private suspend fun awaitReady() {
    if (isReady) return
    suspendCancellableCoroutine { continuation ->
      readyWaiters.add { continuation.resume(Unit) }
    }
  }

  private fun markReady() {
    isReady = true
    val waiters = readyWaiters.toList()
    readyWaiters.clear()
    waiters.forEach { it() }
  }

  internal fun log(message: String, error: Throwable? = null) {
    Log.w(TAG, message, error)
  }
}

/**
 * Dispatches background events sent with [ExtensionBridgeBackground.pendingIntent].
 *
 * Declared in the plugin's manifest, so apps do not need to register it.
 */
class ExtensionBridgeBackgroundReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val name = intent.getStringExtra(ExtensionBridgeBackground.EXTRA_NAME) ?: return
    @Suppress("DEPRECATION")
    val bundle = intent.getBundleExtra(ExtensionBridgeBackground.EXTRA_ARGUMENTS)
    val arguments = bundle?.keySet()?.associateWith { @Suppress("DEPRECATION") bundle.get(it) }

    val pendingResult = goAsync()
    ExtensionBridgeBackground.dispatchAsync(context, name, arguments) { result ->
      result.exceptionOrNull()?.let {
        ExtensionBridgeBackground.log("Background event \"$name\" failed.", it)
      }
      pendingResult.finish()
    }
  }
}
