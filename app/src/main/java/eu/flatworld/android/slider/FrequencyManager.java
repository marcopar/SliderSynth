package eu.flatworld.android.slider;

import android.util.Log;

public class FrequencyManager {
	float hz[] = null;
	float hzPosition[] = null;

	public FrequencyManager(int firstOctave, int numberOfOctaves) {
		hz = new float[numberOfOctaves + 1];
		hzPosition = new float[numberOfOctaves + 1];
		float range = 1f / numberOfOctaves;

		for (int i = 0; i < numberOfOctaves + 1; i++) {
            int n = 1 + 12 * (i + firstOctave);
            float f = 440 * (float) Math.pow(2, (n - 49f) / 12);
            hz[i] = f;
			hzPosition[i] = i * range;
		}
	}

	public float getFrequency(float value) {
		float min = 1;
		float max = 0;
		int minpos = 0;
		int maxpos = 1;
		int i = 0;
		for (i = 0; i < hzPosition.length - 1; i++) {
			min = hzPosition[i];
			max = hzPosition[i + 1];
			minpos = i;
			maxpos = i+1;
			if (value >= min && value <= max) {
				break;
			}
		}
		float f =  hz[minpos] + (value - min) / (max - min) * (hz[maxpos] - hz[minpos]);
		return f;
	}
}
