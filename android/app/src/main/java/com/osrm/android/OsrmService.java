package com.osrm.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.LinkedList;
import java.util.Locale;

public class OsrmService extends Service {
    private static final String TAG = "OsrmService";
    private static final String CHANNEL_ID = "osrm_engine";
    private static final int NOTIFY_ID = 1001;
    private static final String PREFS_NAME = "osrm_config";
    private static final int MAX_LOG_LINES = 2000;

    private SharedPreferences prefs;
    private String configIp = "127.0.0.1";
    private int configPort = 5747;
    private int configMonitorPort = 5001;
    private String configDataDir;
    private boolean configAutoStart = true;
    private boolean configAutoRestart = true;
    private boolean configUseNative = false;

    private String binaryPath;
    private Process engineProcess;
    private volatile long engineStartTime = 0;
    private volatile int enginePid = -1;
    private volatile String engineStatus = "stopped";
    private volatile int restartCount = 0;
    private volatile long lastMemoryKb = 0;
    private volatile boolean engineStopRequested = false;

    private final LinkedList<String> logBuffer = new LinkedList<>();
    private final Object logLock = new Object();

    private MonitorServer monitorServer;
    private Thread engineReaderThread;
    private Thread healthThread;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        loadConfig();

        if (!configUseNative) {
            // Locate binary: native lib dir → assets extraction → deploy-managed
            String libDir = getApplicationInfo().nativeLibraryDir;
            String nativeBin = libDir + "/libosrm_routed.so";
            File nativeFile = new File(nativeBin);
            if (nativeFile.exists()) {
                binaryPath = nativeBin;
            } else {
                File dataBin = new File(getFilesDir().getParentFile(), "osrm-routed");
                if (!dataBin.exists()) extractBinary(dataBin);
                binaryPath = dataBin.getAbsolutePath();
            }
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification n = buildNotification("OSRM 引擎初始化中...");
        startForeground(NOTIFY_ID, n);
        if (monitorServer == null || !monitorServer.isRunning()) startMonitorServer();
        if (configAutoStart) startEngine();
        else updateNotification("OSRM 引擎待命中");
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopEngine();
        if (monitorServer != null) { monitorServer.stop(); monitorServer = null; }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ─── Config ──────────────────────────────────────────────────────

    private void loadConfig() {
        configIp = prefs.getString("bind_ip", "127.0.0.1");
        configPort = prefs.getInt("bind_port", 5747);
        configMonitorPort = prefs.getInt("monitor_port", 5001);
        configDataDir = prefs.getString("data_dir", null);
        configAutoStart = prefs.getBoolean("auto_start", true);
        configAutoRestart = prefs.getBoolean("auto_restart", true);
        configUseNative = prefs.getBoolean("use_native", false);
        if (configDataDir == null || configDataDir.isEmpty()) {
            File ext = getExternalFilesDir(null);
            configDataDir = (ext != null ? ext : getFilesDir()) + "/osrm_data/";
        }
    }

    public boolean updateConfig(String json) {
        try {
            String ip = extractJsonString(json, "ip");
            if (ip != null) configIp = ip;
            String ps = extractJsonString(json, "port");
            if (ps != null) configPort = Integer.parseInt(ps);
            String dd = extractJsonString(json, "data_dir");
            if (dd != null) configDataDir = dd;
            String ar = extractJsonString(json, "auto_restart");
            if (ar != null) configAutoRestart = "true".equals(ar);
            String as = extractJsonString(json, "auto_start");
            if (as != null) configAutoStart = "true".equals(as);
            String un = extractJsonString(json, "use_native");
            if (un != null) configUseNative = "true".equals(un);

            prefs.edit()
                .putString("bind_ip", configIp)
                .putInt("bind_port", configPort)
                .putInt("monitor_port", configMonitorPort)
                .putString("data_dir", configDataDir)
                .putBoolean("auto_start", configAutoStart)
                .putBoolean("auto_restart", configAutoRestart)
                .putBoolean("use_native", configUseNative)
                .apply();

            boolean runningNow = "running".equals(engineStatus) || "healthy".equals(engineStatus);
            if (runningNow) restartEngine();
            else if (configAutoStart) startEngine();
            return true;
        } catch (Exception e) {
            Log.e(TAG, "updateConfig error", e);
            return false;
        }
    }

    public String getConfigJson() {
        return "{\"ip\":\"" + escape(configIp) + "\",\"port\":" + configPort
            + ",\"data_dir\":\"" + escape(configDataDir) + "\""
            + ",\"auto_restart\":" + configAutoRestart
            + ",\"auto_start\":" + configAutoStart
            + ",\"use_native\":" + configUseNative
            + ",\"monitor_port\":" + configMonitorPort + "}";
    }

    // ─── Engine lifecycle (ProcessBuilder) ───────────────────────────

    public boolean startEngine() {
        if ("running".equals(engineStatus) || "healthy".equals(engineStatus)) return false;
        new Thread(this::startEngineSync).start();
        return true;
    }

    private void startEngineSync() {
        synchronized (this) {
            if (!configUseNative && engineProcess != null && engineProcess.isAlive()) {
                engineStatus = "running";
                return;
            }
            if (configUseNative && OsrmNative.isRunning()) {
                engineStatus = "running";
                return;
            }
            engineStopRequested = false;

            File dataDir = new File(configDataDir);
            if (!dataDir.isDirectory()) {
                addLog("ERROR", "Data directory not found: " + configDataDir);
                updateNotification("錯誤: 找不到圖資目錄");
                engineStatus = "stopped";
                return;
            }

            File props = findOsrmProperties(dataDir);
            if (props == null) {
                addLog("ERROR", "No .osrm.properties in " + configDataDir);
                updateNotification("錯誤: 圖資不完整");
                engineStatus = "stopped";
                return;
            }

            String osrmBase = props.getAbsolutePath();
            osrmBase = osrmBase.substring(0, osrmBase.lastIndexOf(".osrm.properties"));

            if (configUseNative) {
                try {
                    addLog("INFO", "Starting native engine: " + osrmBase + " @ :" + configPort);
                    boolean ok = OsrmNative.start(osrmBase, configPort);
                    if (!ok) {
                        addLog("ERROR", "Native engine start returned false");
                        engineStatus = "stopped";
                        updateNotification("啟動失敗");
                        return;
                    }
                    engineStartTime = System.currentTimeMillis();
                    enginePid = -2; // -2 = in-process native engine
                    engineStatus = "running";
                    addLog("INFO", "Native engine started @ :" + configPort);
                    updateNotification("OSRM 運行中 (port " + configPort + ")");

                    healthThread = new Thread(this::monitorNativeHealth);
                    healthThread.setDaemon(true);
                    healthThread.setName("native-health");
                    healthThread.start();

                } catch (Exception e) {
                    addLog("ERROR", "Native engine start failed: " + e.getMessage());
                    engineStatus = "stopped";
                    updateNotification("啟動失敗");
                }
                return;
            }

            try {
                ProcessBuilder pb = new ProcessBuilder(
                    binaryPath,
                    "--algorithm", "mld",
                    "--ip", configIp,
                    "--port", String.valueOf(configPort),
                    osrmBase
                );
                pb.directory(dataDir);
                pb.redirectErrorStream(true);

                addLog("INFO", "Starting: " + binaryPath + " --ip " + configIp
                    + " --port " + configPort + " " + osrmBase);

                engineProcess = pb.start();
                engineStartTime = System.currentTimeMillis();
                enginePid = getPid(engineProcess);
                engineStatus = "running";
                addLog("INFO", "Engine started, PID=" + enginePid + " @ :" + configPort);
                updateNotification("OSRM 運行中 (port " + configPort + ")");

                engineReaderThread = new Thread(this::readEngineOutput);
                engineReaderThread.setDaemon(true);
                engineReaderThread.setName("engine-reader");
                engineReaderThread.start();

                healthThread = new Thread(this::monitorProcessHealth);
                healthThread.setDaemon(true);
                healthThread.setName("engine-health");
                healthThread.start();

            } catch (Exception e) {
                addLog("ERROR", "Engine start failed: " + e.getMessage());
                engineStatus = "stopped";
                updateNotification("啟動失敗");
            }
        }
    }

    public void stopEngine() {
        synchronized (this) {
            engineStopRequested = true;
            if (configUseNative) {
                addLog("INFO", "Stopping native engine");
                OsrmNative.stop();
                enginePid = -1;
                engineStartTime = 0;
                engineStatus = "stopped";
                addLog("INFO", "Native engine stopped");
                updateNotification("OSRM 引擎已停止");
            } else if (engineProcess != null) {
                addLog("INFO", "Stopping engine PID=" + enginePid);
                engineProcess.destroy();
                try { engineProcess.waitFor(5000, java.util.concurrent.TimeUnit.MILLISECONDS); } catch (Exception ignored) {}
                if (engineProcess.isAlive()) engineProcess.destroyForcibly();
                engineProcess = null;
                enginePid = -1;
                engineStartTime = 0;
                engineStatus = "stopped";
                addLog("INFO", "Engine stopped");
                updateNotification("OSRM 引擎已停止");
            }
        }
    }

    public void restartEngine() {
        new Thread(() -> { stopEngine(); try { Thread.sleep(500); } catch (Exception ignored) {} startEngine(); }).start();
    }

    // ─── Monitor server ──────────────────────────────────────────────

    private void startMonitorServer() {
        try {
            monitorServer = new MonitorServer(configMonitorPort, this, getAssets());
            monitorServer.start();
            addLog("INFO", "Monitor API @ 127.0.0.1:" + configMonitorPort);
        } catch (Exception e) {
            Log.e(TAG, "MonitorServer start failed", e);
            addLog("WARN", "Monitor server failed: " + e.getMessage());
        }
    }

    // ─── Logging ─────────────────────────────────────────────────────

    private void addLog(String level, String msg) {
        String ts = new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date());
        String line = ts + " [" + level + "] " + msg;
        if ("ERROR".equals(level)) Log.e(TAG, msg);
        else if ("WARN".equals(level)) Log.w(TAG, msg);
        else Log.i(TAG, msg);
        synchronized (logLock) {
            logBuffer.addLast(line);
            if (logBuffer.size() > MAX_LOG_LINES) logBuffer.removeFirst();
        }
    }

