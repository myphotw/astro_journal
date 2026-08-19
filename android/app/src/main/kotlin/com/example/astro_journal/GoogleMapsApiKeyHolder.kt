package com.example.astro_journal

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log

object GoogleMapsApiKeyHolder {
    const val LOG_TAG = "GOOGLE_MAP"
    private const val TAG = LOG_TAG
    private const val META_KEY = "com.google.android.geo.API_KEY"
    private val PLACEHOLDERS = setOf(
        "DUMMY-KEY-HERE",
        "DEBUG-NOT-CONFIGURED",
        "YOUR_GOOGLE_MAPS_API_KEY",
        "",
    )

    fun applyBuildConfiguredKey(context: Context) {
        val apiKey = resolveActiveKey(context)
        if (isValidKey(apiKey)) {
            applyToManifestMetaData(context, apiKey!!)
        }
    }

    fun readStatus(context: Context): Map<String, Any> {
        val key = resolveActiveKey(context)
        val configured = isValidKey(key)
        return mapOf(
            "configured" to configured,
            "keyLength" to (key?.length ?: 0),
        )
    }

    private fun resolveActiveKey(context: Context): String? {
        return readManifestKey(context)
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
