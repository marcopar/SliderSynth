package eu.flatworld.android.slider;

import android.content.res.Configuration;

import com.badlogic.gdx.backends.android.AndroidApplication;

public class SliderActivity extends AndroidApplication {
	public void onCreate(android.os.Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		initialize(new Slider(this), false);
	}

	@Override
	public void onConfigurationChanged(Configuration config) {
		super.onConfigurationChanged(config);
	}
	
	
}
