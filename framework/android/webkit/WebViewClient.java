package android.webkit;

import android.graphics.Bitmap;

public class WebViewClient {
    public boolean shouldOverrideUrlLoading(WebView view, String url) { return false; }
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        return shouldOverrideUrlLoading(view, request.getUrl().toString());
    }
    public void onPageStarted(WebView view, String url, Bitmap favicon) {}
    public void onPageFinished(WebView view, String url) {}
    public void onLoadResource(WebView view, String url) {}
    public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {}
    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
        if (request.isForMainFrame()) onReceivedError(view, error.getErrorCode(), error.getDescription().toString(), request.getUrl().toString());
    }
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {}
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
        if (handler != null) handler.cancel();
    }
}
