package com.osrm.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import java.io.File;

public class OsrmService extends Service {
    private static final String TAG = "OsrmService";
    private static final String CHANNEL_ID = "osrm_engine";
    private static final int NOTIFY_ID = 1001;

    private String dataPath;
    private boolean running = false;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        dataPath = getExternalFilesDir(null) + "/osrm_data/";
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (running) return START_STICKY;

        Notification notification = buildNotification("OSRM 引擎啟動中...");
        startForeground(NOTIFY_ID, notification);

        new Thread(() -> {
            try {
                File dataDir = new File(dataPath);
                if (!dataDir.exists() || !new File(dataDir, "taiwan-latest.osrm").exists()) {
                    Log.e(TAG, "OSRM data not found at " + dataPath);
                    stopSelf();
                    return;
                }
                boolean ok = OsrmNative.start(dataPath, 5000);
                if (ok) {
                    running = true;
                    updateNotification("OSRM 引擎運行中 (port 5000)");
                    Log.i(TAG, "OSRM engine started on port 5000");
                } else {
                    Log.e(TAG, "Failed to start OSRM engine");
                    stopSelf();
                }
            } catch (Exception e) {
                Log.e(TAG, "Error starting OSRM", e);
                stopSelf();
            }
        }).start();

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (running) {
            OsrmNative.stop();
            running = false;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ---- notification helpers ----

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, "OSRM Engine",
                NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Keep OSRM routing engine running");
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
            .setOngoing(true)
            .build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null)
            nm.notify(NOTIFY_ID, buildNotification(text));
    }
}
