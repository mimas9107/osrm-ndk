#!/usr/bin/env bash
# ============================================================================
# 03_build_bzip2.sh
# Compile bzip2 compression library for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/libbz2.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "bzip2 already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building bzip2 ..."
# Clean previous builds
make -C "$DEPS_DIR/bzip2-1.0.8" clean

# Build static library and install
make -C "$DEPS_DIR/bzip2-1.0.8" -j"$JOBS" \
  CC="$CC" AR="$AR" RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  libbz2.a

make -C "$DEPS_DIR/bzip2-1.0.8" \
  CC="$CC" AR="$AR" RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  PREFIX="$PREFIX" \
  install

info "bzip2 successfully installed to $PREFIX"
