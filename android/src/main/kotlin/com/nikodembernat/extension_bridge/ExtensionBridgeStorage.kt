package com.nikodembernat.extension_bridge

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64

/**
 * Key-value storage shared between the app and its widgets, services and other components.
 *
 * This is the native counterpart of `SharedStorage` in Dart: values written in Dart with
 * `bridge.storage.set(...)` can be read here and vice versa.
 *
 * ```kotlin
 * val storage = ExtensionBridgeStorage(context, appGroup = "group.com.example.app")
 * val counter = storage.getLong("counter") ?: 0
 * ```
 *
 * Values live in the [SharedPreferences] named after the app group. Strings, booleans and integers
 * are stored as plain preferences, so they can also be read with the usual `getString`,
 * `getBoolean` and `getLong`. Doubles and bytes need a type tag, which this class handles.
 */
class ExtensionBridgeStorage
@JvmOverloads
constructor(
    context: Context,
    /** The app group used as namespace, or `null` for the default one. */
    val appGroup: String? = null,
) {
  /** The name of the [SharedPreferences] holding the values. */
  val preferencesName: String = appGroup ?: DEFAULT_NAME

  /** The underlying [SharedPreferences]. */
  val preferences: SharedPreferences =
      context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

  private val types: SharedPreferences =
      context.applicationContext.getSharedPreferences(
          "$preferencesName$TYPES_SUFFIX",
          Context.MODE_PRIVATE,
      )

  // region Reading

  /** The value stored under [key], decoded to the type it was written with. */
  fun get(key: String): Any? = decode(key, preferences.all[key])

  /** The string stored under [key]. */
  fun getString(key: String): String? = get(key) as? String

  /** The integer stored under [key]. */
  fun getLong(key: String): Long? =
      when (val value = get(key)) {
        is Long -> value
        is Int -> value.toLong()
        else -> null
      }

  /** The floating point number stored under [key]. Integers are converted. */
  fun getDouble(key: String): Double? =
      when (val value = get(key)) {
        is Double -> value
        is Long -> value.toDouble()
        is Int -> value.toDouble()
        else -> null
      }

  /** The boolean stored under [key]. */
  fun getBoolean(key: String): Boolean? = get(key) as? Boolean

  /** The bytes stored under [key] (a `Uint8List` in Dart). */
  fun getBytes(key: String): ByteArray? = get(key) as? ByteArray

  /**
   * The JSON string stored under [key] with `setJson` in Dart.
   *
   * Decode it with the JSON library of your choice, e.g. `org.json.JSONObject` or
   * `kotlinx.serialization`.
   */
  fun getJson(key: String): String? = getString(key)

  /** Every stored value, decoded. */
  fun getAll(): Map<String, Any> =
      preferences.all.mapNotNull { (key, value) -> decode(key, value)?.let { key to it } }.toMap()

  /** Whether a value is stored under [key]. */
  fun contains(key: String): Boolean = preferences.contains(key)

  // endregion

  // region Writing

  /**
   * Stores [value] under [key], or removes the key when [value] is `null`.
   *
   * Supported types are [String], [Boolean], [Int], [Long], [Float], [Double] and [ByteArray].
   *
   * @throws IllegalArgumentException for unsupported types.
   */
  fun set(key: String, value: Any?) {
    val editor = preferences.edit()
    val typeEditor = types.edit()
    typeEditor.remove(key)
    when (value) {
      null -> editor.remove(key)
      is String -> editor.putString(key, value)
      is Boolean -> editor.putBoolean(key, value)
      is Int -> editor.putLong(key, value.toLong())
      is Long -> editor.putLong(key, value)
      is Float,
      is Double -> {
        editor.putLong(key, java.lang.Double.doubleToRawLongBits((value as Number).toDouble()))
        typeEditor.putString(key, TYPE_DOUBLE)
      }
      is ByteArray -> {
        editor.putString(key, Base64.encodeToString(value, Base64.NO_WRAP))
        typeEditor.putString(key, TYPE_BYTES)
      }
      else ->
          throw IllegalArgumentException(
              "Cannot store ${value::class.java.simpleName}. Supported types are String, " +
                  "Boolean, Int, Long, Float, Double and ByteArray."
          )
    }
    typeEditor.commit()
    editor.commit()
  }

  /** Removes the value stored under [key]. */
  fun remove(key: String) = set(key, null)

  /** Removes every stored value. */
  fun clear() {
    types.edit().clear().commit()
    preferences.edit().clear().commit()
  }

  // endregion

  private fun decode(key: String, value: Any?): Any? =
      when (types.getString(key, null)) {
        TYPE_DOUBLE -> (value as? Long)?.let { java.lang.Double.longBitsToDouble(it) }
        TYPE_BYTES -> (value as? String)?.let { Base64.decode(it, Base64.NO_WRAP) }
        else ->
            when (value) {
              is Float -> value.toDouble()
              is Set<*> -> value.toList()
              else -> value
            }
      }

  companion object {
    /** The preferences used when no app group is given. */
    const val DEFAULT_NAME = "extension_bridge"

    private const val TYPES_SUFFIX = ".extension_bridge_types"
    private const val TYPE_DOUBLE = "double"
    private const val TYPE_BYTES = "bytes"
  }
}
