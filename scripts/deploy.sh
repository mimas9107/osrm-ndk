#!/usr/bin/env bash
# deploy.sh — Push osrm-routed + data to Android device and run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"

if ! $ADB devices | grep -q "device$"; then
  echo "ERROR: No Android device connected. Please connect and enable USB debugging."
  exit 1
fi

echo "=== Pushing osrm-routed binary ==="
$ADB push "$PROJECT_DIR/build_android/output/osrm-routed" /data/local/tmp/
$ADB shell chmod +x /data/local/tmp/osrm-routed

echo "=== Pushing Taiwan OSRM data ==="
OSRM_DATA="${OSRM_DATA_DIR:-$PROJECT_DIR/../myosm/osrm_data}"
if [ -d "$OSRM_DATA" ]; then
  $ADB shell mkdir -p /data/local/tmp/osrm_data
  $ADB push "$OSRM_DATA"/taiwan-latest.osrm* /data/local/tmp/osrm_data/
else
  echo "WARNING: OSRM data not found at $OSRM_DATA"
  echo "Please push data manually and update the path below."
fi

echo ""
echo "=== Starting OSRM engine ==="
echo "Run on device:"
echo "  adb shell /data/local/tmp/osrm-routed --algorithm mld \\"
echo "    /data/local/tmp/osrm_data/taiwan-latest.osrm"
echo ""
echo "Then test from device browser:"
echo "  http://localhost:5000/route?profile=driving&coordinates=121.5,25.0;121.6,25.1"
