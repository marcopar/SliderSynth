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
    Thread threadMix;
    Thread threadWrite;

    int sampleRate;
    int bufferSize = 0;
    short[] mixBuffer;
    short[] writeBuffer;
    float[] tmpBuffer;
    float[] finalBuffer;
    float[] keyboardBuffer;

    CircularBuffer cb;

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

    void sumBuffers(float[] dest, float[] src, int n) {
        for (int i = 0; i < n; i++) {
            dest[i] += src[i];
        }
    }

    void setBuffer(float[] dest, float value) {
        for (int i = 0; i < dest.length; i++) {
            dest[i] = value;
        }
    }

    void fillBuffer(short[] buffer, int n) {
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
                sg.getValues(tmpBuffer, n);
                sumBuffers(keyboardBuffer, tmpBuffer, n);
            }
            Filter filter = k.getFilter();
            if (filter != null) {
                filter.filter(keyboardBuffer, 0, n);
            }
            sumBuffers(finalBuffer, keyboardBuffer, n);
        }
        for (int i = 0; i < n; i++) {
            float val = finalBuffer[i];
            if (val > 1) {
                val = 1;
            }
            if (val < -1) {
                val = -1;
            }
            buffer[i] = (short) (val * Short.MAX_VALUE);
        }
    }

    void doMix() {
        while (!stop) {
            long t = System.currentTimeMillis();
            int n = Math.min(cb.getFreeSpace(), mixBuffer.length);
            fillBuffer(mixBuffer, n);
            cb.write(mixBuffer, 0, n);
            Thread.yield();
            //Log.d(SliderSynth.LOGTAG, String.format("fill %d %d %d", n, cb.getFreeSpace(), (System.currentTimeMillis() - t)));
        }
    }

    void writeMix() {
        while (!stop) {
            long t = System.currentTimeMillis();
            int n = Math.min(cb.getAvailableData(), writeBuffer.length);
            cb.read(writeBuffer, 0, n);
            track.write(writeBuffer, 0, n);
            //Log.d(SliderSynth.LOGTAG, String.format("write %d %d %d", cb.getAvailableData(), n, (System.currentTimeMillis() - t)));
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
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT);
        if (bufferSize < minSize) {
            bufferSize = minSize;
        }
        track = new AudioTrack(AudioManager.STREAM_MUSIC, sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT, bufferSize,
                AudioTrack.MODE_STREAM);
        track.play();
        Log.i(SliderSynth.LOGTAG, "Minimum buffer size: " + minSize);
        Log.i(SliderSynth.LOGTAG, "Buffer size: " + bufferSize);
        writeBuffer = new short[bufferSize];
        mixBuffer = new short[bufferSize];
        finalBuffer = new float[bufferSize];
        tmpBuffer = new float[bufferSize];
        keyboardBuffer = new float[bufferSize];
        cb = new CircularBuffer(bufferSize);
        stop = false;
        threadMix = new Thread(new Runnable() {
            public void run() {
                doMix();
            }
        });
        threadMix.setPriority(Thread.MAX_PRIORITY);
        threadMix.start();
        threadWrite = new Thread(new Runnable() {
            public void run() {
                writeMix();
            }
        });
        threadWrite.start();
    }

    @Override
    public void stop() {
        if (threadMix != null) {
            stop = true;
            try {
                threadMix.join();
            } catch (Exception ex) {
            }
        }
        if (threadWrite != null) {
            stop = true;
            try {
                threadWrite.join();
            } catch (Exception ex) {
            }
        }
        keyboards.clear();
        keyboards = null;
        writeBuffer = null;
        mixBuffer = null;
        cb.clear();
        cb = null;
        if (track != null) {
            track.stop();
        }
    }
}
