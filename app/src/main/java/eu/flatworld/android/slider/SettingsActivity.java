package eu.flatworld.android.slider;

import android.content.SharedPreferences;
import android.content.SharedPreferences.OnSharedPreferenceChangeListener;
import android.os.Bundle;
import android.preference.EditTextPreference;
import android.preference.ListPreference;
import android.preference.Preference;
import android.preference.PreferenceActivity;
import android.preference.PreferenceCategory;
import android.preference.PreferenceManager;
import android.preference.PreferenceScreen;
import android.view.Window;
import android.view.WindowManager;

public class SettingsActivity extends PreferenceActivity implements
        OnSharedPreferenceChangeListener {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN);
        super.onCreate(savedInstanceState);

        addPreferencesFromResource(R.xml.preferences);
        PreferenceManager.setDefaultValues(getBaseContext(), R.xml.preferences, true);
        for (int i = 0; i < getPreferenceScreen().getPreferenceCount(); i++) {
            initSummary(getPreferenceScreen().getPreference(i));
        }
        updateKeyboardCategoryStatus();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Set up a listener whenever a key changes
        getPreferenceScreen().getSharedPreferences()
                .registerOnSharedPreferenceChangeListener(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        // Unregister the listener whenever a key changes
        getPreferenceScreen().getSharedPreferences()
                .unregisterOnSharedPreferenceChangeListener(this);
    }

    //this is for issue 4611 Background from PreferenceActivity is not applied to sub-PreferenceScreen (comment 35)
    //https://code.google.com/p/android/issues/detail?id=4611
    @Override
    public boolean onPreferenceTreeClick(PreferenceScreen preferenceScreen, Preference preference) {
        super.onPreferenceTreeClick(preferenceScreen, preference);
        if (preference != null)
            if (preference instanceof PreferenceScreen)
                if (((PreferenceScreen) preference).getDialog() != null)
                    ((PreferenceScreen) preference).getDialog().getWindow().getDecorView().setBackgroundDrawable(this.getWindow().getDecorView().getBackground().getConstantState().newDrawable());
        return false;
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences sharedPreferences,
                                          String key) {
        updatePrefSummary(findPreference(key));
        if (key.equals("numberofkeyboards")) {
            updateKeyboardCategoryStatus();
        }
    }

    private void updateKeyboardCategoryStatus() {
        ListPreference lpNok = (ListPreference) findPreference("numberofkeyboards");
        PreferenceScreen pc = (PreferenceScreen) findPreference("keyboard1");
        pc.setEnabled(true);
        int n = Integer.parseInt(lpNok.getValue());
        pc = (PreferenceScreen) findPreference("keyboard2");
        if (n >= 2) {
            pc.setEnabled(true);
        } else {
            pc.setEnabled(false);
        }
        pc = (PreferenceScreen) findPreference("keyboard3");
        if (n >= 3) {
            pc.setEnabled(true);
        } else {
            pc.setEnabled(false);
        }
        pc = (PreferenceScreen) findPreference("keyboard4");
        if (n >= 4) {
            pc.setEnabled(true);
        } else {
            pc.setEnabled(false);
        }
    }

    private void initSummary(Preference p) {
        if (p instanceof PreferenceCategory) {
            PreferenceCategory pCat = (PreferenceCategory) p;
            for (int i = 0; i < pCat.getPreferenceCount(); i++) {
                initSummary(pCat.getPreference(i));
            }
        } else if (p instanceof PreferenceScreen) {
            PreferenceScreen pCat = (PreferenceScreen) p;
            for (int i = 0; i < pCat.getPreferenceCount(); i++) {
                initSummary(pCat.getPreference(i));
            }
        } else {
            updatePrefSummary(p);
        }

    }

    private void updatePrefSummary(Preference p) {
        if (p instanceof ListPreference) {
            ListPreference listPref = (ListPreference) p;
            String s = p.getSummary().toString();
            s = s.substring(0, s.indexOf(":") + 1);
            p.setSummary(String.format("%s %s", s, String.valueOf(listPref.getEntry())));
        }
        if (p instanceof EditTextPreference) {
            EditTextPreference editTextPref = (EditTextPreference) p;
            String s = p.getSummary().toString();
            s = s.substring(0, s.indexOf(":") + 1);
            p.setSummary(String.format("%s %s", s, String.valueOf(editTextPref.getText())));
        }

    }

}
