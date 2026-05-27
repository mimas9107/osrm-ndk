---
name:          "CHANGELOG.md"
description:   "OSRM Android NDK 專案變更記錄，為版本號的單一事實來源 (Source of Truth)"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 16:40:00"
project_version: "0.3.0"
document_version: "1.2.0"
agent_sign: ['opencode/current_agent']
---

# CHANGELOG

## 0.3.0 — 2026/05/27

### Phase 1 Simplified — 自含式 Android APK 里程碑 ✅

#### Added
- **`MonitorServer.java`**: 輕量 HTTP 監控伺服器 (`127.0.0.1:5001`)，提供 8 個 REST API (`/status`, `/config`, `/logs`, `/start`, `/stop`, `/restart`, `/ping`, `/stop_server`)；同時以 AssetManager 提供同源儀表板靜態檔案 (`/`, `/dashboard.css`, `/dashboard.js`)
- **`dashboard.html` / `dashboard.css` / `dashboard.js`**: 自含式暗色主題 WebView 監控儀表板（狀態卡、設定面板、log 檢視器、啟動/停止/重啟按鈕）
- **`scripts/osrm-cli.sh`**: 遠端 CLI 工具，支援 `status|logs|config|start|stop|restart|forward|route`

#### Changed
- **`OsrmService.java`**: 從 jniLibs (`/data/app/.../lib/arm64/libosrm_routed.so`) 載入二進位；加入 MonitorServer 防重複啟動保護；`readEngineOutput` 加入 `synchronized` 二次驗證 `engineStopRequested` 防止 stop→auto-restart 競爭；`startMonitorServer()` 傳入 AssetManager
- **`MainActivity.java`**: WebView 改載入 `http://127.0.0.1:5001/`（同源，避開 file→http CORS 封鎖）；加入 `onReceivedError` 自動重試（最多 20 次，每次間隔 1s）；Handler 延遲 500ms 啟動給 MonitorServer 緩衝
- **`AndroidManifest.xml`**: `FOREGROUND_SERVICE`, `INTERNET`, 前台服務 type + notification channel; 加入 `usesCleartextTraffic="true"`（WebView 允許 HTTP）
- **`MonitorServer.java`**: 接受 `AssetManager` 建構參數；加入 `serveAsset()` 提供靜態檔案；路由 `/`, `/dashboard.css`, `/dashboard.js`
- **`build.gradle.kts`**: 關閉 CMake (`abiFilters.clear()`), 開 ProGuard, target SDK 35
- **`deploy_moto.sh`**: 最終階段改為 `chmod 644` 確保 .osrm 資料檔可被 app 讀取

#### Fixed
- **SELinux noexec**: 二進位無法從 `getFilesDir()` (`files/` 子目錄) 執行；解決方案：使用 jniLibs (package manager 在安裝時自動展開) 或從 assets 解壓到 app 根目錄
- **AGP 8.2+ jniLibs 展開問題**: AGP 不會為未載入的 .so 解壓；解決方案：二進位移到 `jniLibs/arm64-v8a/libosrm_routed.so`（PackageManager 安裝時自動解壓到 native lib dir）
- **WebView CORS 封鎖**: `file://` origin 的 XHR 到 `http://127.0.0.1:5001` 被瀏覽器安全策略阻擋；解決方案：MonitorServer 同源提供靜態檔案，WebView 載入 `http://127.0.0.1:5001/`
- **按鈕無反應 (`showMsg` 未定義)**: `doStart/doStop/doRestart` 呼叫的 `showMsg()` 不曾定義，拋 ReferenceError；解決方案：加入 `showMsg()` 函數
- **停止後自動重啟**: JS `updateStatus` 每 3 秒輪詢時若 `status === 'stopped' && auto_start` 就呼叫 `doStart()`，抵消使用者的停止操作；解決方案：改用一次性 `maybeAutoStart()`，首次載入只觸發一次
- **MonitorServer EADDRINUSE**: `onStartCommand` 因 Activity 重建被多次呼叫導致 MonitorServer 重複綁定；解決方案：加入 `monitorServer.isRunning()` 檢查

#### Technical Details
- 測試裝置: VOG-L29 (Huawei P30 Pro, Android 10, 8 核)
- APK 大小: 4.3MB (3MB osrm-routed binary + 1.3MB 程式碼/資源)
- WebView: Google WebView 148.0.7778.120
- 路由回應: ~12ms (9.3km 路徑計算, motorcycle profile)

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
