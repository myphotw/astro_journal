package com.example.astro_journal



import android.app.Application

import android.content.Context

import android.util.Log

import com.google.android.gms.maps.MapsInitializer



class MainApplication : Application() {

    override fun attachBaseContext(base: Context?) {

        super.attachBaseContext(base)

        if (base != null) {

            GoogleMapsApiKeyHolder.applyBuildConfiguredKey(base)

        }

    }



    override fun onCreate() {

        GoogleMapsApiKeyHolder.applyBuildConfiguredKey(this)

        try {

            MapsInitializer.initialize(this)

        } catch (error: Exception) {

            Log.e(GoogleMapsApiKeyHolder.LOG_TAG, "MapsInitializer failed", error)

        }

        super.onCreate()

    }

}


