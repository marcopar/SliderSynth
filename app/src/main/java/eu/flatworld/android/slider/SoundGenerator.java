package eu.flatworld.android.slider;


public class SoundGenerator {
    Oscillator oscillator;
    Envelope envelope;
    LagProcessor lagProcessor;

    float targetFrequency = -1;
    float targetVolume = -1;

    long timestamp;

    public SoundGenerator(int sampleRate) {
        oscillator = new Oscillator(0, sampleRate);
        envelope = new Envelope();
        envelope.setAttack(sampleRate / 10);
        envelope.setDecay(0);
        envelope.setRelease(sampleRate / 10);
        envelope.setSustain(1);
        envelope.setMax(1);
        lagProcessor = new LagProcessor();
        lagProcessor.setSamples(sampleRate / 10);
        timestamp = System.currentTimeMillis();
    }

    public void setTargetFrequency(float targetFrequency) {
        this.targetFrequency = targetFrequency;
    }

    public void setTargetVolume(float targetVolume) {
        this.targetVolume = targetVolume;
    }

    public Oscillator getOscillator() {
        return oscillator;
    }

    public Envelope getEnvelope() {
        return envelope;
    }

    public LagProcessor getLagProcessor() {
        return lagProcessor;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public float getValue() {
        long cs = oscillator.getCurrentSample();
        if (cs == 0) {
            oscillator.setFrequency(targetFrequency);
            //lagProcessor.setTargetValue(targetVolume);
            envelope.setSustain(targetVolume);
            envelope.setMax(targetVolume);
        }
        float o = oscillator.getValue();
        float e = envelope.getValue();
        //float lp2 = lagProcessor.getValue();
        float lp = 1;
        return o * e * lp;
    }
}
