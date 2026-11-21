package android.content.pm;

import android.content.ComponentName;
import android.content.Intent;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;

/** Resolve package metadata declared by the manifest. */



















public class SystemPackageManager extends PackageManager {

    /**
     * Manifest meta-data, keyed by fully-qualified component name.
     *
     * Static because there is one manifest per process while SystemPackageManager is
     * constructed per Context — an instance field would mean whichever Context an app
     * happened to ask through decided whether the data existed.
     */
    private static final Map<String, android.os.Bundle> sComponentMetaData =
            new HashMap<String, android.os.Bundle>();

    /** Meta-data declared directly under &lt;application&gt;. */
    private static android.os.Bundle sApplicationMetaData = new android.os.Bundle();

    /** The running package, so a query naming it can be answered. */
    private static String sPackageName = "";
    private static String sProcessName = "";
    private static boolean sApplicationEnabled = true;

    /** Every activity the manifest declared, in launch order. */
    private static final List<String> sActivities = new ArrayList<String>();

    private static final Map<String, ServiceInfo> sServices = new HashMap<String, ServiceInfo>();
    private static final Map<String, ProviderInfo> sProviders = new LinkedHashMap<String, ProviderInfo>();
    private static final Map<String, List<ServiceFilter>> sServiceFilters =
            new HashMap<String, List<ServiceFilter>>();
    private static final Map<String, Integer> sComponentStates = new HashMap<String, Integer>();

    @Override
    public void setComponentEnabledSetting(ComponentName component, int state, int flags) {
        if (component == null) return;
        synchronized (SystemPackageManager.class) {
            sComponentStates.put(component.flattenToString(), state);
        }
    }

    @Override
    public int getComponentEnabledSetting(ComponentName component) {
        if (component == null) return COMPONENT_ENABLED_STATE_DEFAULT;
        synchronized (SystemPackageManager.class) {
            Integer state = sComponentStates.get(component.flattenToString());
            return state == null ? COMPONENT_ENABLED_STATE_DEFAULT : state;
        }
    }

    private static final class ServiceFilter {
        final android.content.IntentFilter filter = new android.content.IntentFilter();
        int priority;
        boolean hasData;
    }

    public static synchronized void registerService(String name, boolean enabled,
            boolean exported, String permission) {
        if (name == null || name.isEmpty()) throw new IllegalArgumentException("Empty service name");
        ServiceInfo info = new ServiceInfo();
        info.name = name;
        info.packageName = sPackageName;
        info.enabled = enabled;
        info.exported = exported;
        info.permission = permission == null || permission.isEmpty() ? null : permission;
        sServices.put(name, info);
        sServiceFilters.put(name, new ArrayList<ServiceFilter>());
    }

    public static synchronized void registerServiceIntentFilter(String name, String[] actions,
            String[] categories, int priority, boolean hasData) {
        List<ServiceFilter> filters = sServiceFilters.get(name);
        if (filters == null) throw new IllegalArgumentException("Unknown service: " + name);
        ServiceFilter entry = new ServiceFilter();
        if (actions != null) for (String action : actions) entry.filter.addAction(action);
        if (categories != null) for (String category : categories) entry.filter.addCategory(category);
        entry.priority = priority;
        entry.hasData = hasData;
        filters.add(entry);
    }

