package com.tilde.pip_news_bot;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;

import com.tilde.pip_news_bot.speech.Extras;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import timber.log.Timber;

/**
 * SpeechRecognitionPlugin
 */
public final class SpeechRecognitionPlugin implements MethodCallHandler, RecognitionListener {

    private SpeechRecognizer speech;
    private MethodChannel speechChannel;
    private String transcription = "";
    private Intent recognizerIntent;
    private Activity activity;

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "speech_recognition");
        channel.setMethodCallHandler(new SpeechRecognitionPlugin(registrar.activity(), channel));
    }

    private SpeechRecognitionPlugin(Activity activity, MethodChannel channel) {
        this.speechChannel = channel;
        this.speechChannel.setMethodCallHandler(this);
        this.activity = activity;
        
        // this forces the app to use only our internal speech recognition component
        final ComponentName componentName = ComponentName.unflattenFromString("com.tilde.pip_news_bot/com.tilde.pip_news_bot.speech.TldWebSocketRecognitionService");

        speech = SpeechRecognizer.createSpeechRecognizer(activity.getApplicationContext(), componentName);
        speech.setRecognitionListener(this);

        recognizerIntent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3);
        // TODO don't hardcode this!
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "lv-LV");
    }

    /**
     *  writes the asr configuration arguments to shared prefs, where asr service
     *  can later access it from.
     */
    private void writeConfig(List<String> arguments) {
        final String endpoint = arguments.get(0);
        final String asrSystem = arguments.get(1);
        final String asrAppId = arguments.get(2);
        final String asrAppSecret = arguments.get(3);
        Timber.d("desired endpoint: %s", endpoint);
        Timber.d("desired system: %s", asrSystem);
        Timber.d("desired appId: %s", asrAppId);
        Timber.d("desired appSecret: %s", asrAppSecret);
        final SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(activity);
        prefs.edit()
                .putString(activity.getString(R.string.keyWsServer), endpoint)
                .putString(activity.getString(R.string.keyAsrSystem), asrSystem)
                .putString(activity.getString(R.string.keyAppID), asrAppId)
                .putString(activity.getString(R.string.keyAppSecurity), asrAppSecret)
                .apply();
    }

    // TODO get rid of the locale stuff here? or, hmmm?
    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case "speech.activate":
                // writing config passes configuration from flutter side to native prefs
                final List<String> arguments = call.arguments();
                writeConfig(arguments);
                // mic permission etc should be handled beforehand by client...
                Locale locale = activity.getResources().getConfiguration().locale;
                Timber.d("Current Locale : %s", locale.toString());
                speechChannel.invokeMethod("speech.onCurrentLocale", locale.toString());
                result.success(true);
                break;
            case "speech.listen":
                recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, getLocale(call.arguments.toString()));
                speech.startListening(recognizerIntent);
                result.success(true);
                break;
            case "speech.cancel":
                speech.cancel();
                result.success(false);
                break;
            case "speech.stop":
                speech.stopListening();
                result.success(true);
                break;
            case "speech.destroy":
                speech.cancel();
                speech.destroy();
                result.success(true);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private Locale getLocale(String code) {
        String[] localeParts = code.split("_");
        return new Locale(localeParts[0], localeParts[1]);
    }

    @Override
    public void onReadyForSpeech(Bundle params) {
        Timber.d("onReadyForSpeech");
        speechChannel.invokeMethod("speech.onSpeechAvailability", true);
    }

    @Override
    public void onBeginningOfSpeech() {
        Timber.d("onRecognitionStarted");
        transcription = "";
        speechChannel.invokeMethod("speech.onRecognitionStarted", null);
    }

    @Override
    public void onRmsChanged(float rmsdB) {
//        Timber.d("onRmsChanged : " + rmsdB);
    }

    @Override
    public void onBufferReceived(byte[] buffer) {
//        Timber.d("onBufferReceived");
    }

    @Override
    public void onEndOfSpeech() {
        Timber.d("onEndOfSpeech");
        speechChannel.invokeMethod("speech.onRecognitionComplete", transcription);
    }

    @Override
    public void onError(int error) {
        Timber.d("onError : %s", error);
        speechChannel.invokeMethod("speech.onSpeechAvailability", false);
        speechChannel.invokeMethod("speech.onError", error);
    }

    @Override
    public void onPartialResults(Bundle partialResults) {
        Timber.d("onPartialResults...");
        ArrayList<String> results = partialResults
                .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        final boolean isSemiFinal = partialResults.getBoolean(Extras.EXTRA_SEMI_FINAL, false);
        if (results != null && !results.isEmpty()) {
            transcription = results.get(0);
        }
        sendTranscription(isSemiFinal);
    }

    @Override
    public void onEvent(int eventType, Bundle params) {
        Timber.d("onEvent : %s", eventType);
    }

    @Override
    public void onResults(Bundle results) {
        Timber.d("onResults...");
        ArrayList<String> matches = results
                .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (matches != null) {
            transcription = matches.get(0);
            Timber.d("onResults -> %s", transcription);
            sendTranscription(true);
        }
        sendTranscription(false);
    }

    private void sendTranscription(boolean isFinal) {
        speechChannel.invokeMethod(isFinal ? "speech.onRecognitionComplete" : "speech.onSpeech", transcription);
    }
}
