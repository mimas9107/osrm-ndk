package com.osrm.android;

/** JNI bridge to native libosrm_android.so */
public final class OsrmNative {
    static {
        System.loadLibrary("osrm_android");
    }

    /** Start OSRM engine with MLD data at {@code dataPath}, listening on {@code port}. */
    public static native boolean start(String dataPath, int port);

    /** Gracefully stop the engine and HTTP server. */
    public static native void stop();

    /** Check if the engine is currently running. */
    public static native boolean isRunning();

    private OsrmNative() {}
}