    /**
     * Register one component's meta-data. Called from the native launcher, once per
     * component, before the app starts.
     *
     * `componentName` empty means the &lt;application&gt; element. Values arrive as
     * strings because that is what AXML stores; a caller wanting an int uses
     * Bundle.getInt, which parses on the way out.
     */
    public static synchronized void registerComponentMetaData(String componentName,
                                                             String[] keys,
                                                             String[] values) {
        if (keys == null || values == null) return;
        android.os.Bundle bundle = new android.os.Bundle();
        final int n = Math.min(keys.length, values.length);
        for (int i = 0; i < n; ++i) {
            if (keys[i] == null || keys[i].isEmpty()) continue;
            String v = values[i] != null ? values[i] : "";
            if ("true".equalsIgnoreCase(v)) {
                bundle.putBoolean(keys[i], true);
            } else if ("false".equalsIgnoreCase(v)) {
                bundle.putBoolean(keys[i], false);
            } else if (v.startsWith("@0x") || (v.startsWith("@") && v.length() > 1 && Character.isDigit(v.charAt(1)))) {
                try {
                    String num = v.startsWith("@0x") ? v.substring(3) : v.substring(1);
                    int resId = (int) Long.parseLong(num, v.startsWith("@0x") ? 16 : 10);
                    bundle.putInt(keys[i], resId);
                } catch (Exception ignored) {
                    bundle.putString(keys[i], v);
                }
            } else {
                boolean isNumber = false;
                boolean isFloat = false;
                if (!v.isEmpty()) {
                    int dots = 0;
                    int start = (v.charAt(0) == '-' || v.charAt(0) == '+') ? 1 : 0;
                    if (start < v.length()) {
                        isNumber = true;
                        for (int k = start; k < v.length(); k++) {
                            char c = v.charAt(k);
                            if (c == '.') {
                                dots++;
                                if (dots > 1) { isNumber = false; break; }
                            } else if (c < '0' || c > '9') {
                                isNumber = false;
                                break;
                            }
                        }
                        if (isNumber && dots == 1 && v.length() > start + 1) {
                            isFloat = true;
                        } else if (dots > 0) {
                            isNumber = false;
                        }
                    }
                }
                if (isNumber) {
                    try {
                        if (isFloat) {
                            bundle.putFloat(keys[i], Float.parseFloat(v));
                        } else {
                            bundle.putInt(keys[i], Integer.parseInt(v));
                        }
                    } catch (NumberFormatException notNumber) {
                        bundle.putString(keys[i], v);
                    }
                } else {
                    bundle.putString(keys[i], v);
                }
            }
        }
        storeMetaData(componentName, bundle);
    }

    private static void storeMetaData(String componentName, android.os.Bundle bundle) {
        if (componentName == null || componentName.isEmpty()) {
            sApplicationMetaData = bundle;
        } else {
            sComponentMetaData.put(componentName, bundle);
        }
    }

    private static int resourceId(String reference, android.content.res.Resources resources) {
        String value = reference.startsWith("@") ? reference.substring(1) : reference;
        if (value.startsWith("0x")) return (int) Long.parseLong(value.substring(2), 16);
        if (!value.isEmpty() && Character.isDigit(value.charAt(0))) return (int) Long.parseLong(value);
        return resources.getIdentifier(value, null, sPackageName);
    }

    public static synchronized void registerComponentMetaDataTyped(String componentName,
            String[] keys, String[] values, int[] types) {
        if (keys == null || values == null || types == null) throw new NullPointerException();
        if (keys.length != values.length || keys.length != types.length)
            throw new IllegalArgumentException("Metadata arrays have different lengths");
        android.os.Bundle bundle = new android.os.Bundle();
        android.content.res.Resources resources = android.content.res.Resources.getSystem();
        for (int i = 0; i < keys.length; i++) {
            String key = keys[i];
            if (key == null || key.isEmpty()) continue;
            String value = values[i] == null ? "" : values[i];
            int type = types[i] & 0xff;
            if ((types[i] & 0x100) != 0) {
                bundle.putInt(key, resourceId(value, resources));
            } else if (type == android.util.TypedValue.TYPE_REFERENCE) {
                android.util.TypedValue resolved = new android.util.TypedValue();
                resources.getValue(resourceId(value, resources), resolved, true);
                if (resolved.type == android.util.TypedValue.TYPE_STRING) {
                    bundle.putString(key, resolved.string == null ? null : resolved.string.toString());
                } else if (resolved.type == android.util.TypedValue.TYPE_INT_BOOLEAN) {
                    bundle.putBoolean(key, resolved.data != 0);
                } else if (resolved.type >= android.util.TypedValue.TYPE_FIRST_INT
                        && resolved.type <= android.util.TypedValue.TYPE_LAST_INT) {
                    bundle.putInt(key, resolved.data);
                } else if (resolved.type == android.util.TypedValue.TYPE_FLOAT) {
                    bundle.putFloat(key, resolved.getFloat());
                }
            } else if (type == android.util.TypedValue.TYPE_INT_BOOLEAN) {
                bundle.putBoolean(key, "true".equalsIgnoreCase(value));
            } else if (type >= android.util.TypedValue.TYPE_FIRST_INT
                    && type <= android.util.TypedValue.TYPE_LAST_INT) {
                bundle.putInt(key, (int) Long.parseLong(value));
            } else if (type == android.util.TypedValue.TYPE_FLOAT) {
                bundle.putFloat(key, Float.parseFloat(value));
            } else if (type == android.util.TypedValue.TYPE_STRING || type == 0) {
                bundle.putString(key, value);
            }
        }
        storeMetaData(componentName, bundle);
    }