    public String getLogsJson(int n) {
        synchronized (logLock) {
            int size = logBuffer.size();
            int start = Math.max(0, size - n);
            StringBuilder sb = new StringBuilder("{\"lines\":[");
            for (int i = start; i < size; i++) {
                if (i > start) sb.append(",");
                sb.append("{\"m\":\"").append(escape(logBuffer.get(i))).append("\"}");
            }
            sb.append("]}");
            return sb.toString();
        }
    }

    // ─── Native health monitor ────────────────────────────────────────

    private void monitorNativeHealth() {
        while ("running".equals(engineStatus) || "healthy".equals(engineStatus)) {
            try { Thread.sleep(5000); } catch (Exception e) { break; }
            synchronized (this) {
                if (!OsrmNative.isRunning()) {
                    if (!engineStopRequested) {
                        engineStatus = "crashed";
                        addLog("WARN", "Native engine stopped unexpectedly");
                        updateNotification("引擎異常終止");
                        if (configAutoRestart) {
                            restartCount++;
                            addLog("INFO", "Auto-restart #" + restartCount);
                            updateNotification("重新啟動中 (#" + restartCount + ")");
                            try { Thread.sleep(2000); } catch (Exception ignored) {}
                            startEngine();
                        } else {
                            engineStartTime = 0;
                        }
                    }
                    break;
                }
                updateSelfMemoryStats();
                updateNotification("OSRM 運行中 (port " + configPort + " " + (lastMemoryKb / 1024) + "MB)");
            }
        }
    }

