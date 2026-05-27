---
name:          "CHANGELOG.md"
description:   "OSRM Android NDK 專案變更記錄，為版本號的單一事實來源 (Source of Truth)"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 15:00:00"
project_version: "0.2.0"
document_version: "1.0.1"
agent_sign: ['opencode/current_agent']
---

# CHANGELOG

## 0.2.0 — 2026/05/27

### 手機端機車 MLD 圖資編譯里程碑

#### Added
- **`deploy_moto.sh`**: 6 階段 checkpoint 部署腳本，支援斷點恢復 (`--phase N`, `--reset`, `--status`)
  - Phase 0: 裝置授權檢查 (型號/API/空間)
  - Phase 1: 推送上位機編譯工具 (osrm-extract, osrm-partition, osrm-customize)
  - Phase 2: 推送原始圖資 (motorcycle.lua + .osm.pbf) + Lua lib 模組
  - Phase 3: 手機端 `osrm-extract` with `--profile motorcycle.lua`
  - Phase 4: 手機端 `osrm-partition` (MLD 4-level)
  - Phase 5: 手機端 `osrm-customize` (MLD 最終)
  - Phase 6: 啟動 `osrm-routed` + 驗證
- **`myosm/obstacles.lua`**: 為 OSRM v5.27 撰寫的 obstacles API 相容層 (新版本 C++ glue)
- **`myosm/motorcycle.lua`**: 加入 `WayHandlers.vehicle_speed_cap` v5.27 相容空函數 shim

#### Changed
- **`ARCHITECTURE.md`**: 更新 Phase 0 驗證範圍，加入手機端編譯流程

#### Fixed
- **Lua handler chain 中斷問題**: `ipairs` 遇 `nil` 截斷 handler chain (缺少 `vehicle_speed_cap` 函數導致 `names`, `weights`, `startpoint` 等 handler 未被執行)
- **`obstacle_map:get()` nil 節點**: `process_turn` 中 `turn.from`/`turn.via` 可能為 nil 導致 crash
- **Docker v26 vs binary v5.27 版本不合**: 改用手機端 native 編譯，不需依賴 Docker

#### Technical Details
- 編譯平台: Android NDK r30-beta1, target API 24 (arm64-v8a)
- 測試裝置: VOG-L29 (Huawei P30 Pro, Android 10, 8 核)
- 圖資: Taiwan OSM (24,906,531 nodes, 1,834,530 ways)
- 產出: 3,998,477 edges, 4-level MLD (10382/805/51/4 cells)
- 路由回應: ~21ms (9.3km 路徑計算)
- 執行記憶體峰值: extract ~1.5GB, partition ~530MB, customize ~1.0GB

---

## 0.1.0 — 2026/05/27

- 專案初始化：OSRM for Android NDK 交叉編譯規劃
- 新增 ARCHITECTURE.md 完整架構規劃
- 新增 scripts/ 編譯工具鏈 (fetch_deps.sh, build_osrm_android.sh, toolchain.cmake)
- 新增 android/ Android 專案範本 (Gradle + JNI + Foreground Service + WebView)
- 建立 4-Phase 開發路徑 (環境→Native→資料→UI)
