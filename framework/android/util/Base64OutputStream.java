package android.util;

import java.io.FilterOutputStream;
import java.io.IOException;
import java.io.OutputStream;

/** Encodes or decodes incrementally without closing an opted-out destination. */
public class Base64OutputStream extends FilterOutputStream {
    private final int flags;
    private final boolean encode;
    private final byte[] pending = new byte[4];
    private final byte[] encoded = new byte[4];
    private int count;
    private int column;
    private boolean finished;
    private boolean closed;

    public Base64OutputStream(OutputStream out, int flags) { this(out, flags, true); }
    public Base64OutputStream(OutputStream out, int flags, boolean encode) {
        super(out); this.flags = flags; this.encode = encode;
    }

    private void checkOpen() throws IOException {
        if (closed) throw new IOException("Stream closed");
    }

    public void write(int value) throws IOException {
        checkOpen();
        if (encode) {
            pending[count++] = (byte) value;
            if (count == 3) emitEncoded();
        } else {
            int c = value & 255;
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t') return;
            if (finished) throw new IOException("Data after padding");
            boolean alphabet = c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9';
            alphabet |= (flags & Base64.URL_SAFE) != 0 ? c == '-' || c == '_' : c == '+' || c == '/';
            if (c == '=') {
                if (count < 2) throw new IOException("Invalid padding");
            } else if (!alphabet || count == 3 && pending[2] == '=') {
                throw new IOException("Invalid base64 data");
            }
            pending[count++] = (byte) c;
            if (count == 4) {
                if (pending[2] == '=' && pending[3] != '=') throw new IOException("Invalid padding");
                finished = pending[2] == '=' || pending[3] == '=';
                emitDecoded();
            }
        }
    }

    public void write(byte[] bytes, int offset, int length) throws IOException {
        checkOpen();
        if (bytes == null) throw new NullPointerException("bytes");
        if (offset < 0 || length < 0 || offset > bytes.length - length) throw new IndexOutOfBoundsException();
        for (int i = 0; i < length; ++i) write(bytes[offset + i]);
    }

    private void newline() throws IOException {
        if ((flags & Base64.CRLF) != 0) out.write('\r');
        out.write('\n'); column = 0;
    }

    private void emitEncoded() throws IOException {
        String alphabet = (flags & Base64.URL_SAFE) != 0
            ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        int bits = (pending[0] & 255) << 16 | (count > 1 ? (pending[1] & 255) << 8 : 0)
            | (count > 2 ? pending[2] & 255 : 0);
        int chars = count + 1;
        int size = (flags & Base64.NO_PADDING) == 0 ? 4 : chars;
        for (int i = 0; i < size; ++i) encoded[i] = (byte) (i < chars ? alphabet.charAt(bits >>> (18 - 6 * i) & 63) : '=');
        out.write(encoded, 0, size); column += size;
        if ((flags & Base64.NO_WRAP) == 0 && column == 76) newline();
        count = 0;
    }

    private void emitDecoded() throws IOException {
        try { out.write(Base64.decode(pending, 0, count, flags)); }
        catch (IllegalArgumentException failure) { throw new IOException("Invalid base64 data", failure); }
        count = 0;
    }

    public void flush() throws IOException { checkOpen(); out.flush(); }

    public void close() throws IOException {
        if (closed) return;
        IOException failure = null;
        try {
            if (encode) {
                if (count != 0) emitEncoded();
                if ((flags & Base64.NO_WRAP) == 0 && column != 0) newline();
            } else if (count != 0) {
                if (count == 1 || pending[count - 1] == '=') throw new IOException("Incomplete base64 data");
                emitDecoded();
            }
        } catch (IOException error) { failure = error; }
        try {
            if ((flags & Base64.NO_CLOSE) != 0) out.flush(); else out.close();
        } catch (IOException error) { if (failure == null) failure = error; }
        closed = true;
        if (failure != null) throw failure;
    }
}