    private void updateSelfMemoryStats() {
        try {
            BufferedReader r = new BufferedReader(new InputStreamReader(
                new FileInputStream("/proc/self/status")));
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("VmRSS:")) {
                    String[] p = line.split("\\s+");
                    if (p.length >= 2) lastMemoryKb = Long.parseLong(p[1]);
                    break;
                }
            }
            r.close();
        } catch (Exception ignored) {}
    }

    // ─── Engine output reader (ProcessBuilder mode) ──────────────────

    private void readEngineOutput() {
        if (engineProcess == null) return;
        try (BufferedReader r = new BufferedReader(new InputStreamReader(engineProcess.getInputStream()))) {
            String line;
            while ((line = r.readLine()) != null) addLog("OSRM", line);
        } catch (Exception e) {
            if (!engineStopRequested) addLog("WARN", "Engine output error: " + e.getMessage());
        }
        synchronized (this) {
            if (!engineStopRequested && engineProcess != null) {
                int exitCode;
                try { exitCode = engineProcess.exitValue(); } catch (Exception e) { exitCode = -1; }
                addLog("WARN", "Engine exited code=" + exitCode);
                engineStatus = "crashed";
                engineProcess = null;
                enginePid = -1;
                updateNotification("引擎已終止 (code " + exitCode + ")");
                synchronized (this) {
                    if (configAutoRestart && !engineStopRequested) {
                        restartCount++;
                        addLog("INFO", "Auto-restart #" + restartCount);
                        updateNotification("重新啟動中 (#" + restartCount + ")");
                        try { Thread.sleep(2000); } catch (Exception ignored) {}
                        startEngine();
                    } else {
                        engineStartTime = 0;
                    }
                }
            }
        }
    }

    // ─── Health monitor (ProcessBuilder mode) ────────────────────────

    private void monitorProcessHealth() {
        while ("running".equals(engineStatus) || "healthy".equals(engineStatus)) {
            try { Thread.sleep(5000); } catch (Exception e) { break; }
            synchronized (this) {
                if (engineProcess == null || !engineProcess.isAlive()) {
                    if (!engineStopRequested) engineStatus = "crashed";
                    break;
                }
                updateProcessMemoryStats();
                updateNotification("OSRM 運行中 (port " + configPort + " " + (lastMemoryKb / 1024) + "MB)");
            }
        }
    }

    private void updateProcessMemoryStats() {
        if (enginePid <= 0) return;
        try {
            BufferedReader r = new BufferedReader(new InputStreamReader(
                new FileInputStream("/proc/" + enginePid + "/status")));
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("VmRSS:")) {
                    String[] p = line.split("\\s+");
                    if (p.length >= 2) lastMemoryKb = Long.parseLong(p[1]);
                    break;
                }
            }
            r.close();
        } catch (Exception ignored) {}
    }

    // ─── Status JSON ─────────────────────────────────────────────────

    public String getStatusJson() {
        long uptime = engineStartTime > 0 ? (System.currentTimeMillis() - engineStartTime) / 1000 : 0;
        boolean binaryOk = configUseNative || new File(binaryPath != null ? binaryPath : "").exists();
        return "{"
            + "\"status\":\"" + engineStatus + "\""
            + ",\"native_running\":" + (configUseNative && OsrmNative.isRunning())
            + ",\"pid\":" + enginePid
            + ",\"uptime_sec\":" + uptime
            + ",\"memory_kb\":" + lastMemoryKb
            + ",\"restart_count\":" + restartCount
            + ",\"config\":" + getConfigJson()
            + ",\"use_native\":" + configUseNative
            + ",\"binary_ok\":" + binaryOk
            + "}";
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    private void extractBinary(File target) {
        try {
            addLog("INFO", "Extracting osrm-routed from assets");
            java.io.InputStream in = getAssets().open("osrm-routed");
            java.io.FileOutputStream out = new java.io.FileOutputStream(target);
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
            in.close();
            out.close();
            if (!target.setExecutable(true, false)) {
                addLog("WARN", "setExecutable returned false");
            }
            addLog("INFO", "Binary extracted to " + target.getAbsolutePath());
        } catch (Exception e) {
            addLog("ERROR", "Binary extraction failed: " + e.getMessage());
        }
    }

    private static File findOsrmProperties(File dataDir) {
        if (dataDir == null || !dataDir.isDirectory()) return null;
        File[] files = dataDir.listFiles();
        if (files == null) return null;
        for (File f : files) {
            if (f.getName().endsWith(".osrm.properties") && f.isFile()) return f;
        }
        return null;
    }

    private static int getPid(Process p) {
        try { return (int) p.getClass().getMethod("pid").invoke(p); } catch (Exception e) { return -1; }
    }

    private static String escape(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    private static String extractJsonString(String json, String key) {
        String search = "\"" + key + "\":\"";
        int start = json.indexOf(search);
        if (start >= 0) {
            start += search.length();
            int end = json.indexOf("\"", start);
            if (end >= 0) return json.substring(start, end);
        }
        search = "\"" + key + "\":";
        start = json.indexOf(search);
        if (start >= 0) {
            start += search.length();
            if (start < json.length() && json.charAt(start) == '"') {
                start++;
                int end = json.indexOf("\"", start);
                if (end >= 0) return json.substring(start, end);
            }
            int end = json.length();
            int comma = json.indexOf(",", start);
            if (comma >= 0) end = comma;
            int brace = json.indexOf("}", start);
            if (brace >= 0 && brace < end) end = brace;
            return json.substring(start, end).trim();
        }
        return null;
    }

    // ─── Notification ────────────────────────────────────────────────

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, "OSRM Engine", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("OSRM routing engine");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private Notification buildNotification(String text) {
        Intent openIntent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("OSRM 離線導航")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentIntent(pi)
            .setOngoing(true).build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(NOTIFY_ID, buildNotification(text));
    }
}
