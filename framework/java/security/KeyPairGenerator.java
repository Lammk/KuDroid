package java.security;
import java.security.spec.AlgorithmParameterSpec;
import java.security.spec.ECGenParameterSpec;
import libcore.io.KuCrypto;

public class KeyPairGenerator {
    private final String algorithm;
    private int bits = 256;
    protected KeyPairGenerator(String algorithm) { this.algorithm = algorithm; }
    public static KeyPairGenerator getInstance(String algorithm) throws NoSuchAlgorithmException {
        if (algorithm == null) throw new NullPointerException("algorithm");
        if (!"EC".equalsIgnoreCase(algorithm) || !KuCrypto.ecAvailable()) throw new NoSuchAlgorithmException(algorithm);
        return new KeyPairGenerator("EC");
    }
    public String getAlgorithm() { return algorithm; }
    public void initialize(int bits) { initialize(bits, null); }
    public void initialize(int bits, SecureRandom random) {
        if (bits != 256 && bits != 384 && bits != 521) throw new InvalidParameterException("Unsupported EC key size");
        this.bits = bits;
    }
    public void initialize(AlgorithmParameterSpec spec) throws InvalidAlgorithmParameterException { initialize(spec, null); }
    public void initialize(AlgorithmParameterSpec spec, SecureRandom random) throws InvalidAlgorithmParameterException {
        if (!(spec instanceof ECGenParameterSpec)) throw new InvalidAlgorithmParameterException("Named EC curve required");
        String name = ((ECGenParameterSpec) spec).getName();
        if ("secp256r1".equalsIgnoreCase(name) || "prime256v1".equalsIgnoreCase(name) || "P-256".equalsIgnoreCase(name)) bits = 256;
        else if ("secp384r1".equalsIgnoreCase(name) || "P-384".equalsIgnoreCase(name)) bits = 384;
        else if ("secp521r1".equalsIgnoreCase(name) || "P-521".equalsIgnoreCase(name)) bits = 521;
        else throw new InvalidAlgorithmParameterException(name);
    }
    public KeyPair generateKeyPair() {
        byte[][] pair = KuCrypto.generateEcKeyPair(bits);
        if (pair == null || pair.length != 2) throw new ProviderException("EC key generation failed");
        try { return new KeyPair(EcKeys.publicKey(pair[0]), EcKeys.privateKey(pair[1])); }
        catch (java.security.spec.InvalidKeySpecException invalid) { throw new ProviderException("Invalid generated key", invalid); }
    }
    public final KeyPair genKeyPair() { return generateKeyPair(); }
}
