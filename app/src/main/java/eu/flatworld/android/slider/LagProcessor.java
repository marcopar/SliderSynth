package eu.flatworld.android.slider;

/**
 * A lag processor, used to implement glide.
 */
public class LagProcessor {
	final Envelope envelope = new Envelope();
	long samplesUp;
	long samplesDown;
	boolean hasLastValue;
	float lastValue;
	float targetValue;
	
	/**
	 * @param param
	 *            the parameter to glide.
	 */
	public LagProcessor() {
		samplesUp = 0;
		samplesDown = 0;
		hasLastValue = false;
		lastValue = 0;
		targetValue = 0;
	}

	public void setSamples(long samples) {
		setSamplesUp(samples);
		setSamplesDown(samples);
	}

	public void setSamplesUp(long samples) {
		samplesUp = samples;
	}

	public void setSamplesDown(long samples) {
		samplesDown = samples;
	}

	public void setTargetValue(float targetValue) 
	{
		this.targetValue = targetValue;
	}
	
	public void reset() {
		hasLastValue = false;
	}

	public float getValue() {
		if (!hasLastValue || lastValue != targetValue) {
			float diff = Math.abs(lastValue - targetValue);
			if (!hasLastValue) {
				// No previous value so the envelope simply ways returns the
				// current
				// value in the sustain state.
				envelope.setMin(0);
				envelope.setMax(targetValue);
				envelope.setAttack(0);
				envelope.setDecay(0);
				envelope.setSustain(targetValue);
				envelope.setRelease(0);
				envelope.noteOn();
			} else if (lastValue < targetValue) {
				// Slope up
				envelope.setMin(lastValue);
				envelope.setMax(targetValue);
				envelope.setAttack((long) (samplesUp * diff));
				envelope.setDecay(0);
				envelope.setSustain(targetValue);
				envelope.setRelease(0);
				envelope.noteOn();
			} else {
				// Slope down
				envelope.setMax(lastValue);
				envelope.setMin(targetValue);
				envelope.setAttack(0);
				envelope.setDecay(0);
				envelope.setSustain(lastValue);
				envelope.setRelease((long) (samplesDown * diff));
				//envelope.noteOn();
				envelope.noteOff();
			}
			lastValue = targetValue;
			hasLastValue = true;
		}

		return envelope.getValue();
	}
}
