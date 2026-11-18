package launch.fixture;

public final class JavaOnlyLaunchActivity extends android.app.Activity {
    public static boolean created;
    public static boolean resumed;

    @Override public void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        created = true;
    }

    @Override public void onResume() {
        super.onResume();
        resumed = true;
        finish();
    }
}
