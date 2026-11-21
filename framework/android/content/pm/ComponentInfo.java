package android.content.pm;

public class ComponentInfo extends PackageItemInfo {
    public ApplicationInfo applicationInfo;
    public String processName;
    public boolean enabled = true;
    public boolean exported;
    public boolean directBootAware;
    public int descriptionRes;

    public ComponentInfo() {}

    public ComponentInfo(ComponentInfo source) {
        super(source);
        applicationInfo = source.applicationInfo;
        processName = source.processName;
        enabled = source.enabled;
        exported = source.exported;
        directBootAware = source.directBootAware;
        descriptionRes = source.descriptionRes;
    }

    public boolean isEnabled() {
        return enabled && applicationInfo.enabled;
    }
}
