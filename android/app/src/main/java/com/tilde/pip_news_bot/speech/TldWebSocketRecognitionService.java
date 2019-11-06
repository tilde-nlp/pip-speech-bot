package com.tilde.pip_news_bot.speech;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.Message;
import android.os.Process;
import android.os.RemoteException;
import android.os.SystemClock;
import android.preference.PreferenceManager;
import android.speech.RecognitionService;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;

import com.tilde.pip_news_bot.Analytics;
import com.tilde.pip_news_bot.R;
import com.tilde.pip_news_bot.authorization.Authorization;
import com.tilde.pip_news_bot.authorization.AuthorizationProvider;
import com.tilde.pip_news_bot.speech.audio.AudioCue;
import com.tilde.pip_news_bot.speech.audio.RawAudioRecorder;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.concurrent.TimeoutException;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import okio.ByteString;
import timber.log.Timber;


public class TldWebSocketRecognitionService extends RecognitionService {

    private static final int TASK_DELAY_SEND = 10;
    private static final int TASK_INTERVAL_SEND = 200;
    public static final int MAX_HYPOTHESES = 100;

    private static final String POSTPROCESS_NUMBERS = "voice_recognition_postprocess_numbers";
    // Pretty-print results
    public static final boolean PRETTY_PRINT = true;

    private static final String EOS = "EOS";
    private boolean mIsEosSent;

    private static final int MSG_RESULT = 1;
    private static final int MSG_ERROR = 2;

    private volatile Looper mSendLooper;

    private volatile Handler mSendHandler;
    private RecognitionResultHandler mRecResultHandler;
    private Runnable mSendRunnable;

    private WebSocket mWebSocket;
    private String mUrl;

    private String mAuth = "";

    private static final int TASK_INTERVAL_VOL = 100;
    private static final int TASK_DELAY_VOL = 500;

    private static final int TASK_INTERVAL_STOP = 1000;
    private static final int TASK_DELAY_STOP = 1000;

    private AudioCue mAudioCue;
    private AudioPauser mAudioPauser;
    private RawAudioRecorder mRecorder;

    private Callback mRecognitionListener;

    private final Handler mVolumeHandler = new Handler();
    private Runnable mShowVolumeTask;

    private final Handler mStopHandler = new Handler();
    private Runnable mStopTask;

    private Bundle mExtras;

    @Override
    public void onCreate() {
        super.onCreate();
    }

    boolean configure() {
        Bundle extras = getExtras();
        if (extras == null) {
            extras = new Bundle();
        }

        final SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(this);

        // TODO remove defaults from resources
        // TODO do the same for iOS counterpart
        // TODO handle null
        final String appId = prefs.getString(getString(R.string.keyAppID), null);
        final String appSecret = prefs.getString(getString(R.string.keyAppSecurity), null);
        final String appSystem = prefs.getString(getString(R.string.keyAsrSystem), null);
        final String wsServer = prefs.getString(getString(R.string.keyWsServer), null);
        Timber.d("appId: %s", appId);
        Timber.d("appSecret: %s", appSecret);
        Timber.d("appSystem: %s", appSystem);
        Timber.d("wsServer: %s", wsServer);
        boolean allConfigProvided = true;
        if (appId == null) {
            Timber.w("ASR: appId not specified.");
            allConfigProvided = false;
        }
        if (appSecret == null) {
            Timber.w("ASR: appSecret not specified.");
            allConfigProvided = false;
        }
        if (appSystem == null) {
            Timber.w("ASR: asr system not specified");
            allConfigProvided = false;
        }
        if (wsServer == null) {
            Timber.w("ASR: ws server not specified");
            allConfigProvided = false;
        }
        if (!allConfigProvided) {
            return false;
        }
        final AuthorizationProvider authProvider = new AuthorizationProvider(appId, appSecret);
        final Authorization auth = authProvider.genAuth();

        final String caller = extras.getString(RecognizerIntent.EXTRA_CALLING_PACKAGE);
        try {
            JSONArray postProcessors = new JSONArray();
            final JSONArray partialPostProcess = new JSONArray();

            if (prefs.getBoolean(POSTPROCESS_NUMBERS, true)) {
                postProcessors.put("numbers");
            }

            JSONObject obj = new JSONObject();
            obj.put("appID", appId);
            obj.put("appKey", auth.appKey);
            obj.put("timestamp", auth.timeStamp);
            obj.put("enable-postprocess", postProcessors);
            obj.put("enable-partial-postprocess", partialPostProcess);

            Bundle params = new Bundle();
            JSONObject customInfo = new JSONObject();
            if (caller != null) {
                customInfo.put("calling_package", caller);
                params.putString("calling_package", caller);
                Analytics.FirebaseLogEvent(this, "wscall_" + caller, params);
            }
            PendingIntent intent = IntentUtils.getPendingIntent(extras);
            if (intent != null) {
                customInfo.put("creator_package", intent.getCreatorPackage());
                params.putString("creator_package", intent.getCreatorPackage());

                Analytics.FirebaseLogEvent(this, "wscr_" + intent.getCreatorPackage(), params);
            }
            obj.put("custom-info", customInfo.toString());
            Timber.i(customInfo.toString());
            mAuth = obj.toString();
            params.putString("service", "RecognitionService");
            params.putString("event", "create");
            Analytics.FirebaseLogEvent(this, "use_ws_RecognitionService", params);

        } catch (JSONException e) {
            e.printStackTrace();
        }

        mUrl = wsServer + "/" + appSystem + getAudioRecorder().getWsArgs();

        boolean isUnlimitedDuration =
                getExtras().getBoolean(Extras.EXTRA_UNLIMITED_DURATION, true)
                        || getExtras().getBoolean(Extras.EXTRA_DICTATION_MODE, true);

        mRecResultHandler = new RecognitionResultHandler(this,
                isUnlimitedDuration,
                getExtras().getBoolean(RecognizerIntent.EXTRA_PARTIAL_RESULTS,
                        false));
        return true;
    }

