package eu.flatworld.android.slider;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

public class Keyboard {
	String id;
	float x;
	float y;
	float w;
	float h;
	
	List<SoundGenerator> soundGenerators;
	FrequencyManager frequencyManager;
	VolumeManager volumeManager;
	
	HashMap<Integer, SoundGenerator> pointerToSoundGenerator;

	public Keyboard(String id, float x, float y, float w, float h,
			int firstOctave, int numberOfOctaves, float maxvol) {
		this.id = id;
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
		soundGenerators = new ArrayList<SoundGenerator>();
		frequencyManager = new FrequencyManager(firstOctave, numberOfOctaves);
		volumeManager = new VolumeManager(maxvol);
		pointerToSoundGenerator = new HashMap<Integer, SoundGenerator>();
	}

	public String getId() {
		return id;
	}

	public void setId(String id) {
		this.id = id;
	}

	public void addSoundGenerator(SoundGenerator soundGenerator) {
		soundGenerators.add(soundGenerator);
	}

	public List<SoundGenerator> getSoundGenerators() {
		return soundGenerators;
	}

	public boolean pointIsInKeyboard(float px, float py) {
		boolean r = (px >= x) && (px < x + w) && (py >= y) && (py < y + h);
		return r;
	}
	
	SoundGenerator getNextSoundGenerator() {
		long ts = Long.MAX_VALUE;
		SoundGenerator olderSg = null;
		for (SoundGenerator sg : soundGenerators) {
			if(sg.getEnvelope().getState() == Envelope.State.DONE) {			
				return sg;
			}
			if(sg.getTimestamp() < ts) {
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
		if(fp <= 0) {
			fp = 0;
		}
		if(fp > 1) {
			fp = 1;
		}
		if(fv <= 0) {
			fv = Float.MIN_VALUE;
		}
		if(fv > 1) {
			fv = 1;
		}
		sg.setTargetFrequency(frequencyManager.getFrequency(fp));
		sg.setTargetVolume(volumeManager.getVolume(fv));
	}

}
