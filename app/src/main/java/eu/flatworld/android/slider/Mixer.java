package eu.flatworld.android.slider;

import java.util.List;

/**
 * Created by marcopar on 03/03/14.
 */
public interface Mixer {
    void addKeyboard(Keyboard keyboard);

    void removeKeyboard(Keyboard keyboard);

    List<Keyboard> getKeyboards();

    int getBufferSize();

    void setBufferSize(int bufferSize);

    int getSampleRate();

    void setSampleRate(int sampleRate);

    void start();

    void stop();
}
