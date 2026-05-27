# Android NDK CMake toolchain for cross-compiling OSRM and dependencies
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/toolchain.cmake \
#         -DANDROID_ABI=arm64-v8a \
#         -DANDROID_PLATFORM=android-24 \
#         ..
#
# This overrides the standard NDK's built-in toolchain to give us
# fine-grained control over compiler flags needed by OSRM's dependencies.

cmake_minimum_required(VERSION 3.22)

# --- Android parameters (set from command line) ---
set(ANDROID_ABI "arm64-v8a" CACHE STRING "Android ABI")
set(ANDROID_PLATFORM "android-24" CACHE STRING "Android API level")
set(ANDROID_NDK "$ENV{ANDROID_NDK_HOME}" CACHE PATH "NDK path")

if(NOT ANDROID_NDK)
  message(FATAL_ERROR "ANDROID_NDK_HOME is not set. Please set it to your NDK path.")
endif()

# --- Architecture mapping ---
if(ANDROID_ABI STREQUAL "arm64-v8a")
  set(ANDROID_TARGET "aarch64-linux-android")
  set(ANDROID_TARGET_ARCH "armv8-a")
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
  set(ANDROID_TARGET "armv7a-linux-androideabi")
  set(ANDROID_TARGET_ARCH "armv7-a")
elseif(ANDROID_ABI STREQUAL "x86_64")
  set(ANDROID_TARGET "x86_64-linux-android")
  set(ANDROID_TARGET_ARCH "x86-64")
else()
  message(FATAL_ERROR "Unsupported ABI: ${ANDROID_ABI}")
endif()

# --- Toolchain paths ---
set(ANDROID_TOOLCHAIN_ROOT "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64")
set(ANDROID_SYSROOT "${ANDROID_TOOLCHAIN_ROOT}/sysroot")

set(CMAKE_SYSROOT "${ANDROID_SYSROOT}")
set(CMAKE_C_COMPILER "${ANDROID_TOOLCHAIN_ROOT}/bin/${ANDROID_TARGET}${ANDROID_PLATFORM#android}-clang")
set(CMAKE_CXX_COMPILER "${ANDROID_TOOLCHAIN_ROOT}/bin/${ANDROID_TARGET}${ANDROID_PLATFORM#android}-clang++")
set(CMAKE_AR "${ANDROID_TOOLCHAIN_ROOT}/bin/llvm-ar" CACHE PATH "ar")
set(CMAKE_RANLIB "${ANDROID_TOOLCHAIN_ROOT}/bin/llvm-ranlib" CACHE PATH "ranlib")
set(CMAKE_STRIP "${ANDROID_TOOLCHAIN_ROOT}/bin/llvm-strip" CACHE PATH "strip")

# --- Compiler flags ---
set(COMMON_FLAGS "-fPIC -O2 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64")
set(CMAKE_C_FLAGS "${COMMON_FLAGS}" CACHE STRING "CFLAGS")
set(CMAKE_CXX_FLAGS "${COMMON_FLAGS} -fvisibility=hidden -fvisibility-inlines-hidden" CACHE STRING "CXXFLAGS")

set(CMAKE_FIND_ROOT_PATH "${ANDROID_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# --- Skip built-in NDK toolchain ---
set(ANDROID_NDK_TOOLCHAIN_INCLUDED ON)