    private static int sApplicationTheme;
    private static final java.util.HashMap<String, Integer> sActivityThemes = new java.util.HashMap<>();

    public static synchronized void registerTheme(String component, int theme) {
        if (component == null || component.isEmpty()) sApplicationTheme = theme;
        else sActivityThemes.put(component, theme);
    }

    public static synchronized int getRegisteredApplicationTheme() { return sApplicationTheme; }

    private static synchronized int activityTheme(String component) {
        Integer theme = sActivityThemes.get(component);
        return theme == null ? 0 : theme;
    }

    /** Register the package name and activity list the manifest declared. */
    public static synchronized void registerPackage(String packageName, String[] activities) {
        registerPackage(packageName, activities, true);
    }

    public static synchronized void registerPackage(String packageName, String[] activities,
            boolean enabled) {
        if (packageName != null) sPackageName = packageName;
        sProcessName = sPackageName;
        sApplicationEnabled = enabled;
        sActivities.clear();
        sServices.clear();
        for (ProviderInfo provider : sProviders.values()) sComponentMetaData.remove(provider.name);
        sProviders.clear();
        android.content.LocalContentProviders.clear();
        sServiceFilters.clear();
        sComponentStates.clear();
        sApplicationTheme = 0;
        sActivityThemes.clear();
        if (activities != null) {
            for (String a : activities) {
                if (a != null && !a.isEmpty()) sActivities.add(a);
            }
        }
    }

    private static int sVersionCode = 1;
    private static String sVersionName = "1.0.0";
    private static long sFirstInstallTime = 0;
    private static long sLastUpdateTime = 0;

    /** Manifest-declared version + install times; 1.0.0/1/0 stays the fallback. */
    public static synchronized void registerPackageInfo(String packageName, int versionCode,
                                                        String versionName, long firstInstallTime,
                                                        long lastUpdateTime) {
        if (packageName != null) sPackageName = packageName;
        sVersionCode = versionCode;
        if (versionName != null) sVersionName = versionName;
        sFirstInstallTime = firstInstallTime;
        sLastUpdateTime = lastUpdateTime;
    }

    public static synchronized String getRegisteredPackageName() {
        return sPackageName;
    }

    /**
     * The meta-data of `componentName`, falling back to the application's.
     *
     * The fallback matches how apps are written rather than how Android stores it: a
     * library documenting a manifest key rarely says which element it belongs under,
     * so across real APKs the same key turns up in either place. Returning the
     * application bundle for an unknown component is more useful than an empty one,
     * and no less correct — Android would have merged nothing, but it would also have
     * had the key in whichever place the app put it.
     */
    private static synchronized android.os.Bundle metaDataFor(String componentName) {
        if (componentName != null) {
            android.os.Bundle b = sComponentMetaData.get(componentName);
            if (b != null) return b;
        }
        return sApplicationMetaData;
    }

    @Override
    public ProviderInfo resolveContentProvider(String authority, int flags) {
        if (authority == null) return null;
        synchronized (SystemPackageManager.class) {
            for (ProviderInfo provider : sProviders.values()) {
                if (!providerEnabled(provider) && (flags & MATCH_DISABLED_COMPONENTS) == 0) continue;
                for (String declared : provider.authority.split(";")) {
                    if (authority.equals(declared)) {
                        try { return providerInfo(provider, flags); }
                        catch (NameNotFoundException failure) { return null; }
                    }
                }
            }
            return SharedPackages.provider(authority);
        }
    }

