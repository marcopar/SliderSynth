package eu.flatworld.android.slider;

import android.content.Context;
import android.graphics.drawable.Drawable;
import android.view.View;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

/**
 * Created by marcopar on 22/07/14.
 */
public class KeyboardView extends View {
    String name;

    List<SoundGenerator> soundGenerators;
    FrequencyManager frequencyManager;
    VolumeManager volumeManager;

    HashMap<Integer, SoundGenerator> pointerToSoundGenerator;

    public KeyboardView(Context context, String name, int firstOctave, int numberOfOctaves, float maxvol,
                        Drawable color) {
        super(context);
        this.name = name;
        soundGenerators = new ArrayList<SoundGenerator>();
        frequencyManager = new FrequencyManager(firstOctave, numberOfOctaves);
        volumeManager = new VolumeManager(maxvol);
        pointerToSoundGenerator = new HashMap<Integer, SoundGenerator>();
        setBackgroundDrawable(color);
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public void addSoundGenerator(SoundGenerator soundGenerator) {
        soundGenerators.add(soundGenerator);
    }

    public List<SoundGenerator> getSoundGenerators() {
        return soundGenerators;
    }

    SoundGenerator getNextSoundGenerator() {
        long ts = Long.MAX_VALUE;
        SoundGenerator olderSg = null;
        for (SoundGenerator sg : soundGenerators) {
            if (sg.getEnvelope().getState() == Envelope.State.DONE) {
                return sg;
            }
            if (sg.getTimestamp() < ts) {
                olderSg = sg;
            }
        }
        return olderSg;
    }

    public void touchDown(int pointer, float px, float py) {
        SoundGenerator sg = getNextSoundGenerator();
        sg.setTimestamp(System.currentTimeMillis());
        pointerToSoundGenerator.put(pointer, sg);
        sg.setTargetFrequency(frequencyManager.getFrequency((px - x) / w));
        sg.setTargetVolume(volumeManager.getVolume((py - y) / h));
        sg.getEnvelope().noteOn();
    }

    public void touchUp(int pointer, float px, float py) {
        SoundGenerator sg = pointerToSoundGenerator.get(pointer);
        sg.getEnvelope().noteOff();
    }

    public void touchDragged(int pointer, float px, float py) {
        SoundGenerator sg = pointerToSoundGenerator.get(pointer);
        float fp = (px - x) / w;
        float fv = (py - y) / h;
        if (fp <= 0) {
            fp = 0;
        }
        if (fp > 1) {
            fp = 1;
        }
        if (fv <= 0) {
            fv = Float.MIN_VALUE;
        }
        if (fv > 1) {
            fv = 1;
        }
        sg.setTargetFrequency(frequencyManager.getFrequency(fp));
        sg.setTargetVolume(volumeManager.getVolume(fv));
    }

    public VolumeManager getVolumeManager() {
        return volumeManager;
    }

}
