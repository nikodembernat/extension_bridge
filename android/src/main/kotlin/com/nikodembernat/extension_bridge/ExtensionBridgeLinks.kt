package com.nikodembernat.extension_bridge

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Builds deep links that open the app and reach Dart as `ExtensionLink`s.
 *
 * The bridge only handles links marked with the [MARKER_PARAMETER] query parameter, so links meant
 * for other parts of the app are left alone.
 *
 * ```kotlin
 * // In an app widget:
 * views.setOnClickPendingIntent(
 *     R.id.root,
 *     ExtensionBridgeLinks.pendingIntent(context, Uri.parse("myapp://counter"), source = "widget"),
 * )
 * ```
 */
object ExtensionBridgeLinks {
  /** The query parameter that marks a URI as an extension link. */
  const val MARKER_PARAMETER = "extension_bridge"

  /** Marks [uri] as an extension link opened by [source], e.g. `widget`. */
  @JvmStatic
  @JvmOverloads
  fun mark(uri: Uri, source: String? = null): Uri {
    val builder = uri.buildUpon().clearQuery()
    for (name in uri.queryParameterNames) {
      if (name == MARKER_PARAMETER) continue
      for (value in uri.getQueryParameters(name)) {
        builder.appendQueryParameter(name, value)
      }
    }
    return builder.appendQueryParameter(MARKER_PARAMETER, source ?: "").build()
  }

  /** Whether [uri] is marked as an extension link. */
  @JvmStatic
  fun isExtensionLink(uri: Uri?): Boolean =
      uri != null && uri.isHierarchical && uri.getQueryParameter(MARKER_PARAMETER) != null

  /**
   * An intent that opens [activity] (the launcher activity by default) with [uri] marked as an
   * extension link.
   */
  @JvmStatic
  @JvmOverloads
  fun intent(
      context: Context,
      uri: Uri,
      source: String? = null,
      activity: Class<out Activity>? = null,
  ): Intent {
    val intent =
        if (activity != null) {
          Intent(context, activity)
        } else {
          context.packageManager.getLaunchIntentForPackage(context.packageName)
              ?: throw IllegalStateException("${context.packageName} has no launcher activity.")
        }
    return intent
        .setAction(Intent.ACTION_VIEW)
        .setData(mark(uri, source))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
  }

  /** A [PendingIntent] for [intent], ready to be used by app widgets and notifications. */
  @JvmStatic
  @JvmOverloads
  fun pendingIntent(
      context: Context,
      uri: Uri,
      source: String? = null,
      activity: Class<out Activity>? = null,
  ): PendingIntent {
    val intent = intent(context, uri, source, activity)
    return PendingIntent.getActivity(
        context,
        intent.data.hashCode(),
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }
}
