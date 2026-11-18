package dalvik.system;

/** The loader every Android app actually runs under. */



















public class BaseDexClassLoader extends ClassLoader {

    private final String mDexPath;
    private final String mLibrarySearchPath;

    /**
     * Absolute path of a loaded guest library, or null.
     *
     * Resolved on the native side because that is the only place that knows where the
     * library actually is: the Java-visible path is the Android one
     * ({@code /data/app/<pkg>/lib/arm64-v8a}), while the file on an iOS device lives
     * under the app container. Returning the Android path would give the caller
     * something that fails to open.
     */
    private static native String findLibraryPath(String name);
    private static native Object[] findResourceBacking(String name);

    public BaseDexClassLoader(String dexPath, java.io.File optimizedDirectory,
            String librarySearchPath, ClassLoader parent) {
        super(parent);
        mDexPath = dexPath;
        mLibrarySearchPath = librarySearchPath;
    }

    public BaseDexClassLoader(String dexPath, String librarySearchPath, ClassLoader parent) {
        this(dexPath, null, librarySearchPath, parent);
    }

    public BaseDexClassLoader(String dexPath, ClassLoader parent) {
        this(dexPath, null, null, parent);
    }

    /** Return the absolute native-library path, or null when unavailable. */









    public String findLibrary(String name) {
        if (name == null || name.length() == 0) return null;
        return findLibraryPath(name);
    }

    public String getLdLibraryPath() {
        return mLibrarySearchPath != null ? mLibrarySearchPath : "";
    }

    @Override
    protected java.net.URL findResource(String name) {
        if (name == null) throw new NullPointerException("name == null");
        Object[] backing = findResourceBacking(name);
        if (backing == null) return null;
        final String path = (String) backing[0];
        final long start = (Long) backing[1];
        final long length = (Long) backing[2];
        try {
            String spec = new java.net.URI("file", "", path, null).toASCIIString();
            if (start > 0) {
                String entry = new java.net.URI(null, null, "/" + name, null)
                        .getRawPath().substring(1);
                spec = "jar:" + spec + "!/" + entry;
            }
            return new java.net.URL(null, spec, new java.net.URLStreamHandler() {
                protected java.net.URLConnection openConnection(java.net.URL url) {
                    return new java.net.URLConnection(url) {
                        public void connect() { connected = true; }
                        public long getContentLengthLong() { return length; }
                        public java.io.InputStream getInputStream() throws java.io.IOException {
                            java.io.FileInputStream input = new java.io.FileInputStream(path);
                            try {
                                long skipped = 0;
                                while (skipped < start) {
                                    long count = input.skip(start - skipped);
                                    if (count <= 0) throw new java.io.EOFException(path);
                                    skipped += count;
                                }
                                connected = true;
                                return new android.content.res.AssetManager.BoundedInputStream(input, length);
                            } catch (java.io.IOException exception) {
                                input.close();
                                throw exception;
                            }
                        }
                    };
                }
            });
        } catch (java.net.URISyntaxException exception) {
            return null;
        } catch (java.net.MalformedURLException exception) {
            return null;
        }
    }

    @Override
    public String toString() {
        return getClass().getName() + "[DexPathList[" + mDexPath + "]]";
    }
}
