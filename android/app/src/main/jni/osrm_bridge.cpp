#include <jni.h>
#include <string>
#include <android/log.h>

#include "http_server.hpp"

#define LOG_TAG "OSRM_JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static HttpServer* g_server = nullptr;
static std::mutex g_mutex;

// ---------------------------------------------------------------------------
// JNI: start
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osrm_android_OsrmNative_start(
    JNIEnv* env, jclass, jstring data_path, jint port) {

    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_server && g_server->is_running()) {
        LOGI("OSRM engine already running");
        return JNI_TRUE;
    }

    const char* path = env->GetStringUTFChars(data_path, nullptr);
    std::string dp(path);
    env->ReleaseStringUTFChars(data_path, path);

    // Ensure data path points to the .osrm file (without extension)
    // OSRM expects the base path (e.g., /data/.../taiwan-latest)
    if (dp.size() > 5 && dp.substr(dp.size() - 5) == ".osrm") {
        dp = dp.substr(0, dp.size() - 5);
    }

    LOGI("Starting OSRM engine with data: %s, port: %d", dp.c_str(), port);

    g_server = new HttpServer(dp, port);
    if (g_server->start()) {
        LOGI("OSRM engine started successfully");
        return JNI_TRUE;
    }

    LOGE("Failed to start OSRM engine");
    delete g_server;
    g_server = nullptr;
    return JNI_FALSE;
}

// ---------------------------------------------------------------------------
// JNI: stop
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT void JNICALL
Java_com_osrm_android_OsrmNative_stop(JNIEnv* env, jclass) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_server) {
        LOGI("Stopping OSRM engine");
        g_server->stop();
        delete g_server;
        g_server = nullptr;
    }
}

// ---------------------------------------------------------------------------
// JNI: isRunning
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osrm_android_OsrmNative_isRunning(JNIEnv* env, jclass) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_server && g_server->is_running() ? JNI_TRUE : JNI_FALSE;
}
