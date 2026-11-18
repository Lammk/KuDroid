package android.net.http;

import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.SSLSession;
import javax.net.ssl.X509TrustManager;

/** Android's extension over {@link X509TrustManager}, used for certificate pinning. */

















public class X509TrustManagerExtensions {

    private final X509TrustManager mDelegate;

    /**
     * @throws IllegalArgumentException if {@code tm} is null, matching Android — the
     *     constructor there requires a manager that implements the internal
     *     TrustManagerImpl and rejects anything else, and a caller that passes null
     *     has a bug worth reporting at the point it happens rather than on first use.
     */
    public X509TrustManagerExtensions(X509TrustManager tm) throws IllegalArgumentException {
        if (tm == null) {
            throw new IllegalArgumentException("tm is null");
        }
        mDelegate = tm;
    }

    /** Verify the chain and return it, ordered leaf-first. */








    public List<X509Certificate> checkServerTrusted(X509Certificate[] chain, String authType,
            String host) throws CertificateException {
        if (chain == null || chain.length == 0) {
            throw new CertificateException("chain is empty");
        }
        mDelegate.checkServerTrusted(chain, authType);
        List<X509Certificate> result = new ArrayList<X509Certificate>();
        for (int i = 0; i < chain.length; i++) {
            if (chain[i] != null) result.add(chain[i]);
        }
        return result;
    }

    /** Whether the chain was issued by a user-installed CA. */






    public boolean isUserAddedCertificate(X509Certificate cert) {
        return false;
    }

    /** Whether this platform supports certificate transparency verification. */
    public boolean isCTVerificationRequired(String hostname) {
        return false;
    }

    public void setCTEnabledOverride(boolean enabled) {
    }

    /**
     * Sockets carrying an SSLSession get the same treatment as the array form; the
     * session is not consulted for the same reason `host` is not.
     */
    public List<X509Certificate> checkServerTrusted(X509Certificate[] chain, String authType,
            SSLSession session) throws CertificateException {
        return checkServerTrusted(chain, authType, (String) null);
    }
}
