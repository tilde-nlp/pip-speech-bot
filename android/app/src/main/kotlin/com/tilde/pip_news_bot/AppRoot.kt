package com.tilde.pip_news_bot

import io.flutter.BuildConfig
import timber.log.Timber
import io.flutter.app.FlutterApplication

class AppRoot : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
    }
}