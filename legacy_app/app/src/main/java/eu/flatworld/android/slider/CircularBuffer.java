package eu.flatworld.android.slider;

public class CircularBuffer {
    private final short[] buffer;
    private int writePosition, readPosition;
    private int available;

    public CircularBuffer(int size) {
        buffer = new short[size];
        available = 0;
    }

    public synchronized int getFreeSpace() {
        return buffer.length - available;
    }

    public synchronized int getAvailableData() {
        return available;
    }

    public synchronized int write(short[] data, int offset, int count) {
        int mw = Math.min(count, getFreeSpace());
        if (mw == 0) {
            return 0;
        }
        if (writePosition >= readPosition) {
            int n = Math.min(mw, buffer.length - writePosition);
            System.arraycopy(data, offset, buffer, writePosition, n);
            if (n < mw) {
                int n2 = Math.min(mw - n, readPosition);
                System.arraycopy(data, offset + n, buffer, 0, n2);
            }
        } else {
            int n = Math.min(mw, readPosition - writePosition);
            System.arraycopy(data, offset, buffer, writePosition, n);
        }
        writePosition = (writePosition + mw) % buffer.length;
        available += mw;
        return mw;
    }

    public synchronized int read(short[] data, int offset, int count) {
        int mr = Math.min(count, getAvailableData());
        if (mr == 0) {
            return 0;
        }
        if (readPosition >= writePosition) {
            int n = Math.min(mr, buffer.length - readPosition);
            System.arraycopy(buffer, readPosition, data, offset, n);
            if (n < mr) {
                int n2 = Math.min(mr - n, writePosition);
                System.arraycopy(buffer, 0, data, offset + n, n2);
            }
        } else {
            int n = Math.min(mr, writePosition - readPosition);
            System.arraycopy(buffer, readPosition, data, offset, n);
        }
        readPosition = (readPosition + mr) % buffer.length;
        available -= mr;
        return mr;
    }

    public synchronized void clear() {
        readPosition = 0;
        writePosition = 0;
    }

    private void dump() {
        for (int i = 0, n = buffer.length; i < n; i++)
            System.out.println(buffer[i]
                    + (i == writePosition ? " <- write" : "")
                    + (i == readPosition ? " <- read" : ""));
        System.out.println();
    }
}