    @Override
    public ProviderInfo getProviderInfo(ComponentName component, int flags) throws NameNotFoundException {
        synchronized (SystemPackageManager.class) {
            if (component != null && !sPackageName.equals(component.getPackageName())) {
                ProviderInfo shared = SharedPackages.provider(component, flags);
                if (shared != null) return shared;
                throw new NameNotFoundException(component.toString());
            }
            ProviderInfo provider = component != null && sPackageName.equals(component.getPackageName())
                    ? sProviders.get(component.getClassName()) : null;
            if (provider == null || (!providerEnabled(provider) && (flags & MATCH_DISABLED_COMPONENTS) == 0))
                throw new NameNotFoundException(component == null ? "null component" : component.toString());
            return providerInfo(provider, flags);
        }
    }

    public static synchronized void registerPackageProcess(String processName) {
        sProcessName = processName == null || processName.isEmpty() ? sPackageName : processName;
    }

    public static synchronized void registerProvider(String name, String authorities, String processName,
            int initOrder, boolean enabled, boolean exported, boolean grantUriPermissions,
            boolean directBootAware, String readPermission, String writePermission) {
        if (name == null || name.isEmpty() || authorities == null || authorities.isEmpty())
            throw new IllegalArgumentException("Provider name and authorities are required");
        ProviderInfo info = new ProviderInfo();
        info.name = name;
        info.packageName = sPackageName;
        info.authority = authorities;
        info.processName = processName == null || processName.isEmpty() ? sProcessName : processName;
        info.initOrder = initOrder;
        info.enabled = enabled;
        info.exported = exported;
        info.grantUriPermissions = grantUriPermissions;
        info.directBootAware = directBootAware;
        info.readPermission = readPermission == null || readPermission.isEmpty() ? null : readPermission;
        info.writePermission = writePermission == null || writePermission.isEmpty() ? null : writePermission;
        sProviders.put(name, info);
    }

    private boolean providerEnabled(ProviderInfo provider) {
        return sApplicationEnabled && providerComponentEnabled(provider);
    }

    private boolean providerComponentEnabled(ProviderInfo provider) {
        int state = getComponentEnabledSetting(new ComponentName(provider.packageName, provider.name));
        return state == COMPONENT_ENABLED_STATE_ENABLED
                || (state == COMPONENT_ENABLED_STATE_DEFAULT && provider.enabled);
    }

    private ProviderInfo providerInfo(ProviderInfo declared, int flags) throws NameNotFoundException {
        ProviderInfo info = new ProviderInfo(declared);
        info.applicationInfo = getApplicationInfo(info.packageName, flags);
        info.enabled = providerComponentEnabled(declared);
        android.os.Bundle data = sComponentMetaData.get(info.name);
        info.metaData = (flags & GET_META_DATA) != 0 && data != null ? new android.os.Bundle(data) : null;
        return info;
    }

    public static synchronized ProviderInfo[] providersForProcess() {
        SystemPackageManager manager = new SystemPackageManager();
        ArrayList<ProviderInfo> providers = new ArrayList<ProviderInfo>();
        for (ProviderInfo provider : sProviders.values()) {
            if (!manager.providerEnabled(provider) || !sProcessName.equals(provider.processName)) continue;
            try { providers.add(manager.providerInfo(provider, GET_META_DATA)); }
            catch (NameNotFoundException failure) { throw new IllegalStateException(failure); }
        }
        Collections.sort(providers, new java.util.Comparator<ProviderInfo>() {
            public int compare(ProviderInfo first, ProviderInfo second) {
                return Integer.compare(second.initOrder, first.initOrder);
            }
        });
        return providers.toArray(new ProviderInfo[providers.size()]);
    }

    @Override
    public String getNameForUid(int uid) {
        synchronized (SystemPackageManager.class) {
            return uid == android.os.Process.myUid() && !sPackageName.isEmpty() ? sPackageName : null;
        }
    }

    @Override
    public ActivityInfo getReceiverInfo(ComponentName component, int flags)
            throws NameNotFoundException {
        // The package database has no registered manifest receivers.
        throw new NameNotFoundException(component == null ? "null component" : component.toString());
    }

