package java.security.spec;
import java.math.BigInteger;
public class EllipticCurve {
    private final ECField field;
    private final BigInteger a;
    private final BigInteger b;
    private final byte[] seed;
    public EllipticCurve(ECField field, BigInteger a, BigInteger b) { this(field, a, b, null); }
    public EllipticCurve(ECField field, BigInteger a, BigInteger b, byte[] seed) {
        if (field == null || a == null || b == null) throw new NullPointerException();
        if (a.signum() < 0 || b.signum() < 0) throw new IllegalArgumentException("Negative coefficient");
        if (field instanceof ECFieldFp && (a.compareTo(((ECFieldFp) field).getP()) >= 0 || b.compareTo(((ECFieldFp) field).getP()) >= 0))
            throw new IllegalArgumentException("Coefficient outside field");
        this.field = field; this.a = a; this.b = b;
        this.seed = seed == null ? null : java.util.Arrays.copyOf(seed, seed.length);
    }
    public ECField getField() { return field; }
    public BigInteger getA() { return a; }
    public BigInteger getB() { return b; }
    public byte[] getSeed() { return seed == null ? null : java.util.Arrays.copyOf(seed, seed.length); }
    public boolean equals(Object other) {
        if (!(other instanceof EllipticCurve)) return false;
        EllipticCurve curve = (EllipticCurve) other;
        return field.equals(curve.field) && a.equals(curve.a) && b.equals(curve.b);
    }
    public int hashCode() { return field.hashCode() * 31 + a.hashCode() * 17 + b.hashCode(); }
}