    void connect() {
        startSocket(mUrl);

        int usageCounter = PreferenceManager.getDefaultSharedPreferences(this)
                .getInt(getString(R.string.keyUsageCounter), 0);
        usageCounter++;

        PreferenceManager.getDefaultSharedPreferences(this).edit()
                .putInt(getString(R.string.keyUsageCounter), usageCounter).apply();
    }

    void disconnect() {
        if (mSendHandler != null) {
            mSendHandler.removeCallbacks(mSendRunnable);
        }

        if (mSendLooper != null) {
            mSendLooper.quit();
            mSendLooper = null;
        }

        if (mWebSocket != null) { // && mWebSocket.mWebSocket.isOpen()) {
            // TODO use webSocket.close() instead?
            mWebSocket.cancel();
//            mWebSocket.end();
            mWebSocket = null;
        }
    }

    private void handleResult(String text) {
        Message msg = new Message();
        msg.what = MSG_RESULT;
        msg.obj = text;
        mRecResultHandler.sendMessage(msg);
    }

    private void handleException(Throwable error) {
        Message msg = new Message();
        msg.what = MSG_ERROR;
        msg.obj = error;
        mRecResultHandler.sendMessage(msg);
    }

    private void startSocket(String url) {
        mIsEosSent = false;

        OkHttpClient client = new OkHttpClient();

        mWebSocket = client.newWebSocket(new Request.Builder().url(url).build(), new WebSocketListener() {
            @Override
            public void onClosed(@NotNull WebSocket webSocket, int code, @NotNull String reason) {
                Timber.i("Websocket closed, code: %s, reason: %s", code, reason);
                handleFinish(mIsEosSent);
            }

            @Override
            public void onClosing(@NotNull WebSocket webSocket, int code, @NotNull String reason) {
                Timber.i("Websocket closing, code: %s, reason: %s", code, reason);
            }

            @Override
            public void onFailure(@NotNull WebSocket webSocket, @NotNull Throwable t, @Nullable Response response) {
                Timber.e(t, "Websocket onFailure, response: %s", response);
                handleException(t);
            }

            @Override
            public void onMessage(@NotNull WebSocket webSocket, @NotNull String text) {
                Timber.i("Websocket text message received: %s", text);
                handleResult(text);
            }

            @Override
            public void onMessage(@NotNull WebSocket webSocket, @NotNull ByteString bytes) {
                Timber.i("Websocket binary message received: %s", bytes);
            }

            @Override
            public void onOpen(@NotNull WebSocket webSocket, @NotNull Response response) {
                Timber.i("Websocket opened");
                webSocket.send(mAuth);
                startSending(webSocket);
            }
        });
    }

