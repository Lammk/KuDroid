package java.security.spec;
import java.math.BigInteger;
public class ECPoint {
    public static final ECPoint POINT_INFINITY = new ECPoint();
    private final BigInteger x;
    private final BigInteger y;
    private ECPoint() { x = null; y = null; }
    public ECPoint(BigInteger x, BigInteger y) {
        if (x == null || y == null) throw new NullPointerException("coordinates");
        this.x = x; this.y = y;
    }
    public BigInteger getAffineX() { return x; }
    public BigInteger getAffineY() { return y; }
    public boolean equals(Object other) {
        if (this == other) return true;
        if (!(other instanceof ECPoint) || x == null) return false;
        ECPoint point = (ECPoint) other;
        return x.equals(point.x) && y.equals(point.y);
    }
    public int hashCode() { return x == null ? 0 : x.hashCode() * 31 + y.hashCode(); }
}
