package eu.flatworld.android.slider;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;

public class MenuActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN);
        setContentView(R.layout.menu);

        Button b = findViewById(R.id.bSettings);
        b.setOnClickListener(v -> {
            Intent i = new Intent(MenuActivity.this, SettingsActivity.class);
            MenuActivity.this.startActivity(i);
        });
        b = findViewById(R.id.bPlay);
        b.setOnClickListener(v -> {
            Intent i = new Intent(MenuActivity.this, SliderSynth.class);
            MenuActivity.this.startActivity(i);
        });
        b = findViewById(R.id.bAbout);
        b.setOnClickListener(v -> {
            Intent i = new Intent(MenuActivity.this, AboutActivity.class);
            MenuActivity.this.startActivity(i);
        });

    }
}
