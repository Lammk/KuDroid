package android.content.pm;

import android.content.ComponentName;
import android.content.Intent;
import android.content.res.AssetManager;
import android.content.res.Resources;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class SharedPackages {
    private SharedPackages() {}
    private static native String nativePackageData(String name, boolean currentPackage);
    private static native String nativeSharedPackages();
    private static native int nativeGeneration();
    private static int sGeneration = -1;
    private static final java.util.HashMap<String, JSONObject> sRecords = new java.util.HashMap<String, JSONObject>();
    private static JSONArray sShared;
    private static void refreshGeneration() {
        int generation = nativeGeneration();
        if (generation != sGeneration) { sRecords.clear(); sShared = null; sGeneration = generation; }
    }

    public static synchronized JSONObject record(String name, boolean currentPackage) {
        refreshGeneration();
        String key = (currentPackage ? "current:" : "installed:") + name;
        JSONObject cached = sRecords.get(key);
        if (cached != null) return cached;
        String data = nativePackageData(name, currentPackage);
        if (data == null || data.isEmpty()) return null;
        try {
            JSONObject record = new JSONObject(data); sRecords.put(key, record); return record;
        } catch (Exception invalid) { return null; }
    }

    public static synchronized JSONArray records() {
        refreshGeneration();
        if (sShared != null) return sShared;
        String data = nativeSharedPackages();
        try { sShared = new JSONArray(data != null ? data : "[]"); return sShared; }
        catch (Exception invalid) { return new JSONArray(); }
    }

    public static ApplicationInfo applicationInfo(JSONObject record) {
        if (record == null) return null;
        String name = record.optString("package", "");
        ApplicationInfo info = new ApplicationInfo();
        info.packageName = name; info.processName = record.optString("process", name);
        if (info.processName.isEmpty()) info.processName = name;
        info.className = record.optString("application", "");
        info.name = info.className;
        info.sourceDir = "/data/app/" + name + "/base.apk";
        info.publicSourceDir = info.sourceDir;
        info.dataDir = "/data/data/" + name;
        info.nativeLibraryDir = "/data/app/" + name + "/lib/" + android.os.Build.CPU_ABI;
        info.uid = android.os.Process.myUid();
        info.targetSdkVersion = record.optInt("targetSdk", android.os.Build.VERSION.SDK_INT);
        info.enabled = record.optBoolean("enabled", true);
        info.metaData = metadata(record, info);
        return info;
    }

    public static PackageInfo packageInfo(JSONObject record) {
        if (record == null) return null;
        PackageInfo info = new PackageInfo();
        info.packageName = record.optString("package", "");
        info.applicationInfo = applicationInfo(record);
        info.versionName = record.optString("versionName", "");
        long version = record.optLong("versionCode", 0);
        info.versionCode = (int) version;
        info.versionCodeMajor = version >>> 32;
        JSONArray permissions = record.optJSONArray("permissions");
        if (permissions != null) {
            info.requestedPermissions = new String[permissions.length()];
            info.requestedPermissionsFlags = new int[permissions.length()];
            for (int i = 0; i < permissions.length(); ++i) {
                info.requestedPermissions[i] = permissions.optString(i);
                if (RuntimePermissions.check(info.packageName, info.requestedPermissions[i]) == PackageManager.PERMISSION_GRANTED)
                    info.requestedPermissionsFlags[i] = 2;
            }
        }
        ArrayList<Signature> signatures = new ArrayList<Signature>();
        JSONArray actual = record.optJSONArray("signatures");
        if (actual != null) for (int i = 0; i < actual.length(); ++i) {
            try { signatures.add(new Signature(actual.optString(i))); } catch (IllegalArgumentException invalid) {}
        }
        if (record.optBoolean("spoofGranted", false)) {
            String fake = record.optString("fakeSignature", "");
            try {
                if (!fake.isEmpty()) {
                    Signature signature = new Signature(fake);
                    signatures.clear(); signatures.add(signature);
                }
            } catch (IllegalArgumentException invalid) {}
        }
        info.signatures = signatures.toArray(new Signature[signatures.size()]);
        info.signingInfo = new SigningInfo(info.signatures);
        return info;
    }

    public static Resources resources(ApplicationInfo info) throws PackageManager.NameNotFoundException {
        AssetManager assets = new AssetManager();
        if (assets.addAssetPath(info.sourceDir) == 0) throw new PackageManager.NameNotFoundException(info.packageName);
        Resources system = Resources.getSystem();
        return new Resources(assets, system.getDisplayMetrics(), system.getConfiguration());
    }

    private static android.os.Bundle metadata(JSONObject record, ApplicationInfo info) {
        android.os.Bundle result = new android.os.Bundle();
        JSONArray entries = record.optJSONArray("metadata");
        if (entries == null) return result;
        for (int i = 0; i < entries.length(); ++i) {
            JSONObject entry = entries.optJSONObject(i);
            if (entry == null) continue;
            String name = entry.optString("name", ""), value = entry.optString("value", "");
            if (name.isEmpty()) continue;
            try {
                int type = entry.optInt("type", 0);
                if (entry.optBoolean("resource", false) || type == 1) {
                    Resources source = resources(info);
                    String reference = value.startsWith("@") ? value.substring(1) : value;
                    int id = reference.startsWith("0x") ? (int) Long.parseLong(reference.substring(2), 16)
                        : (!reference.isEmpty() && Character.isDigit(reference.charAt(0))) ? (int) Long.parseLong(reference)
                        : source.getIdentifier(reference, null, info.packageName);
                    if (entry.optBoolean("resource", false)) result.putInt(name, id);
                    else {
                        android.util.TypedValue resolved = new android.util.TypedValue();
                        source.getValue(id, resolved, true);
                        if (resolved.type == 3) result.putString(name, resolved.string.toString());
                        else result.putInt(name, resolved.data);
                    }
                } else if (type == 18) result.putBoolean(name, "true".equalsIgnoreCase(value));
                else if (type >= 16 && type <= 31) result.putInt(name, Integer.decode(value));
                else if (type == 4) result.putFloat(name, Float.parseFloat(value));
                else result.putString(name, value);
            } catch (Exception invalid) { android.util.Log.w("PackageManager", "Cannot resolve metadata: " + name); }
        }
        return result;
    }

    public static ServiceInfo service(ComponentName component, int flags) {
        if (component == null) return null;
        JSONObject owner = record(component.getPackageName(), false);
        if (owner == null || !owner.optBoolean("shared", false)) return null;
        JSONArray services = owner.optJSONArray("services");
        if (services == null) return null;
        for (int i = 0; i < services.length(); ++i) {
            JSONObject value = services.optJSONObject(i);
            if (value == null || !component.getClassName().equals(value.optString("name", ""))) continue;
            ServiceInfo info = new ServiceInfo(); info.name = component.getClassName();
            info.packageName = component.getPackageName(); info.applicationInfo = applicationInfo(owner);
            info.processName = info.applicationInfo.processName;
            info.enabled = value.optBoolean("enabled", true) && owner.optBoolean("enabled", true);
            info.exported = value.optBoolean("exported", false);
            info.permission = value.optString("permission", "");
            if (info.permission.isEmpty()) info.permission = null;
            if ((flags & PackageManager.GET_META_DATA) != 0) info.metaData = metadata(value, info.applicationInfo);
            return info;
        }
        return null;
    }

    public static List<ResolveInfo> queryServices(Intent intent, int flags) {
        ArrayList<ResolveInfo> result = new ArrayList<ResolveInfo>();
        if (intent == null) return result;
        JSONArray packages = records();
        for (int p = 0; p < packages.length(); ++p) {
            JSONObject record = packages.optJSONObject(p);
            if (record == null || !record.optBoolean("enabled", true)) continue;
            String owner = record.optString("package", "");
            if (owner.equals(SystemPackageManager.getRegisteredPackageName())) continue;
            if (intent.getPackage() != null && !owner.equals(intent.getPackage())) continue;
            JSONArray services = record.optJSONArray("services");
            if (services == null) continue;
            for (int s = 0; s < services.length(); ++s) {
                JSONObject service = services.optJSONObject(s);
                if (service == null || !service.optBoolean("enabled", true) ||
                    !service.optBoolean("exported", false)) continue;
                ComponentName component = intent.getComponent();
                int priority = 0;
                boolean matches = component != null && owner.equals(component.getPackageName()) &&
                    service.optString("name", "").equals(component.getClassName());
                if (component == null) {
                    JSONArray filters = service.optJSONArray("filters");
                    if (filters != null) for (int f = 0; f < filters.length(); ++f) {
                        JSONObject filter = filters.optJSONObject(f);
                        if (filter == null || filter.optBoolean("hasData", false) ||
                            intent.getData() != null || intent.getType() != null) continue;
                        android.content.IntentFilter parsed = new android.content.IntentFilter();
                        JSONArray actions = filter.optJSONArray("actions");
                        JSONArray categories = filter.optJSONArray("categories");
                        if (actions != null) for (int i = 0; i < actions.length(); ++i) parsed.addAction(actions.optString(i));
                        if (categories != null) for (int i = 0; i < categories.length(); ++i) parsed.addCategory(categories.optString(i));
                        if (parsed.countActions() == 0 || (intent.getAction() != null && !parsed.hasAction(intent.getAction()))) continue;
                        boolean accepted = true;
                        if (intent.getCategories() != null) for (String category : intent.getCategories()) {
                            if (!parsed.hasCategory(category)) accepted = false;
                        }
                        if ((flags & PackageManager.MATCH_DEFAULT_ONLY) != 0 &&
                            !parsed.hasCategory("android.intent.category.DEFAULT")) accepted = false;
                        if (accepted) { matches = true; priority = Math.max(priority, filter.optInt("priority", 0)); }
                    }
                }
                if (!matches) continue;
                ServiceInfo info = service(new ComponentName(owner, service.optString("name", "")), flags);
                ResolveInfo resolved = new ResolveInfo(); resolved.serviceInfo = info; resolved.priority = priority;
                result.add(resolved);
            }
        }
        return result;
    }

    public static ProviderInfo provider(String authority) {
        JSONArray packages = records();
        for (int p = 0; p < packages.length(); ++p) {
            JSONObject record = packages.optJSONObject(p);
            if (record == null || !record.optBoolean("enabled", true)) continue;
            JSONArray providers = record.optJSONArray("providers");
            if (providers == null) continue;
            for (int i = 0; i < providers.length(); ++i) {
                JSONObject value = providers.optJSONObject(i);
                if (value == null || !value.optBoolean("enabled", true)) continue;
                String authorities = value.optString("authority", "");
                boolean match = false;
                for (String candidate : authorities.split(";")) if (candidate.equals(authority)) match = true;
                if (!match) continue;
                return providerInfo(record, value, PackageManager.GET_META_DATA);
            }
        }
        return null;
    }

    public static ProviderInfo provider(ComponentName component, int flags) {
        if (component == null) return null;
        JSONObject record = record(component.getPackageName(), false);
        JSONArray providers = record != null ? record.optJSONArray("providers") : null;
        if (providers == null) return null;
        for (int i = 0; i < providers.length(); ++i) {
            JSONObject value = providers.optJSONObject(i);
            if (value == null || !component.getClassName().equals(value.optString("name", ""))) continue;
            boolean enabled = record.optBoolean("enabled", true) && value.optBoolean("enabled", true);
            if (!enabled && (flags & PackageManager.MATCH_DISABLED_COMPONENTS) == 0) return null;
            return providerInfo(record, value, flags);
        }
        return null;
    }

    private static ProviderInfo providerInfo(JSONObject record, JSONObject value, int flags) {
        ProviderInfo info = new ProviderInfo(); info.name = value.optString("name", "");
        info.packageName = record.optString("package", ""); info.authority = value.optString("authority", "");
        info.applicationInfo = applicationInfo(record); info.enabled = record.optBoolean("enabled", true) && value.optBoolean("enabled", true);
        info.exported = value.optBoolean("exported", false);
        info.processName = value.optString("process", info.applicationInfo.processName);
        if (info.processName.isEmpty()) info.processName = info.applicationInfo.processName;
        info.initOrder = value.optInt("initOrder", 0);
        info.readPermission = value.optString("readPermission", "");
        info.writePermission = value.optString("writePermission", "");
        if (info.readPermission.isEmpty()) info.readPermission = null;
        if (info.writePermission.isEmpty()) info.writePermission = null;
        info.grantUriPermissions = value.optBoolean("grantUriPermissions", false);
        info.directBootAware = value.optBoolean("directBootAware", false);
        if ((flags & PackageManager.GET_META_DATA) != 0) info.metaData = metadata(value, info.applicationInfo);
        return info;
    }

    public static ProviderInfo[] providersForPackage(String owner) {
        ArrayList<ProviderInfo> result = new ArrayList<ProviderInfo>();
        JSONObject record = record(owner, false);
        JSONArray providers = record != null ? record.optJSONArray("providers") : null;
        if (providers == null) return new ProviderInfo[0];
        ApplicationInfo application = applicationInfo(record);
        for (int i = 0; i < providers.length(); ++i) {
            JSONObject value = providers.optJSONObject(i);
            if (value == null) continue;
            String authorities = value.optString("authority", "");
            if (authorities.isEmpty()) continue;
            ProviderInfo info = provider(authorities.split(";")[0]);
            if (info != null && application.processName.equals(info.processName)) result.add(info);
        }
        java.util.Collections.sort(result, new java.util.Comparator<ProviderInfo>() {
            public int compare(ProviderInfo a, ProviderInfo b) { return Integer.compare(b.initOrder, a.initOrder); }
        });
        return result.toArray(new ProviderInfo[result.size()]);
    }
}
