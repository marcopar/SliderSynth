package eu.flatworld.android.slider;

public class Slider {
    /*
    public static String LOGTAG = "slidersynth";
    public static int PIXMAP_WIDTH = 1024;
	public static int PIXMAP_HEIGHT = 512;

	public static int MAX_CHANNELS = 4;

	int[] lastTx = new int[MAX_CHANNELS];
	int[] lastTy = new int[MAX_CHANNELS];

	Mixer mixer;
	List<Keyboard> keyboards;
	Context context;
	float h;
	float w;
	float x;
	float y;
	float density;

	float bgR;
	float bgG;
	float bgB;
	float bgA;
	float fgR;
	float fgG;
	float fgB;
	float fgA;

	boolean showStats = false;
	boolean dynamicBackground = false;

	public Slider(Context context) {
		this.context = context;
		Arrays.fill(lastTx, Integer.MAX_VALUE);
		Arrays.fill(lastTy, Integer.MAX_VALUE);
	}

	CpuLoad cpu = new CpuLoad();
	void drawStats(float x, float y) {

    }

	public void create() {
		String version;
		try {
			version = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
		} catch(Exception ex) {
			version = "-";
			Log.e(LOGTAG, "Error getting version", ex);
		}
		SharedPreferences pref = PreferenceManager.getDefaultSharedPreferences(context);
		init();
	}

	public void resize(int width, int height) {
	}

	public void pause() {
		deinit();
	}

	public void resume() {
		init();
	}

	public void dispose() {
	}

	void init() {
		SharedPreferences pref = PreferenceManager.getDefaultSharedPreferences(context);
		PreferenceManager.setDefaultValues(context, R.xml.preferences, true);

		showStats = pref.getBoolean("showstats", false);
		dynamicBackground = pref.getBoolean("dynamicbackground", false);

		int numberOfKeyboards = 2;
		int screenLayout = context.getResources().getConfiguration().screenLayout & Configuration.SCREENLAYOUT_SIZE_MASK;
		if(screenLayout == Configuration.SCREENLAYOUT_SIZE_LARGE) {
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
								+ ex.toString(), ex);
			}
			int attack = pref.getInt("attack" + (i + 1), 50);
			int release = pref.getInt("release" + (i + 1), 250);
			float maxvol = pref.getInt("maxvol" + (i + 1), 20) / 100f;
			KeyboardView kbd = new KeyboardView("kbd" + i, 0,
					i * h / numberOfKeyboards, w, h / numberOfKeyboards,
					firstOctave, octavesPerKeyboard, maxvol);
			for (int j = 0; j < MAX_CHANNELS; j++) {
				SoundGenerator sg = new SoundGenerator(sampleRate);
				sg.getOscillator().setWaveForm(
						WaveForm.valueOf(pref.getString(
								String.format("waveform%d", i + 1), "SINE")));
				sg.getEnvelope().setAttack((attack * sampleRate) / 1000);
				sg.getEnvelope().setRelease((release * sampleRate) / 1000);
				sg.getLagProcessor().setSamples(sampleRate * 2);
				kbd.addSoundGenerator(sg);
			}
			mixer.addKeyboard(kbd);
		}
		keyboards = mixer.getKeyboards();
		mixer.setSampleRate(sampleRate);
		mixer.start();
	}

	void deinit() {
		mixer.stop();
	}

	public boolean keyDown(int keycode) {
        //if (keycode == Input.Keys.MENU) {
          //  Intent i = new Intent(context, SettingsActivity.class);
			// context.startActivity(i);
		//}
		//return false;
	}

	HashMap<Integer, Keyboard> pointerKeyboard = new HashMap<Integer, Keyboard>();

	public boolean touchDown(int tx, int ty, int pointer, int button) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		Keyboard kbd = null;
		for (int i = 0; i < keyboards.size(); i++) {
			kbd = keyboards.get(i);
			if (kbd.pointIsInKeyboard(x, y)) {
				break;
			}
		}
		kbd.touchDown(pointer, x, y);
		pointerKeyboard.put(pointer, kbd);
		return true;
	}

	public boolean touchUp(int tx, int ty, int pointer, int button) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		Keyboard kbd = pointerKeyboard.get(pointer);
		kbd.touchUp(pointer, x, y);
		return true;
	}

	public boolean touchDragged(int tx, int ty, int pointer) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		if(lastTx[pointer] == tx && lastTy[pointer] == ty) {
			return true;
		}
		lastTx[pointer] = tx;
		lastTy[pointer] = ty;

		Keyboard kbd = pointerKeyboard.get(pointer);
		kbd.touchDragged(pointer, x, y);
		return true;
	}*/
}
