package com.tilde.pip_news_bot.speech;


public final class Extras {

    /**
     * Boolean.
     * True iff the server has sent final=true, i.e. the following hypotheses
     * will not be transcriptions of the same audio anymore.
     */
    public static final String EXTRA_SEMI_FINAL = "com.tilde.tildesbalss.extra.SEMI_FINAL";

    /**
     * Boolean.
     * True iff the recognizer should play audio cues to indicate start and end of
     * recording, as well as error conditions.
     */
    public static final String EXTRA_AUDIO_CUES = "com.tilde.tildesbalss.extra.AUDIO_CUES";

    /**
     * Boolean.
     * True iff continuous recognition should be used.
     * Same as EXTRA_UNLIMITED_DURATION.
     */
    static final String EXTRA_UNLIMITED_DURATION = "android.speech.extra.UNLIMITED_DURATION";
    static final String EXTRA_DICTATION_MODE = "android.speech.extra.DICTATION_MODE";

}