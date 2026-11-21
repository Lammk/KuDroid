package java.security;

import java.io.ByteArrayOutputStream;
import libcore.io.KuCrypto;

public abstract class MessageDigest {
    private final String algorithm;
    private final String nativeAlgorithm;
    private final ByteArrayOutputStream input = new ByteArrayOutputStream();

    protected MessageDigest(String algorithm) {
        this.algorithm = algorithm;
        nativeAlgorithm = canonical(algorithm);
    }
    private static String canonical(String algorithm) {
        if (algorithm == null) return null;
        String name = algorithm.replace("-", "").toUpperCase(java.util.Locale.ROOT);
        if ("SHA".equals(name)) name = "SHA1";
        return "MD5".equals(name) || "SHA1".equals(name) || "SHA224".equals(name) ||
            "SHA256".equals(name) || "SHA384".equals(name) || "SHA512".equals(name) ? name : null;
    }
    public static MessageDigest getInstance(String algorithm) throws NoSuchAlgorithmException {
        if (algorithm == null) throw new NullPointerException("algorithm");
        if (canonical(algorithm) == null || !KuCrypto.symmetricAvailable()) throw new NoSuchAlgorithmException(algorithm);
        return new PlatformDigest(algorithm);
    }
    public void update(byte value) {
        if (input.size() == Integer.MAX_VALUE) throw new OutOfMemoryError();
        input.write(value);
    }
    public void update(byte[] bytes, int offset, int len) {
        if (bytes == null) throw new IllegalArgumentException("Missing input");
        if (offset < 0 || len < 0 || offset > bytes.length - len) throw new IllegalArgumentException("Invalid input range");
        if (len > Integer.MAX_VALUE - input.size()) throw new OutOfMemoryError();
        input.write(bytes, offset, len);
    }
    public void update(byte[] bytes) {
        if (bytes == null) throw new IllegalArgumentException("Missing input");
        update(bytes, 0, bytes.length);
    }
    public final void update(java.nio.ByteBuffer buffer) {
        if (buffer == null) throw new NullPointerException("buffer");
        byte[] chunk = new byte[Math.min(4096, buffer.remaining())];
        while (buffer.hasRemaining()) {
            int count = Math.min(chunk.length, buffer.remaining());
            buffer.get(chunk, 0, count); update(chunk, 0, count);
        }
    }
    public byte[] digest() {
        byte[] result = KuCrypto.digest(nativeAlgorithm, input.toByteArray());
        input.reset();
        return result;
    }
    public byte[] digest(byte[] bytes) { update(bytes); return digest(); }
    public int digest(byte[] output, int offset, int len) throws DigestException {
        if (output == null) throw new IllegalArgumentException("Missing output");
        if (offset < 0 || len < 0 || offset > output.length - len) throw new IllegalArgumentException("Invalid output range");
        if (len < getDigestLength()) throw new DigestException("Output is too short");
        byte[] result = digest();
        System.arraycopy(result, 0, output, offset, result.length);
        return result.length;
    }
    public void reset() { input.reset(); }
    public final int getDigestLength() {
        if ("MD5".equals(nativeAlgorithm)) return 16;
        if ("SHA1".equals(nativeAlgorithm)) return 20;
        if ("SHA224".equals(nativeAlgorithm)) return 28;
        if ("SHA256".equals(nativeAlgorithm)) return 32;
        if ("SHA384".equals(nativeAlgorithm)) return 48;
        if ("SHA512".equals(nativeAlgorithm)) return 64;
        return 0;
    }
    public static boolean isEqual(byte[] left, byte[] right) {
        if (left == right) return true;
        if (left == null || right == null) return false;
        if (right.length == 0) return left.length == 0;
        int difference = left.length ^ right.length;
        for (int i = 0; i < left.length; ++i) difference |= left[i] ^ right[i % right.length];
        return difference == 0;
    }
    public final String getAlgorithm() { return algorithm; }
    private static final class PlatformDigest extends MessageDigest {
        PlatformDigest(String algorithm) { super(algorithm); }
    }
}
