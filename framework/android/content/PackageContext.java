package android.content;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.SharedPackages;
import android.content.res.AssetManager;
import android.content.res.Resources;

public final class PackageContext extends android.app.ApplicationContext {
    private final ApplicationInfo mInfo;
    private final Resources mResources;
    private android.app.Application mApplication;

    public PackageContext(String name, int flags) throws PackageManager.NameNotFoundException {
        super(name);
        org.json.JSONObject record = SharedPackages.record(name, false);
        if (record == null) throw new PackageManager.NameNotFoundException(name);
        if ((flags & Context.CONTEXT_INCLUDE_CODE) != 0 && !record.optBoolean("shared", false))
            throw new PackageManager.NameNotFoundException("Code is not loaded for " + name);
        mInfo = SharedPackages.applicationInfo(record);
        mResources = SharedPackages.resources(mInfo);
    }
    public ApplicationInfo getApplicationInfo() { return mInfo; }
    public AssetManager getAssets() { return mResources.getAssets(); }
    public Resources getResources() { return mResources; }
    public Context getApplicationContext() { return mApplication != null ? mApplication : this; }
    public void setApplication(android.app.Application application) { mApplication = application; }
    public Resources.Theme getTheme() { return mResources.getDefaultTheme(); }
    public ContentResolver getContentResolver() { return new ContentResolver(this); }
    public ClassLoader getClassLoader() {
        return dalvik.system.PackageClassLoader.get(mInfo.packageName);
    }
}
