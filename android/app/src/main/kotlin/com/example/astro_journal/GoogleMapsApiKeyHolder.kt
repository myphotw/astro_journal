package com.example.astro_journal

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log

object GoogleMapsApiKeyHolder {
    const val LOG_TAG = "GOOGLE_MAP"
    private const val TAG = LOG_TAG
    private const val PREFS = "astro_journal_maps_api"
    private const val PREF_KEY = "google_maps_api_key"
    private const val META_KEY = "com.google.android.geo.API_KEY"
    private val PLACEHOLDERS = setOf("DUMMY-KEY-HERE", "YOUR_GOOGLE_MAPS_API_KEY", "")

    fun applyFromPreferences(context: Context) {
        val apiKey = resolveActiveKey(context)
        if (isValidKey(apiKey)) {
            applyToManifestMetaData(context, apiKey!!)
        }
    }

    fun sync(context: Context, apiKey: String?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (apiKey.isNullOrEmpty()) {
            prefs.edit().remove(PREF_KEY).apply()
            Log.i(TAG, "Native Maps API key cleared")
            return
        }

        prefs.edit().putString(PREF_KEY, apiKey).apply()
        applyToManifestMetaData(context, apiKey)
        Log.i(TAG, "Native Maps API key synced (length=${apiKey.length})")
    }

    fun readStatus(context: Context): Map<String, Any> {
        val key = resolveActiveKey(context)
        val configured = isValidKey(key)
        return mapOf(
            "configured" to configured,
            "keyLength" to (key?.length ?: 0),
        )
    }

    fun readManifestApiKey(context: Context): String? {
        val key = readManifestKey(context)
        return if (isValidKey(key)) key else null
    }

    private fun resolveActiveKey(context: Context): String? {
        val cached = readCachedKey(context)
        if (isValidKey(cached)) return cached

        val manifestKey = readManifestKey(context)
        if (isValidKey(manifestKey)) return manifestKey

        return cached ?: manifestKey
    }

    private fun readCachedKey(context: Context): String? {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREF_KEY, null)
    }

    private fun readManifestKey(context: Context): String? {
        return try {
            val appInfo = context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA,
            )
            appInfo.metaData?.getString(META_KEY)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to read manifest meta-data key", error)
            null
        }
    }

    private fun isValidKey(key: String?): Boolean {
        return !key.isNullOrBlank() && key !in PLACEHOLDERS
    }

    private fun applyToManifestMetaData(context: Context, apiKey: String) {
        try {
            val appInfo = context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA,
            )
            if (appInfo.metaData == null) {
                appInfo.metaData = Bundle()
            }
            appInfo.metaData.putString(META_KEY, apiKey)
        } catch (error: Exception) {
            Log.e(TAG, "Failed to inject Maps API key into manifest meta-data", error)
        }
    }
}
