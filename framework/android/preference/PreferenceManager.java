package android.preference;

import android.content.Context;
import android.content.SharedPreferences;

/** Open the package's default shared preferences. */












public class PreferenceManager {

    private final Context mContext;

    public PreferenceManager(Context context) {
        mContext = context;
    }

    public static SharedPreferences getDefaultSharedPreferences(Context context) {
        if (context == null) {
            // A null context has nowhere to persist to, but returning null here would turn
            // a missing context into a NullPointerException inside the caller, one step
            // removed from the cause. An empty in-memory store is honest and survivable.
            return new android.content.SharedPreferencesImpl("_no_context");
        }
        return context.getSharedPreferences(getDefaultSharedPreferencesName(context),
                                            getDefaultSharedPreferencesMode());
    }

    public static String getDefaultSharedPreferencesName(Context context) {
        final String pkg = context != null ? context.getPackageName() : null;
        return (pkg != null ? pkg : "android") + "_preferences";
    }

    public static int getDefaultSharedPreferencesMode() {
        return Context.MODE_PRIVATE;
    }

    public SharedPreferences getSharedPreferences() {
        return getDefaultSharedPreferences(mContext);
    }

    /**
     * Android's own no-op when an app has no XML preference resources to migrate. Apps call
     * it defensively on startup.
     */
    public static void setDefaultValues(Context context, int resId, boolean readAgain) {}

    public static void setDefaultValues(Context context, String sharedPreferencesName,
                                        int sharedPreferencesMode, int resId,
                                        boolean readAgain) {}

    public Context getContext() { return mContext; }
}
