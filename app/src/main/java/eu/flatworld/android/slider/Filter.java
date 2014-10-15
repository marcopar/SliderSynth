package eu.flatworld.android.slider;

/**
 * Created by marcopar on 15/10/14.
 */
public interface Filter {
    void reset();

    void filter(short[] samples, int offset, int length);
}
