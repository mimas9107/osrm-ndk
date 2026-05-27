package com.osrm.android;

import android.content.res.AssetManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

public class MonitorServer {
    private static final String TAG = "MonitorServer";

    private final int port;
    private final OsrmService service;
    private final AssetManager assets;
    private ServerSocket serverSocket;
    private volatile boolean running = false;

    public MonitorServer(int port, OsrmService service, AssetManager assets) {
        this.port = port;
        this.service = service;
        this.assets = assets;
    }

    public void start() throws Exception {
        serverSocket = new ServerSocket(port, 10, InetAddress.getByName("127.0.0.1"));
        running = true;
        Thread t = new Thread(this::acceptLoop);
        t.setDaemon(true);
        t.setName("monitor-server");
        t.start();
        Log.i(TAG, "listening on 127.0.0.1:" + port);
    }

    public void stop() {
        running = false;
        try { serverSocket.close(); } catch (Exception ignored) {}
    }

    public boolean isRunning() { return running; }

    private void acceptLoop() {
        while (running) {
            try {
                Socket client = serverSocket.accept();
                handle(client);
            } catch (SocketException e) {
                if (!running) break;
                Log.e(TAG, "socket error", e);
            } catch (Exception e) {
                Log.e(TAG, "accept error", e);
            }
        }
    }

    private void handle(Socket client) {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(client.getInputStream()));
             OutputStream out = client.getOutputStream()) {

            String line = r.readLine();
            if (line == null) return;
            String[] parts = line.split(" ", 3);
            if (parts.length < 2) return;
            String method = parts[0];
            String rawPath = parts[1];
            String path = rawPath.contains("?") ? rawPath.substring(0, rawPath.indexOf("?")) : rawPath;

            if ("GET".equals(method)) {
                if ("/".equals(path) || "/dashboard.html".equals(path)) {
                    serveAsset(out, path, "www/dashboard.html", "text/html; charset=utf-8");
                    return;
                } else if ("/dashboard.css".equals(path)) {
                    serveAsset(out, path, "www/dashboard.css", "text/css; charset=utf-8");
                    return;
                } else if ("/dashboard.js".equals(path)) {
                    serveAsset(out, path, "www/dashboard.js", "application/javascript; charset=utf-8");
                    return;
                }
            }

            int cl = 0;
            while ((line = r.readLine()) != null && !line.isEmpty()) {
                if (line.toLowerCase().startsWith("content-length:"))
                    cl = Integer.parseInt(line.substring(15).trim());
            }

            String body = "";
            if (cl > 0) {
                char[] buf = new char[cl];
                r.read(buf, 0, cl);
                body = new String(buf);
            }

            String json;
            int code;

            if ("GET".equals(method)) {
                if ("/status".equals(path)) {
                    json = service.getStatusJson();
                    code = 200;
                } else if ("/config".equals(path)) {
                    json = service.getConfigJson();
                    code = 200;
                } else if ("/logs".equals(path)) {
                    int n = 50;
                    int idx = rawPath.indexOf("?n=");
                    if (idx >= 0) { try { n = Integer.parseInt(rawPath.substring(idx + 3)); } catch (Exception ignored) {} }
                    json = service.getLogsJson(n);
                    code = 200;
                } else if ("/ping".equals(path)) {
                    json = "{\"pong\":true}";
                    code = 200;
                } else {
                    json = "{\"error\":\"not found\"}";
                    code = 404;
                }
            } else if ("POST".equals(method)) {
                if ("/start".equals(path)) {
                    boolean ok = service.startEngine();
                    json = "{\"ok\":" + ok + "}";
                    code = ok ? 200 : 409;
                } else if ("/stop".equals(path)) {
                    service.stopEngine();
                    json = "{\"ok\":true}";
                    code = 200;
                } else if ("/restart".equals(path)) {
                    service.restartEngine();
                    json = "{\"ok\":true}";
                    code = 200;
                } else if ("/config".equals(path)) {
                    boolean ok = service.updateConfig(body);
                    json = "{\"ok\":" + ok + "}";
                    code = ok ? 200 : 400;
                } else {
                    json = "{\"error\":\"not found\"}";
                    code = 404;
                }
            } else {
                json = "{\"error\":\"method not allowed\"}";
                code = 405;
            }

            byte[] data = json.getBytes(StandardCharsets.UTF_8);
            String header = "HTTP/1.1 " + code + " " + reason(code) + "\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Content-Length: " + data.length + "\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Connection: close\r\n\r\n";
            out.write(header.getBytes(StandardCharsets.UTF_8));
            out.write(data);
            out.flush();

        } catch (Exception e) {
            Log.e(TAG, "handle error", e);
        }
    }

    private void serveAsset(OutputStream out, String requestPath, String assetPath, String mime) {
        try {
            InputStream in = assets.open(assetPath);
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            byte[] tmp = new byte[8192];
            int n;
            while ((n = in.read(tmp)) >= 0) buf.write(tmp, 0, n);
            in.close();
            byte[] data = buf.toByteArray();

            String header = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: " + mime + "\r\n"
                + "Content-Length: " + data.length + "\r\n"
                + "Connection: close\r\n\r\n";
            out.write(header.getBytes(StandardCharsets.UTF_8));
            out.write(data);
            out.flush();
        } catch (Exception e) {
            Log.e(TAG, "failed to serve " + assetPath, e);
            try {
                String err = "{\"error\":\"file not found\"}";
                byte[] errData = err.getBytes(StandardCharsets.UTF_8);
                String header = "HTTP/1.1 404 Not Found\r\n"
                    + "Content-Type: application/json; charset=utf-8\r\n"
                    + "Content-Length: " + errData.length + "\r\n"
                    + "Connection: close\r\n\r\n";
                out.write(header.getBytes(StandardCharsets.UTF_8));
                out.write(errData);
                out.flush();
            } catch (Exception ignored) {}
        }
    }

    private static String reason(int c) {
        switch (c) {
            case 200: return "OK";
            case 400: return "Bad Request";
            case 404: return "Not Found";
            case 405: return "Method Not Allowed";
            case 409: return "Conflict";
            default: return "";
        }
    }
}
