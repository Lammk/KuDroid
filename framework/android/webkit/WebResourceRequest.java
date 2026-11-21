package android.webkit;

import java.util.Map;

public interface WebResourceRequest {
    android.net.Uri getUrl();
    String getMethod();
    Map<String, String> getRequestHeaders();
    boolean isForMainFrame();
    boolean isRedirect();
    boolean hasGesture();
}
