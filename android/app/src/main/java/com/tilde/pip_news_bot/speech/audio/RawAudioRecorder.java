package com.tilde.pip_news_bot.speech.audio;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AcousticEchoCanceler;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;

import timber.log.Timber;

public final class RawAudioRecorder {

    private static final int RESOLUTION = AudioFormat.ENCODING_PCM_16BIT;
    private static final int BUFFER_SIZE_MUTLIPLIER = 4; // was: 2

    private short RESOLUTION_IN_BYTES = 2;
    private short CHANNELS = 1;

    public enum State {
        READY,      // recorder is ready, but not yet recording
        RECORDING,  // recorder recording
        ERROR,      // error occurred, reconstruction needed
        STOPPED     // recorder stopped
    }
    private AudioRecord mRecorder;
    private double mAvgEnergy = 0;
    private final int mSampleRate;

    private final int mOneSec;
    private State mState;

    private final byte[] mRecording;
    private int mRecordedLength = 0;
    private int mConsumedLength = 0;

    private boolean mNoise;
    private boolean mGain;
    private boolean mEcho;

    private byte[] mBuffer;

    private RawAudioRecorder(int audioSource,
                             int sampleRate,
                             boolean noise,
                             boolean gain,
                             boolean echo) {

        mSampleRate = sampleRate;
        mNoise = noise;
        mGain = gain;
        mEcho = echo;

        mOneSec = RESOLUTION_IN_BYTES * CHANNELS * mSampleRate;
        mRecording = new byte[mOneSec * 35];
        mRecorder = null;

        try {
            int bufferSize = getBufferSize();
            int framePeriod = bufferSize / (2 * RESOLUTION_IN_BYTES * CHANNELS);
            createRecorder(audioSource, sampleRate, bufferSize);
            createBuffer(framePeriod);
            setState(State.READY);
        } catch (Exception e) {
            if (e.getMessage() == null) {
                handleError("Unknown error occurred while initializing recorder");
            } else {
                handleError(e.getMessage());
            }
        }
    }

    public RawAudioRecorder(int sampleRate, boolean noise, boolean gain, boolean echo) {
        this(MediaRecorder.AudioSource.VOICE_RECOGNITION, sampleRate, noise, gain, echo);
    }

    private void createRecorder(int audioSource, int sampleRate, int bufferSize) {
        mRecorder = new AudioRecord(audioSource, sampleRate,
                AudioFormat.CHANNEL_IN_MONO, RESOLUTION, bufferSize);

        int audioSessionId = mRecorder.getAudioSessionId();
        if (mNoise) {
            if (NoiseSuppressor.create(audioSessionId) == null) {
                Timber.i("NoiseSuppressor: failed");
            } else {
                Timber.i("NoiseSuppressor: ON");
            }
        } else {
            Timber.i("NoiseSuppressor: OFF");
        }

        if (mGain) {
            if (AutomaticGainControl.create(audioSessionId) == null) {
                Timber.i("AutomaticGainControl: failed");
            } else {
                Timber.i("AutomaticGainControl: ON");
            }
        } else {
            Timber.i("AutomaticGainControl: OFF");
        }

        if (mEcho) {
            if (AcousticEchoCanceler.create(audioSessionId) == null) {
                Timber.i("AcousticEchoCanceler: failed");
            } else {
                Timber.i("AcousticEchoCanceler: ON");
            }
        } else {
            Timber.i("AcousticEchoCanceler: OFF");
        }


        if (getSpeechRecordState() != AudioRecord.STATE_INITIALIZED) {
            throw new IllegalStateException("SpeechRecord initialization failed");
        }
    }

    private void createBuffer(int framePeriod) {
        mBuffer = new byte[framePeriod * RESOLUTION_IN_BYTES * CHANNELS];
    }

    private int getSpeechRecordState() {
        if (mRecorder == null) {
            return AudioRecord.STATE_UNINITIALIZED;
        }
        return mRecorder.getState();
    }

    private void handleError(String msg) {
        release();
        setState(State.ERROR);
        Timber.e(msg);
    }

    public synchronized byte[] consumeRecording() {
        byte[] bytes = getCurrentRecording(mConsumedLength);
        mConsumedLength = mRecordedLength;
        return bytes;
    }

    private byte[] getCurrentRecording(int startPos) {
        int len = getLength() - startPos;
        byte[] bytes = new byte[len];
        System.arraycopy(mRecording, startPos, bytes, 0, len);
        Timber.i("Copied from: " + startPos + ": " + bytes.length + " bytes");
        return bytes;
    }

    public State getState() {
        return mState;
    }

    private void setState(State state) {
        mState = state;
    }

    public static byte[] getRecordingAsWav(byte[] pcm, int sampleRate) {
        return AudioUtils.getRecordingAsWav(pcm, sampleRate);
    }

