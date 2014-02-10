package eu.flatworld.android.slider;

import android.app.ListActivity;
import android.content.Intent;
import android.content.res.Resources;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.ArrayAdapter;
import android.widget.ListView;
import android.widget.SimpleAdapter;

public class MenuActivity extends ListActivity {
	String[] values;
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		requestWindowFeature(Window.FEATURE_NO_TITLE);
	    getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
	    getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN);
	    super.onCreate(savedInstanceState);
	    
	    values = this.getResources().getStringArray(R.array.menu);
	    
	    ArrayAdapter<String> aa = new ArrayAdapter<String>(this, android.R.layout.simple_list_item_1, values);
	    setListAdapter(aa);
	}

	@Override
	protected void onListItemClick(ListView l, View v, int position, long id) {
		// TODO Auto-generated method stub
		super.onListItemClick(l, v, position, id);
		if(values[position].equals(this.getResources().getString(R.string.mainmenu_settings))) {
			Intent i = new Intent(this, SettingsActivity.class);
			this.startActivity(i);
		}
		if(values[position].equals(this.getResources().getString(R.string.mainmenu_about))) {
			Intent i = new Intent(this, AboutActivity.class);
			this.startActivity(i);
		}
	}
	
	
	
}
