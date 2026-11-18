import org.apache.http.HttpVersion;
import org.apache.http.conn.scheme.PlainSocketFactory;
import org.apache.http.conn.scheme.Scheme;
import org.apache.http.conn.scheme.SchemeRegistry;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.impl.conn.tsccm.ThreadSafeClientConnManager;
import org.apache.http.params.BasicHttpParams;
import org.apache.http.params.HttpConnectionParams;
import org.apache.http.params.HttpProtocolParams;

public final class LegacyHttpTests {
    public static int run() {
        BasicHttpParams params = new BasicHttpParams();
        HttpProtocolParams.setVersion(params, HttpVersion.HTTP_1_1);
        HttpProtocolParams.setContentCharset(params, "UTF-8");
        HttpConnectionParams.setConnectionTimeout(params, 3000);
        HttpConnectionParams.setSoTimeout(params, 3000);
        HttpConnectionParams.setSocketBufferSize(params, 8192);
        SchemeRegistry registry = new SchemeRegistry();
        registry.register(new Scheme("http", PlainSocketFactory.getSocketFactory(), 80));
        ThreadSafeClientConnManager manager = new ThreadSafeClientConnManager(params, registry);
        DefaultHttpClient client = new DefaultHttpClient(manager, params);
        if (client.getConnectionManager() != manager || HttpConnectionParams.getSoTimeout(params) != 3000)
            throw new AssertionError("Legacy HTTP client setup");
        manager.shutdown();
        System.out.println("PASS legacy HTTP client and connection manager initialize");
        System.out.flush();
        return 1;
    }
}
