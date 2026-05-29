#!/usr/bin/env bash
# ============================================================================
# 05_build_lua.sh
# Compile Lua 5.3.6 library for Android ARM64.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_android.sh"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_REBUILD=true
fi

if [ -f "$PREFIX/lib/liblua.a" ] && [ "$FORCE_REBUILD" = false ]; then
  info "Lua already built, skipping. Use --force to rebuild."
  exit 0
fi

info "Building Lua 5.3.6 ..."
# Clean previous builds
make -C "$DEPS_DIR/lua-5.3.6" clean

# Build and install Lua using posix target (excludes readline dependency)
make -C "$DEPS_DIR/lua-5.3.6" -j"$JOBS" \
  CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" \
  MYLDFLAGS="$LDFLAGS" \
  posix

make -C "$DEPS_DIR/lua-5.3.6" \
  CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
  INSTALL_TOP="$PREFIX" \
  install

info "Lua successfully installed to $PREFIX"
