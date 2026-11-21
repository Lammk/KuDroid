package java.security.interfaces;
public interface ECPublicKey extends ECKey, java.security.PublicKey {
    java.security.spec.ECPoint getW();
}
