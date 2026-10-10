package com.nikodembernat.extension_bridge_example

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import com.nikodembernat.extension_bridge.ExtensionBridgeBackground
import com.nikodembernat.extension_bridge.ExtensionBridgeLinks
import com.nikodembernat.extension_bridge.ExtensionBridgeStorage

/**
 * A home screen widget showing the shared counter.
 *
 * Tapping the counter opens the app with an extension link, tapping "+" increments the counter in
 * the Dart background callback without opening the app.
 */
class CounterWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
    val storage = ExtensionBridgeStorage(context, APP_GROUP)
    val views =
        RemoteViews(context.packageName, R.layout.counter_widget).apply {
          setTextViewText(R.id.counter, (storage.getLong("counter") ?: 0L).toString())
          setOnClickPendingIntent(
              R.id.counter,
              ExtensionBridgeLinks.pendingIntent(
                  context,
                  Uri.parse("extensionbridge://counter"),
                  source = "widget",
              ),
          )
          setOnClickPendingIntent(
              R.id.increment,
              ExtensionBridgeBackground.pendingIntent(context, "increment"),
          )
        }
    manager.updateAppWidget(widgetIds, views)
  }

  companion object {
    const val APP_GROUP = "group.com.nikodembernat.extensionBridgeExample"

    /** Redraws every counter widget. */
    fun updateAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(ComponentName(context, CounterWidgetProvider::class.java))
      if (ids.isNotEmpty()) {
        CounterWidgetProvider().onUpdate(context, manager, ids)
      }
    }
  }
}
