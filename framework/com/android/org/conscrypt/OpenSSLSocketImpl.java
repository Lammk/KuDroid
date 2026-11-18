package com.android.org.conscrypt;

/** Provide the socket type used for platform TLS detection. */

















public abstract class OpenSSLSocketImpl extends javax.net.ssl.SSLSocket {

    protected OpenSSLSocketImpl() {
    }

    /** ALPN protocols, reflected on by HTTP clients to negotiate HTTP/2. */




    public void setAlpnProtocols(byte[] alpnProtocols) {
    }

    public byte[] getAlpnSelectedProtocol() {
        return null;
    }

    public void setUseSessionTickets(boolean useSessionTickets) {
    }

    public void setHostname(String hostname) {
    }

    public void setChannelIdEnabled(boolean enabled) {
    }

    public byte[] getNpnSelectedProtocol() {
        return null;
    }

    public void setNpnProtocols(byte[] npnProtocols) {
    }
}
