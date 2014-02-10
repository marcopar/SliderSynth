package eu.flatworld.android.slider;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.preference.PreferenceManager;
import android.util.Log;

import com.badlogic.gdx.ApplicationListener;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.InputProcessor;
import com.badlogic.gdx.audio.AudioDevice;
import com.badlogic.gdx.graphics.GL10;
import com.badlogic.gdx.graphics.GL11;
import com.badlogic.gdx.graphics.OrthographicCamera;
import com.badlogic.gdx.graphics.Pixmap;
import com.badlogic.gdx.graphics.Pixmap.Format;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.BitmapFont;
import com.badlogic.gdx.graphics.g2d.NinePatch;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.math.MathUtils;
import com.badlogic.gdx.math.Vector3;

public class Slider implements ApplicationListener, InputProcessor {	
	public static String LOGTAG = "slider";
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

	BitmapFont bf;
	SpriteBatch sb;
	OrthographicCamera cam;
	Vector3 p1 = new Vector3();

	Pixmap pixmap;
	Texture texture;
	NinePatch[] npKbd;

	public Slider(Context context) {
		this.context = context;
		Arrays.fill(lastTx, Integer.MAX_VALUE);
		Arrays.fill(lastTy, Integer.MAX_VALUE);
	}

	CpuLoad cpu = new CpuLoad();
	void drawStats(float x, float y) {
		bf.draw(sb, String.format("FPS: %2d  CPU: %.2f", Gdx.graphics.getFramesPerSecond(), cpu.getUsage()),x, y);
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

		npKbd = new NinePatch[MAX_CHANNELS];
		for (int i = 0; i < MAX_CHANNELS; i++) {
			npKbd[i] = new NinePatch(
					new Texture("keyboard" + (i + 1) + ".png"), 8, 8, 8, 8);
		}
		Gdx.input.setInputProcessor(this);
		Gdx.input.setCatchMenuKey(true);
		density = Gdx.graphics.getDensity();
		w = Gdx.graphics.getWidth();
		h = Gdx.graphics.getHeight();		

		bf = new BitmapFont();
		bf.setScale(density);

		cam = new OrthographicCamera(w, h);
		cam.position.set(w / 2, h / 2, 0);
		cam.update();

		sb = new SpriteBatch();
		sb.setProjectionMatrix(cam.combined);

		init();
	}

	public void render() {
		Gdx.gl.glClearColor(bgR, bgG, bgB, bgA);
		Gdx.gl.glClear(GL10.GL_COLOR_BUFFER_BIT);
		sb.begin();
		
		for (int i = 0; i < keyboards.size(); i++) {
			Keyboard k = keyboards.get(i);
			npKbd[i].draw(sb, k.x, k.y, k.w, k.h);
		}

		if (showStats) {
			sb.setColor(1f, 1f, 1f, 1f);
			drawStats(Gdx.graphics.getWidth() - 250, 50);
		}
		sb.end();
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
		
		pixmap = new Pixmap(PIXMAP_WIDTH, PIXMAP_HEIGHT, Format.RGBA8888);
		texture = new Texture(pixmap);
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

		mixer = new Mixer();
		int byteBufferSize = MathUtils.round(sampleRate * bufferSize / 1000f);
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
			Keyboard kbd = new Keyboard("kbd" + i, 0,
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
		updateRGBA(-1, 0, 0);
	}

	void deinit() {
		mixer.stop();
		texture.dispose();
		pixmap.dispose();
	}

	@Override
	public boolean keyDown(int keycode) {
		if (keycode == Input.Keys.MENU) {
			Intent i = new Intent(context, SettingsActivity.class);
			context.startActivity(i);
		}
		return false;
	}

	@Override
	public boolean keyUp(int keycode) {
		return false;
	}

	@Override
	public boolean keyTyped(char character) {
		return false;
	}

	float hsv[] = new float[] { 0, 1, 1 };

	void updateRGBA(int pointer, float x, float y) {
		if(!dynamicBackground || pointer == -1) {
			bgR = 0;
			bgG = 0;
			bgB = 0;
			bgA = 0;
			return;
		}
		if (pointer == 0) {
			hsv[0] = x / w * 360;			
		}
		if (pointer == 1) {
			hsv[1] = (float)Math.max(y / h, 0.5);
			hsv[2] = 1;//x / w;
		}
		int c = android.graphics.Color.HSVToColor(hsv);
		bgR = ((c & 0xFF0000) >> 16) / 255f;
		bgG = ((c & 0xFF00) >> 8) / 255f;
		bgB = (c & 0xFF) / 255f;
		bgA = 1;
		float gray = (float) (0.3 * bgR + 0.59 * bgG + 0.11 * bgB);
		if (gray > 0.5) {
			fgR = 0;
			fgG = 0;
			fgB = 0;
			fgA = 0.5f;
		} else {
			fgR = 1;
			fgG = 1;
			fgB = 1;
			fgA = 0.5f;
		}
	}

	HashMap<Integer, Keyboard> pointerKeyboard = new HashMap<Integer, Keyboard>();

	@Override
	public boolean touchDown(int tx, int ty, int pointer, int button) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		cam.unproject(p1.set(tx, ty, 0));
		x = (int) p1.x;
		y = (int) p1.y;
		updateRGBA(pointer, x, y);
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

	@Override
	public boolean touchUp(int tx, int ty, int pointer, int button) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		cam.unproject(p1.set(tx, ty, 0));
		this.x = (int) p1.x;
		this.y = (int) p1.y;
		Keyboard kbd = pointerKeyboard.get(pointer);
		kbd.touchUp(pointer, x, y);
		return true;
	}

	@Override
	public boolean touchDragged(int tx, int ty, int pointer) {
		if (pointer >= MAX_CHANNELS) {
			return false;
		}
		if(lastTx[pointer] == tx && lastTy[pointer] == ty) {
			return true;
		}
		lastTx[pointer] = tx;
		lastTy[pointer] = ty;
		
		cam.unproject(p1.set(tx, ty, 0));
		x = (int) p1.x;
		y = (int) p1.y;
		updateRGBA(pointer, x, y);
		Keyboard kbd = pointerKeyboard.get(pointer);
		kbd.touchDragged(pointer, x, y);
		return true;
	}

	@Override
	public boolean mouseMoved(int x, int y) {
		return false;
	}

	@Override
	public boolean scrolled(int amount) {
		return false;
	}
}
