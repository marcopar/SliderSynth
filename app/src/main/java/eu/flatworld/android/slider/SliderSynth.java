package eu.flatworld.android.slider;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import java.util.Arrays;
import java.util.List;

public class SliderSynth extends Activity {
    public static String LOGTAG = "slidersynth";

    public static int MAX_CHANNELS = 4;

    int[] lastTx = new int[MAX_CHANNELS];
    int[] lastTy = new int[MAX_CHANNELS];

    Mixer mixer;
    List<KeyboardView> keyboards;

    float density;

    boolean showStats = false;
    boolean dynamicBackground = false;

    CpuLoad cpu = new CpuLoad();
    Drawable keyboardColor[] = null;

    public SliderSynth() {
        Arrays.fill(lastTx, Integer.MAX_VALUE);
        Arrays.fill(lastTy, Integer.MAX_VALUE);
        String version;
        try {
            version = getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception ex) {
            version = "-";
            Log.e(LOGTAG, "Error getting version", ex);
        }

    }

    void init() {
        SharedPreferences pref = PreferenceManager.getDefaultSharedPreferences(this);
        PreferenceManager.setDefaultValues(this, R.xml.preferences, true);

        showStats = pref.getBoolean("showstats", false);
        dynamicBackground = pref.getBoolean("dynamicbackground", false);

        int numberOfKeyboards = 2;
        int screenLayout = getResources().getConfiguration().screenLayout & Configuration.SCREENLAYOUT_SIZE_MASK;
        if (screenLayout == Configuration.SCREENLAYOUT_SIZE_LARGE) {
            numberOfKeyboards = 4;
        }
        try {
            numberOfKeyboards = Integer.valueOf(pref.getString(
                    "numberofkeyboards", "" + numberOfKeyboards));
        } catch (Throwable ex) {
            Log.w(LOGTAG, "Parse numberofkeyboards: " + ex.toString(), ex);
        }

        int sampleRate = 44100;
        try {
            sampleRate = Integer.valueOf(pref.getString("samplerate", "44100"));
        } catch (Throwable ex) {
            Log.w(LOGTAG, "Parse samplerate: " + ex.toString(), ex);
        }

        int bufferSize = pref.getInt("buffersize", 50);

        mixer = new AddAndClipMixer();
        int byteBufferSize = Math.round(sampleRate * bufferSize / 1000f);
        mixer.setBufferSize(byteBufferSize);
        ViewGroup parent = (ViewGroup) findViewById(R.id.contentLayout);
        parent.removeAllViews();
        LinearLayout.LayoutParams l = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0);
        l.weight = 1;
        for (int i = 0; i < numberOfKeyboards; i++) {
            int firstOctave = 4;
            try {
                firstOctave = Integer.valueOf(pref.getString("firstoctave"
                        + (i + 1), "4"));
            } catch (Throwable ex) {
                Log.w(LOGTAG,
                        "Parse firstoctave " + (i + 1) + ": " + ex.toString(), ex);
            }
            int octavesPerKeyboard = 2;
            try {
                octavesPerKeyboard = Integer.valueOf(pref.getString(
                        "octavesperkeyboard" + (i + 1), "2"));
            } catch (Throwable ex) {
                Log.w(LOGTAG,
                        "Parse octavesperkeyboard " + (i + 1) + ": "
                                + ex.toString(), ex
                );
            }
            int attack = pref.getInt("attack" + (i + 1), 50);
            int release = pref.getInt("release" + (i + 1), 250);
            float maxvol = pref.getInt("maxvol" + (i + 1), 20) / 100f;
            KeyboardView kbd = new KeyboardView(this, "kbd" + i,
                    firstOctave, octavesPerKeyboard, maxvol, keyboardColor[i]);
            for (int j = 0; j < MAX_CHANNELS; j++) {
                SoundGenerator sg = new SoundGenerator(sampleRate);
                sg.getOscillator().setWaveForm(
                        WaveForm.valueOf(pref.getString(
                                String.format("waveform%d", i + 1), "SINE"))
                );
                sg.getEnvelope().setAttack((attack * sampleRate) / 1000);
                sg.getEnvelope().setRelease((release * sampleRate) / 1000);
                sg.getLagProcessor().setSamples(sampleRate * 2);
                kbd.addSoundGenerator(sg);
            }
            mixer.addKeyboard(kbd);
            parent.addView(kbd);
        }
        keyboards = mixer.getKeyboards();
        mixer.setSampleRate(sampleRate);
        mixer.start();
    }

    void deinit() {
        mixer.stop();
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.main);
        keyboardColor = new Drawable[]{getResources().getDrawable(R.drawable.keyboard_red),
                getResources().getDrawable(R.drawable.keyboard_green),
                getResources().getDrawable(R.drawable.keyboard_blue),
                getResources().getDrawable(R.drawable.keyboard_yellow)};
    }

    @Override
    protected void onResume() {
        super.onResume();
        init();
    }

    @Override
    protected void onPause() {
        super.onPause();
        deinit();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.slider_synth, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        // Handle action bar item clicks here. The action bar will
        // automatically handle clicks on the Home/Up button, so long
        // as you specify a parent activity in AndroidManifest.xml.
        int id = item.getItemId();
        if (id == R.id.action_settings) {
            Intent i = new Intent(this, SettingsActivity.class);
            this.startActivity(i);
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
}