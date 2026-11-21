package android.app;

import android.content.ContentProvider;
import android.content.LocalContentProviders;
import android.content.pm.ProviderInfo;
import android.content.pm.SystemPackageManager;

final class ProviderBootstrap {
    private ProviderBootstrap() {}

    static void install(Application application, AppComponentFactory factory) {
        ClassLoader loader = application.getClassLoader();
        AppComponentFactory components = factory != null ? factory : new AppComponentFactory();
        for (ProviderInfo info : SystemPackageManager.providersForProcess()) {
            try {
                ContentProvider provider = components.instantiateProvider(loader, info.name);
                provider.attachInfo(application, info);
                LocalContentProviders.publish(info, provider);
                android.util.Log.i("ActivityThread", "Provider.onCreate() done: " + info.name);
            } catch (Exception failure) {
                throw new RuntimeException("Unable to get provider " + info.name, failure);
            }
        }
    }
}
