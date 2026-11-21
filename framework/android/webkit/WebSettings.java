package android.webkit;

public class WebSettings {
    private boolean mJavaScriptEnabled;
    private boolean mDomStorageEnabled;
    private boolean mAllowFileAccess;
    private boolean mMediaGesture = true;
    private String mUserAgent;
    private static String defaultUserAgent;
    private final WebView owner;

    public WebSettings() { owner = null; }
    WebSettings(WebView owner) { this.owner = owner; }
    private void changed() { if (owner != null) owner.settingsChanged(); }
    String customUserAgent() { return mUserAgent; }
    static void updateDefaultUserAgent(String value) { if (value != null && !value.isEmpty()) defaultUserAgent = value; }
    public static String getDefaultUserAgent(android.content.Context context) {
        String value = WebView.nativeUserAgent();
        updateDefaultUserAgent(value);
        return defaultUserAgent != null ? defaultUserAgent : "Mozilla/5.0";
    }
    public void setJavaScriptEnabled(boolean flag) { mJavaScriptEnabled = flag; changed(); }
    public boolean getJavaScriptEnabled() { return mJavaScriptEnabled; }
    public void setDomStorageEnabled(boolean flag) { mDomStorageEnabled = flag; changed(); }
    public boolean getDomStorageEnabled() { return mDomStorageEnabled; }
    public void setUserAgentString(String ua) { mUserAgent = ua == null || ua.isEmpty() ? null : ua; changed(); }
    public String getUserAgentString() { return mUserAgent != null ? mUserAgent : getDefaultUserAgent(null); }
    public void setAllowFileAccess(boolean allow) { mAllowFileAccess = allow; changed(); }
    public boolean getAllowFileAccess() { return mAllowFileAccess; }
    public void setAllowContentAccess(boolean allow) {}
    public void setLoadsImagesAutomatically(boolean flag) {}
    public void setBlockNetworkImage(boolean flag) {}
    public void setBlockNetworkLoads(boolean flag) {}
    public void setDatabaseEnabled(boolean flag) {}
    public void setAppCacheEnabled(boolean flag) {}
    public void setAppCachePath(String appCachePath) {}
    public void setGeolocationEnabled(boolean flag) {}
    public void setSupportZoom(boolean support) {}
    public void setBuiltInZoomControls(boolean enabled) {}
    public void setDisplayZoomControls(boolean enabled) {}
    public void setUseWideViewPort(boolean use) {}
    public void setLoadWithOverviewMode(boolean overview) {}
    public void setMediaPlaybackRequiresUserGesture(boolean require) { mMediaGesture = require; changed(); }
    public boolean getMediaPlaybackRequiresUserGesture() { return mMediaGesture; }
    public void setMixedContentMode(int mode) {}
}
