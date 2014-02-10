package eu.flatworld.android.slider;



public class VolumeManager {
	float maximumVolume;
	
	public VolumeManager(float maximumVolume) {
		this.maximumVolume = maximumVolume;
	}
	
	public float getVolume(float value) {
		//float v = value * maximumVolume;
		return maximumVolume;
	}
}
