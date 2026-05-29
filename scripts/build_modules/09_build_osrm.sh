#!/usr/bin/env bash
# ============================================================================
# 09_build_osrm.sh
# Compile OSRM backend (v5.27.1) for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$INSTALL_DIR/bin/osrm-routed" ] && [ "$FORCE_REBUILD" = false ]; then
  info "OSRM backend already built, skipping. Use --force to rebuild."
  exit 0
fi

# ---------- Gatekeeper Check ----------
info "Checking compiled dependencies in $PREFIX ..."
MISSING_DEPS=()
for lib in libz.a libexpat.a libbz2.a libxml2.a liblua.a libtbb.a libcivetweb.a libboost_program_options.a; do
  if [ ! -f "$PREFIX/lib/$lib" ]; then
    MISSING_DEPS+=("$lib")
  fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  err "Missing required dependency static libraries in $PREFIX/lib:"
  for missing in "${MISSING_DEPS[@]}"; do
    echo "  - $missing"
  done
  err "Please compile dependencies by running their respective scripts first."
  exit 1
fi
info "All dependency checks passed."

# ---------- OSRM backend compilation ----------
info "Building OSRM backend ..."
OSRM_SRC="$DEPS_DIR/osrm-backend"
OSRM_BLD="$BUILD_DIR/osrm"
mkdir -p "$OSRM_BLD"

cmake -S "$OSRM_SRC" -B "$OSRM_BLD" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_PIE=ON \
  -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DBoost_INCLUDE_DIR="$PREFIX/include" \
  -DBoost_LIBRARY_DIR="$PREFIX/lib" \
  -DTBB_INCLUDE_DIR="$PREFIX/include" \
  -DTBB_LIBRARY="$PREFIX/lib/libtbb.a" \
  -DLUA_INCLUDE_DIR="$PREFIX/include" \
  -DLUA_LIBRARY="$PREFIX/lib/liblua.a" \
  -DZLIB_INCLUDE_DIR="$PREFIX/include" \
  -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
  -DEXPAT_INCLUDE_DIR="$PREFIX/include" \
  -DEXPAT_LIBRARY="$PREFIX/lib/libexpat.a" \
  -DLIBXML2_INCLUDE_DIR="$PREFIX/include/libxml2" \
  -DLIBXML2_LIBRARY="$PREFIX/lib/libxml2.a" \
  -DBZIP2_INCLUDE_DIR="$PREFIX/include" \
  -DBZIP2_LIBRARY="$PREFIX/lib/libbz2.a" \
  -DENABLE_JSON_FORMAT=ON \
  -DBUILD_TOOLS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"

cmake --build "$OSRM_BLD" -j "$JOBS"
cmake --install "$OSRM_BLD"

# Verify and strip binaries
if [ -f "$INSTALL_DIR/bin/osrm-routed" ]; then
  file "$INSTALL_DIR/bin/osrm-routed" || true
  "${STRIP}" "$INSTALL_DIR/bin/osrm-routed"
  ls -lh "$INSTALL_DIR/bin/osrm-routed"
  info "OSRM backend successfully installed to $INSTALL_DIR"
else
  err "Build completed but target file $INSTALL_DIR/bin/osrm-routed is missing!"
  exit 1
fi