    @Override
    public android.content.res.Resources getResourcesForApplication(ApplicationInfo info)
            throws NameNotFoundException {
        if (info == null) throw new NullPointerException("info == null");
        synchronized (SystemPackageManager.class) {
            if (!sPackageName.equals(info.packageName) && !"android".equals(info.packageName))
                return SharedPackages.resources(getApplicationInfo(info.packageName, GET_META_DATA));
        }
        return android.content.res.Resources.getSystem();
    }

    @Override
    public List<PackageInfo> getInstalledPackages(int flags) {
        synchronized (SystemPackageManager.class) {
            List<PackageInfo> packages = new ArrayList<PackageInfo>();
            if (!sPackageName.isEmpty()) {
                try {
                    packages.add(getPackageInfo(sPackageName, flags));
                } catch (NameNotFoundException ignored) {
                    // Only packages with available metadata are listed.
                }
            }
            org.json.JSONArray records = SharedPackages.records();
            for (int i = 0; i < records.length(); ++i) {
                org.json.JSONObject record = records.optJSONObject(i);
                if (record != null && !sPackageName.equals(record.optString("package", "")))
                    packages.add(SharedPackages.packageInfo(record));
            }
            return packages;
        }
    }

    @Override
    public PackageInfo getPackageInfo(String packageName, int flags) throws NameNotFoundException {
        if (!sPackageName.equals(packageName)) {
            PackageInfo installed = SharedPackages.packageInfo(SharedPackages.record(packageName, false));
            if (installed == null) throw new NameNotFoundException(packageName);
            return installed;
        }
        PackageInfo pi = new PackageInfo();
        pi.packageName = packageName;
        pi.applicationInfo = getApplicationInfo(packageName, flags);
        // Return registered manifest values or platform defaults.

        pi.versionName = sVersionName;
        pi.versionCode = sVersionCode;
        pi.firstInstallTime = sFirstInstallTime;
        pi.lastUpdateTime = sLastUpdateTime;
        PackageInfo installed = SharedPackages.packageInfo(SharedPackages.record(packageName, true));
        pi.signatures = installed != null ? installed.signatures : new Signature[0];
        pi.signingInfo = new SigningInfo(pi.signatures);
        if ((flags & GET_PROVIDERS) != 0 && sPackageName.equals(packageName)) {
            synchronized (SystemPackageManager.class) {
                ArrayList<ProviderInfo> providers = new ArrayList<ProviderInfo>();
                for (ProviderInfo provider : sProviders.values()) {
                    if (providerEnabled(provider) || (flags & MATCH_DISABLED_COMPONENTS) != 0)
                        providers.add(providerInfo(provider, flags));
                }
                if (!providers.isEmpty()) pi.providers = providers.toArray(new ProviderInfo[providers.size()]);
            }
        }
        return pi;
    }

    @Override
    public ApplicationInfo getApplicationInfo(String packageName, int flags) throws NameNotFoundException {
        if (!sPackageName.equals(packageName) && !"android".equals(packageName)) {
            ApplicationInfo installed = SharedPackages.applicationInfo(SharedPackages.record(packageName, false));
            if (installed == null) throw new NameNotFoundException(packageName);
            return installed;
        }
        ApplicationInfo ai = new ApplicationInfo();
        ai.packageName = packageName;
        ai.processName = packageName;
        if (sPackageName.equals(packageName)) ai.processName = sProcessName;
        ai.enabled = !sPackageName.equals(packageName) || sApplicationEnabled;
        ai.dataDir = "/data/data/" + packageName;
        ai.sourceDir = "/data/app/" + packageName + "/base.apk";
        ai.publicSourceDir = "/data/app/" + packageName + "/base.apk";
        ai.nativeLibraryDir = "/data/app/" + packageName + "/lib/" + android.os.Build.CPU_ABI;
        // Android only fills metaData when GET_META_DATA is asked for, but filling it
        // always is harmless and saves an app that forgot the flag — a common mistake
        // whose symptom (metaData present but empty) is indistinguishable from the
        // manifest not declaring anything.
        ai.metaData = metaDataFor(null);
        ai.theme = sPackageName.equals(packageName) ? getRegisteredApplicationTheme() : 0;
        return ai;
    }

