package android.os;

/** Reports the state of the mounted primary guest user. */
public class UserManager {
    private static final UserManager INSTANCE = new UserManager();

    public static UserManager get(android.content.Context context) {
        if (context == null) throw new NullPointerException("context");
        return INSTANCE;
    }

    public boolean isUserUnlocked() {
        // Guest credential storage is mounted before application startup.
        return true;
    }

    public boolean isUserUnlocked(UserHandle user) {
        if (user == null) throw new NullPointerException("user");
        return user.getIdentifier() == 0 && isUserUnlocked();
    }
}
