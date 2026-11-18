package java.lang;

/** Describe the package associated with a class. */












public class Package {

    private final String name;

    Package(String name) {
        this.name = name != null ? name : "";
    }

    public String getName() {
        return name;
    }

    /**
     * No manifest in a DEX, so these are unknown rather than invented.
     *
     * A made-up version would be worse than null: code that compares versions to
     * decide on a behaviour would take a branch based on fiction.
     */
    public String getSpecificationTitle() { return null; }

    public String getSpecificationVersion() { return null; }

    public String getSpecificationVendor() { return null; }

    public String getImplementationTitle() { return null; }

    public String getImplementationVersion() { return null; }

    public String getImplementationVendor() { return null; }

    public boolean isSealed() { return false; }

    public boolean isCompatibleWith(String desired) {
        // Without a specification version there is nothing to compare against;
        // claiming compatibility could let a caller proceed on a false premise.
        return false;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof Package)) return false;
        return name.equals(((Package) other).name);
    }

    @Override
    public int hashCode() {
        return name.hashCode();
    }

    @Override
    public String toString() {
        return "package " + name;
    }
}
