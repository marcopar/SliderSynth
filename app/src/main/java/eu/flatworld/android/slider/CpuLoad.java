package eu.flatworld.android.slider;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.Timer;
import java.util.TimerTask;
 
public class CpuLoad 
{
	long total = 0;
	long idle = 0;
 
	float usage = 0;
	Timer t = new Timer();
	
	TimerTask tt = new TimerTask() {
		
		@Override
		public void run() {
			readUsage();			
		}
	};
	
	public CpuLoad( )
	{
		t.schedule(tt, 0, 2000);
	}
 
	public float getUsage( )
	{
		return usage;
	}
 
	private void readUsage( )
	{
		try
		{
			BufferedReader reader = new BufferedReader( new InputStreamReader( new FileInputStream( "/proc/stat" ) ), 1000 );
			String load = reader.readLine();
			reader.close();		
 
			String[] toks = load.split(" ");
 
			long currTotal = Long.parseLong(toks[2]) + Long.parseLong(toks[3]) + Long.parseLong(toks[4]);
			long currIdle = Long.parseLong(toks[5]);
 
			this.usage = (currTotal - total) * 100.0f / (currTotal - total + currIdle - idle);
			this.total = currTotal;
			this.idle = currIdle;
		}
		catch( IOException ex )
		{
			ex.printStackTrace();			
		}
	}
}