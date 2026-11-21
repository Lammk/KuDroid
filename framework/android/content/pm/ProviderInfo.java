package android.content.pm;

import android.os.Parcel;
import android.os.Parcelable;

public class ProviderInfo extends ComponentInfo implements Parcelable {
    public String authority;
    public String readPermission;
    public String writePermission;
    public boolean grantUriPermissions;
    public boolean multiprocess;
    public int initOrder;
    public int flags;
    public boolean isSyncable;
    public static final int FLAG_SINGLE_USER = 0x40000000;

    public ProviderInfo() {}
    public ProviderInfo(ProviderInfo source) {
        super(source);
        authority = source.authority;
        readPermission = source.readPermission;
        writePermission = source.writePermission;
        grantUriPermissions = source.grantUriPermissions;
        multiprocess = source.multiprocess;
        initOrder = source.initOrder;
        flags = source.flags;
        isSyncable = source.isSyncable;
    }
    public int describeContents() { return 0; }
    public void writeToParcel(Parcel dest, int flags) {}
}
