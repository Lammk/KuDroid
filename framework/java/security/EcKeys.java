package java.security;
import java.math.BigInteger;
import java.security.spec.*;
import libcore.io.KuCrypto;

final class EcKeys {
    private EcKeys() {}
    static PublicKey publicKey(byte[] der) throws InvalidKeySpecException { return new Public(der); }
    static PrivateKey privateKey(byte[] der) throws InvalidKeySpecException { return new Private(der); }
    private static abstract class Material {
        final byte[] encoded;
        final byte[][] info;
        final int bits;
        private ECParameterSpec parameters;
        Material(byte[] encoded, boolean privateKey) throws InvalidKeySpecException {
            if (encoded == null) throw new InvalidKeySpecException("Missing EC encoding");
            info = KuCrypto.inspectEcKey(encoded, privateKey);
            if (info == null || info.length != 3 || info[0].length != 2) throw new InvalidKeySpecException("Invalid EC encoding");
            bits = (info[0][0] & 255) << 8 | info[0][1] & 255;
            this.encoded = java.util.Arrays.copyOf(encoded, encoded.length);
        }
        public String getAlgorithm() { return "EC"; }
        public byte[] getEncoded() { return java.util.Arrays.copyOf(encoded, encoded.length); }
        public synchronized ECParameterSpec getParams() {
            if (parameters == null) parameters = parameters(bits);
            return parameters;
        }
    }
    private static final class Public extends Material implements java.security.interfaces.ECPublicKey {
        Public(byte[] der) throws InvalidKeySpecException { super(der, false); }
        public String getFormat() { return "X.509"; }
        public ECPoint getW() {
            int length = (bits + 7) / 8;
            byte[] point = info[1];
            return new ECPoint(new BigInteger(1, java.util.Arrays.copyOfRange(point, 1, 1 + length)),
                new BigInteger(1, java.util.Arrays.copyOfRange(point, 1 + length, 1 + 2 * length)));
        }
    }
    private static final class Private extends Material implements java.security.interfaces.ECPrivateKey {
        Private(byte[] der) throws InvalidKeySpecException { super(der, true); }
        public String getFormat() { return "PKCS#8"; }
        public BigInteger getS() { return new BigInteger(1, info[2]); }
    }
    private static BigInteger number(String hex) { return new BigInteger(hex, 16); }
    private static ECParameterSpec parameters(int bits) {
        String p, b, x, y, order;
        if (bits == 256) {
            p = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff";
            b = "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b";
            x = "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296";
            y = "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5";
            order = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551";
        } else if (bits == 384) {
            p = "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff";
            b = "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef";
            x = "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7";
            y = "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f";
            order = "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973";
        } else if (bits == 521) {
            p = BigInteger.ONE.shiftLeft(521).subtract(BigInteger.ONE).toString(16);
            b = "0051953eb9618e1c9a1f929a21a0b68540eea2da725b99b315f3b8b489918ef109e156193951ec7e937b1652c0bd3bb1bf073573df883d2c34f1ef451fd46b503f00";
            x = "00c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3dbaa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd66";
            y = "011839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e662c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd16650";
            order = "01fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb6fb71e91386409";
        } else throw new IllegalArgumentException("Unsupported EC group");
        BigInteger prime = number(p);
        return new ECParameterSpec(new EllipticCurve(new ECFieldFp(prime), prime.subtract(BigInteger.valueOf(3)), number(b)),
            new ECPoint(number(x), number(y)), number(order), 1);
    }
}
