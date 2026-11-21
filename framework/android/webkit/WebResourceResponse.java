package android.webkit;

import java.io.InputStream;
import java.util.Map;

public class WebResourceResponse {
    private String mMimeType;
    private String mEncoding;
    private int mStatusCode = 200;
    private String mReasonPhrase = "OK";
    private InputStream mData;
    private Map<String,String> mHeaders;

    public WebResourceResponse(String mimeType, String encoding, InputStream data) {
        mMimeType = mimeType;
        mEncoding = encoding;
        mData = data;
    }
    public String getMimeType() { return mMimeType; }
    public WebResourceResponse(String mimeType, String encoding, int statusCode, String reasonPhrase,
                               Map<String,String> headers, InputStream data) {
        this(mimeType, encoding, data); mStatusCode = statusCode; mReasonPhrase = reasonPhrase; mHeaders = headers;
    }
    public Map<String,String> getResponseHeaders() { return mHeaders; }
    public void setResponseHeaders(Map<String,String> headers) { mHeaders = headers; }
    public void setMimeType(String value) { mMimeType = value; }
    public void setEncoding(String value) { mEncoding = value; }
    public void setData(InputStream value) { mData = value; }
    public String getEncoding() { return mEncoding; }
    public int getStatusCode() { return mStatusCode; }
    public String getReasonPhrase() { return mReasonPhrase; }
    public InputStream getData() { return mData; }
}
