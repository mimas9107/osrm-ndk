#!/usr/bin/env bash
# ============================================================================
# 04_build_libxml2.sh
# Compile libxml2 library for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libxml2.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "libxml2 already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building libxml2 ..."
mkdir -p "$BUILD_DIR/libxml2"

cmake -S "$DEPS_DIR/libxml2" -B "$BUILD_DIR/libxml2" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DLIBXML2_WITH_PYTHON=OFF \
  -DLIBXML2_WITH_TESTS=OFF \
  -DLIBXML2_WITH_PROGRAMS=OFF \
  -DLIBXML2_WITH_ZLIB=ON \
  -DLIBXML2_WITH_LZMA=OFF \
  -DLIBXML2_WITH_ICONV=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$BUILD_DIR/libxml2" -j "$JOBS"
cmake --install "$BUILD_DIR/libxml2"

info "libxml2 successfully installed to $PREFIX"
