package eu.flatworld.android.slider;


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

    public synchronized void write(short[] data, int offset, int count) {
        int copy = 0;
        if (writePosition > readPosition || available == 0) {
            copy = Math.min(buffer.length - writePosition, count);
            System.arraycopy(data, offset, buffer, writePosition, copy);
            writePosition = (writePosition + copy) % buffer.length;
            available += copy;
            count -= copy;
            if (count == 0)
                return;
        }
        copy = Math.min(readPosition - writePosition, count);
        System.arraycopy(data, offset, buffer, writePosition, copy);
        writePosition += copy;
        available += copy;
    }

    public synchronized void combine(short[] data, int offset, int count) {
        int copy = 0;
        if (writePosition > readPosition || available == 0) {
            copy = Math.min(buffer.length - writePosition, count);
            combine(data, offset, buffer, writePosition, copy);
            writePosition = (writePosition + copy) % buffer.length;
            available += copy;
            count -= copy;
            if (count == 0)
                return;
        }
        copy = Math.min(readPosition - writePosition, count);
        combine(data, offset, buffer, writePosition, copy);
        writePosition += copy;
        available += copy;
    }

    public synchronized int read(short[] data, int offset, int count) {
        if (available == 0)
            return 0;

        int total = count = Math.min(available, count);

        int copy = Math.min(buffer.length - readPosition, total);
        System.arraycopy(buffer, readPosition, data, offset, copy);
        readPosition = (readPosition + copy) % buffer.length;
        available -= copy;
        count -= copy;
        if (count > 0 && available > 0) {
            copy = Math.min(buffer.length - available, count);
            System.arraycopy(buffer, readPosition, data, offset, copy);
            readPosition = (readPosition + copy) % buffer.length;
            available -= copy;
        }

        return total;
    }

    public synchronized void clear() {
        for (int i = 0, n = buffer.length; i < n; i++)
            buffer[i] = 0;
        readPosition = 0;
        writePosition = 0;
        available = 0;
    }

    public void setWritePosition(int writePosition) {
        this.writePosition = Math.abs(writePosition) % buffer.length;
    }

    public int getWritePosition() {
        return writePosition;
    }

    public void setReadPosition(int readPosition) {
        this.readPosition = Math.abs(readPosition) % buffer.length;
    }

    public int getReadPosition() {
        return readPosition;
    }

    private void dump() {
        for (int i = 0, n = buffer.length; i < n; i++)
            System.out.println(buffer[i]
                    + (i == writePosition ? " <- write" : "")
                    + (i == readPosition ? " <- read" : ""));
        System.out.println();
    }

    static short clamp(short v, short min, short max) {
        if (v < min) {
            return min;
        }
        if (v > max) {
            return max;
        }
        return v;
    }

    static private void combine(short[] src, int srcPos, short[] dest,
                                int destPos, int length) {
        for (int i = 0; i < length; i++) {
            int destIndex = destPos + i;
            short a = src[srcPos + i];
            short b = dest[destIndex];
            dest[destIndex] = clamp((short) (a + b - a * b
                    / Short.MAX_VALUE), (short) 0, Short.MAX_VALUE);
            // dest[destIndex] = (short)(a + b / 2);
        }
    }
}