    /**
     * The ActivityInfo of a declared component.
     *
     * Was absent entirely, so the call was auto-stubbed to null and the caller's
     * `ai.metaData` became a NullPointerException — GameActivity.onCreate died exactly
     * there. Throwing NameNotFoundException for an unknown component is what Android
     * does and what callers are written to expect; returning an empty ActivityInfo
     * instead would hide a wrong component name until something later read a field
     * off it.
     */
    @Override
    public ActivityInfo getActivityInfo(ComponentName component, int flags)
            throws NameNotFoundException {
        if (component == null) throw new NameNotFoundException("null component");
        final String className = component.getClassName();
        if (className == null || className.isEmpty()) {
            throw new NameNotFoundException("component has no class name");
        }

        ActivityInfo ai = new ActivityInfo();
        ai.name = className;
        ai.packageName = component.getPackageName() != null
                ? component.getPackageName() : sPackageName;
        ai.metaData = metaDataFor(className);
        ai.theme = activityTheme(className);
        ai.exported = true;
        ai.enabled = true;
        try {
            ai.applicationInfo = getApplicationInfo(ai.packageName, flags);
        } catch (NameNotFoundException ignored) {
            // The activity is still describable without it.
        }
        return ai;
    }

    @Override
    public ServiceInfo getServiceInfo(ComponentName component, int flags)
            throws NameNotFoundException {
        if (component == null) throw new NameNotFoundException("null component");
        if (!sPackageName.equals(component.getPackageName())) {
            ServiceInfo shared = SharedPackages.service(component, flags);
            if (shared == null) throw new NameNotFoundException(component.flattenToString());
            return shared;
        }
        synchronized (SystemPackageManager.class) {
            ServiceInfo declared = sServices.get(component.getClassName());
            if (declared == null || !declared.packageName.equals(component.getPackageName()))
                throw new NameNotFoundException(component.flattenToString());
            ServiceInfo info = new ServiceInfo();
            info.name = declared.name;
            info.packageName = declared.packageName;
            info.enabled = declared.enabled;
            info.exported = declared.exported;
            info.permission = declared.permission;
            info.applicationInfo = getApplicationInfo(info.packageName, flags);
            info.processName = info.packageName;
            if ((flags & GET_META_DATA) != 0) info.metaData = metaDataFor(info.name);
            return info;
        }
    }

    private boolean serviceEnabled(ServiceInfo info) {
        if (sPackageName.equals(info.packageName) ? !sApplicationEnabled : !info.applicationInfo.enabled) return false;
        int state = getComponentEnabledSetting(new ComponentName(info.packageName, info.name));
        return state == COMPONENT_ENABLED_STATE_ENABLED
                || (state == COMPONENT_ENABLED_STATE_DEFAULT && info.enabled);
    }

