package eu.flatworld.android.slider;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;

public class AddAndClipMixer implements Mixer {
    List<KeyboardView> keyboards;
    AudioTrack track;

    boolean stop = false;
    Thread thread;

    int sampleRate;
    int bufferSize = 0;
    short[] buffer;
    float[] tmpBuffer;
    float[] finalBuffer;
    float[] keyboardBuffer;

    public AddAndClipMixer() {
        keyboards = new ArrayList<KeyboardView>();
    }

    @Override
    public void addKeyboard(KeyboardView keyboard) {
        keyboards.add(keyboard);
    }

    @Override
    public void removeKeyboard(KeyboardView keyboard) {
        keyboards.remove(keyboard);
    }

    @Override
    public List<KeyboardView> getKeyboards() {
        return keyboards;
    }

    @Override
    public int getBufferSize() {
        return bufferSize;
    }

    @Override
    public void setBufferSize(int bufferSize) {
        this.bufferSize = bufferSize;
    }

    @Override
    public int getSampleRate() {
        return sampleRate;
    }

    @Override
    public void setSampleRate(int sampleRate) {
        this.sampleRate = sampleRate;
    }

    void sumBuffers(float[] dest, float[] src) {
        for (int i = 0; i < dest.length; i++) {
            dest[i] += src[i];
        }
    }

    void setBuffer(float[] dest, float value) {
        for (int i = 0; i < dest.length; i++) {
            dest[i] = value;
        }
    }

    void fillBuffer(short[] buffer) {
        // Log.d(Slider.LOGTAG, "Start fill");
        setBuffer(finalBuffer, 0);
        for (int j = 0; j < keyboards.size(); j++) {
            setBuffer(keyboardBuffer, 0);
            KeyboardView k = keyboards.get(j);
            List<SoundGenerator> sgg = k.getSoundGenerators();
            for (int m = 0; m < sgg.size(); m++) {
                SoundGenerator sg = sgg.get(m);
                if (sg.getEnvelope().isDone()) {
                    continue;
                }
                sg.getValues(tmpBuffer);
                sumBuffers(keyboardBuffer, tmpBuffer);
            }
            Filter filter = k.getFilter();
            if (filter != null) {
                filter.filter(keyboardBuffer, 0, keyboardBuffer.length);
            }
            sumBuffers(finalBuffer, keyboardBuffer);
        }
        for (int i = 0; i < buffer.length; i++) {
            float val = finalBuffer[i];
            if (val > 1) {
                val = 1;
            }
            if (val < -1) {
                val = -1;
            }
            buffer[i] = (short) (val * Short.MAX_VALUE);
        }
        // Log.d(Slider.LOGTAG, "Stop fill");
    }

    void doMix() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO);
        while (!stop) {
            long t = System.currentTimeMillis();
            fillBuffer(buffer);
            Log.d(SliderSynth.LOGTAG, String.format("fill %d", (System.currentTimeMillis() - t)));
            t = System.currentTimeMillis();
            int n = track.write(buffer, 0, bufferSize);
            Log.d(SliderSynth.LOGTAG, String.format("write %d", (System.currentTimeMillis() - t)));
        }
    }

    void sleep(long t) {
        try {
            Thread.sleep(t);
        } catch (Exception ex) {
        }
    }

    @Override
    public void start() {
        int minSize = AudioTrack.getMinBufferSize(sampleRate,
                AudioFormat.CHANNEL_CONFIGURATION_MONO,
                AudioFormat.ENCODING_PCM_16BIT);
        if (bufferSize < minSize) {
            bufferSize = minSize;
        }
        track = new AudioTrack(AudioManager.STREAM_MUSIC, sampleRate,
                AudioFormat.CHANNEL_CONFIGURATION_MONO,
                AudioFormat.ENCODING_PCM_16BIT, bufferSize,
                AudioTrack.MODE_STREAM);
        track.play();
        Log.i(SliderSynth.LOGTAG, "Minimum buffer size: " + minSize);
        Log.i(SliderSynth.LOGTAG, "Buffer size: " + bufferSize);
        buffer = new short[bufferSize];
        finalBuffer = new float[bufferSize];
        tmpBuffer = new float[bufferSize];
        keyboardBuffer = new float[bufferSize];
        stop = false;
        thread = new Thread(new Runnable() {
            public void run() {
                doMix();
            }
        });
        thread.setPriority(Thread.MAX_PRIORITY);
        thread.start();
    }

    @Override
    public void stop() {
        if (thread != null) {
            stop = true;
            try {
                thread.join();
            } catch (Exception ex) {
            }
        }
        keyboards.clear();
        keyboards = null;
        buffer = null;
        if (track != null) {
            track.stop();
        }
    }
}
