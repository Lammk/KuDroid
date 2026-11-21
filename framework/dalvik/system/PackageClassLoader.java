package dalvik.system;

/** Loads package code with the framework as its parent. */
public final class PackageClassLoader extends ClassLoader {
    private static final java.util.HashMap<String, PackageClassLoader> LOADERS =
            new java.util.HashMap<String, PackageClassLoader>();
    private final String packageName;

    private PackageClassLoader(String owner) {
        super(null);
        packageName = owner;
    }

    public static synchronized PackageClassLoader get(String owner) {
        PackageClassLoader loader = LOADERS.get(owner);
        if (loader == null) {
            loader = new PackageClassLoader(owner);
            LOADERS.put(owner, loader);
        }
        return loader;
    }

    private static native Class<?> findPackageClass(String owner, String name)
            throws ClassNotFoundException;

    public Class<?> loadClass(String name) throws ClassNotFoundException {
        return findPackageClass(packageName, name);
    }

    protected Class<?> findClass(String name) throws ClassNotFoundException {
        return loadClass(name);
    }
}
