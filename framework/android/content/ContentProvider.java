package android.content;

import android.content.pm.ProviderInfo;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import java.io.FileNotFoundException;

public abstract class ContentProvider implements ComponentCallbacks2 {
    private Context mContext;
    private String mReadPermission;
    private String mWritePermission;

    public ContentProvider() {}

    public final Context getContext() { return mContext; }
    public final String getReadPermission() { return mReadPermission; }
    public final String getWritePermission() { return mWritePermission; }
    protected final void setReadPermission(String permission) { mReadPermission = permission; }
    protected final void setWritePermission(String permission) { mWritePermission = permission; }

    public void attachInfo(Context context, ProviderInfo info) {
        if (mContext != null) return;
        if (context == null) throw new NullPointerException("context");
        mContext = context;
        if (info != null) {
            setReadPermission(info.readPermission);
            setWritePermission(info.writePermission);
        }
        onCreate();
    }

    public abstract boolean onCreate();
    public abstract Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder);
    public abstract String getType(Uri uri);
    public abstract Uri insert(Uri uri, ContentValues values);
    public abstract int delete(Uri uri, String selection, String[] selectionArgs);
    public abstract int update(Uri uri, ContentValues values, String selection, String[] selectionArgs);

    public Bundle call(String method, String argument, Bundle extras) { return null; }
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        throw new FileNotFoundException("No files supported at " + uri);
    }
    public android.content.res.AssetFileDescriptor openAssetFile(Uri uri, String mode) throws FileNotFoundException {
        return new android.content.res.AssetFileDescriptor(openFile(uri, mode), 0, -1);
    }
    public void shutdown() {}
    public void onLowMemory() {}
    public void onTrimMemory(int level) {}
    public void onConfigurationChanged(android.content.res.Configuration configuration) {}
}
