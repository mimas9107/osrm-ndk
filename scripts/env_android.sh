#!/usr/bin/env bash
# ============================================================================
# env_android.sh
# Centralized Android NDK environment variables for modular build system.
# ============================================================================

# Protect against double sourcing
if [ "${_ENV_ANDROID_SOURCED:-0}" -eq 1 ]; then
  return 0
fi
_ENV_ANDROID_SOURCED=1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEPS_DIR="${PROJECT_DIR}/deps"
export BUILD_DIR="${PROJECT_DIR}/build_android"
export INSTALL_DIR="${BUILD_DIR}/install"
export PREFIX="${INSTALL_DIR}/android-24/arm64-v8a"
export JOBS=$(nproc 2>/dev/null || echo 4)

# ---------- Auto-detect Android NDK ----------
DEFAULT_NDK="$HOME/Android/Sdk/ndk"
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  if [ -d "$DEFAULT_NDK" ]; then
    NDK_VERSIONS=("$DEFAULT_NDK"/*)
    if [ ${#NDK_VERSIONS[@]} -gt 0 ]; then
      export ANDROID_NDK_HOME="${NDK_VERSIONS[-1]}"
      info "Auto-detected NDK: $ANDROID_NDK_HOME"
    fi
  fi
fi

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  err "ANDROID_NDK_HOME is not set. Please set it:"
  echo "  export ANDROID_NDK_HOME=\$HOME/Android/Sdk/ndk/<version>"
  exit 1
fi

if [ ! -d "$ANDROID_NDK_HOME" ]; then
  err "ANDROID_NDK_HOME directory does not exist: $ANDROID_NDK_HOME"
  exit 1
fi

export TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
export CC="${TOOLCHAIN}/bin/aarch64-linux-android24-clang"
export CXX="${TOOLCHAIN}/bin/aarch64-linux-android24-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export STRIP="${TOOLCHAIN}/bin/llvm-strip"
export SYSROOT="${TOOLCHAIN}/sysroot"

export CFLAGS="-fPIC -O2 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64"
export CXXFLAGS="$CFLAGS -fvisibility=hidden"
export LDFLAGS="-fPIC"

# Export toolchain binaries to PATH so subprocesses can resolve them (e.g. CMake or Makefile internals)
export PATH="${TOOLCHAIN}/bin:${PATH}"

# Ensure basic build directories exist
mkdir -p "$PREFIX"/{lib,include,bin}
mkdir -p "$BUILD_DIR"