    private void startSending(final WebSocket webSocket) {
        HandlerThread thread = new HandlerThread("WsSendHandlerThread",
                Process.THREAD_PRIORITY_BACKGROUND);
        thread.start();
        mSendLooper = thread.getLooper();
        mSendHandler = new Handler(mSendLooper);

        // Send chunks to the server
        mSendRunnable = new Runnable() {
            public void run() {
                RawAudioRecorder recorder = getAudioRecorder();
                if (recorder == null || recorder.getState() !=
                        RawAudioRecorder.State.RECORDING) {
                    webSocket.send(EOS);
                    mIsEosSent = true;
                } else {
                    byte[] buffer = recorder.consumeRecordingAndTruncate();
                    send(webSocket, buffer);
                    if (buffer.length > 0) {
                        onBufferReceived(buffer);
                    }

                    boolean success = mSendHandler.postDelayed(this, TASK_INTERVAL_SEND);
                    if (!success) {
                        Timber.i("mSendHandler.postDelayed returned false");
                    }
                }
            }
        };
        Timber.i(mSendHandler + ".postDelayed(" + mSendRunnable + ", TASK_DELAY_SEND);");
        mSendHandler.postDelayed(mSendRunnable, TASK_DELAY_SEND);
    }

    private void send(WebSocket webSocket, byte[] buffer) {
        if (buffer != null && buffer.length > 0) {
            webSocket.send(ByteString.of(buffer));
        }
    }

    private static class RecognitionResultHandler extends Handler {
        private final WeakReference<TldWebSocketRecognitionService> mRef;
        private final boolean mIsUnlimitedDuration;
        private final boolean mIsPartialResults;

        RecognitionResultHandler(TldWebSocketRecognitionService c,
                                 boolean isUnlimitedDuration, boolean isPartialResults) {
            mRef = new WeakReference<>(c);
            mIsUnlimitedDuration = isUnlimitedDuration;
            mIsPartialResults = isPartialResults;
        }

        @Override
        public void handleMessage(Message msg) {
            TldWebSocketRecognitionService outerClass = mRef.get();
            if (outerClass != null) {
                if (msg.what == MSG_ERROR) {
                    Exception e = (Exception) msg.obj;
                    if (e instanceof TimeoutException) {
                        outerClass.onError(SpeechRecognizer.ERROR_NETWORK_TIMEOUT);
                    } else {
                        outerClass.onError(SpeechRecognizer.ERROR_NETWORK);
                    }
                } else if (msg.what == MSG_RESULT) {
                    try {
                        WebSocketResponse response = new WebSocketResponse((String) msg.obj);
                        int statusCode = response.getStatus();
                        if (statusCode ==
                                WebSocketResponse.STATUS_SUCCESS && response.isResult()) {
                            WebSocketResponse.Result responseResult = response.parseResult();
                            if (responseResult.isFinal()) {
                                ArrayList<String> hypotheses =
                                        responseResult.getHypotheses(
                                        );
                                if (hypotheses.isEmpty()) {
                                    outerClass.onError(SpeechRecognizer.ERROR_SPEECH_TIMEOUT);
                                } else {
                                    if (mIsUnlimitedDuration) {
                                        outerClass.onPartialResults(toResultsBundle(hypotheses,
                                                true));
                                    } else {
                                        outerClass.mIsEosSent = true;
                                        outerClass.onEndOfSpeech();
                                        outerClass.onResults(toResultsBundle(hypotheses, true));
                                    }
                                }
                            } else {
                                if (mIsPartialResults) {
                                    ArrayList<String> hypotheses =
                                            responseResult.getHypotheses(
                                            );
                                    if (!hypotheses.isEmpty()) {
                                        outerClass.onPartialResults(toResultsBundle(hypotheses,
                                                false));
                                    }
                                }
                            }
                        } else if (statusCode == WebSocketResponse.STATUS_SUCCESS) {
                            Timber.i("Adaptation_state currently not handled");
                        } else if (statusCode == WebSocketResponse.STATUS_ABORTED) {
                            outerClass.onError(SpeechRecognizer.ERROR_SERVER);
                        } else if (statusCode == WebSocketResponse.STATUS_NOT_AVAILABLE) {
                            outerClass.onError(SpeechRecognizer.ERROR_RECOGNIZER_BUSY);
                        } else if (statusCode == WebSocketResponse.STATUS_NO_SPEECH) {
                            outerClass.onError(SpeechRecognizer.ERROR_SPEECH_TIMEOUT);
                        } else if (statusCode == WebSocketResponse.STATUS_NO_VALID_FRAMES) {
                            outerClass.onError(SpeechRecognizer.ERROR_NO_MATCH);
                        } else {
                            // Server sent unsupported status code, client should be updated
                            outerClass.onError(SpeechRecognizer.ERROR_CLIENT);
                        }
                    } catch (WebSocketResponse.WebSocketResponseException e) {
                        Timber.e(e, (String) msg.obj);
                        outerClass.onError(SpeechRecognizer.ERROR_SERVER);
                    }
                }
            }
        }
    }

