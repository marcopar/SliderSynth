package eu.flatworld.android.slider;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.ViewGroup;
import android.widget.LinearLayout;

public class SliderSynth extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.main);

        LayoutInflater inflater = (LayoutInflater) getSystemService(Context.LAYOUT_INFLATER_SERVICE);
        ViewGroup parent = (ViewGroup) findViewById(R.id.contentLayout);

        KeyboardView kv;
        LinearLayout.LayoutParams l = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0);
        l.weight = 1;
        kv = new KeyboardView(this, getResources().getDrawable(R.drawable.keyboard_red));
        parent.addView(kv, l);
        kv = new KeyboardView(this, getResources().getDrawable(R.drawable.keyboard_green));
        parent.addView(kv, l);
        kv = new KeyboardView(this, getResources().getDrawable(R.drawable.keyboard_blue));
        parent.addView(kv, l);
        kv = new KeyboardView(this, getResources().getDrawable(R.drawable.keyboard_yellow));
        parent.addView(kv, l);
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
