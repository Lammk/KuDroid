package android.view.inputmethod;

/** Description of one installed input method. */






public final class InputMethodInfo {
    private final String mId;
    private final String mPackageName;
    private final String mServiceName;

    public InputMethodInfo(String id, String packageName, String serviceName) {
        mId = id;
        mPackageName = packageName;
        mServiceName = serviceName;
    }

    public String getId() { return mId; }
    public String getPackageName() { return mPackageName; }
    public String getServiceName() { return mServiceName; }
    public int getSubtypeCount() { return 0; }
    public boolean isDefault(android.content.Context context) { return false; }

    @Override
    public String toString() { return "InputMethodInfo{" + mId + "}"; }
}