    static Bundle toResultsBundle(ArrayList<String> hypotheses, boolean isFinal) {
        Bundle bundle = new Bundle();
        bundle.putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, hypotheses);
        bundle.putBoolean(Extras.EXTRA_SEMI_FINAL, isFinal);
        return bundle;
    }

    RawAudioRecorder getAudioRecorder() {
        if (mRecorder == null) {
            mRecorder = createAudioRecorder(
                    Integer.parseInt(getString(R.string.defaultRecordingRate))
            );
        }
        return mRecorder;
    }

    private void afterRecording() {
        // Nothing to do, e.g. if the audio has already been sent to the server during recording
    }

    public void onDestroy() {
        super.onDestroy();
        disconnectAndStopRecording();
    }

    @Override
    protected void onStartListening(final Intent recognizerIntent,
                                    Callback listener) {
        // TODO this is where the service gets the intent to recognize things
        // TODO we can try feeding things in here to audio recorder
        mRecognitionListener = listener;
        Timber.i("onStartListening");

        mExtras = recognizerIntent.getExtras();
        if (mExtras == null) {
            mExtras = new Bundle();
        }

        if (mExtras.containsKey(Extras.EXTRA_AUDIO_CUES)) {
            setAudioCuesEnabled(mExtras.getBoolean(Extras.EXTRA_AUDIO_CUES));
        } else {
            // TODO obtain the default from flutter side
            setAudioCuesEnabled(true);
        }

        final boolean configurationOk = configure();
        if (!configurationOk) {
            Timber.w("ASR not configured correctly. Skipping...");
            return;
        }

        mAudioPauser = new AudioPauser(this);

        try {
            onReadyForSpeech(new Bundle());
            mAudioPauser.pause();
            startRecord();
        } catch (IOException e) {
            onError(SpeechRecognizer.ERROR_AUDIO);
            return;
        }

        onBeginningOfSpeech();
        connect();
    }

    @Override
    protected void onStopListening(Callback listener) {
        Timber.i("onStopListening");
        onEndOfSpeech();
    }

    @Override
    protected void onCancel(Callback listener) {
        Timber.i("onCancel");
        disconnectAndStopRecording();
        onResults(new Bundle());
    }

    void handleFinish(boolean isEosSent) {
        if (isEosSent) {
            onCancel(mRecognitionListener);
        } else {
            onError(SpeechRecognizer.ERROR_SPEECH_TIMEOUT);
        }
    }

    Bundle getExtras() {
        return mExtras;
    }

    private void onReadyForSpeech(Bundle bundle) {
        if (mAudioCue != null) {
            mAudioCue.playStartSoundAndSleep();
        }
        try {
            mRecognitionListener.readyForSpeech(bundle);
        } catch (RemoteException ignored) {
        }
    }

    private void onRmsChanged(float rms) {
        try {
            mRecognitionListener.rmsChanged(rms);
        } catch (RemoteException ignored) {
        }
    }

    void onError(int errorCode) {
        disconnectAndStopRecording();
        if (mAudioCue != null) {
            mAudioCue.playStopSound();
        }
        try {
            mRecognitionListener.error(errorCode);
        } catch (RemoteException ignored) {
        }
    }

    void onResults(Bundle bundle) {
        disconnectAndStopRecording();
        try {
            mRecognitionListener.results(bundle);
        } catch (RemoteException ignored) {
        }
    }

    void onPartialResults(Bundle bundle) {
        try {
            mRecognitionListener.partialResults(bundle);
        } catch (RemoteException ignored) {
        }
    }

    private void onBeginningOfSpeech() {
        try {
            mRecognitionListener.beginningOfSpeech();
        } catch (RemoteException ignored) {
        }
    }

    /**
     * Fires the endOfSpeech callback, provided that the recorder is currently recording.
     */
    void onEndOfSpeech() {
        if (mRecorder == null || mRecorder.getState() != RawAudioRecorder.State.RECORDING) {
            return;
        }

        stopRecording();

        if (mAudioCue != null) {
            mAudioCue.playStopSound();
        }
        try {
            mRecognitionListener.endOfSpeech();
        } catch (RemoteException ignored) {
        }
        afterRecording();

    }

    void onBufferReceived(byte[] buffer) {
        try {
            mRecognitionListener.bufferReceived(buffer);
        } catch (RemoteException ignored) {
        }
    }

    private static RawAudioRecorder createAudioRecorder(int sampleRate) {
        return new RawAudioRecorder(sampleRate, false, false, false);
    }

    private void startRecord() throws IOException {
        mRecorder = getAudioRecorder();

        if (mRecorder.getState() == RawAudioRecorder.State.ERROR) {
            throw new IOException();
        }

        if (mRecorder.getState() != RawAudioRecorder.State.READY) {
            throw new IOException();
        }

        mRecorder.start();

        if (mRecorder.getState() != RawAudioRecorder.State.RECORDING) {
            throw new IOException();
        }

        // Monitor the volume level
        mShowVolumeTask = new Runnable() {
            public void run() {
                if (mRecorder != null) {
                    onRmsChanged(mRecorder.getRmsdb());
                    mVolumeHandler.postDelayed(this, TASK_INTERVAL_VOL);
                }
            }
        };

        mVolumeHandler.postDelayed(mShowVolumeTask, TASK_DELAY_VOL);


        final long timeToFinish = SystemClock.uptimeMillis() + 1000 * 10000;

        // Check if we should stop recording
        mStopTask = new Runnable() {
            public void run() {
                if (mRecorder != null) {
                    if (timeToFinish < SystemClock.uptimeMillis()) {
                        onEndOfSpeech();
                    } else {
                        mStopHandler.postDelayed(this, TASK_INTERVAL_STOP);
                    }
                }
            }
        };

        mStopHandler.postDelayed(mStopTask, TASK_DELAY_STOP);
    }


    private void stopRecording() {
        Timber.i("TldWebSocketRecognitionService stopRecording%s", mRecorder);
        if (mRecorder != null) {
            mRecorder.release();
            mRecorder = null;
        }
        mVolumeHandler.removeCallbacks(mShowVolumeTask);
        mStopHandler.removeCallbacks(mStopTask);
        if (mAudioPauser != null) {
            mAudioPauser.resume();
        }
    }


    private void setAudioCuesEnabled(boolean enabled) {
        if (enabled) {
            mAudioCue = new AudioCue(this);
        } else {
            mAudioCue = null;
        }
    }

    private void disconnectAndStopRecording() {
        disconnect();
        stopRecording();
    }

    private class AudioPauser {

        private final boolean mIsMuteStream;
        private final AudioManager mAudioManager;
        private final AudioManager.OnAudioFocusChangeListener mAfChangeListener;
        private int mCurrentVolume = 0;
        private boolean isPausing = false;

        AudioPauser(Context context) {
            this(context, true);
        }

        AudioPauser(Context context, boolean isMuteStream) {
            mAudioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
            mIsMuteStream = isMuteStream;

            mAfChangeListener = focusChange -> Timber.i("onAudioFocusChange: %s", focusChange);
        }

        void pause() {
            if (!isPausing) {
                int result = mAudioManager.requestAudioFocus(mAfChangeListener,
                        AudioManager.STREAM_MUSIC,
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);

                if (result != AudioManager.AUDIOFOCUS_GAIN)
                    return;
                try {
                    if (mIsMuteStream) {
                        mCurrentVolume = mAudioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
                        if (mCurrentVolume > 0) {
                            mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0);
                        }
                    }
                    isPausing = true;
                } catch (SecurityException ex) {
                    Timber.e("mAudioManager.setStreamVolume failed");
                }
            }
        }

        void resume() {
            if (isPausing) {
                mAudioManager.abandonAudioFocus(mAfChangeListener);
                if (mIsMuteStream && mCurrentVolume > 0) {
                    mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mCurrentVolume, 0);
                }
                isPausing = false;
            }
        }

    }
}