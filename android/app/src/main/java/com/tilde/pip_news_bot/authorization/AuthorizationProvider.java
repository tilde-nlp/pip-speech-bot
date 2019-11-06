package com.tilde.pip_news_bot.authorization;

import org.apache.commons.codec.digest.DigestUtils;

import java.nio.charset.StandardCharsets;

public final class AuthorizationProvider {

    private final String appID;
    private final String appSecret;

    public AuthorizationProvider(final String appId, final String appSecret) {
        this.appID = appId;
        this.appSecret = appSecret;
    }

    public Authorization genAuth() {
        final long tsLong = System.currentTimeMillis() / 1000;
        final String timeStamp = Long.toString(tsLong);
        final byte[] data2hash = (timeStamp + appID + appSecret).getBytes(StandardCharsets.UTF_8);
        final String appKey = DigestUtils.shaHex(data2hash);
        return new Authorization(appID, appKey, timeStamp);
    }
}
