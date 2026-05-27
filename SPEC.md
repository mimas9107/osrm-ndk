---
name:             "SPEC.md"
description:      "OSRM Android NDK — 技術規格文件"
created_date:     "2026/05/27 15:00:00"
modified_date:    "2026/05/27 16:45:00"
project_version:  "0.3.0"
document_version: "1.1.0"
agent_sign: ['opencode/current_agent']
---

# SPEC — 技術規格文件

## OSRM Android NDK — 自含式 APK 路由服務

---

## 1. 系統概觀

將 OSRM C++ 路由引擎 (v5.27.1) 透過 Android NDK 交叉編譯為 ARM64 原生程式碼，以 Android APK 形式在手機端運行自含式路由服務，並透過 WebView 儀表板進行監控與管理。

| 屬性 | 規格 |
|------|------|
| 目標架構 | `arm64-v8a` (Android 24+) |
| OSRM 版本 | v5.27.1 |
| 演算法 | MLD (Multi-Level Dijkstra) |
| 路權設定 | 機車專屬 (`motorcycle.lua`) |
| 圖資來源 | OpenStreetMap Taiwan (geofabrik.de) |
| HTTP API | 標準 OSRM v5 API |
| 部署方式 | APK 安裝 (jniLibs 自動展開) |
| 監控 API | `127.0.0.1:5001` (同源儀表板) |
| 儀表板 | WebView + HTML/CSS/JS (自含式) |

### 1.1 架構圖

