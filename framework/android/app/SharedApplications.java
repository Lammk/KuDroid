package android.app;

import android.content.PackageContext;
import android.content.pm.PackageManager;
import android.content.pm.SharedPackages;
import java.util.HashMap;

public final class SharedApplications {
    private static final HashMap<String, Application> sApplications = new HashMap<String, Application>();
    private static final HashMap<String, AppComponentFactory> sFactories = new HashMap<String, AppComponentFactory>();
    private static final HashMap<String, RuntimeException> sFailures = new HashMap<String, RuntimeException>();
    private SharedApplications() {}

    public static synchronized Application get(String owner) throws Exception {
        Application existing = sApplications.get(owner);
        if (existing != null) return existing;
        RuntimeException previousFailure = sFailures.get(owner);
        if (previousFailure != null) throw previousFailure;
        org.json.JSONObject record = SharedPackages.record(owner, false);
        if (record == null || !record.optBoolean("shared", false)) throw new PackageManager.NameNotFoundException(owner);
        PackageContext context = new PackageContext(owner, android.content.Context.CONTEXT_INCLUDE_CODE);
        ClassLoader loader = context.getClassLoader();
        String factoryName = record.optString("componentFactory", "");
        AppComponentFactory factory = factoryName.isEmpty() ? new AppComponentFactory()
            : (AppComponentFactory) Class.forName(factoryName, true, loader).newInstance();
        String applicationName = record.optString("application", "");
        Application application = factory.instantiateApplication(loader,
            applicationName.isEmpty() ? "android.app.Application" : applicationName);
        application.attach(context);
        context.setApplication(application);
        sApplications.put(owner, application); sFactories.put(owner, factory);
        try {
            for (android.content.pm.ProviderInfo info : SharedPackages.providersForPackage(owner)) {
                android.content.ContentProvider provider = factory.instantiateProvider(loader, info.name);
                provider.attachInfo(application, info);
                android.content.LocalContentProviders.publish(info, provider);
            }
            application.onCreate();
        }
        catch (Throwable failure) {
            sApplications.remove(owner); sFactories.remove(owner);
            android.content.LocalContentProviders.removePackage(owner);
            RuntimeException error = new RuntimeException("Shared application initialization failed: " + owner, failure);
            sFailures.put(owner, error);
            throw error;
        }
        return application;
    }
    public static synchronized AppComponentFactory factory(String owner) throws Exception {
        get(owner); return sFactories.get(owner);
    }
    public static synchronized Application[] snapshot() {
        return sApplications.values().toArray(new Application[sApplications.size()]);
    }
    public static synchronized void clear() { sApplications.clear(); sFactories.clear(); sFailures.clear(); }
}
