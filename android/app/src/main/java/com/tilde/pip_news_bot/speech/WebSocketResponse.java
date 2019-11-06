package com.tilde.pip_news_bot.speech;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;


final class WebSocketResponse {

    // Usually used when recognition results are sent.
    static final int STATUS_SUCCESS = 0;

    // Audio contains a large portion of silence or non-speech.
    static final int STATUS_NO_SPEECH = 1;

    // Recognition was aborted for some reason.
    static final int STATUS_ABORTED = 2;

    // No valid frames found before end of stream.
    static final int STATUS_NO_VALID_FRAMES = 5;

    // Used when all recognizer processes are currently in use and recognition cannot be performed.
    static final int STATUS_NOT_AVAILABLE = 9;

    private final JSONObject mJson;
    private final int mStatus;

    WebSocketResponse(String data) throws WebSocketResponseException {
        try {
            mJson = new JSONObject(data);
            mStatus = mJson.getInt("status");
        } catch (JSONException e) {
            throw new WebSocketResponseException(e);
        }
    }

    int getStatus() {
        return mStatus;
    }

    boolean isResult() {
        return mJson.has("result");
    }

    Result parseResult() throws WebSocketResponseException {
        try {
            return new Result(mJson.getJSONObject("result"));
        } catch (JSONException e) {
            throw new WebSocketResponseException(e);
        }
    }

    public static class Result {
        private final JSONObject mResult;

        Result(JSONObject result) {
            mResult = result;
        }

           ArrayList<String> getHypotheses()
                throws WebSocketResponseException {
            try {
                ArrayList<String> hypotheses = new ArrayList<>();
                JSONArray array = mResult.getJSONArray("hypotheses");
                for (int i = 0; i < array.length() &&
                        i < TldWebSocketRecognitionService.MAX_HYPOTHESES; i++) {
                    String transcript = array.getJSONObject(i).getString("transcript")
                            .replaceAll("<[^<>]+>", "");
                    if (TldWebSocketRecognitionService.PRETTY_PRINT) {
                        hypotheses.add(TextUtils.prettyPrint(transcript));
                    } else {
                        hypotheses.add(transcript);
                    }
                }
                return hypotheses;
            } catch (JSONException e) {
                throw new WebSocketResponseException(e);
            }
        }

        /**
         * The "final" field does not have to exist, but if it does then it must be a boolean.
         *
         * @return true iff this result is final
         */
        public boolean isFinal() {
            return mResult.optBoolean("final", false);
        }
    }


    static class WebSocketResponseException extends Exception {
        WebSocketResponseException(JSONException e) {
            super(e);
        }
    }
}