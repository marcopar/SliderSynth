package eu.flatworld.android.slider;

//an extremely inefficient implementation with no checks

public class CircularBuffer {
    private final short[] buffer;
    private int writePosition, readPosition;
    private int available;

    public CircularBuffer(int size) {
        buffer = new short[size];
    }

    public synchronized int getFreeSpace() {
        int n = 0;
        if (writePosition > readPosition) {
            n += writePosition - readPosition;
        } else {
            n += buffer.length - readPosition + writePosition;
        }
        return n;
    }

    public synchronized int getAvailableData() {
        int n = 0;
        if (readPosition > writePosition) {
            n += readPosition - writePosition;
        } else {
            n += buffer.length - writePosition + readPosition;
        }
        return n;
    }

    public synchronized void write(short[] data, int offset, int count) {
        if (writePosition >= readPosition) {
            int n = Math.min(count, buffer.length - writePosition);
            System.arraycopy(data, offset, buffer, writePosition, n);
            writePosition += n;
            if (n < count) {
                int n2 = Math.min(count - n, readPosition);
                System.arraycopy(data, offset + n, buffer, 0, n2);
                writePosition = n2;
            }
        } else {
            int n = Math.min(count, readPosition - writePosition);
            System.arraycopy(data, offset, buffer, writePosition, n);
            writePosition += n;
        }
    }

    public synchronized void read(short[] data, int offset, int count) {
        if (readPosition >= writePosition) {
            int n = Math.min(count, buffer.length - readPosition);
            System.arraycopy(buffer, readPosition, data, offset, n);
            readPosition += n;
            if (n < count) {
                int n2 = Math.min(count - n, writePosition);
                System.arraycopy(buffer, 0, data, offset + n, n2);
                writePosition = n2;
            }
        } else {
            int n = Math.min(count, writePosition - readPosition);
            System.arraycopy(buffer, readPosition, data, offset, n);
            readPosition += n;
        }
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
