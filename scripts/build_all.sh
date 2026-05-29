#!/usr/bin/env bash
# ============================================================================
# build_all.sh
# Master script to compile all OSRM dependencies, core libraries, and binaries.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env_android.sh"

FORCE_FLAG=""
if [ "${1:-}" = "--force" ]; then
  FORCE_FLAG="--force"
  info "Force rebuild enabled. Rebuilding all components from scratch."
fi

# Run each module in order
MODULES_DIR="${SCRIPT_DIR}/build_modules"
for script in \
  01_build_zlib.sh \
  02_build_expat.sh \
  03_build_bzip2.sh \
  04_build_libxml2.sh \
  05_build_lua.sh \
  06_build_tbb.sh \
  07_build_civetweb.sh \
  08_build_boost.sh \
  09_build_osrm.sh; do
  
  info "===================================================================="
  info "  Executing: $script"
  info "===================================================================="
  
  bash "${MODULES_DIR}/${script}" $FORCE_FLAG
done

# Run packaging step
info "===================================================================="
info "  Executing artifact packaging"
info "===================================================================="
bash "${SCRIPT_DIR}/package_artifacts.sh"

info "=== All components built and packaged successfully ==="
