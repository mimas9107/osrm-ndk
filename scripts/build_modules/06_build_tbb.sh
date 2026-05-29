#!/usr/bin/env bash
# ============================================================================
# 06_build_tbb.sh
# Compile Intel oneTBB library for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libtbb.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "oneTBB already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building oneTBB ..."
mkdir -p "$BUILD_DIR/tbb"

cmake -S "$DEPS_DIR/oneTBB" -B "$BUILD_DIR/tbb" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DTBB_TEST=OFF \
  -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-error=attribute-alias" \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$BUILD_DIR/tbb" -j "$JOBS"
cmake --install "$BUILD_DIR/tbb"

info "oneTBB successfully installed to $PREFIX"
