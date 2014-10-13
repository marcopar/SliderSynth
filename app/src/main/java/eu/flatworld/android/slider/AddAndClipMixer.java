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
    int bufferSize = 44100;
    short[] buffer;
    EchoFilter ef = new EchoFilter(1 * 44100, 0.6f);

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

    void fillBuffer(short[] buffer) {
        // Log.d(Slider.LOGTAG, "Start fill");
        for (int i = 0; i < buffer.length; i++) {
            float val = 0;
            for (int j = 0; j < keyboards.size(); j++) {
                KeyboardView k = keyboards.get(j);
                List<SoundGenerator> sgg = k.getSoundGenerators();
                for (int m = 0; m < sgg.size(); m++) {
                    SoundGenerator sg = sgg.get(m);
                    if (sg.getEnvelope().isReleased()) {
                        continue;
                    }
                    val += sg.getValue();
                }
            }
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
        while (!stop) {
            fillBuffer(buffer);
            ef.filter(buffer, 0, buffer.length);
            int n = track.write(buffer, 0, bufferSize);
            // Log.d(Slider.LOGTAG, String.format("Write buffer %d/%d", n,
            // buffer.length));
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
        Log.i(SliderSynth.LOGTAG, "Minimum buffer size: " + bufferSize);
        buffer = new short[bufferSize];
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
