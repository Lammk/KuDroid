package android.webkit;

import java.util.HashMap;
import java.util.Map;

public abstract class CookieManager {
    private static PlatformCookies instance;
    protected CookieManager() {}
    public static synchronized CookieManager getInstance() {
        if (instance == null) instance = new PlatformCookies();
        return instance;
    }
    static void dispatchNativeEvent(long handle, int event, long request, int flags) {
        if (instance == null || handle != instance.handle || event != 11) return;
        ValueCallback<Boolean> callback = instance.callbacks.remove(request);
        if (callback != null) callback.onReceiveValue(flags != 0);
    }
    public abstract void setAcceptCookie(boolean accept);
    public abstract boolean acceptCookie();
    public abstract void setAcceptThirdPartyCookies(WebView view, boolean accept);
    public abstract boolean acceptThirdPartyCookies(WebView view);
    public abstract void setCookie(String url, String value);
    public abstract void setCookie(String url, String value, ValueCallback<Boolean> callback);
    public abstract String getCookie(String url);
    public abstract void removeAllCookies(ValueCallback<Boolean> callback);
    public abstract void flush();
    public boolean hasCookies() { return false; }
    public void removeSessionCookies(ValueCallback<Boolean> callback) { if (callback != null) callback.onReceiveValue(false); }
    public void removeAllCookie() { removeAllCookies(null); }
    public void removeSessionCookie() { removeSessionCookies(null); }
    private static final class PlatformCookies extends CookieManager {
        final long handle = WebView.nativeCreate(android.app.ActivityThread.getPackageName());
        final Map<Long, ValueCallback<Boolean>> callbacks = new HashMap<>();
        private final Map<WebView, Boolean> thirdParty = new java.util.WeakHashMap<>();
        private long nextRequest = 1;
        private boolean accept = true;
        public void setAcceptCookie(boolean value) {
            accept = value; WebView.nativeCommand(handle, 16, 0, null, null, value ? 1 : 0, 0, 0, 0);
        }
        public boolean acceptCookie() { return accept; }
        public void setAcceptThirdPartyCookies(WebView view, boolean value) { thirdParty.put(view, value); }
        public boolean acceptThirdPartyCookies(WebView view) { Boolean value = thirdParty.get(view); return value != null && value; }
        private long register(ValueCallback<Boolean> callback) {
            long request = nextRequest++;
            if (callback != null) callbacks.put(request, callback);
            if (handle == 0 && callback != null) { callbacks.remove(request); callback.onReceiveValue(false); }
            return request;
        }
        public void setCookie(String url, String value) { setCookie(url, value, null); }
        public void setCookie(String url, String value, ValueCallback<Boolean> callback) {
            WebView.nativeCommand(handle, 13, register(callback), url, value, 0, 0, 0, 0);
        }
        public String getCookie(String url) { return accept ? WebView.nativeCookies(handle, url) : null; }
        public boolean hasCookies() { String value = WebView.nativeCookies(handle, null); return value != null && !value.isEmpty(); }
        public void removeAllCookies(ValueCallback<Boolean> callback) {
            WebView.nativeCommand(handle, 14, register(callback), null, null, 0, 0, 0, 0);
        }
        public void removeSessionCookies(ValueCallback<Boolean> callback) {
            WebView.nativeCommand(handle, 14, register(callback), null, null, 1, 0, 0, 0);
        }
        public void flush() { WebView.nativeCommand(handle, 15, 0, null, null, 0, 0, 0, 0); }
    }
}
