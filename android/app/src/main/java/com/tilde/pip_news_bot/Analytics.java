package com.tilde.pip_news_bot;


import android.content.Context;
import android.os.Bundle;
import androidx.annotation.NonNull;

import timber.log.Timber;

public class Analytics {

    private Analytics() {}

    public static void FirebaseLogEvent(Context appContext, @NonNull String var1, Bundle var2) {
        Timber.w("Analytics not setup, called with var1: %s, var2: %s", var1, var2);
    }

}