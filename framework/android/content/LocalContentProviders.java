package android.content;

import android.content.pm.ProviderInfo;
import java.util.HashMap;

public final class LocalContentProviders {
    private static final HashMap<String, ContentProvider> sProviders = new HashMap<String, ContentProvider>();
    private LocalContentProviders() {}

    public static void clear() {
        synchronized (android.app.SharedApplications.class) {
            synchronized (LocalContentProviders.class) { sProviders.clear(); }
            android.app.SharedApplications.clear();
        }
    }

    public static ContentProvider get(String authority) {
        ContentProvider existing;
        synchronized (LocalContentProviders.class) { existing = sProviders.get(authority); }
        if (existing != null) return existing;
        synchronized (android.app.SharedApplications.class) {
        synchronized (LocalContentProviders.class) { existing = sProviders.get(authority); }
        if (existing != null) return existing;
        ProviderInfo info = android.content.pm.SharedPackages.provider(authority);
        if (info == null || !info.exported) return null;
        try {
            android.app.Application application = android.app.SharedApplications.get(info.packageName);
            synchronized (LocalContentProviders.class) { existing = sProviders.get(authority); }
            if (existing != null) return existing;
            ContentProvider provider = android.app.SharedApplications.factory(info.packageName)
                .instantiateProvider(application.getClassLoader(), info.name);
            provider.attachInfo(application, info); publish(info, provider);
            return provider;
        } catch (Exception failure) {
            throw new RuntimeException("Unable to get provider " + info.name, failure);
        }
        }
    }

    public static synchronized ContentProvider[] snapshot() {
        java.util.IdentityHashMap<ContentProvider, Boolean> unique =
                new java.util.IdentityHashMap<ContentProvider, Boolean>();
        for (ContentProvider provider : sProviders.values()) unique.put(provider, Boolean.TRUE);
        return unique.keySet().toArray(new ContentProvider[unique.size()]);
    }

    public static synchronized void removePackage(String owner) {
        java.util.ArrayList<String> authorities = new java.util.ArrayList<String>();
        for (java.util.Map.Entry<String, ContentProvider> entry : sProviders.entrySet()) {
            ContentProvider provider = entry.getValue();
            if (provider.getContext() != null && owner.equals(provider.getContext().getPackageName()))
                authorities.add(entry.getKey());
        }
        for (String authority : authorities) sProviders.remove(authority);
    }

    public static synchronized void publish(ProviderInfo info, ContentProvider provider) {
        for (String authority : info.authority.split(";")) {
            if (!authority.isEmpty()) sProviders.put(authority, provider);
        }
    }
}
