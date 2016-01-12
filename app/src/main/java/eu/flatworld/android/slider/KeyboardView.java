package eu.flatworld.android.slider;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.drawable.Drawable;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

/**
 * Created by marcopar on 22/07/14.
 */
public class KeyboardView extends View {
    final static int LIGHT_COLOR = 0xFFF0F0F0;
    final static int DARK_COLOR = 0xFF0F0F0F;

    String name;

    List<SoundGenerator> soundGenerators;
    FrequencyManager frequencyManager;
    VolumeManager volumeManager;
    Filter filter;

    HashMap<Integer, SoundGenerator> pointerToSoundGenerator;

    Paint paintText = new Paint();
    Paint paintSemitone = new Paint();
    Paint paintMarker = new Paint();

    boolean showSemitonesLines = false;
    boolean showSemitonesNames = false;
    boolean showCurrentNotes;

    Drawable background;
    ColorEffect colorEffect;

    float lastX[] = new float[20];
    float lastY[] = new float[20];

    final static String semitonesNames[] = {"A", "A#", "B", "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#"};

    public KeyboardView(Context context, String name, int firstOctave, int numberOfOctaves, float maxvol,
                        Drawable background, boolean showSemitonesLines, boolean showSemitonesNames, ColorEffect colorEffect,
                        boolean showCurrentNotes) {
        super(context);
        this.name = name;
        this.showSemitonesLines = showSemitonesLines;
        this.showSemitonesNames = showSemitonesNames;
        this.showCurrentNotes = showCurrentNotes;
        this.background = background;
        this.colorEffect = colorEffect;
        soundGenerators = new ArrayList<SoundGenerator>();
        frequencyManager = new FrequencyManager(firstOctave, numberOfOctaves);
        volumeManager = new VolumeManager(maxvol);
        pointerToSoundGenerator = new HashMap<Integer, SoundGenerator>();
        setBackgroundDrawable(background);
        paintText.setColor(LIGHT_COLOR);
        paintText.setTextSize(20);
        paintSemitone.setColor(LIGHT_COLOR);
        paintSemitone.setStrokeWidth(2);
        paintMarker.setColor(LIGHT_COLOR);
        paintMarker.setStrokeWidth(4);
        paintMarker.setAntiAlias(true);
        Arrays.fill(lastX, -1);
        Arrays.fill(lastY, -1);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        int semitones = frequencyManager.getNumberOfOctaves() * 12;
        if (showSemitonesLines) {
            for (int i = 1; i < semitones; i++) {
                canvas.drawLine(i * getWidth() / semitones, 0, i * getWidth() / semitones, getHeight(), paintSemitone);
            }
        }
        if (showSemitonesNames) {
            for (int i = 0; i < semitones; i++) {
                canvas.drawText(semitonesNames[i % 12], i * getWidth() / semitones + 5, 23, paintText);
            }
        }
        if (showCurrentNotes) {
            for (int i = 0; i < lastX.length; i++) {
                if (lastX[i] != -1) {
                    canvas.drawLine(lastX[i], 0, lastX[i], getHeight(), paintMarker);
                }
            }
        }
        //canvas.drawText(String.format("%.1f Hz", soundGenerators.get(0).getOscillator().getFrequency()), 20, getHeight() - 20, paintText);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int maskedAction = event.getActionMasked();
        switch (maskedAction) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                touchDown(event);
                break;
            }
            case MotionEvent.ACTION_MOVE: {
                touchDragged(event);
                break;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                touchUp(event);
                break;
            }
        }
        return true;
    }


    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public void setFilter(Filter filter) {
        this.filter = filter;
    }

    public Filter getFilter() {
        return filter;
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

    int getSmoothRainbowColor(int pointer, float x, float y) {
        int w = getWidth();
        int h = getHeight();
        float hsv[] = new float[]{0, 1, 1};

        hsv[0] = x / w * 360;
        hsv[1] = y / h;
        hsv[2] = 1;
        return android.graphics.Color.HSVToColor(hsv);
    }

    int getHardRainbowColor(int pointer, float x, float y) {
        return 0xFF000000 + (int) Math.round(0xFFFFFF * Math.random());
    }

    int getBgColor(int pointer, float x, float y, ColorEffect colorMode) {
        int color = -1;
        switch (colorMode) {
            case NONE:
                color = -1;
                break;
            case SOFT_RAINBOW:
                color = getSmoothRainbowColor(pointer, x, y);
                break;
            case HARD_RAINBOW:
                color = getHardRainbowColor(pointer, x, y);
                break;
        }
        float brightness = 0.2126f * ((color & 0xFF0000) >> 16) + 0.7152f * ((color & 0xFF00) >> 8) + 0.0722f * (color & 0xFF);
        if (brightness >= 127) {
            paintText.setColor(DARK_COLOR);
            paintSemitone.setColor(DARK_COLOR);
            paintMarker.setColor(DARK_COLOR);
        } else {
            paintText.setColor(LIGHT_COLOR);
            paintSemitone.setColor(LIGHT_COLOR);
            paintMarker.setColor(LIGHT_COLOR);
        }
        return color;
    }

    public void touchDown(MotionEvent event) {
        int pointerIndex = event.getActionIndex();
        int pointer = event.getPointerId(pointerIndex);
        float px = event.getX(pointerIndex);
        float py = event.getY(pointerIndex);
        int w = getWidth();
        int h = getHeight();
        SoundGenerator sg = getNextSoundGenerator();
        sg.setTimestamp(System.currentTimeMillis());
        pointerToSoundGenerator.put(pointer, sg);
        sg.setTargetFrequency(frequencyManager.getFrequency(px / w));
        sg.setTargetVolume(volumeManager.getVolume(py / h));
        sg.getEnvelope().noteOn();
        if (colorEffect != ColorEffect.NONE) {
            setBackgroundColor(getBgColor(pointer, px, py, colorEffect));
        }
        lastX[pointer] = px;
        lastY[pointer] = py;
        invalidate();
    }

    public void touchUp(MotionEvent event) {
        int pointerIndex = event.getActionIndex();
        int pointer = event.getPointerId(pointerIndex);
        float px = event.getX(pointerIndex);
        float py = event.getY(pointerIndex);

        SoundGenerator sg = pointerToSoundGenerator.get(pointer);
        sg.getEnvelope().noteOff();
        setBackgroundDrawable(background);
        lastX[pointer] = -1;
        lastY[pointer] = -1;
        paintText.setColor(LIGHT_COLOR);
        paintSemitone.setColor(LIGHT_COLOR);
        paintMarker.setColor(LIGHT_COLOR);
        invalidate();
    }

    public void touchDragged(MotionEvent event) {
        for (int i = 0; i < event.getPointerCount(); i++) {
            int pointer = event.getPointerId(i);
            int w = getWidth();
            int h = getHeight();
            float px = event.getX(i);
            float py = event.getY(i);
            SoundGenerator sg = pointerToSoundGenerator.get(pointer);
            float fp = px / w;
            float fv = py / h;
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
            if (colorEffect != ColorEffect.NONE) {
                setBackgroundColor(getBgColor(pointer, px, py, colorEffect));
            }
            lastX[pointer] = px;
            lastY[pointer] = py;
            invalidate();
        }
    }

    public VolumeManager getVolumeManager() {
        return volumeManager;
    }

    public FrequencyManager getFrequencyManager() {
        return frequencyManager;
    }
}
