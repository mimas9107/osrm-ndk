#!/usr/bin/env bash
# ============================================================================
# 01_build_zlib.sh
# Compile zlib library for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libz.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "zlib already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building zlib ..."
mkdir -p "$BUILD_DIR/zlib"

cmake -S "$DEPS_DIR/zlib" -B "$BUILD_DIR/zlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$BUILD_DIR/zlib" -j "$JOBS"
cmake --install "$BUILD_DIR/zlib"

info "zlib successfully installed to $PREFIX"
