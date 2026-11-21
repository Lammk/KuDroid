package libcore.io;

public final class KuCrypto {
    private KuCrypto() {}
    public static native boolean rsaAvailable();
    public static native boolean validateRsaSpki(byte[] encoded);
    public static native int verifyRsaSignature(String algorithm, byte[] encoded,
                                               byte[] message, byte[] signature);
    public static native boolean symmetricAvailable();
    public static native byte[] digest(String algorithm, byte[] input);
    public static native byte[] pkcs12Sha1Key(char[] password, byte[] salt, int iterations);
    public static native byte[] aesCbc(boolean encrypt, byte[] key, byte[] iv, byte[] input);
    public static native byte[] randomBytes(int length);
    public static native boolean ecAvailable();
    public static native byte[][] generateEcKeyPair(int bits);
    public static native byte[][] inspectEcKey(byte[] encoded, boolean privateKey);
    public static native byte[] signEc(String hash, byte[] encoded, byte[] message);
    public static native int verifyEc(String hash, byte[] encoded, byte[] message, byte[] signature);
}
