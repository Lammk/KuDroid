package android.database;

/** Receive callbacks when content changes. */













public class ContentObserver {
    private final android.os.Handler mHandler;

    /**
     * @param handler the Handler whose thread onChange should run on; may be null, which
     *                Android takes to mean "call me on the calling thread".
     */
    public ContentObserver(android.os.Handler handler) {
        mHandler = handler;
    }

    /** Kept for the no-argument form some code still uses. */
    public ContentObserver() {
        this(null);
    }

    /**
     * True if this observer wants changes made by its own process reported back.
     *
     * False, matching Android's default. An observer that says true and then acts on its own
     * writes can loop, so the conservative answer is also the correct default.
     */
    public boolean deliverSelfNotifications() {
        return false;
    }

    public void onChange(boolean selfChange) {
    }

    public void onChange(boolean selfChange, android.net.Uri uri) {
        onChange(selfChange);
    }

    public void onChange(boolean selfChange, android.net.Uri uri, int flags) {
        onChange(selfChange, uri);
    }

    /** Dispatch a change to this observer on its Handler's thread. */





    public final void dispatchChange(boolean selfChange, android.net.Uri uri) {
        if (mHandler == null) {
            onChange(selfChange, uri);
            return;
        }
        final boolean self = selfChange;
        final android.net.Uri changed = uri;
        mHandler.post(new Runnable() {
            @Override
            public void run() {
                onChange(self, changed);
            }
        });
    }

    public final void dispatchChange(boolean selfChange) {
        dispatchChange(selfChange, null);
    }
}
