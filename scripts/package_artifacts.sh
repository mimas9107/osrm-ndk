#!/usr/bin/env bash
# ============================================================================
# package_artifacts.sh
# Package built binaries into the Android application module (jniLibs & assets).
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_android.sh"

ROUTED_BIN="$INSTALL_DIR/bin/osrm-routed"

if [ ! -f "$ROUTED_BIN" ]; then
  err "Built executable not found: $ROUTED_BIN"
  err "Please compile OSRM backend by running 09_build_osrm.sh first."
  exit 1
fi

# 1. Package into jniLibs (rename to libosrm_routed.so for APK extraction)
JNILIBS_DIR="${PROJECT_DIR}/android/app/src/main/jniLibs/arm64-v8a"
info "Packaging executable to jniLibs: $JNILIBS_DIR/libosrm_routed.so"
mkdir -p "$JNILIBS_DIR"
cp "$ROUTED_BIN" "$JNILIBS_DIR/libosrm_routed.so"
"$STRIP" "$JNILIBS_DIR/libosrm_routed.so"
ls -lh "$JNILIBS_DIR/libosrm_routed.so"

# 2. Package into assets
ASSETS_DIR="${PROJECT_DIR}/android/app/src/main/assets"
info "Packaging executable to assets: $ASSETS_DIR/osrm-routed"
mkdir -p "$ASSETS_DIR"
cp "$ROUTED_BIN" "$ASSETS_DIR/osrm-routed"
"$STRIP" "$ASSETS_DIR/osrm-routed"
ls -lh "$ASSETS_DIR/osrm-routed"

info "Packaging complete. The binaries are ready for Gradle packaging."
