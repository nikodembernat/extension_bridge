package com.nikodembernat.extension_bridge

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * Native code that Dart can call through `bridge.feature(name)`.
 *
 * Implement it for anything the bridge does not do by itself, such as updating an app widget, and
 * register it once, for example in `MainActivity.configureFlutterEngine`:
 * ```kotlin
 * class WidgetsFeature : ExtensionBridgeFeature {
 *   override val name = "widgets"
 *
 *   override suspend fun handle(call: ExtensionBridgeCall): Any? =
 *       when (call.method) {
 *         "reload" -> CounterWidget.updateAll(call.context)
 *         else -> throw ExtensionBridgeException.notImplemented(call)
 *       }
 * }
 *
 * ExtensionBridgePlugin.registerFeature(WidgetsFeature())
 * ```
 *
 * All methods are called on the main thread.
 */
interface ExtensionBridgeFeature {
  /** The name Dart uses to reach this feature. */
  val name: String

  /**
   * Handles a call made with `ExtensionFeature.invoke` in Dart.
   *
   * The returned value is sent back to Dart and must be supported by the standard message codec.
   * Throw an [ExtensionBridgeException] to fail the call with a specific code.
   */
  suspend fun handle(call: ExtensionBridgeCall): Any?

  /**
   * Starts the event stream [stream], requested with `ExtensionFeature.events` in Dart.
   *
   * Send events through [sink] until the returned subscription is cancelled, which happens when
   * Dart stops listening. The default implementation throws a `not-implemented` error.
   */
  fun listen(
      stream: String,
      arguments: Any?,
      context: ExtensionBridgeContext,
      sink: ExtensionBridgeEventSink,
  ): ExtensionBridgeSubscription =
      throw ExtensionBridgeException(
          ExtensionBridgeException.NOT_IMPLEMENTED,
          "Feature \"$name\" has no stream \"$stream\".",
      )
}

/** The Android context a feature runs in. */
open class ExtensionBridgeContext(
    /** The application context. */
    val context: Context,
    /** The activity Flutter is attached to, if any. */
    val activity: Activity?,
)

/** A method call coming from Dart. */
class ExtensionBridgeCall(
    /** The name of the called method. */
    val method: String,
    /** The arguments passed from Dart, or `null`. */
    val arguments: Any?,
    context: Context,
    activity: Activity?,
) : ExtensionBridgeContext(context, activity) {
  /** The argument called [key] when the arguments are a map. */
  inline fun <reified T> argument(key: String): T? = (arguments as? Map<*, *>)?.get(key) as? T

  /**
   * The argument called [key], or an `invalid-arguments` error when it is missing or has another
   * type.
   */
  inline fun <reified T> requireArgument(key: String): T =
      argument<T>(key)
          ?: throw ExtensionBridgeException(
              ExtensionBridgeException.INVALID_ARGUMENTS,
              "Method \"$method\" requires a ${T::class.java.simpleName} argument \"$key\".",
          )
}

/**
 * An error sent back to Dart, where it becomes an `ExtensionBridgeException` with the same code,
 * message and details.
 */
open class ExtensionBridgeException(
    /** A machine readable error code. */
    val code: String,
    message: String? = null,
    /** Additional, codec compatible details. */
    val details: Any? = null,
    cause: Throwable? = null,
) : Exception(message, cause) {
  companion object {
    /** The code used when a feature does not implement a method or stream. */
    const val NOT_IMPLEMENTED = "not-implemented"
    /** The code used when the arguments of a call are invalid. */
    const val INVALID_ARGUMENTS = "invalid-arguments"
    /** The code used when something is not available on this platform. */
    const val UNSUPPORTED = "unsupported"

    /** The error for a method a feature does not implement. */
    fun notImplemented(call: ExtensionBridgeCall) =
        ExtensionBridgeException(NOT_IMPLEMENTED, "Method \"${call.method}\" is not implemented.")
  }
}

/** Sends events of one stream to Dart. Safe to use from any thread. */
class ExtensionBridgeEventSink(
    private val onEvent: (Any?) -> Unit,
    private val onError: (ExtensionBridgeException) -> Unit,
    private val onEnd: () -> Unit,
) {
  private val mainHandler = Handler(Looper.getMainLooper())

  /** Sends a codec compatible event. */
  fun send(event: Any?) = onMain { onEvent(event) }

  /** Sends an error, which Dart receives as an `ExtensionBridgeException`. */
  fun fail(error: ExtensionBridgeException) = onMain { onError(error) }

  /** Closes the stream. */
  fun end() = onMain { onEnd() }

  private fun onMain(action: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) action() else mainHandler.post(action)
  }
}

/** A running event stream, cancelled when Dart stops listening. */
class ExtensionBridgeSubscription(onCancel: () -> Unit = {}) {
  private var onCancel: (() -> Unit)? = onCancel

  /** Stops the stream. Calling this more than once has no effect. */
  fun cancel() {
    val action = onCancel
    onCancel = null
    action?.invoke()
  }
}
