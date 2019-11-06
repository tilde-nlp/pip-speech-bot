package com.tilde.pip_news_bot.speech.audio;

import android.content.Context;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.SystemClock;

import com.tilde.pip_news_bot.R;

public final class AudioCue {

    private static final int DELAY_AFTER_START_BEEP = 200;
    private final Context context;
    private final int startSound;
    private final int stopSound;
    private final int errorSound;

    public AudioCue(Context context) {
        this(context,
                R.raw.tilde_start,
                R.raw.tilde_stop,
                AudioManager.FX_KEYPRESS_STANDARD);
    }

    public AudioCue(Context context, int startSound, int stopSound, int errorSound) {
        this.context = context;
        this.startSound = startSound;
        this.stopSound = stopSound;
        this.errorSound = errorSound;
    }

    public void playStartSoundAndSleep() {
        if (playSound(startSound)) {
            SystemClock.sleep(DELAY_AFTER_START_BEEP);
        }
    }

    public void playStopSound() {
        playSound(stopSound);
    }

    public void playErrorSound() {
        playSound(errorSound);
    }

    private boolean playSound(int sound) {
        MediaPlayer mp = MediaPlayer.create(context, sound);
        // create can return null, e.g. on Android Wear
        if (mp == null) {
            return false;
        }
        // mp.setAudioStreamType(AudioManager.STREAM_MUSIC);
        mp.setOnCompletionListener(MediaPlayer::release);
        mp.start();
        return true;
    }

}
