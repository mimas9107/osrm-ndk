#!/usr/bin/env bash
# ============================================================================
# 02_build_expat.sh
# Compile Expat XML parser for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libexpat.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "expat already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building expat ..."
mkdir -p "$BUILD_DIR/expat"

cmake -S "$DEPS_DIR/libexpat/expat" -B "$BUILD_DIR/expat" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DEXPAT_BUILD_TOOLS=OFF \
  -DEXPAT_BUILD_TESTS=OFF \
  -DEXPAT_BUILD_DOCS=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$BUILD_DIR/expat" -j "$JOBS"
cmake --install "$BUILD_DIR/expat"

info "expat successfully installed to $PREFIX"
