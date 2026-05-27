#!/usr/bin/env bash
# ============================================================================
# deploy_moto.sh — Push OSRM v5.27 tools + motorcycle.lua to Android,
#                  compile motorcycle routing data on-device (MLD),
#                  with checkpoint phases for crash recovery.
#
# Usage:
#   ./deploy_moto.sh              # Run all phases from current state
#   ./deploy_moto.sh --status     # Show completed/phases
#   ./deploy_moto.sh --phase N    # Resume from phase N
#   ./deploy_moto.sh --reset      # Clear all phase state
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"

# ---------- paths (host) ----------
TOOL_SRC="$PROJECT_DIR/build_android/install/bin"
DATA_SRC="$PROJECT_DIR/../myosm/osrm_data"
LUA_SRC="$PROJECT_DIR/../myosm/motorcycle.lua"
PBF_SRC="$DATA_SRC/taiwan-latest.osm.pbf"

# ---------- paths (phone) ----------
PHONE_DIR="/data/local/tmp"
PHONE_TOOLS="$PHONE_DIR/tools"
PHONE_DATA="$PHONE_DIR/moto_data"
PHONE_BASE="taiwan-moto"
PBF_NAME="taiwan-latest.osm.pbf"
LUA_LIB_SRC="$PROJECT_DIR/deps/osrm-backend/profiles/lib"

# ---------- local state file ----------
STATE_FILE="/tmp/.deploy_moto_phase"
MAX_PHASE=6

# ============================================================================
# Helpers
# ============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
phase() { echo -e "\n${CYAN}══════════════ Phase $1 ══════════════${NC}"; }

get_phase() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo -1
  fi
}

set_phase() {
  echo "$1" > "$STATE_FILE"
  info "Checkpoint: phase $1 completed"
}

adb_test() {
  $ADB shell echo ok 2>/dev/null | grep -q ok
}

# ============================================================================
# Main
# ============================================================================

RESUME_FROM=-1

case "${1:-}" in
  --status)
    echo "Current phase: $(get_phase) (max: $MAX_PHASE)"
    echo "Use --phase N to resume from phase N"
    echo "Use --reset to clear state"
    exit 0
    ;;
  --reset)
    rm -f "$STATE_FILE"
    info "State cleared"
    exit 0
    ;;
  --phase)
    RESUME_FROM="${2:?Missing phase number}"
    ;;
  --help|-h)
    echo "Usage: $0 [--phase N | --status | --reset]"
    exit 0
    ;;
esac

CURRENT_PHASE=$(get_phase)

