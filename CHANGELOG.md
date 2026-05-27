---
name:          "CHANGELOG.md"
description:   "OSRM Android NDK 專案變更記錄，為版本號的單一事實來源 (Source of Truth)"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 17:20:00"
project_version: "0.4.0"
document_version: "1.3.0"
agent_sign: ['opencode/current_agent']
---

# CHANGELOG

## 0.4.0 — 2026/05/27

### Phase 1 Standard — JNI Bridge 基礎建設 🏗️

#### Added
- **`libosrm_android.so`**: 以 JNI bridge 直接載入 OSRM engine 的 native shared library，取代 ProcessBuilder 獨立行程模式
- **`http_server.cpp` 自含 URL parser**: 解析 `/route/v1/{profile}/{lon,lat;...}?options` 格式，直接設定 RouteParameters 欄位
- **雙模式支援**: `OsrmService.java` 可透過 `use_native` 設定切換 JNI bridge (`OsrmNative.start/stop/isRunning`) 或既有 ProcessBuilder

#### Changed
- **`http_server.cpp`**: 全部重寫 — 移除不相容的 `FlatbuffersFormat`/`set_from_query`/`ToJson()`，改用 `json::Object` + `util::json::render()`；civetweb 1.15 callback 改為 1-arg signature，`user_data` 從 `mg_request_info` 取得
- **`osrm_bridge.cpp`**: 加入 graceful shutdown timeout (5s)、Java exception 拋出、auto-stop-before-restart 保護
- **`OsrmService.java`**: 拆出 `monitorNativeHealth`/`monitorProcessHealth`，native 模式讀 `/proc/self/status`，`getStatusJson` 新增 `native_running`、`use_native` 欄位；**修正健康監視器競爭條件**：在各自的迴圈開頭檢查 `configUseNative` 與監視器類型是否匹配，不匹配則立即退出，避免舊監視器錯誤標記新引擎為 crashed
- **`CMakeLists.txt`**: 加入 fmt 9.1 include path + `format.cc` 原始檔
- **`build.gradle.kts`**: 啟用 CMake externalNativeBuild，限制 ABI 為 `arm64-v8a`

#### Fixed
- **Civetweb 1.15 callback 簽名**: `begin_request` 僅接受 1 個引數 (`mg_connection*`)，無法直接傳 `cbdata`；改由 `mg_request_info->user_data` 取得
- **`osrm::Alias` 無隱含建構子**: `FloatLongitude(lon)` 編譯錯誤，需用聚合初始化 `FloatLongitude{lon}`
- **`osrm::Algorithm` 命名空間**: `osrm::Algorithm::MLD` 不存在，正確為 `osrm::EngineConfig::Algorithm::MLD`
- **`util::json::render` 需 2 引數**: `render(json_object)` 錯誤，需 `render(string&, object)`
- **fmt 符號未定義**: `json_renderer.hpp` 依賴 `<fmt/compile.h>`，需加入 `third_party/fmt-9.1.0/include` 並編譯 `format.cc`
- **Java 25 與 Gradle 8.9 不相容**: Java 25.0.3 觸發 Gradle 異常錯誤訊息，需使用 Java 21
- **ABI 未指定**: Gradle 預設 `armeabi-v7a`，與 OSRM 的 `arm64-v8a` 靜態庫不相容；加入 `abiFilters += "arm64-v8a"`
- **stopEngine() 未殺死 ProcessBuilder**: 在模式切換時若 `configUseNative` 已設為 true，`stopEngine()` 只會執行 native 分支，導致舊的 `osrm-routed` 進程殘留佔用 port 5747；現改為無論何種模式均嘗試殺死 `engineProcess` 再停止 native engine
- **binaryPath 為 null**: 當從 native 模式切換回 ProcessBuilder 時，因 `onCreate()` 中僅在 `!configUseNative` 時解析 binary 路徑，導致切換回去後 `binaryPath` 為 null；現改為在 `onCreate()` 無條件解析，並在 `updateConfig()` 重啟/啟動引擎前再次確認

#### Technical Details
- `libosrm_android.so`: 3.4 MB (ARM64, 靜態連結 OSRM + fmt + civetweb)
- APK 大小: 6.6 MB (含 `libosrm_android.so` + `libosrm_routed.so`)
- 編譯工具: NDK r30-beta1, CMake 3.22.1, Gradle 8.9, Java 21
- 路由埠: 5747 (JNI 模式) / 5000 (ProcessBuilder 模式)

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
