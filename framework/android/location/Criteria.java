package android.location;

/** Describe criteria for selecting a location provider. */





public class Criteria {
/**   ch nh x c: kh ng c  y u c u. */
    public static final int NO_REQUIREMENT = 0;
    /** precision: low. */
    public static final int ACCURACY_LOW = 1;
    /** precision: average. */
    public static final int ACCURACY_MEDIUM = 2;
    /** accuracy: high. */
    public static final int ACCURACY_HIGH = 3;

    /** energy: no requests. */
    public static final int POWER_LOW = 1;
    /** energy: average. */
    public static final int POWER_MEDIUM = 2;
    /** energy: high. */
    public static final int POWER_HIGH = 3;

    private int mAccuracy = NO_REQUIREMENT;
    private int mPowerRequirement = NO_REQUIREMENT;

    public Criteria() {
    }

    public Criteria(Criteria criteria) {
        if (criteria != null) {
            mAccuracy = criteria.mAccuracy;
            mPowerRequirement = criteria.mPowerRequirement;
        }
    }

    public int getAccuracy() {
        return mAccuracy;
    }

    public void setAccuracy(int accuracy) {
        mAccuracy = accuracy;
    }

    public int getPowerRequirement() {
        return mPowerRequirement;
    }

    public void setPowerRequirement(int powerRequirement) {
        mPowerRequirement = powerRequirement;
    }
}