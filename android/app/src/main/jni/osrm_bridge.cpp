#include <jni.h>
#include <string>
#include <chrono>
#include <thread>
#include <mutex>
#include <android/log.h>

#include "http_server.hpp"

#define LOG_TAG "OSRM_JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static HttpServer* g_server = nullptr;
static std::mutex g_mutex;
static int g_port = 5000;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

static void stop_server_locked() {
    if (g_server) {
        LOGI("Stopping OSRM engine");
        g_server->stop();

        // Graceful shutdown: wait up to 5s for civetweb to fully stop
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (g_server->is_running() && std::chrono::steady_clock::now() < deadline) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (g_server->is_running()) {
            LOGE("Graceful shutdown timed out after 5s");
        }

        delete g_server;
        g_server = nullptr;
        g_port = 5000;
        LOGI("OSRM engine stopped");
    }
}

static void throw_java_exception(JNIEnv* env, const char* msg) {
    jclass ex = env->FindClass("java/lang/RuntimeException");
    if (ex) {
        env->ThrowNew(ex, msg);
    }
}

// ---------------------------------------------------------------------------
// JNI: start
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osrm_android_OsrmNative_start(
    JNIEnv* env, jclass, jstring data_path, jint port) {

    std::lock_guard<std::mutex> lock(g_mutex);

    // If already running, stop first before restarting
    if (g_server && g_server->is_running()) {
        LOGI("Engine already running, stopping first");
        stop_server_locked();
    }

    const char* path = env->GetStringUTFChars(data_path, nullptr);
    if (!path) {
        throw_java_exception(env, "data_path is null");
        return JNI_FALSE;
    }
    std::string dp(path);
    env->ReleaseStringUTFChars(data_path, path);

    // Sanitize: strip .osrm extension if present
    if (dp.size() > 5 && dp.substr(dp.size() - 5) == ".osrm") {
        dp = dp.substr(0, dp.size() - 5);
    }

    LOGI("Starting OSRM engine with data: %s, port: %d", dp.c_str(), port);

    g_server = new HttpServer(dp, port);
    if (!g_server->start()) {
        LOGE("Failed to start OSRM engine on port %d with data %s", port, dp.c_str());
        delete g_server;
        g_server = nullptr;
        throw_java_exception(env, ("OSRM engine failed to start on port " + std::to_string(port)).c_str());
        return JNI_FALSE;
    }

    g_port = port;
    LOGI("OSRM engine started successfully on :%d", port);
    return JNI_TRUE;
}

// ---------------------------------------------------------------------------
// JNI: stop
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT void JNICALL
Java_com_osrm_android_OsrmNative_stop(JNIEnv* env, jclass) {
    std::lock_guard<std::mutex> lock(g_mutex);
    stop_server_locked();
}

// ---------------------------------------------------------------------------
// JNI: isRunning
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osrm_android_OsrmNative_isRunning(JNIEnv* env, jclass) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_server && g_server->is_running() ? JNI_TRUE : JNI_FALSE;
}
