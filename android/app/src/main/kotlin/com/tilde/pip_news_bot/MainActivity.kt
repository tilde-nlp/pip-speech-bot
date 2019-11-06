package com.tilde.pip_news_bot

import android.os.Bundle

import io.flutter.app.FlutterActivity
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    GeneratedPluginRegistrant.registerWith(this)
    // FIXME manual registration, sigh... there's probably a more correct way to do this
    //  than emulating flutter 3rd party plugin registration...
    SpeechRecognitionPlugin.registerWith(
            this.registrarFor("com.tilde.pip_news_bot.speech_recognition"))
  }
}
