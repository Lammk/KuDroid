package android.net.wifi;

public class WifiManager {
    public static final int WIFI_STATE_DISABLING = 0;
    public static final int WIFI_STATE_DISABLED = 1;
    public static final int WIFI_STATE_ENABLING = 2;
    public static final int WIFI_STATE_ENABLED = 3;
    public static final int WIFI_STATE_UNKNOWN = 4;

    public WifiManager() {}
    public boolean isWifiEnabled() { return true; }
    public int getWifiState() { return WIFI_STATE_ENABLED; }
    public WifiInfo getConnectionInfo() { return new WifiInfo(); }

    public MulticastLock createMulticastLock(String tag) { return new MulticastLock(tag); }

    public class MulticastLock {
        private final String tag;
        private int references;
        private boolean referenceCounted = true;
        private boolean held;

        private MulticastLock(String tag) { this.tag = tag; }

        public synchronized void setReferenceCounted(boolean value) { referenceCounted = value; }

        public synchronized void acquire() {
            if (!referenceCounted || ++references == 1) held = true;
        }

        public synchronized void release() {
            if (!referenceCounted || --references == 0) held = false;
            if (references < 0) throw new RuntimeException("MulticastLock under-locked " + tag);
        }

        public synchronized boolean isHeld() { return held; }
    }
}
