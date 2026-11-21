package android.content;

public class ContentProviderClient implements AutoCloseable {
    private ContentProvider mProvider;
    private boolean mReleased;

    public ContentProviderClient() {}
    ContentProviderClient(ContentProvider provider) { mProvider = provider; }

    private synchronized ContentProvider provider() {
        if (mReleased) throw new IllegalStateException("ContentProviderClient is closed");
        if (mProvider == null) throw new IllegalStateException("No content provider");
        return mProvider;
    }

    public android.database.Cursor query(android.net.Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) throws android.os.RemoteException {
        return provider().query(uri, projection, selection, selectionArgs, sortOrder);
    }
    public android.net.Uri insert(android.net.Uri uri, ContentValues values) throws android.os.RemoteException {
        return provider().insert(uri, values);
    }
    public int delete(android.net.Uri uri, String selection, String[] selectionArgs) throws android.os.RemoteException {
        return provider().delete(uri, selection, selectionArgs);
    }
    public int update(android.net.Uri uri, ContentValues values, String selection, String[] selectionArgs)
            throws android.os.RemoteException {
        return provider().update(uri, values, selection, selectionArgs);
    }
    public String getType(android.net.Uri uri) throws android.os.RemoteException { return provider().getType(uri); }
    public android.os.Bundle call(String method, String argument, android.os.Bundle extras)
            throws android.os.RemoteException { return provider().call(method, argument, extras); }
    public synchronized boolean release() {
        if (mReleased) return false;
        mReleased = true;
        mProvider = null;
        return true;
    }
    public void close() { release(); }
}
