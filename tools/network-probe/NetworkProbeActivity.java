package org.kudroid.networkprobe;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;

public final class NetworkProbeActivity extends Activity {
    private TextView output;
    private final StringBuilder results = new StringBuilder("Network probe\n\n");
    private int passes;
    private int failures;
    private String lanHost;
    private String lanToken;
    private String broadcastAddress;
    private int lanTcpPort;
    private int lanUdpPort;

    public static int run() {
        NetworkProbeActivity probe = new NetworkProbeActivity();
        probe.runTests();
        if (probe.failures != 0) throw new AssertionError("Connectivity failures: " + probe.failures);
        return probe.passes;
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        output = new TextView(this);
        output.setBackgroundColor(0xFFFFFFFF);
        output.setTextColor(0xFF111111);
        output.setTextSize(18);
        output.setPadding(24, 32, 24, 24);
        output.setText(results.toString());
        setContentView(output);
        try {
            BufferedReader config = new BufferedReader(new InputStreamReader(
                    getAssets().open("lan-target.txt"), "UTF-8"));
            try {
                lanHost = config.readLine();
                lanTcpPort = Integer.parseInt(config.readLine());
                lanUdpPort = Integer.parseInt(config.readLine());
                lanToken = config.readLine();
                broadcastAddress = config.readLine();
            } finally { config.close(); }
        } catch (java.io.FileNotFoundException absent) {
            lanHost = null;
        } catch (Exception error) {
            report("FAIL LAN configuration: " + error.toString());
            return;
        }
        new Thread(new Runnable() {
            @Override public void run() { runTests(); }
        }, "Network probe").start();
    }

    private void report(final String message) {
        Log.i("NetworkProbe", message);
        if (message.startsWith("PASS ")) ++passes;
        if (message.startsWith("FAIL ")) ++failures;
        if (output == null) return;
        runOnUiThread(new Runnable() {
            @Override public void run() {
                results.append(message).append('\n');
                output.setText(results.toString());
            }
        });
    }

    private void runTests() {
        report("BEGIN");
        if (lanHost != null) {
            runLanTests();
            report("DONE");
            return;
        }
        try {
            InetAddress[] addresses = InetAddress.getAllByName("example.com");
            if (addresses.length == 0) throw new java.io.IOException("No DNS addresses");
            report("PASS DNS: " + addresses.length + " addresses");
        } catch (Exception error) {
            report("FAIL DNS: " + error.toString());
        }
        try {
            Socket socket = new Socket();
            try {
                socket.connect(new InetSocketAddress("example.com", 80), 5000);
                report("PASS TCP: connected to port 80");
            } finally { socket.close(); }
        } catch (Exception error) {
            report("FAIL TCP: " + error.toString());
        }
        exchange("HTTP", "http://example.com/");
        exchange("HTTPS", "https://example.com/");
        report("DONE");
    }

    private void runLanTests() {
        report("LAN target: " + lanHost);
        try {
            Socket socket = new Socket();
            try {
                socket.connect(new InetSocketAddress(lanHost, lanTcpPort), 5000);
                report("PASS LAN TCP: " + lanHost + ":" + lanTcpPort);
            } finally { socket.close(); }
        } catch (Exception error) {
            report("FAIL LAN TCP: " + error.toString());
        }
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL("http://" + lanHost + ":" + lanTcpPort + "/probe").openConnection();
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(5000);
            connection.setRequestProperty("Connection", "close");
            if (connection.getResponseCode() != 200) throw new java.io.IOException("Unexpected HTTP status");
            BufferedReader body = new BufferedReader(new InputStreamReader(connection.getInputStream(), "UTF-8"));
            String received;
            try { received = body.readLine(); } finally { body.close(); }
            if (!lanToken.equals(received)) throw new java.io.IOException("Local response token differs");
            report("PASS LAN HTTP: verified local server response");
        } catch (Exception error) {
            report("FAIL LAN HTTP: " + error.toString());
        } finally {
            if (connection != null) connection.disconnect();
        }
        udpExchange(lanHost, false);
        if (broadcastAddress != null && !broadcastAddress.isEmpty()) udpExchange(broadcastAddress, true);
    }

    private void udpExchange(String destination, boolean broadcast) {
        String name = broadcast ? "LAN UDP broadcast" : "LAN UDP unicast";
        DatagramSocket socket = null;
        try {
            socket = new DatagramSocket();
            socket.setSoTimeout(5000);
            socket.setBroadcast(broadcast);
            String message = (broadcast ? "broadcast " : "unicast ") + lanToken;
            byte[] sent = message.getBytes("UTF-8");
            socket.send(new DatagramPacket(sent, sent.length, InetAddress.getByName(destination), lanUdpPort));
            byte[] data = new byte[256];
            DatagramPacket response = new DatagramPacket(data, data.length);
            socket.receive(response);
            String received = new String(data, response.getOffset(), response.getLength(),
                    java.nio.charset.StandardCharsets.UTF_8);
            if (!message.equals(received) || response.getPort() != lanUdpPort
                    || !InetAddress.getByName(lanHost).equals(response.getAddress()))
                throw new java.io.IOException("Local UDP echo or peer differs");
            report("PASS " + name + ": verified echo from " + response.getAddress().getHostAddress());
        } catch (Exception error) {
            report("FAIL " + name + ": " + error.toString());
        } finally {
            if (socket != null) socket.close();
        }
    }

    private void exchange(String name, String address) {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(5000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Connection", "close");
            int status = connection.getResponseCode();
            if (status < 100) throw new java.io.IOException("No HTTP response");
            InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            int bytes = 0;
            if (stream != null) {
                try {
                    byte[] buffer = new byte[512];
                    int count = stream.read(buffer);
                    if (count > 0) bytes = count;
                } finally { stream.close(); }
            }
            report("PASS " + name + ": status " + status + ", body " + bytes + " bytes");
        } catch (Exception error) {
            report("FAIL " + name + ": " + error.toString());
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
