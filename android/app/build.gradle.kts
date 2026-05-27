plugins {
    id("com.android.application")
}

android {
    namespace = "com.osrm.android"
    compileSdk = 36
    ndkVersion = "30.0.14904198"

    defaultConfig {
        applicationId = "com.osrm.android"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.3.0"
        ndk { abiFilters += "arm64-v8a" }
    }

    buildTypes {
        debug {
            // Extract native libs to filesystem (needed for ProcessBuilder)
            isMinifyEnabled = false
            packaging { jniLibs { useLegacyPackaging = true } }
        }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // JNI .so build (Phase 1 Standard)
    externalNativeBuild {
        cmake {
            path = file("src/main/jni/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.9.24")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.24")
    }
}

dependencies {
    implementation("androidx.core:core:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.webkit:webkit:1.9.0")
}