    @Override
    public List<ResolveInfo> queryIntentServices(Intent intent, int flags) {
        if (intent == null) throw new NullPointerException("intent == null");
        List<ResolveInfo> result = new ArrayList<ResolveInfo>();
        synchronized (SystemPackageManager.class) {
            ComponentName component = intent.getComponent();
            if (component != null) {
                try {
                    ServiceInfo info = getServiceInfo(component, flags);
                    if (serviceEnabled(info) && (sPackageName.equals(info.packageName) || info.exported)) {
                        ResolveInfo resolved = new ResolveInfo();
                        resolved.serviceInfo = info;
                        result.add(resolved);
                    }
                } catch (NameNotFoundException ignored) {}
                return result;
            }
            if (intent.getPackage() != null && !sPackageName.equals(intent.getPackage())) return SharedPackages.queryServices(intent, flags);
            for (ServiceInfo declared : sServices.values()) {
                if (!serviceEnabled(declared)) continue;
                ServiceFilter best = null;
                for (ServiceFilter entry : sServiceFilters.get(declared.name)) {
                    // Data filters require URI and MIME matching before they can resolve.
                    if (entry.hasData || intent.getData() != null || intent.getType() != null) continue;
                    if (entry.filter.countActions() == 0 || (intent.getAction() != null
                            && !entry.filter.hasAction(intent.getAction()))) continue;
                    boolean matches = true;
                    java.util.Set<String> categories = intent.getCategories();
                    if (categories != null) for (String category : categories) {
                        if (!entry.filter.hasCategory(category)) { matches = false; break; }
                    }
                    if ((flags & MATCH_DEFAULT_ONLY) != 0
                            && !entry.filter.hasCategory("android.intent.category.DEFAULT")) matches = false;
                    if (matches && (best == null || entry.priority > best.priority)) best = entry;
                }
                if (best == null) continue;
                ResolveInfo resolved = new ResolveInfo();
                try {
                    resolved.serviceInfo = getServiceInfo(
                            new ComponentName(declared.packageName, declared.name), flags);
                } catch (NameNotFoundException ignored) { continue; }
                resolved.priority = best.priority;
                resolved.isDefault = best.filter.hasCategory("android.intent.category.DEFAULT");
                result.add(resolved);
            }
        }
        result.addAll(SharedPackages.queryServices(intent, flags));
        Collections.sort(result, new java.util.Comparator<ResolveInfo>() {
            public int compare(ResolveInfo a, ResolveInfo b) {
                if (a.priority != b.priority) return a.priority > b.priority ? -1 : 1;
                return a.serviceInfo.name.compareTo(b.serviceInfo.name);
            }
        });
        return result;
    }

    @Override
    public int checkPermission(String permName, String pkgName) {
        return RuntimePermissions.check(pkgName, permName);
    }

    /** Whether the device has a named feature. */












    @Override
    public boolean hasSystemFeature(String name) {
        if (name == null) {
            return false;
        }
        // Alternate device types and television interfaces are not exposed.
        if (name.equals("android.software.leanback") ||
                name.equals("android.software.leanback_only") ||
                name.startsWith("android.hardware.type.")) {
            return false;
        }
        // No input hardware is reachable; see android.hardware.input.InputManager, which
        // reports the same thing through getInputDeviceIds().
        if (name.equals(FEATURE_GAMEPAD)) {
            return false;
        }
        // Camera and microphone are real, but only the original camera API is bridged:
        // no flash control, and none of the Camera2 capability levels.
        if (name.equals("android.hardware.camera.flash") ||
                name.startsWith("android.hardware.camera.level.") ||
                name.startsWith("android.hardware.camera.capability.")) {
            return false;
        }
        // Report only audio guarantees supported by the host.



        if (name.equals(FEATURE_AUDIO_LOW_LATENCY) || name.equals(FEATURE_AUDIO_PRO)) {
            return false;
        }
        return true;
    }

    @Override
    public boolean hasSystemFeature(String name, int version) {
        // Check whether a feature meets the requested version.


        return hasSystemFeature(name);
    }

    /**
     * Resolve an Intent to the component that handles it.
     *
     * Returned a blank ResolveInfo before, whose activityInfo was null — an app that
     * resolved an Intent and read the result got a NullPointerException instead of
     * either an answer or a null it could check.
     */
    @Override
    public ResolveInfo resolveActivity(Intent intent, int flags) {
        if (intent == null) return null;
        final ComponentName component = intent.getComponent();
        if (component == null) {
            // Resolve implicit intents against registered filters.

            if (android.app.ActivityThread.externalUrl(intent) != null) {
                ResolveInfo ri = new ResolveInfo();
                ri.activityInfo = new ActivityInfo();
                ri.activityInfo.name = "com.android.browser.BrowserActivity";
                ri.activityInfo.packageName = "com.android.browser";
                return ri;
            }
            return null;
        }
        try {
            ResolveInfo ri = new ResolveInfo();
            ri.activityInfo = getActivityInfo(component, flags);
            return ri;
        } catch (NameNotFoundException e) {
            return null;
        }
    }

    @Override
    public List<ResolveInfo> queryIntentActivities(Intent intent, int flags) {
        ResolveInfo one = resolveActivity(intent, flags);
        if (one == null) return Collections.emptyList();
        List<ResolveInfo> out = new ArrayList<ResolveInfo>(1);
        out.add(one);
        return out;
    }
}
