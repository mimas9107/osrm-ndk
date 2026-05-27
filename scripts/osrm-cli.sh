#!/bin/bash
# osrm-cli.sh — 遠端 OSRM 儀表板 CLI 工具
# 用法: ./osrm-cli.sh status|logs|config|start|stop|restart|ping|forward|route
#
# 透過 adb forward 連線手機端 MonitorServer (port 5001) 或 OSRM API (port)
set -euo pipefail

MONITOR_PORT=${OSRM_MONITOR_PORT:-5001}
OSRM_PORT=${OSRM_PORT:-5747}
CMD="${1:-status}"
shift 2>/dev/null || true

case "$CMD" in
  status)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s "http://127.0.0.1:${MONITOR_PORT}/status" | python3 -m json.tool 2>/dev/null || \
    curl -s "http://127.0.0.1:${MONITOR_PORT}/status"
    ;;
  config)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s "http://127.0.0.1:${MONITOR_PORT}/config" | python3 -m json.tool 2>/dev/null || \
    curl -s "http://127.0.0.1:${MONITOR_PORT}/config"
    ;;
  logs)
    N="${1:-50}"
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s "http://127.0.0.1:${MONITOR_PORT}/logs?n=${N}" | \
      python3 -c "
import sys, json
data = json.load(sys.stdin)
for line in data.get('lines', []):
    print(line.get('m', ''))
" 2>/dev/null || curl -s "http://127.0.0.1:${MONITOR_PORT}/logs?n=${N}"
    ;;
  start)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/start" | python3 -m json.tool 2>/dev/null || \
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/start"
    ;;
  stop)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/stop" | python3 -m json.tool 2>/dev/null || \
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/stop"
    ;;
  restart)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/restart" | python3 -m json.tool 2>/dev/null || \
    curl -s -X POST "http://127.0.0.1:${MONITOR_PORT}/restart"
    ;;
  ping)
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}" >/dev/null 2>&1
    curl -s "http://127.0.0.1:${MONITOR_PORT}/ping"
    ;;
  route)
    LON1="${2:-121.5}"
    LAT1="${3:-25.0}"
    LON2="${4:-121.55}"
    LAT2="${5:-25.05}"
    adb forward "tcp:${OSRM_PORT}" "tcp:${OSRM_PORT}" >/dev/null 2>&1
    curl -s "http://127.0.0.1:${OSRM_PORT}/route/v1/driving/${LON1},${LAT1};${LON2},${LAT2}?overview=false" \
      | python3 -m json.tool 2>/dev/null || \
    curl -s "http://127.0.0.1:${OSRM_PORT}/route/v1/driving/${LON1},${LAT1};${LON2},${LAT2}?overview=false"
    ;;
  forward)
    echo "Forwarding monitor:${MONITOR_PORT}  osrm:${OSRM_PORT}  (Ctrl+C to stop)..."
    adb forward "tcp:${MONITOR_PORT}" "tcp:${MONITOR_PORT}"
    adb forward "tcp:${OSRM_PORT}" "tcp:${OSRM_PORT}"
    while true; do sleep 3600; done
    ;;
  *)
    echo "用法: $0 {status|logs|config|start|stop|restart|ping|forward|route} [args]"
    echo ""
    echo "指令:"
    echo "  status          查看引擎狀態 (JSON)"
    echo "  config          查看設定"
    echo "  logs [N]        顯示最近 N 條 log (預設 50)"
    echo "  start           啟動引擎"
    echo "  stop            停止引擎"
    echo "  restart         重啟引擎"
    echo "  ping            健康檢查"
    echo "  route [l1] [a1] [l2] [a2]  路由查詢 (預設台北市中心)"
    echo "  forward         持續轉發 monitor + osrm port"
    echo ""
    echo "環境變數:"
    echo "  OSRM_MONITOR_PORT  監控 port (預設 5001)"
    echo "  OSRM_PORT          OSRM API port (預設 5747)"
    ;;
esac
