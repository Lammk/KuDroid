package android.webkit;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Canvas;
import android.net.Uri;
import android.widget.FrameLayout;
import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;

public class WebView extends FrameLayout {
    private static final Map<Long, WeakReference<WebView>> views = new HashMap<>();
    private final WebSettings settings = new WebSettings(this);
    private WebViewClient client = new WebViewClient();
    private WebChromeClient chrome = new WebChromeClient();
    private final Map<Long, ValueCallback<String>> evaluations = new HashMap<>();
    private long handle;
    private long nextRequest = 1;
    private String url;
    private String originalUrl;
    private String title = "";
    private int progress;
    private int backCount;
    private int forwardCount;
    private boolean destroyed;
    private boolean closed;
    private boolean windowVisible = true;
    private boolean aggregatedVisible = true;

    public WebView(Context context) { super(context); createHost(); }
    public WebView(Context context, android.util.AttributeSet attrs) { super(context, attrs); createHost(); }
    public WebView(Context context, android.util.AttributeSet attrs, int style) { super(context, attrs, style); createHost(); }
    public WebView(Context context, android.util.AttributeSet attrs, int style, boolean privateBrowsing) { this(context, attrs, style); }
    private void createHost() {
        String packageName = android.app.ActivityThread.getPackageName();
        handle = nativeCreate(packageName != null && !packageName.isEmpty() ? packageName : getContext().getPackageName());
        if (handle != 0) synchronized (views) { views.put(handle, new WeakReference<WebView>(this)); }
        settingsChanged();
    }
    static native long nativeCreate(String packageName);
    static native void nativeCommand(long handle, int command, long request, String text, String detail,
                                     double a, double b, double c, double d);
    static native String nativeCookies(long handle, String url);
    static native String nativeUserAgent();
    private void command(int kind, long request, String text, String detail, double a, double b, double c, double d) {
        if (destroyed) throw new IllegalStateException("WebView is destroyed");
        nativeCommand(handle, kind, request, text, detail, a, b, c, d);
    }
    void settingsChanged() {
        if (destroyed || handle == 0) return;
        nativeCommand(handle, 3, 0, settings.customUserAgent(), null,
            settings.getJavaScriptEnabled() ? 1 : 0, settings.getDomStorageEnabled() ? 1 : 0,
            settings.getMediaPlaybackRequiresUserGesture() ? 1 : 0, settings.getAllowFileAccess() ? 1 : 0);
    }
    public void loadUrl(String value) { loadUrl(value, null); }
    public void loadUrl(String value, Map<String,String> headers) {
        if (value == null) throw new NullPointerException("url");
        if (value.regionMatches(true, 0, "javascript:", 0, 11)) { evaluateJavascript(value.substring(11), null); return; }
        closed = false; originalUrl = value;
        JSONObject metadata = new JSONObject();
        if (headers != null) for (Map.Entry<String,String> entry : headers.entrySet()) {
            try { metadata.put(entry.getKey(), entry.getValue()); } catch (org.json.JSONException invalid) { throw new IllegalArgumentException(invalid); }
        }
        command(1, 0, value, metadata.toString(), 0, 0, 0, 0);
        updateFrame();
        if (handle == 0) client.onReceivedError(this, -10, "Web content host is unavailable", value);
    }
    public void loadData(String data, String mimeType, String encoding) {
        if ("base64".equalsIgnoreCase(encoding)) {
            data = new String(android.util.Base64.decode(data, android.util.Base64.DEFAULT), java.nio.charset.StandardCharsets.UTF_8);
        }
        loadDataWithBaseURL(null, data, mimeType, "UTF-8", null);
    }
    public void loadDataWithBaseURL(String baseUrl, String data, String mimeType, String encoding, String historyUrl) {
        if (data == null) throw new NullPointerException("data");
        closed = false; originalUrl = baseUrl;
        command(2, 0, data, baseUrl, 0, 0, 0, 0); updateFrame();
    }
    public String getUrl() { return url; }
    public String getOriginalUrl() { return originalUrl; }
    public String getTitle() { return title; }
    public int getProgress() { return progress; }
    public WebSettings getSettings() { return settings; }
    public void setWebViewClient(WebViewClient value) { client = value != null ? value : new WebViewClient(); }
    public WebViewClient getWebViewClient() { return client; }
    public void setWebChromeClient(WebChromeClient value) { chrome = value != null ? value : new WebChromeClient(); }
    public WebChromeClient getWebChromeClient() { return chrome; }
    public void addJavascriptInterface(Object object, String name) { android.util.Log.w("WebView", "Java object script interfaces are unavailable"); }
    public void removeJavascriptInterface(String name) {}
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
        if (script == null) throw new NullPointerException("script");
        long request = nextRequest++;
        if (callback != null) evaluations.put(request, callback);
        command(11, request, script, null, 0, 0, 0, 0);
        if (handle == 0 && callback != null) { evaluations.remove(request); callback.onReceiveValue("null"); }
    }
    public void reload() { closed = false; command(8, 0, null, null, 0, 0, 0, 0); updateFrame(); }
    public boolean canGoBack() { return backCount > 0; }
    public boolean canGoForward() { return forwardCount > 0; }
    public boolean canGoBackOrForward(int steps) { return steps >= -backCount && steps <= forwardCount; }
    public void goBack() { goBackOrForward(-1); }
    public void goForward() { goBackOrForward(1); }
    public void goBackOrForward(int steps) {
        if (!canGoBackOrForward(steps) || steps == 0) return;
        command(steps < 0 ? 6 : 7, 0, null, null, steps, 0, 0, 0);
    }
    public void stopLoading() { command(9, 0, null, null, 0, 0, 0, 0); }
    public void destroy() {
        if (destroyed) return;
        nativeCommand(handle, 10, 0, null, null, 0, 0, 0, 0);
        synchronized (views) { views.remove(handle); }
        evaluations.clear(); destroyed = true; handle = 0;
    }
    private void updateFrame() {
        if (destroyed || handle == 0) return;
        boolean visible = !closed && windowVisible && aggregatedVisible && isAttachedToWindow() && isShown();
        nativeCommand(handle, 5, 0, null, null, visible ? 1 : 0, 0, 0, 0);
        if (!visible || getWidth() <= 0 || getHeight() <= 0) return;
        int[] location = new int[2]; getLocationOnScreen(location);
        android.view.View root = getRootView();
        nativeCommand(handle, 4, 0, root.getWidth() + "," + root.getHeight(), null,
            location[0], location[1], getWidth(), getHeight());
    }
    @Override public void draw(Canvas canvas) { super.draw(canvas); updateFrame(); }
    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom); updateFrame();
    }
    @Override protected void onAttachedToWindow() { super.onAttachedToWindow(); updateFrame(); }
    @Override protected void onDetachedFromWindow() {
        nativeCommand(handle, 5, 0, null, null, 0, 0, 0, 0); super.onDetachedFromWindow();
    }
    @Override public void onVisibilityAggregated(boolean visible) { super.onVisibilityAggregated(visible); aggregatedVisible = visible; updateFrame(); }
    @Override protected void onWindowVisibilityChanged(int visibility) {
        super.onWindowVisibilityChanged(visibility); windowVisible = visibility == VISIBLE; updateFrame();
    }
    private void closeFromHost() {
        closed = true; stopLoading(); updateFrame();
        Context context = getContext();
        while (context instanceof ContextWrapper && !(context instanceof Activity)) {
            Context next = ((ContextWrapper) context).getBaseContext();
            if (next == null || next == context) break;
            context = next;
        }
        if (context instanceof Activity) ((Activity) context).finish();
    }
    public static void dispatchNativeEvent(long handle, int event, long request, String text, String detail, int flags) {
        WeakReference<WebView> reference;
        synchronized (views) { reference = views.get(handle); }
        WebView view = reference != null ? reference.get() : null;
        if (view == null || view.destroyed) {
            if (event == 1) nativeCommand(handle, 12, request, null, null, 0, 0, 0, 0);
            CookieManager.dispatchNativeEvent(handle, event, request, flags);
            return;
        }
        switch (event) {
            case 1: {
                boolean handled = true;
                try { handled = view.client.shouldOverrideUrlLoading(view, new NativeRequest(text, detail, flags)); }
                finally { nativeCommand(handle, 12, request, null, null, handled ? 0 : 1, 0, 0, 0); }
                break;
            }
            case 2: view.url = text; view.client.onPageStarted(view, text, null); break;
            case 3: view.url = text; view.client.onPageFinished(view, text); break;
            case 4: view.client.onReceivedError(view, new NativeRequest(text, "{}", 1), new NativeError(flags, detail)); break;
            case 5:
                try { JSONObject history = new JSONObject(detail); view.backCount = history.optInt("back", 0); view.forwardCount = history.optInt("forward", 0); }
                catch (org.json.JSONException ignored) { view.backCount = view.forwardCount = 0; }
                if (text != null && !text.isEmpty()) view.url = text;
                break;
            case 6: view.title = text; view.chrome.onReceivedTitle(view, text); break;
            case 7: view.client.onReceivedHttpError(view, new NativeRequest(text, "{}", (flags & 65536) != 0 ? 1 : 0),
                nativeResponse(flags & 65535, detail)); break;
            case 8: view.progress = flags; view.chrome.onProgressChanged(view, flags); break;
            case 9: view.closeFromHost(); break;
            case 10: {
                ValueCallback<String> callback = view.evaluations.remove(request);
                if (callback != null) callback.onReceiveValue(text); break;
            }
            case 12: WebSettings.updateDefaultUserAgent(text); break;
            case 13: view.chrome.onConsoleMessage(new ConsoleMessage(text, detail, flags, ConsoleMessage.MessageLevel.LOG)); break;
            default: break;
        }
    }
    private static final class NativeError extends WebResourceError {
        private final int code; private final String description;
        NativeError(int code, String description) { this.code = code; this.description = description; }
        public int getErrorCode() { return code; }
        public CharSequence getDescription() { return description; }
    }
    private static WebResourceResponse nativeResponse(int status, String detail) {
        Map<String,String> headers = new HashMap<>();
        String mime = null, encoding = null;
        try {
            JSONObject data = new JSONObject(detail);
            mime = data.optString("mime", null); encoding = data.optString("encoding", null);
            JSONObject values = data.optJSONObject("headers");
            if (values != null) {
                java.util.Iterator<String> keys = values.keys();
                while (keys.hasNext()) { String key = keys.next(); headers.put(key, values.optString(key)); }
            }
        } catch (org.json.JSONException ignored) { }
        return new WebResourceResponse(mime, encoding, status, "HTTP error", headers, null);
    }
    private static final class NativeRequest implements WebResourceRequest {
        private final Uri uri;
        private final Map<String,String> headers = new HashMap<>();
        private String method = "GET";
        private final int flags;
        NativeRequest(String value, String detail, int flags) {
            uri = Uri.parse(value != null ? value : ""); this.flags = flags;
            try {
                JSONObject data = new JSONObject(detail);
                method = data.optString("method", "GET");
                JSONObject values = data.optJSONObject("headers");
                if (values != null) {
                    java.util.Iterator<String> keys = values.keys();
                    while (keys.hasNext()) { String key = keys.next(); headers.put(key, values.optString(key)); }
                }
            } catch (org.json.JSONException ignored) { }
        }
        public Uri getUrl() { return uri; }
        public String getMethod() { return method; }
        public Map<String,String> getRequestHeaders() { return java.util.Collections.unmodifiableMap(headers); }
        public boolean isForMainFrame() { return (flags & 1) != 0; }
        public boolean hasGesture() { return (flags & 2) != 0; }
        public boolean isRedirect() { return (flags & 4) != 0; }
    }
}
