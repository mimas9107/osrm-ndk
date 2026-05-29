#!/usr/bin/env bash
# ============================================================================
# 07_build_civetweb.sh
# Compile Civetweb embedded HTTP server for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libcivetweb.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "civetweb already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building civetweb ..."
mkdir -p "$BUILD_DIR/civetweb"

cmake -S "$DEPS_DIR/civetweb" -B "$BUILD_DIR/civetweb" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DCIVETWEB_ENABLE_SSL=OFF \
  -DCIVETWEB_ENABLE_WEBSOCKETS=OFF \
  -DCIVETWEB_BUILD_TESTING=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$BUILD_DIR/civetweb" -j "$JOBS"
cmake --install "$BUILD_DIR/civetweb"

info "civetweb successfully installed to $PREFIX"
