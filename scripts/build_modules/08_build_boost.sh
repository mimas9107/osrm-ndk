#!/usr/bin/env bash
# ============================================================================
# 08_build_boost.sh
# Compile Boost static libraries for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

# Check if a critical boost file exists to skip compilation
if [ -f "$PREFIX/lib/libboost_program_options.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "Boost already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building Boost ..."
cd "$DEPS_DIR/boost_1_83_0"

# Bootstrap b2 engine
if [ ! -f b2 ]; then
  ./bootstrap.sh --with-toolset=clang
fi

# Generate user-config.jam with absolute toolchain paths and LLVM-prefixed tools
cat > tools/build/src/user-config.jam << EOF
using clang : android : aarch64-linux-android24-clang++ :
  <archiver>llvm-ar
  <ranlib>llvm-ranlib
  <compileflags>-fPIC
  <compileflags>-O2
  <compileflags>-D_LARGEFILE64_SOURCE
  <compileflags>-D_FILE_OFFSET_BITS=64
  <compileflags>--sysroot=${TOOLCHAIN}/sysroot
;
EOF

# Compile selected libraries using b2
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
info "Boost successfully installed to $PREFIX"