    private int getBufferSize() {
        int minBufferSizeInBytes = AudioRecord.getMinBufferSize(mSampleRate,
                AudioFormat.CHANNEL_IN_MONO, RESOLUTION);
        if (minBufferSizeInBytes == AudioRecord.ERROR_BAD_VALUE) {
            throw new IllegalArgumentException("SpeechRecord.getMinBufferSize: " +
                    "parameters not supported by hardware");
        } else if (minBufferSizeInBytes == AudioRecord.ERROR) {
            Timber.e("SpeechRecord.getMinBufferSize: unable to query hardware for output properties");
            minBufferSizeInBytes = 0;
        }
        int bufferSize = BUFFER_SIZE_MUTLIPLIER * minBufferSizeInBytes;
        Timber.i("SpeechRecord buffer size: " + bufferSize + ", min size = " + minBufferSizeInBytes);
        return bufferSize;
    }

    public synchronized byte[] consumeRecordingAndTruncate() {
        int len = getConsumedLength();
        byte[] bytes = getCurrentRecording(len);
        setRecordedLength();
        setConsumedLength();
        return bytes;
    }

    private int getStatus(int numOfBytes, int len) {

        if (numOfBytes < 0) {
            Timber.i("AudioRecord error: %s", numOfBytes);
            return numOfBytes;
        }
        if (numOfBytes > len) {
            Timber.e("Read more bytes than is buffer length:" + numOfBytes + ": " + len);
            return -100;
        } else if (numOfBytes == 0) {
            Timber.e("Read zero bytes");
            return -200;
        } else if (mRecording.length < mRecordedLength + numOfBytes) {
            Timber.e("Recorder buffer overflow: %s", mRecordedLength);
            return -300;
        }
        return 0;
    }

    private int read(AudioRecord recorder, byte[] buffer) {
        int len = buffer.length;
        int numOfBytes = recorder.read(buffer, 0, len);
        int status = getStatus(numOfBytes, len);
        if (status == 0) {
            System.arraycopy(buffer, 0, mRecording, mRecordedLength, numOfBytes);
            mRecordedLength += len;
        }
        return status;
    }
    private int getConsumedLength() {
        return mConsumedLength;
    }

    private void setConsumedLength() {
        mConsumedLength = 0;
    }

    private void setRecordedLength() {
        mRecordedLength = 0;
    }

    private int getLength() {
        return mRecordedLength;
    }

    public boolean isPausing() {
        double pauseScore = getPauseScore();
        Timber.i("Pause score: %s", pauseScore);
        return pauseScore > 7;
    }

    public float getRmsdb() {
        long sumOfSquares = getRms(mRecordedLength, mBuffer.length);
        double rootMeanSquare = Math.sqrt(sumOfSquares / (mBuffer.length / 2));
        if (rootMeanSquare > 1) {
            return (float) (10 * Math.log10(rootMeanSquare));
        }
        return 0;
    }

    private double getPauseScore() {
        long t2 = getRms(mRecordedLength, mOneSec);
        if (t2 == 0) {
            return 0;
        }
        double t = mAvgEnergy / t2;
        mAvgEnergy = (2 * mAvgEnergy + t2) / 3;
        return t;
    }

    public synchronized void release() {
        if (mRecorder != null) {
            if (mRecorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                stop();
            }
            mRecorder.release();
            mRecorder = null;
        }
    }

    public void start() {
        if (getSpeechRecordState() == AudioRecord.STATE_INITIALIZED) {
            mRecorder.startRecording();
            if (mRecorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                setState(State.RECORDING);
                new Thread() {
                    public void run() {
                        recorderLoop(mRecorder);
                    }
                }.start();
            } else {
                handleError("startRecording() failed");
            }
        } else {
            handleError("start() called on illegal state");
        }
    }

    private void stop() {
        if (getSpeechRecordState() == AudioRecord.STATE_INITIALIZED &&
                mRecorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
            try {
                mRecorder.stop();
                setState(State.STOPPED);
            } catch (IllegalStateException e) {
                handleError("native stop() called in illegal state: " + e.getMessage());
            }
        } else {
            handleError("stop() called in illegal state");
        }
    }

    private static short getShort(byte argB1, byte argB2) {
        return (short) (argB1 | (argB2 << 8));
    }

    private void recorderLoop(AudioRecord recorder) {
        while (recorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
            int status = read(recorder, mBuffer);
            if (status < 0) {
                handleError("status = " + status);
                break;
            }
        }
    }

    private long getRms(int end, int span) {
        int begin = end - span;
        if (begin < 0) {
            begin = 0;
        }
        // make sure begin is even
        if (0 != (begin % 2)) {
            begin++;
        }

        long sum = 0;
        for (int i = begin; i < end; i += 2) {
            short curSample = getShort(mRecording[i], mRecording[i + 1]);
            sum += curSample * curSample;
        }
        return sum;
    }

    public String getWsArgs() {
        return "?content-type=audio/x-raw,+layout=(string)interleaved,+rate=(int)" +
                mSampleRate + ",+format=(string)S16LE,+channels=(int)1";
    }
}
