#!/usr/bin/env bash
# ============================================================================
# build_osrm_android.sh
# 交叉編譯 OSRM backend 及其所有相依套件至 Android ARM64
#
# Usage:
#   export ANDROID_NDK_HOME=/path/to/android-ndk-r26d
#   ./scripts/build_osrm_android.sh [--rebuild-deps] [--skip-deps]
#
# Output: ./build_android/install/  — 所有編譯產物
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_DIR="${PROJECT_DIR}/deps"
BUILD_DIR="${PROJECT_DIR}/build_android"
INSTALL_DIR="${BUILD_DIR}/install"
PREFIX="${INSTALL_DIR}/android-24/arm64-v8a"
JOBS=$(nproc 2>/dev/null || echo 4)

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------- 自動偵測 NDK 路徑 ----------
DEFAULT_NDK="$HOME/Android/Sdk/ndk"
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  if [ -d "$DEFAULT_NDK" ]; then
    NDK_VERSIONS=("$DEFAULT_NDK"/*)
    if [ ${#NDK_VERSIONS[@]} -gt 0 ]; then
      ANDROID_NDK_HOME="${NDK_VERSIONS[-1]}"
      info "Auto-detected NDK: $ANDROID_NDK_HOME"
    fi
  fi
fi
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  err "ANDROID_NDK_HOME is not set. Please set it:"
  echo "  export ANDROID_NDK_HOME=\$HOME/Android/Sdk/ndk/<version>"
  exit 1
fi

TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
CC="${TOOLCHAIN}/bin/aarch64-linux-android24-clang"
CXX="${TOOLCHAIN}/bin/aarch64-linux-android24-clang++"
AR="${TOOLCHAIN}/bin/llvm-ar"
RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
STRIP="${TOOLCHAIN}/bin/llvm-strip"
SYSROOT="${TOOLCHAIN}/sysroot"

export CC CXX AR RANLIB STRIP SYSROOT
export CFLAGS="-fPIC -O2 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64"
export CXXFLAGS="$CFLAGS -fvisibility=hidden"
export LDFLAGS="-fPIC"
export PATH="${TOOLCHAIN}/bin:${PATH}"

mkdir -p "$PREFIX"/{lib,include,bin}
mkdir -p "$BUILD_DIR"/{zlib,expat,bzip2,libxml2,lua,tbb,civetweb,osrm}

REBUILD_DEPS=false
SKIP_DEPS=false
for arg in "$@"; do
  case "$arg" in
    --rebuild-deps) REBUILD_DEPS=true ;;
    --skip-deps)    SKIP_DEPS=true ;;
  esac
done

# ============================================================================
# Helper: CMake cross-compile
# ============================================================================
cmake_android() {
  local src="$1" bld="$2"
  shift 2
  cmake -S "$src" -B "$bld" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_PIE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"
    "$@"
  cmake --build "$bld" -j "$JOBS"
  cmake --install "$bld"
}

# ============================================================================
# Phase 1: Dependencies
# ============================================================================
if [ "$SKIP_DEPS" = false ]; then

  # --- zlib ---
  if [ ! -f "$PREFIX/lib/libz.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building zlib ..."
    cmake_android "$DEPS_DIR/zlib" "$BUILD_DIR/zlib"
  else
    info "zlib already built"
  fi

  # --- expat ---
  if [ ! -f "$PREFIX/lib/libexpat.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building expat ..."
    cmake_android "$DEPS_DIR/libexpat/expat" "$BUILD_DIR/expat" \
      -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF
  else
    info "expat already built"
  fi

  # --- bzip2 ---
  if [ ! -f "$PREFIX/lib/libbz2.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building bzip2 ..."
    make -C "$DEPS_DIR/bzip2-1.0.8" -j"$JOBS" \
      CC="$CC" AR="$AR" RANLIB="$RANLIB" \
      CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
      libbz2.a \
      PREFIX="$PREFIX" install
  else
    info "bzip2 already built"
  fi

  # --- libxml2 ---
  if [ ! -f "$PREFIX/lib/libxml2.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building libxml2 ..."
    cmake_android "$DEPS_DIR/libxml2" "$BUILD_DIR/libxml2" \
      -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_TESTS=OFF \
      -DLIBXML2_WITH_PROGRAMS=OFF \
      -DLIBXML2_WITH_ZLIB=ON \
      -DLIBXML2_WITH_ICONV=OFF
  else
    info "libxml2 already built"
  fi

  # --- Lua ---
  if [ ! -f "$PREFIX/lib/liblua.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building Lua 5.3.6 ..."
    make -C "$DEPS_DIR/lua-5.3.6" -j"$JOBS" \
      CC="$CC" AR="$AR RANLIB=$RANLIB" RANLIB="$RANLIB" \
      CFLAGS="$CFLAGS -DLUA_USE_LINUX" SYSCFLAGS="-DLUA_USE_LINUX" \
      MYLDFLAGS="$LDFLAGS" \
      aarch64-linux-android \
      INSTALL_TOP="$PREFIX" install
  else
    info "Lua already built"
  fi

  # --- oneTBB ---
  if [ ! -f "$PREFIX/lib/libtbb.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building oneTBB ..."
    cmake_android "$DEPS_DIR/oneTBB" "$BUILD_DIR/tbb" \
      -DTBB_TEST=OFF -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-error=attribute-alias"
  else
    info "oneTBB already built"
  fi

  # --- civetweb ---
  if [ ! -f "$PREFIX/lib/libcivetweb.a" ] || [ "$REBUILD_DEPS" = true ]; then
    info "Building civetweb ..."
    cmake_android "$DEPS_DIR/civetweb" "$BUILD_DIR/civetweb" \
      -DCIVETWEB_ENABLE_SSL=OFF -DCIVETWEB_ENABLE_WEBSOCKETS=OFF \
      -DCIVETWEB_BUILD_TESTING=OFF
  else
    info "civetweb already built"
  fi
fi

# ============================================================================
# Phase 2: Boost (uses b2, needs separate handling)
# ============================================================================
if [ ! -f "$PREFIX/lib/libboost_program_options.a" ] || [ "$REBUILD_DEPS" = true ]; then
  info "Building Boost ..."
  cd "$DEPS_DIR/boost_1_83_0"
  
  # Generate b2 if needed
  if [ ! -f b2 ]; then
    ./bootstrap.sh --with-toolset=clang
  fi

  # Generate project config for Android
  cat > tools/build/src/user-config.jam << 'EOF'
using clang : android : aarch64-linux-android24-clang++ :
  <archiver>aarch64-linux-android-ar
  <ranlib>aarch64-linux-android-ranlib
  <compileflags>-fPIC
  <compileflags>-O2
  <compileflags>-D_LARGEFILE64_SOURCE
  <compileflags>-D_FILE_OFFSET_BITS=64
  <compileflags>--sysroot=$(ANDROID_NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64/sysroot
;
EOF

  ./b2 -j"$JOBS" \
    toolset=clang-android \
    target-os=linux \
    architecture=arm \
    address-model=64 \
    abi=aapcs \
    link=static \
    runtime-link=static \
    threading=multi \
    variant=release \
    --with-program_options \
    --with-filesystem \
    --with-system \
    --with-thread \
    --with-iostreams \
    --with-date_time \
    --prefix="$PREFIX" \
    install

  cd "$PROJECT_DIR"
else
  info "Boost already built"
fi

# ============================================================================
# Phase 3: OSRM backend
# ============================================================================
if [ ! -f "$INSTALL_DIR/osrm-routed" ] || [ "$REBUILD_DEPS" = true ]; then
  info "Building OSRM backend ..."

  OSRM_SRC="$DEPS_DIR/osrm-backend"
  OSRM_BLD="$BUILD_DIR/osrm"

  cmake -S "$OSRM_SRC" -B "$OSRM_BLD" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
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
    -DBUILD_TESTING=OFF

  cmake --build "$OSRM_BLD" -j"$JOBS"
  cmake --install "$OSRM_BLD"

  # Verify output
  file "$INSTALL_DIR/bin/osrm-routed" || true
  "${STRIP}" "$INSTALL_DIR/bin/osrm-routed"
  ls -lh "$INSTALL_DIR/bin/osrm-routed"
else
  info "OSRM already built"
fi

# ============================================================================
# Phase 4: Package native library for Android
# ============================================================================
info "Packaging native library ..."
mkdir -p "$BUILD_DIR/output/jniLibs/arm64-v8a"
mkdir -p "$BUILD_DIR/output/data"

cp "$INSTALL_DIR/lib/libosrm.a" "$BUILD_DIR/output/jniLibs/arm64-v8a/" 2>/dev/null || true

info "=== Build complete ==="
info "Binary:      $INSTALL_DIR/bin/osrm-routed"
info "Libraries:   $PREFIX/lib/"
info "Android lib: $BUILD_DIR/output/jniLibs/arm64-v8a/"
echo ""
info "Next step: copy osrm-routed binary to device and test:"
echo "  adb push $INSTALL_DIR/bin/osrm-routed /data/local/tmp/"
echo "  adb push /path/to/taiwan-latest.osrm* /data/local/tmp/osrm_data/"
echo "  adb shell /data/local/tmp/osrm-routed --algorithm mld \\"
echo "    /data/local/tmp/osrm_data/taiwan-latest.osrm"
