package java.security.spec;
public class ECGenParameterSpec implements AlgorithmParameterSpec {
    private final String name;
    public ECGenParameterSpec(String name) {
        if (name == null) throw new NullPointerException("name");
        this.name = name;
    }
    public String getName() { return name; }
}
