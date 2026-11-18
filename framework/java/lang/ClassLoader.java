package java.lang;

public class ClassLoader {

    private final ClassLoader parent;

    protected ClassLoader() {
        this.parent = null;
    }

    protected ClassLoader(ClassLoader parent) {
        this.parent = parent;
    }

    public ClassLoader getParent() {
        return parent;
    }

    public Class<?> loadClass(String name) throws ClassNotFoundException {
        return Class.forName(name);
    }

    protected Class<?> findClass(String name) throws ClassNotFoundException {
        return Class.forName(name);
    }

    public java.io.InputStream getResourceAsStream(String name) {
        java.net.URL resource = getResource(name);
        try {
            return resource == null ? null : resource.openStream();
        } catch (java.io.IOException exception) {
            return null;
        }
    }

    public java.net.URL getResource(String name) {
        if (name == null) throw new NullPointerException("name == null");
        java.net.URL resource = parent == null ? null : parent.getResource(name);
        return resource == null ? findResource(name) : resource;
    }

    protected java.net.URL findResource(String name) {
        return null;
    }

    public static java.net.URL getSystemResource(String name) {
        return getSystemClassLoader().getResource(name);
    }

    public static java.io.InputStream getSystemResourceAsStream(String name) {
        return getSystemClassLoader().getResourceAsStream(name);
    }

    public String findLibrary(String libname) {
        if (libname == null) return null;
        if (!libname.startsWith("lib")) libname = "lib" + libname;
        if (!libname.endsWith(".so")) libname = libname + ".so";
        return "/data/app/" + android.app.ActivityThread.getPackageName() + "/lib/arm64-v8a/" + libname;
    }

    public static ClassLoader getSystemClassLoader() {
        return SystemHolder.INSTANCE;
    }

    /** The one loader in the process, created lazily. */














    private static final class SystemHolder {
        static final ClassLoader INSTANCE = new dalvik.system.PathClassLoader(null, null, null);
    }
}
