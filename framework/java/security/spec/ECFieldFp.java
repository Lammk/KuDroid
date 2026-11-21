package java.security.spec;
import java.math.BigInteger;
public class ECFieldFp implements ECField {
    private final BigInteger p;
    public ECFieldFp(BigInteger p) {
        if (p == null) throw new NullPointerException("p");
        if (p.signum() <= 0) throw new IllegalArgumentException("p must be positive");
        this.p = p;
    }
    public BigInteger getP() { return p; }
    public int getFieldSize() { return p.bitLength(); }
    public boolean equals(Object other) { return other instanceof ECFieldFp && p.equals(((ECFieldFp) other).p); }
    public int hashCode() { return p.hashCode(); }
}
