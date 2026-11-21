package java.security.spec;
import java.math.BigInteger;
public class ECParameterSpec implements AlgorithmParameterSpec {
    private final EllipticCurve curve;
    private final ECPoint generator;
    private final BigInteger order;
    private final int cofactor;
    public ECParameterSpec(EllipticCurve curve, ECPoint generator, BigInteger order, int cofactor) {
        if (curve == null || generator == null || order == null) throw new NullPointerException();
        if (order.signum() <= 0 || cofactor <= 0) throw new IllegalArgumentException("Invalid group order");
        this.curve = curve; this.generator = generator; this.order = order; this.cofactor = cofactor;
    }
    public EllipticCurve getCurve() { return curve; }
    public ECPoint getGenerator() { return generator; }
    public BigInteger getOrder() { return order; }
    public int getCofactor() { return cofactor; }
}
