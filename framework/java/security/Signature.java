package java.security;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import libcore.io.KuCrypto;

public abstract class Signature {
    private final String algorithm;
    private final String nativeAlgorithm;
    private byte[] publicKey;
    private byte[] privateKey;
    private final ByteArrayOutputStream message = new ByteArrayOutputStream();

    protected Signature(String algorithm) {
        this.algorithm = algorithm;
        this.nativeAlgorithm = canonical(algorithm);
    }

    private static String canonical(String algorithm) {
        String[] supported = {"SHA1withRSA", "SHA224withRSA", "SHA256withRSA", "SHA384withRSA", "SHA512withRSA",
                             "NONEwithECDSA", "SHA1withECDSA", "SHA256withECDSA", "SHA384withECDSA", "SHA512withECDSA"};
        for (String name : supported) if (name.equalsIgnoreCase(algorithm)) return name;
        return null;
    }

    public static Signature getInstance(String algorithm) throws NoSuchAlgorithmException {
        if (algorithm == null) throw new NullPointerException();
        String name = canonical(algorithm);
        if (name == null || !(name.endsWith("ECDSA") ? KuCrypto.ecAvailable() : KuCrypto.rsaAvailable()))
            throw new NoSuchAlgorithmException(algorithm);
        return new PlatformSignature(algorithm);
    }

    public final String getAlgorithm() { return algorithm; }

    public final void initVerify(PublicKey key) throws InvalidKeyException {
        publicKey = null;
        privateKey = null;
        message.reset();
        if (nativeAlgorithm.endsWith("ECDSA")) {
            if (key == null || !"EC".equalsIgnoreCase(key.getAlgorithm()) || !"X.509".equalsIgnoreCase(key.getFormat()))
                throw new InvalidKeyException("Expected an EC X.509 public key");
            byte[] encoded = key.getEncoded();
            if (encoded == null || KuCrypto.inspectEcKey(encoded, false) == null) throw new InvalidKeyException("Invalid EC public key");
            publicKey = Arrays.copyOf(encoded, encoded.length);
            return;
        }
        if (key == null || !"RSA".equalsIgnoreCase(key.getAlgorithm()) ||
            !"X.509".equalsIgnoreCase(key.getFormat()))
            throw new InvalidKeyException("Expected an RSA X.509 public key");
        byte[] encoded = key.getEncoded();
        if (encoded == null || !KuCrypto.validateRsaSpki(encoded))
            throw new InvalidKeyException("Invalid RSA public key");
        publicKey = Arrays.copyOf(encoded, encoded.length);
    }

    private void requireVerify() throws SignatureException {
        if (publicKey == null) throw new SignatureException("Signature is not initialized for verification");
    }

    public final void initSign(PrivateKey key) throws InvalidKeyException { initSign(key, null); }
    public final void initSign(PrivateKey key, SecureRandom random) throws InvalidKeyException {
        publicKey = null; privateKey = null; message.reset();
        if (!nativeAlgorithm.endsWith("ECDSA") || key == null || !"EC".equalsIgnoreCase(key.getAlgorithm()) ||
            !"PKCS#8".equalsIgnoreCase(key.getFormat())) throw new InvalidKeyException("Expected an EC PKCS#8 private key");
        byte[] encoded = key.getEncoded();
        if (encoded == null || KuCrypto.inspectEcKey(encoded, true) == null) throw new InvalidKeyException("Invalid EC private key");
        privateKey = Arrays.copyOf(encoded, encoded.length);
    }

    private void requireInitialized() throws SignatureException {
        if (publicKey == null && privateKey == null) throw new SignatureException("Signature is not initialized");
    }

    public final byte[] sign() throws SignatureException {
        if (privateKey == null) throw new SignatureException("Signature is not initialized for signing");
        try { return KuCrypto.signEc(nativeAlgorithm.substring(0, nativeAlgorithm.indexOf("with")), privateKey, message.toByteArray()); }
        finally { message.reset(); }
    }

    private static void checkRange(byte[] bytes, int offset, int length) {
        if (bytes == null) throw new NullPointerException();
        if (offset < 0 || length < 0 || offset > bytes.length || length > bytes.length - offset)
            throw new IllegalArgumentException("Invalid byte array range");
    }

    public final void update(byte input) throws SignatureException {
        requireInitialized();
        if (message.size() == Integer.MAX_VALUE) throw new OutOfMemoryError();
        message.write(input);
    }

    public final void update(byte[] input) throws SignatureException {
        requireInitialized();
        if (input == null) throw new NullPointerException();
        update(input, 0, input.length);
    }

    public final void update(byte[] input, int offset, int length) throws SignatureException {
        requireInitialized();
        checkRange(input, offset, length);
        if (length > Integer.MAX_VALUE - message.size()) throw new OutOfMemoryError();
        message.write(input, offset, length);
    }

    public final boolean verify(byte[] signature) throws SignatureException {
        requireVerify();
        if (signature == null) throw new NullPointerException();
        return verify(signature, 0, signature.length);
    }

    public final boolean verify(byte[] signature, int offset, int length) throws SignatureException {
        requireVerify();
        checkRange(signature, offset, length);
        byte[] bytes = offset == 0 && length == signature.length ? signature : Arrays.copyOfRange(signature, offset, offset + length);
        try {
            int result = nativeAlgorithm.endsWith("ECDSA")
                ? KuCrypto.verifyEc(nativeAlgorithm.substring(0, nativeAlgorithm.indexOf("with")), publicKey, message.toByteArray(), bytes)
                : KuCrypto.verifyRsaSignature(nativeAlgorithm, publicKey, message.toByteArray(), bytes);
            if (result < 0) throw new SignatureException("Signature verification failed");
            return result == 1;
        } finally {
            message.reset();
        }
    }

    private static final class PlatformSignature extends Signature {
        PlatformSignature(String algorithm) { super(algorithm); }
    }
}
