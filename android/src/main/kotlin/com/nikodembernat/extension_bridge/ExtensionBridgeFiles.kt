package com.nikodembernat.extension_bridge

import android.content.Context
import java.io.File

/**
 * Files shared between the app and its widgets, services and other components.
 *
 * This is the native counterpart of `SharedFiles` in Dart: a file written in Dart with
 * `bridge.files.write('avatar.png', bytes)` is found here under the same name.
 *
 * ```kotlin
 * val files = ExtensionBridgeFiles(context, appGroup = "group.com.example.app")
 * val avatar = BitmapFactory.decodeFile(files.file("avatar.png").path)
 * ```
 */
class ExtensionBridgeFiles
@JvmOverloads
constructor(
    context: Context,
    /** The app group used as namespace, or `null` for the default one. */
    val appGroup: String? = null,
) {
  /** The directory holding the shared files. */
  val directory: File =
      File(context.applicationContext.filesDir, "extension_bridge/${appGroup ?: "default"}")

  /** The file called [name], which does not have to exist. */
  fun file(name: String): File = File(directory, name)

  /** Reads the file called [name], or returns `null` if it does not exist. */
  fun read(name: String): ByteArray? = file(name).takeIf { it.isFile }?.readBytes()

  /** Whether the file called [name] exists. */
  fun exists(name: String): Boolean = file(name).isFile

  /** Atomically writes [bytes] to the file called [name] and returns it. */
  fun write(name: String, bytes: ByteArray): File {
    val target = file(name)
    target.parentFile?.mkdirs()
    val temporary = File(target.path + ".extension_bridge.tmp")
    temporary.writeBytes(bytes)
    if (!temporary.renameTo(target)) {
      temporary.copyTo(target, overwrite = true)
      temporary.delete()
    }
    return target
  }

  /** Deletes the file called [name] and returns whether it existed. */
  fun delete(name: String): Boolean = file(name).let { it.isFile && it.delete() }
}
