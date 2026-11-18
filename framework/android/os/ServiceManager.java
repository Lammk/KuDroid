package android.os;

/** Resolve in-process system services. */









public final class ServiceManager {
    private ServiceManager() {
    }

    /** Returns a binder for the named service, or null when the runtime does not implement it. */




    public static IBinder getService(String name) {
        return null;
    }

    /**
     * Publish a service under a name. In-process only; a later put for the
     * same name replaces the earlier binder.
     */
    public static void addService(String name, IBinder binder) {
    }

    /** List every published service name. Empty here: nothing is pre-registered. */
    public static String[] listServices() {
        return new String[0];
    }

    /** Like getService but for services that live in this process. */



    public static IBinder checkService(String name) {
        return null;
    }
}
