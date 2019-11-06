package com.tilde.pip_news_bot.speech;

import android.app.PendingIntent;
import android.os.Bundle;
import android.os.Parcelable;
import android.speech.RecognizerIntent;


final class IntentUtils {

    private IntentUtils() {
    }

    static PendingIntent getPendingIntent(Bundle extras) {
        Parcelable extraResultsPendingIntentAsParceable =
                extras.getParcelable(RecognizerIntent.EXTRA_RESULTS_PENDINGINTENT);
        if (extraResultsPendingIntentAsParceable != null) {
            if (extraResultsPendingIntentAsParceable instanceof PendingIntent) {
                return (PendingIntent) extraResultsPendingIntentAsParceable;
            }
        }
        return null;
    }
}
