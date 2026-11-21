package android.os;

public class Binder implements IBinder {
    private IInterface mOwner;
    private String mDescriptor;
    private static final ThreadLocal<Long> CALLING_IDENTITY = new ThreadLocal<Long>() {
        protected Long initialValue() { return Long.valueOf(processIdentity()); }
    };

    public Binder() {}

    private static long processIdentity() {
        return ((long) Process.myPid() << 32) | (Process.myUid() & 0xffffffffL);
    }

    public static int getCallingUid() { return (int) CALLING_IDENTITY.get().longValue(); }
    public static int getCallingPid() { return (int) (CALLING_IDENTITY.get().longValue() >>> 32); }

    public static long clearCallingIdentity() {
        long previous = CALLING_IDENTITY.get().longValue();
        CALLING_IDENTITY.set(Long.valueOf(processIdentity()));
        return previous;
    }

    public static void restoreCallingIdentity(long token) {
        CALLING_IDENTITY.set(Long.valueOf(token));
    }

    public void attachInterface(IInterface owner, String descriptor) {
        mOwner = owner;
        mDescriptor = descriptor;
    }

    public String getInterfaceDescriptor() { return mDescriptor; }
    public boolean isBinderAlive() { return true; }
    public boolean pingBinder() { return true; }

    public IInterface queryLocalInterface(String descriptor) {
        return mDescriptor != null && mDescriptor.equals(descriptor) ? mOwner : null;
    }

    public final boolean transact(int code, Parcel data, Parcel reply, int flags)
            throws RemoteException {
        if (data != null) data.setDataPosition(0);
        boolean handled = onTransact(code, data, reply, flags);
        if (reply != null) reply.setDataPosition(0);
        return handled;
    }

    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags)
            throws RemoteException {
        if (code == INTERFACE_TRANSACTION) {
            if (reply != null) reply.writeString(getInterfaceDescriptor());
            return true;
        }
        return false;
    }

    // Local binders live for the duration of their process.
    public void linkToDeath(DeathRecipient recipient, int flags) {}
    public boolean unlinkToDeath(DeathRecipient recipient, int flags) { return true; }
}
