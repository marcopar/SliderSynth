package eu.flatworld.android.slider;

import java.util.ArrayList;
import java.util.List;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.util.Log;

public class Mixer implements Runnable {
	List<Keyboard> keyboards;
	AudioTrack track;

	boolean stop = false;
	Thread thread;

	int sampleRate;
	int bufferSize = 44100;
	short[] buffer;

	public Mixer() {
		keyboards = new ArrayList<Keyboard>();
	}

	public void addKeyboard(Keyboard keyboard) {
		keyboards.add(keyboard);
	}

	public void removeKeyboard(Keyboard keyboard) {
		keyboards.remove(keyboard);
	}

	public List<Keyboard> getKeyboards() {
		return keyboards;
	}

	public int getBufferSize() {
		return bufferSize;
	}

	public void setBufferSize(int bufferSize) {
		this.bufferSize = bufferSize;
	}

	public int getSampleRate() {
		return sampleRate;
	}

	public void setSampleRate(int sampleRate) {
		this.sampleRate = sampleRate;
	}

	void fillBuffer(short[] buffer) {
		// Log.d(Slider.LOGTAG, "Start fill");
		for (int i = 0; i < buffer.length; i++) {
			float val = 0;
			for (int j = 0; j < keyboards.size(); j++) {
				Keyboard k = keyboards.get(j);
				List<SoundGenerator> sgg = k.getSoundGenerators();
				for (int m = 0; m < sgg.size(); m++) {
					SoundGenerator sg = sgg.get(m);
					if (sg.getEnvelope().isReleased()) {
						continue;
					}
					val += sg.getValue();
				}
			}
			if (val > 1) {
				val = 1;
			}
			if (val < -1) {
				val = -1;
			}
			buffer[i] = (short) (val * Short.MAX_VALUE);
			Thread.yield();
		}
		// Log.d(Slider.LOGTAG, "Stop fill");
	}

	public void run() {
		while (!stop) {
			fillBuffer(buffer);
			int n = track.write(buffer, 0, bufferSize);
			// Log.d(Slider.LOGTAG, String.format("Write buffer %d/%d", n,
			// buffer.length));
		}
	}

	void sleep(long t) {
		try {
			Thread.sleep(t);
		} catch (Exception ex) {
		}
	}

	public void start() {
		int minSize = AudioTrack.getMinBufferSize(sampleRate,
				AudioFormat.CHANNEL_CONFIGURATION_MONO,
				AudioFormat.ENCODING_PCM_16BIT);
		if (bufferSize < minSize) {
			bufferSize = minSize;
		}
		track = new AudioTrack(AudioManager.STREAM_MUSIC, sampleRate,
				AudioFormat.CHANNEL_CONFIGURATION_MONO,
				AudioFormat.ENCODING_PCM_16BIT, bufferSize,
				AudioTrack.MODE_STREAM);
		track.play();
		Log.i(Slider.LOGTAG, "Minimum buffer size: " + minSize);
		Log.i(Slider.LOGTAG, "Minimum buffer size: " + bufferSize);
		buffer = new short[bufferSize];
		stop = false;
		thread = new Thread(this);
		thread.setPriority(Thread.MAX_PRIORITY);
		thread.start();
	}

	public void stop() {
		if (thread != null) {
			stop = true;
			try {
				thread.join();
			} catch (Exception ex) {
			}
		}
		keyboards.clear();
		keyboards = null;
		buffer = null;
		if (track != null) {
			track.stop();
		}
	}
}