# ============================================================================
# Phase 0: Device check
# ============================================================================
if [ "$CURRENT_PHASE" -lt 0 ] && [ "$RESUME_FROM" -le 0 ]; then
  phase "0/6 — Device connectivity & authorization"

  if ! $ADB devices 2>/dev/null | grep -qE "^[[:alnum:]]+\s+device$"; then
    err "No authorized device found."
    echo ""
    echo "  Please:"
    echo "    1. Connect Android device via USB"
    echo "    2. Enable USB debugging (Developer options)"
    echo "    3. Accept the RSA fingerprint prompt on device"
    echo ""
    echo "  Then re-run: $0"
    echo ""
    $ADB devices 2>/dev/null || true
    exit 1
  fi

  DEVICE_MODEL=$($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  ANDROID_API=$($ADB shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
  info "Device: $DEVICE_MODEL (API $ANDROID_API)"

  # Check available space
  AVAIL_KB=$($ADB shell df -k /data/local/tmp 2>/dev/null | tail -1 | awk '{print $4}')
  if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 2000000 ] 2>/dev/null; then
    err "Insufficient space on device: ${AVAIL_KB}KB available"
    err "Need at least 2GB for processing"
    exit 1
  fi
  info "Available space: ~$((AVAIL_KB / 1024))MB on /data/local/tmp"

  set_phase 0
  CURRENT_PHASE=0
fi

# ============================================================================
# Phase 1: Push tools (osrm-extract, osrm-partition, osrm-customize)
# ============================================================================
if [ "$CURRENT_PHASE" -lt 1 ] && { [ "$RESUME_FROM" -le 1 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "1/6 — Pushing OSRM processing tools to device"

  $ADB shell mkdir -p "$PHONE_TOOLS"

  for tool in osrm-extract osrm-partition osrm-customize; do
    if [ ! -f "$TOOL_SRC/$tool" ]; then
      err "Missing tool: $TOOL_SRC/$tool"
      exit 1
    fi
    info "Pushing $tool ($(du -h "$TOOL_SRC/$tool" | cut -f1)) ..."
    $ADB push "$TOOL_SRC/$tool" "$PHONE_TOOLS/"
  done

  $ADB shell chmod +x "$PHONE_TOOLS/osrm-extract" "$PHONE_TOOLS/osrm-partition" "$PHONE_TOOLS/osrm-customize"

  # Verify
  $ADB shell "$PHONE_TOOLS/osrm-extract --help 2>&1 | head -3" || true
  info "Tools pushed & verified"

  set_phase 1
  CURRENT_PHASE=1
fi

# ============================================================================
# Phase 2: Push raw data (motorcycle.lua + osm.pbf)
# ============================================================================
if [ "$CURRENT_PHASE" -lt 2 ] && { [ "$RESUME_FROM" -le 2 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "2/6 — Pushing motorcycle.lua profile & raw OSM data"

  # Check sources
  [ -f "$LUA_SRC" ] || { err "motorcycle.lua not found at $LUA_SRC"; exit 1; }
  [ -f "$PBF_SRC" ] || { err ".osm.pbf not found at $PBF_SRC"; exit 1; }

  $ADB shell mkdir -p "$PHONE_DATA"

  info "Pushing motorcycle.lua ..."
  $ADB push "$LUA_SRC" "$PHONE_DATA/$PHONE_BASE.lua"

  info "Pushing $PBF_NAME ($(du -h "$PBF_SRC" | cut -f1)) ..."
  $ADB push "$PBF_SRC" "$PHONE_DATA/$PHONE_BASE.osm.pbf"

  # Push Lua lib files (set.lua, sequence.lua, etc.)
  info "Pushing OSRM Lua lib modules ..."
  $ADB shell rm -rf "$PHONE_DATA/lib"
  $ADB push "$LUA_LIB_SRC" "$PHONE_DATA"

  info "Data pushed to $PHONE_DATA/"

  set_phase 2
  CURRENT_PHASE=2
fi

# ============================================================================
# Phase 3: osrm-extract with motorcycle.lua (on device)
# ============================================================================
if [ "$CURRENT_PHASE" -lt 3 ] && { [ "$RESUME_FROM" -le 3 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "3/6 — osrm-extract with motorcycle profile (on device)"

  info "This may take 10–30 minutes on device..."
  info "Starting osrm-extract ..."

  $ADB shell "cd $PHONE_DATA && \
    $PHONE_TOOLS/osrm-extract \
      --profile $PHONE_DATA/$PHONE_BASE.lua \
      $PHONE_DATA/$PHONE_BASE.osm.pbf \
      2>&1" | tee /tmp/osrm_extract_moto.log

  # Check for success (presence of .osrm.properties — the main data marker)
  if $ADB shell "[ -f $PHONE_DATA/$PHONE_BASE.osrm.properties ]"; then
    info "osrm-extract completed successfully"
    $ADB shell ls -lh "$PHONE_DATA/$PHONE_BASE.osrm"*
  else
    err "osrm-extract may have failed. Check /tmp/osrm_extract_moto.log"
    exit 1
  fi

  set_phase 3
  CURRENT_PHASE=3
fi

# ============================================================================
# Phase 4: osrm-partition (MLD preprocessing, on device)
# ============================================================================
if [ "$CURRENT_PHASE" -lt 4 ] && { [ "$RESUME_FROM" -le 4 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "4/6 — osrm-partition (MLD partition, on device)"

  $ADB shell "cd $PHONE_DATA && \
    $PHONE_TOOLS/osrm-partition \
      $PHONE_DATA/$PHONE_BASE.osrm \
      2>&1" | tee /tmp/osrm_partition_moto.log

  if $ADB shell "[ -f $PHONE_DATA/$PHONE_BASE.osrm.partition ]"; then
    info "osrm-partition completed"
  else
    err "osrm-partition failed. Check /tmp/osrm_partition_moto.log"
    exit 1
  fi

  set_phase 4
  CURRENT_PHASE=4
fi

# ============================================================================
# Phase 5: osrm-customize (MLD finalize, on device)
# ============================================================================
if [ "$CURRENT_PHASE" -lt 5 ] && { [ "$RESUME_FROM" -le 5 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "5/6 — osrm-customize (MLD customize, on device)"

  $ADB shell "cd $PHONE_DATA && \
    $PHONE_TOOLS/osrm-customize \
      $PHONE_DATA/$PHONE_BASE.osrm \
      2>&1" | tee /tmp/osrm_customize_moto.log

  if $ADB shell "[ -f $PHONE_DATA/$PHONE_BASE.osrm.mldgr ]"; then
    info "osrm-customize completed"
    $ADB shell ls -lh "$PHONE_DATA/$PHONE_BASE.osrm"*
  else
    err "osrm-customize failed. Check /tmp/osrm_customize_moto.log"
    exit 1
  fi

  set_phase 5
  CURRENT_PHASE=5
fi

# ============================================================================
# Phase 6: Verify & push osrm-routed, start engine
# ============================================================================
if [ "$CURRENT_PHASE" -lt 6 ] && { [ "$RESUME_FROM" -le 6 ] || [ "$RESUME_FROM" -eq -1 ]; }; then
  phase "6/6 — Pushing osrm-routed & starting engine"

  OSRM_ROUTED_SRC="$PROJECT_DIR/build_android/output/osrm-routed"
  if [ ! -f "$OSRM_ROUTED_SRC" ]; then
    OSRM_ROUTED_SRC="$TOOL_SRC/osrm-routed"
  fi

  info "Pushing osrm-routed ..."
  $ADB push "$OSRM_ROUTED_SRC" "$PHONE_DIR/"
  $ADB shell chmod +x "$PHONE_DIR/osrm-routed"

  info "Starting osrm-routed in background (motorcycle profile)..."
  $ADB shell "nohup $PHONE_DIR/osrm-routed \
    --algorithm mld \
    --port 5000 \
    $PHONE_DATA/$PHONE_BASE.osrm \
    > $PHONE_DIR/osrm_routed.log 2>&1 &"

  # Wait for startup
  sleep 3

  # Verify
  if $ADB shell "ps -A 2>/dev/null | grep -q osrm-routed" || \
     $ADB shell "pgrep osrm-routed 2>/dev/null | head -1 | grep -q ."; then
    info "osrm-routed is running!"
  else
    warn "osrm-routed may not have started. Check log:"
    $ADB shell "cat $PHONE_DIR/osrm_routed.log 2>/dev/null | tail -10"
  fi

  set_phase 6
  CURRENT_PHASE=6
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All phases complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Data directory on phone:  $PHONE_DATA/"
echo "  Data base name:           $PHONE_BASE.osrm"
echo "  osrm-routed PID:"
$ADB shell "pgrep osrm-routed 2>/dev/null" || echo "    (not running)"
echo ""
echo "  Test on device browser (OSRM v5 API):"
echo "    http://localhost:5000/route/v1/driving/121.5,25.0;121.55,25.05?overview=false"
echo "  Test from PC via adb forward:"
echo "    adb forward tcp:5000 tcp:5000"
echo "    curl 'http://localhost:5000/route/v1/driving/121.5,25.0;121.55,25.05'"
echo ""
echo "  View server log:"
echo "    adb shell cat $PHONE_DIR/osrm_routed.log"
echo ""
echo "  Re-run to skip completed phases."
echo "  To reset all state: $0 --reset"
