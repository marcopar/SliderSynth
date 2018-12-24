package eu.flatworld.android.slider;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.Window;
import android.view.WindowManager;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

public class AboutActivity extends AppCompatActivity implements OnClickListener {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        String version;
        try {
            version = getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception ex) {
            version = "-";
            Log.e(SliderSynth.LOGTAG, "Error getting version", ex);
        }

        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
        super.onCreate(savedInstanceState);

        setContentView(R.layout.about);
        TextView tv = findViewById(R.id.aboutTVName);
        try {
            tv.setText(getResources().getString(R.string.app_name) + " " + version + "\n\nwww.flatworld.eu");
        } catch (Exception e) {
            tv.setText(getResources().getString(R.string.app_name) + "\n\nwww.flatworld.eu");
        }

        tv = findViewById(R.id.aboutTVName);
        tv.setOnClickListener(this);
    }


    @Override
    public void onClick(View v) {
        if (v.getId() == R.id.aboutTVName) {
            Uri webpage = Uri.parse("http://www.flatworld.eu/");
            Intent intent = new Intent(Intent.ACTION_VIEW, webpage);
            startActivity(intent);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
    }
}
