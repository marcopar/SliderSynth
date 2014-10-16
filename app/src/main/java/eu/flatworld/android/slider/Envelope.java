package eu.flatworld.android.slider;


/**
 * An envelope controls a value over time.
 */
public class Envelope {
    long attack;
    float attackSlope;
    long decay;
    long decayEnd;
    float decaySlope;
    float sustain;
    long release;
    long releaseStart;
    long releaseEnd;
    float releaseSlope;
    float max;
    float min;
    long currentSample;
    float lastValue;
    float releaseStartValue;

    public enum State {
        ATTACK, DECAY, SUSTAIN, RELEASE, DONE
    }

    ;

    State state;

    public Envelope() {
        attack = 0;
        attackSlope = 0;
        decay = 0;
        decayEnd = 0;
        decaySlope = 0;
        sustain = 1;
        release = 0;
        releaseStart = 0;
        releaseEnd = 0;
        releaseSlope = 0;
        min = 0;
        max = 1;
        currentSample = 0;
        releaseStartValue = 0;
        state = State.DONE;
    }

    /**
     * @param attack in samples
     */
    public void setAttack(long attack) {
        this.attack = attack;
        recalculateSlopes();
    }

    public long getAttack() {
        return attack;
    }

    /**
     * @param decay in samples
     */
    public void setDecay(long decay) {
        this.decay = decay;
        recalculateSlopes();
    }

    public long getDecay() {
        return decay;
    }

    /**
     * @param sustain volume (usually between 0.0 and 1.0)
     */
    public void setSustain(float sustain) {
        this.sustain = sustain;
        recalculateSlopes();
    }

    public float getSustain() {
        return sustain;
    }


    /**
     * @param release in samples
     */
    public void setRelease(long release) {
        this.release = release;
    }

    public long getRelease() {
        return release;
    }

    public void setMax(float max) {
        this.max = max;
        recalculateSlopes();
    }

    public float getMax() {
        return max;
    }

    public void setMin(float min) {
        this.min = min;
        recalculateSlopes();
    }

    public float getMin() {
        return min;
    }

    public State getState() {
        return state;
    }

    void recalculateSlopes() {
        decayEnd = attack + decay;
        if (attack == 0) {
            attackSlope = 1;
        } else {
            attackSlope = (max - min) / attack;
        }
        if (decay == 0) {
            decaySlope = 1;
        } else {
            decaySlope = (max - sustain) / decay;
        }
    }

    /**
     * Invoked when the note is pressed.
     */
    public synchronized void noteOn() {
        if (state == State.DONE) {
            currentSample = 0;
        } else {
            //find the current sample from the current value so the attack slope
            //starts where the release/decay slope arrived
            //value = currentSample * attackSlope + min;
            if (attackSlope != 0) {
                currentSample = Math.round((lastValue - min) / attackSlope);
            } else {
                currentSample = 0;
            }
        }
        //recalculateSlopes();
        state = State.ATTACK;
        //Log.d(SliderSynth.LOGTAG, "n on" + state.toString());
    }

    /**
     * Invoked when the note is released.
     */
    public synchronized void noteOff() {
        state = State.RELEASE;
        releaseStartValue = lastValue;
        if (release == 0) {
            releaseSlope = 1;
        } else {
            releaseSlope = (releaseStartValue - min) / release;
        }
        releaseStart = currentSample;
        releaseEnd = currentSample + release;
        //Log.d(SliderSynth.LOGTAG, "n off" + state.toString());
    }

    /**
     * @return true when the note has finished playing.
     */
    public boolean isDone() {
        return (state == State.DONE);
    }

    public float getValue() {
        currentSample++;
        float value = 0;
        if (state == State.ATTACK || state == State.DECAY) {
            if (currentSample > decayEnd) {
                state = State.SUSTAIN;
                //Log.d(SliderSynth.LOGTAG, state.toString());
            } else if (currentSample > attack) {
                state = State.DECAY;
                //Log.d(SliderSynth.LOGTAG, state.toString());
            }
        }
        if (state == State.SUSTAIN) {
            if (sustain <= 0) {
                state = State.DONE;
                //Log.d(SliderSynth.LOGTAG, state.toString());
            }
        }
        if (state == State.RELEASE) {
            if (currentSample > releaseEnd) {
                state = State.DONE;
                //Log.d(SliderSynth.LOGTAG, state.toString());
            }
        }
        switch (state) {
            case ATTACK:
                value = currentSample * attackSlope + min;
                value = Math.min(value, max);
                break;
            case DECAY:
                value = max - (currentSample - attack) * decaySlope;
                value = Math.max(value, sustain);
                break;
            case SUSTAIN:
                value = sustain;
                break;
            case RELEASE:
                value = releaseStartValue - (currentSample - releaseStart)
                        * releaseSlope;
                value = Math.max(value, min);
                break;
            case DONE:
                value = min;
                break;
            default:
                throw new IllegalStateException("Unhandled state: " + state);
        }
        lastValue = value;
        return value;
    }

}
