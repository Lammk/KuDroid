package android.content.pm;

import android.content.res.XmlResourceParser;
import android.os.Bundle;

public class PackageItemInfo {
    public String name;
    public String packageName;
    public int labelRes;
    public CharSequence nonLocalizedLabel;
    public int icon;
    public int banner;
    public int logo;
    public Bundle metaData;

    public PackageItemInfo() {}

    public PackageItemInfo(PackageItemInfo source) {
        name = source.name;
        packageName = source.packageName;
        labelRes = source.labelRes;
        nonLocalizedLabel = source.nonLocalizedLabel;
        icon = source.icon;
        banner = source.banner;
        logo = source.logo;
        metaData = source.metaData == null ? null : new Bundle(source.metaData);
    }

    public XmlResourceParser loadXmlMetaData(PackageManager manager, String key) {
        if (metaData == null) return null;
        int id = metaData.getInt(key);
        return id == 0 ? null : manager.getXml(packageName, id, null);
    }

    public CharSequence loadLabel(PackageManager manager) {
        if (nonLocalizedLabel != null) return nonLocalizedLabel;
        CharSequence label = labelRes == 0 ? null : manager.getText(packageName, labelRes, null);
        return label != null ? label : name != null ? name : packageName;
    }
}
