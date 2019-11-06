package com.tilde.pip_news_bot.authorization;

public final class Authorization {

    public final String appID;
    public final String appKey;
    public final String timeStamp;

    Authorization(String appID, String appKey, String timeStamp) {
        this.appID = appID;
        this.appKey = appKey;
        this.timeStamp = timeStamp;
    }
}