```
┌─────────────────────────────────────────────────────────┐
│  Android App (com.osrm.android)                         │
│                                                         │
│  ┌──────────────┐   ┌──────────────────────────────┐   │
│  │  MainActivity │   │  OsrmService (Foreground)    │   │
│  │  ┌──────────┐ │   │  ┌────────┐ ┌─────────────┐ │   │
│  │  │ WebView  │ │   │  │OSRM    │ │MonitorServer│ │   │
│  │  │dashboard │◄───┼──┤Engine  │ │ :5001        │ │   │
│  │  │(同源 XHR) │ │   │  │:5747   │ │  JSON API    │ │   │
│  │  └──────────┘ │   │  └────────┘ │  + 靜態檔案  │ │   │
│  └──────────────┘   │              └─────────────┘ │   │
│                     └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. 編譯管線

```
Host (x86_64 Linux)                     Android Device (ARM64)
─────────────────────                   ─────────────────────
NDK Cross-Compile
  └── deps/*.a → osrm-extract ──────────►  osrm-extract --profile motorcycle.lua
                    osrm-partition ──────►  osrm-partition (MLD partition)
                    osrm-customize ──────►  osrm-customize (MLD customize)
                    osrm-routed ─────────►  osrm-routed @ :5000
                                          ▲
myosm/osrm_data/                          │
  └── taiwan-latest.osm.pbf ──────────────┘
myosm/motorcycle.lua ────────────────────┘
```

### 2.1 主機端編譯 (Host)

| 步驟 | 輸入 | 產出 |
|------|------|------|
| `fetch_deps.sh` | — | `deps/` (原始碼) |
| `build_osrm_android.sh` | `deps/` | `build_android/install/bin/osrm-*` (ARM64) |

### 2.2 手機端編譯 (Device)

| Phase | 指令 | 輸入 | 產出 | 預期時間 |
|-------|------|------|------|----------|
| 3 | `osrm-extract --profile motorcycle.lua` | `.osm.pbf` (310MB) + `.lua` | `.osrm.*` (26 files) | ~65s |
| 4 | `osrm-partition` | `.osrm.*` | `.osrm.partition`, `.osrm.cells` | ~41s |
| 5 | `osrm-customize` | `.osrm.*` | `.osrm.mldgr`, `.osrm.cell_metrics` | ~27s |
| 6 | `osrm-routed --algorithm mld` | `.osrm.*` | HTTP API @ :5000 | ~3s |

---

## 3. 元件規格

### 3.1 OSRM 路由引擎

| 項目 | 值 |
|------|-----|
| 執行檔 | `osrm-routed` (2.9 MB stripped) |
| 編譯工具 | `osrm-extract` (82 MB), `osrm-partition` (15 MB), `osrm-customize` (38 MB) |
| 連結方式 | 動態連結 (`libc.so`, `libm.so`, `libdl.so`) |
| HTTP 伺服器 | 內建 (civetweb) |
| 預設埠號 | 5000 |

### 3.2 Lua Profile

| 項目 | 值 |
|------|-----|
| 設定檔 | `motorcycle.lua` (17 KB) |
| API 版本 | 4 |
| 路權優先 | `motorcycle` > `motor_vehicle` > `vehicle` > `access` |
| 禁行道路 | `highway=motorway`, `highway=motorway_link` (speed=0) |
| 速限來源 | `maxspeed` tag → `maxspeed_table["tw:*"]` → 路面分類預設 |
| 額外模組 | `obstacles.lua` (相容層, 模擬 v26+ C++ glue) |

### 3.3 相容層

| 模組 | 用途 | 說明 |
|------|------|------|
| `obstacles.lua` | 障礙物 API | 模擬 v26+ C++ 注入的全域變數 (`obstacle_type`, `obstacle_direction`, `Obstacle`, `obstacle_map`) |
| `WayHandlers.vehicle_speed_cap` | 速度上限 | v5.27 無此 handler，以空函數 shim 避免 handler chain 截斷 |

---

## 4. API 規格

### 4.1 路由查詢

```
GET /route/v1/{profile}/{lon1},{lat1};{lon2},{lat2}[?options]
```

| 參數 | 類型 | 預設 | 說明 |
|------|------|------|------|
| `profile` | string | `driving` | 固定為 `driving` (motorcycle 路權已編譯入圖資) |
| `coordinates` | string | — | 分號分隔的 `lng,lat` 座標對 |
| `overview` | string | `simplified` | `full`(完整幾何), `simplified`(簡化), `false`(不傳) |
| `steps` | bool | `false` | 是否回傳每步指令 |
| `alternatives` | bool | `false` | 是否回傳替代路線 |
| `geometries` | string | `polyline` | `polyline`(編碼), `geojson`(完整), `false` |

### 4.2 回應格式

```json
{
  "code": "Ok",
  "routes": [{
    "legs": [{
      "distance": 9297.7,
      "duration": 1004.5,
      "steps": []
    }],
    "distance": 9297.7,
    "duration": 1004.5
  }],
  "waypoints": [{...}, {...}]
}
```

---

## 5. 資源需求

### 5.1 記憶體 (實測 VOG-L29 / 6GB RAM)

| 階段 | RAM 峰值 | 說明 |
|------|----------|------|
| `osrm-extract` | 1.5 GB | 最高峰，需解析 24.9M nodes |
| `osrm-partition` | 530 MB | MLD recursive bisection |
| `osrm-customize` | 1.0 GB | cell customization |
| `osrm-routed` (運行) | ~600 MB–1.0 GB | 載入 MLD 圖資 |

### 5.2 儲存空間

| 資料 | 大小 |
|------|------|
| `.osm.pbf` (原始) | 310 MB |
| `.osrm.*` (編譯後) | ~1.1 GB (26 files) |
| 工具 binary | 140 MB (3 files) |
| 手機端總需求 | ~1.6 GB |

### 5.3 圖資資料

| 項目 | 數值 |
|------|------|
| Nodes | 24,906,531 |
| Ways | 1,834,530 |
| Relations | 7,656 |
| Restrictions | 2,481 |
| Extracted edges | 3,998,477 |
| MLD cells (4 levels) | 10,382 / 805 / 51 / 4 |
| MLD cell_metrics | 381 MB |

---

## 6. 部署

### 6.1 快速部署 (既有圖資)

```bash
./scripts/deploy.sh
```

### 6.2 手機端編譯 (機車圖資)

```bash
./scripts/deploy_moto.sh                          # 完整 6 階段
./scripts/deploy_moto.sh --phase 3                # 從 extract 恢復
./scripts/deploy_moto.sh --status                 # 查看進度
./scripts/deploy_moto.sh --reset                  # 清除狀態
```

### 6.3 手動測試

```bash
adb forward tcp:5000 tcp:5000
curl 'http://localhost:5000/route/v1/driving/121.5,25.0;121.55,25.05?overview=false'
# → {"code":"Ok","routes":[{"legs":[{"distance":9297.7,"duration":1004.5}]}]}
```

---

## 7. 錯誤碼

| 錯誤 | 原因 | 處理 |
|------|------|------|
| `InvalidUrl` | API 路徑不正確 | 改用 `/route/v1/{profile}/{coordinates}` 格式 |
| `NoEdge` | 該路段無可行路徑 | 檢查座標是否在可路由範圍 |
| `There are no edges remaining after parsing` | profile 過濾所有 way | 檢查 Lua profile handler chain |

---

## 8. 限制

- 僅支援 Taiwan OSM 圖資 (geofabrik.de)
- 需 Android 7.0+ (API 24) 且支援 PIE binary
- 建議裝置 RAM ≥ 4GB (6GB 為佳)
- 僅支援 MLD 演算法 (未編譯 CH)
- 僅 single-profile 運行 (motorcycle 路權已 baked-in)
