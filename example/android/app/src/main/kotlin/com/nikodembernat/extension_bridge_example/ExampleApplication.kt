package com.nikodembernat.extension_bridge_example

import android.app.Application
import com.nikodembernat.extension_bridge.ExtensionBridgePlugin

/**
 * Registers the native features of the example.
 *
 * Features are registered in the Application rather than the Activity, so they are also available
 * when a home screen widget starts the background isolate without opening the app.
 */
class ExampleApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    ExtensionBridgePlugin.registerFeature(ExampleFeature())
  }
}
