package java.security.spec;
public class PKCS8EncodedKeySpec extends EncodedKeySpec {
    public PKCS8EncodedKeySpec(byte[] encodedKey) { super(encodedKey); }
    public final String getFormat() { return "PKCS#8"; }
}
