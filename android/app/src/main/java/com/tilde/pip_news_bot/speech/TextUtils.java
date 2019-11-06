package com.tilde.pip_news_bot.speech;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

final class TextUtils {

    private static final Set<Character> CHARACTERS_WS =
            new HashSet<>(Arrays.asList(' ', '\n', '\t'));

    private static final Set<Character> CHARACTERS_PUNCT =
            new HashSet<>(Arrays.asList(',', ':', ';', '.', '!', '?', '-', ')'));

    private static final Set<Character> CHARACTERS_EOS =
            new HashSet<>(Arrays.asList('.', '!', '?', ')'));

    private TextUtils() {
    }

    static String prettyPrint(String str) {
        boolean isSentenceStart = false;
        boolean isWhitespaceBefore = false;
        String text = "";
        for (String tok : str.split(" ")) {
            if (tok.length() == 0) {
                continue;
            }
            String glue = " ";
            char firstChar = tok.charAt(0);
            if (isWhitespaceBefore
                    || CHARACTERS_WS.contains(firstChar)
                    || CHARACTERS_PUNCT.contains(firstChar)) {
                glue = "";
            }

            if (isSentenceStart) {
                tok = Character.toUpperCase(firstChar) + tok.substring(1);
            }

            if (text.length() == 0) {
                text = tok;
            } else {
                text += glue + tok;
            }

            isWhitespaceBefore = CHARACTERS_WS.contains(firstChar);


            if (tok.length() > 1) {
                isSentenceStart = false;
            } else if (CHARACTERS_EOS.contains(firstChar)) {
                isSentenceStart = true;
            } else if (!isWhitespaceBefore) {
                isSentenceStart = false;
            }
        }
        return text;
    }
}
