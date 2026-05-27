---
name:          "ARCHITECTURE.md"
description:   "OSRM Android NDK — 完整架構規劃與開發路徑"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 16:50:00"
project_version: "0.3.0"
document_version: "1.2.0"
agent_sign: ['opencode/current_agent']
---

# Android OSRM Backend — 架構規劃書

將 OSRM C++ 路由引擎透過 Android NDK 交叉編譯為 ARM64 原生程式碼，
封裝為 Android Foreground Service，在手機本地提供完整 OSRM HTTP API。

---

## 一、核心指標

| 項目 | 數值 |
|------|------|
| 目標架構 | `arm64-v8a` |
| 最低 API | 24 (Android 7.0) |
| 圖資資料 (台灣 MLD) | ~1.33 GB |
| 預估運行記憶體 | 800 MB – 1.5 GB |
| 路由演算法 | MLD (Multi-Level Dijkstra) |
| HTTP API | 與標準 OSRM 完全相容 |

## 二、系統架構

```
┌─────────────────────────────────────────────┐
│               Android App                     │
│  ┌──────────┐   ┌─────────────────────────┐  │
│  │ MainActivity │   │   OsrmForegroundService │  │
│  │ (WebView/UI) │   │  ┌──────────────────┐  │  │
│  │              │   │  │  Native Bridge   │  │  │
│  │              │   │  │  (JNI)           │  │  │
│  └──────┬───────┘   │  └────────┬─────────┘  │  │
│         │           │           │             │  │
│         │           │  ┌────────▼─────────┐  │  │
│         └───────────┼──►  libosrm_android.so │  │
│                     │  │  ┌──────────────┐  │  │
│                     │  │  │ libosrm core │  │  │
│                     │  │  ├──────────────┤  │  │
│                     │  │  │ civetweb     │  │  │
│                     │  │  │ (HTTP server)│  │  │
│                     │  │  └──────────────┘  │  │
│                     │  └────────────────────┘  │
│                     └─────────────────────────┘  │
└─────────────────────────────────────────────┘
                          │
                          │ http://localhost:5000
                          │
              ┌───────────▼────────────┐
              │  Pre-compiled .osrm    │
              │  data (MLD, Taiwan)    │
              │  ~1.33 GB              │
              └────────────────────────┘
```

### 設計原則

1. **最大化 reuse**：暴露與 Docker 版完全相同的 HTTP API，myosm 前端在 WebView 中可無痛遷移
2. **最小 JNI 層**：Java/Kotlin 只負責生命週期管理；路由邏輯全在 native 層
3. **嵌入式 HTTP 伺服器**：使用 civetweb (MIT License) 取代完整的外置 HTTP server，降低 binary 體積

---

## 三、相依性與交叉編譯

### 依賴套件清單

| 套件 | 版本 | 說明 | 編譯方式 |
|------|------|------|---------|
| Boost | 1.83+ | program_options, filesystem, system, thread, iostreams, date_time | b2 with android toolchain |
| TBB | 2021.10+ | oneAPI TBB (oneTBB) | CMake, 需 patch 部分 atomic |
| Lua | 5.3.6 | 執行 motorcycle.lua 設定檔 | make with ndk-cross |
| zlib | 1.3 | 壓縮 | CMake |
| expat | 2.6+ | XML 解析 | CMake |
| bzip2 | 1.0.8 | 壓縮 | make |
| libxml2 | 2.12+ | XML | CMake |
| civetweb | 1.15+ | 嵌入式 HTTP 伺服器 | CMake (optional, 僅 Phase 2) |
| OSRM | v5.27.1 | 主引擎 | CMake with custom toolchain |

### 編譯流程

   ```
   NDK r26+ toolchain
          │
          ▼
     ┌──────────┐    ┌──────────┐    ┌──────────────┐
     │ Build    │───►│ Build    │───►│ 手機端編譯    │
     │ deps     │    │ libosrm  │    │ (on-device)   │
     │ (static) │    │ (shared) │    │               │
     └──────────┘    └──────────┘    │ osrm-extract  │
                           │         │ + motorcycle  │
                           ▼         │ .lua profile  │
                    libosrm.a / .so  │               │
                                     │ osrm-partition│
                                     │ + customize   │
                                     │               │
                                     │ osrm-routed   │
                                     │ @ port 5000   │
                                     └──────────────┘
   ```

關鍵技術挑戰：
- **Boost.iostreams**：需要 zlib/bzip2 的 Android port，需注意 linking 順序
- **oneTBB atomic**：ARM64 平臺需要使用 `__atomic_load_8` / `__atomic_compare_exchange_8` 內建函式，需確保 NDK 版本 ≥ 26
- **記憶體限制**：需在 app 層實作記憶體監控，接近臨界值時 graceful shutdown

---

## 四、Phases 開發時程

### Phase 0：環境建置與驗證 [X]

```
[目標]   C 驗證 Android NDK 能否成功編譯 libosrm
[驗證標準] 在終端機產出 arm64 版本的 osrm-routed binary
[步驟]
  1. 安裝 NDK r26+ 並驗證 standalone toolchain
  2. 使用 scripts/build_android_osrm.sh 執行完整編譯
  3. 在 Android 裝置 (或模擬器) 的 Termux 測試 binary 能否啟動
  4. 記錄記憶體與 startup time 數據
```

### Phase 0a：手機端機車圖資編譯 [X]

```
[目標]   在手機端以 motorcycle.lua profile 完成 MLD 圖資編譯
[驗證標準] osrm-routed 成功啟動，HTTP API 返回有效路徑
[步驟]
  1. scripts/deploy_moto.sh (6-phase checkpoint)
  2. 手機端執行 osrm-extract --profile motorcycle.lua
  3. 手機端執行 osrm-partition (MLD)
  4. 手機端執行 osrm-customize
  5. 啟動 osrm-routed + curl 驗證
[關鍵修復]
  - obstacles.lua 相容層 (OSRM v26+ feature backport)
  - WayHandlers.vehicle_speed_cap nil handler chain 截斷
[驗證數據]
  - Taiwan OSM: 24.9M nodes, 1.8M ways → 3.99M edges
  - MLD: 4-level (10382/805/51/4 cells)
  - RAM: extract 1.5GB, partition 530MB, customize 1.0GB
  - API latency: ~21ms (9.3km route)
```

### Phase 1s：自含式 APK + 儀表板 (v0.3.0) [X]

```
[目標]   以 ProcessBuilder 啟動 osrm-routed，WebView 監控儀表板
[驗證標準] APK 安裝後可在手機端啟動/停止/設定 OSRM 引擎
[步驟]
  1. 將 osrm-routed binary 打包至 jniLibs (PkgManager 自動展開)
  2. 實作 OsrmService (Foreground Service + ProcessBuilder)
  3. 實作 MonitorServer (port 5001, JSON API + 靜態檔服務)
  4. 開發 WebView 儀表板 (HTML/CSS/JS)
  5. 實作設定持久化 (SharedPreferences)
  6. 開發 CLI 工具 (osrm-cli.sh)
[關鍵修正]
  - SELinux noexec: 使用 jniLibs 而非 getFilesDir()
  - WebView CORS: 同源 http://127.0.0.1:5001/ 載入
  - 停止後自動重啟: 改為一次性 maybeAutoStart()
  - 按鈕無反應: 補上 showMsg()
  - MonitorServer EADDRINUSE: 防重複啟動保護
```

### Phase 1：Java/Native Bridge (JNI) [ ]

```
[目標] 建立 Android 專案，可透過 JNI 啟動/停止 OSRM
[驗證標準] App 啟動後可從瀏覽器訪問 http://localhost:5000/route
[步驟]
  1. 建立 Android Gradle 專案
  2. 整合 libosrm_android.so 到 APK
  3. 實作 OsrmForegroundService (持續背景執行)
  4. 驗證 HTTP API 正確性 (對比 Docker 版輸出)
```

### Phase 2：離線圖資管理 [ ]

```
[目標] 支援 OSRM data 的首次下載與更新
[驗證標準] 可從網路下載 .osrm 壓縮包，解壓後正確載入
[步驟]
  1. 包裝 Taiwan MLD .osrm 資料為 ZIP (約 600MB 壓縮)
  2. 實作 DownloadManager 整合至 app
  3. 增加 data integrity check (SHA256)
  4. 支援 data 放在 external storage 以節省 internal space
```

### Phase 3：WebView 整合前端 UI [/]

```
[目標] 整合地圖顯示、路線規劃互動介面
[驗證標準] 可在手機上完成完整的多點配送路線規劃流程
[步驟]
  1. 將 myosm/frontend 打包至 assets/，透過 WebView 載入
  2. 調整 WebView 設定 (JavaScript enabled, file access)
  3. 實作離線圖磚支援 (mbtiles 或 vector tiles)
  4. 效能調校與低記憶體情境處理
[進度]
  - WebView 儀表板已完成（監控用途，非地圖前端）
  - 地圖前端尚待整合
```

---

## 五、Android 專案結構

```
android/
├── build.gradle.kts                 # Root Gradle (AGP 8.2+)
├── settings.gradle.kts              # Module settings
├── gradle.properties                # Android config
├── app/
│   ├── build.gradle.kts             # App module
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── assets/
│       │   └── www/                 # myosm frontend (from ../myosm/frontend)
│       │       ├── index.html
│       │       ├── css/
│       │       └── js/
│       ├── java/com/osrm/android/
│       │   ├── MainActivity.java    # WebView host
│       │   ├── OsrmService.java     # Foreground Service (native lifecycle)
│       │   ├── OsrmNative.java      # JNI wrapper class
│       │   └── DataManager.java     # .osrm download & extraction
│       └── jni/
│           ├── CMakeLists.txt       # Native lib build config
│           ├── osrm_bridge.cpp      # JNI functions
│           ├── osrm_bridge.h
│           ├── http_server.cpp      # civetweb embedded HTTP server
│           └── http_server.h
├── scripts/
│   ├── build_osrm_android.sh        # Full cross-compilation pipeline
│   ├── toolchain.cmake              # Android NDK CMake toolchain
│   └── fetch_deps.sh                # Download all source dependencies
```

---

## 六、關鍵實作細節

### 6.1 Native Bridge API (JNI)

```java
// OsrmNative.java
class OsrmNative {
    static { System.loadLibrary("osrm_android"); }
    
    // 啟動 OSRM 引擎 (blocking)
    public static native boolean start(String dataPath, int port);
    
    // 停止引擎
    public static native void stop();
    
    // 健康檢查
    public static native boolean isRunning();
}
```

### 6.2 HTTP Server 設計

在 native 層啟動 civetweb，監聽 `127.0.0.1:5000`，註冊 `callbacks` 處理：
- `GET /route` → `osrm::Engine::Route()`
- `GET /trip` → `osrm::Engine::Trip()`
- `GET /table` → `osrm::Engine::Table()`
- `GET /match` → `osrm::Engine::Match()`
- `GET /nearest` → `osrm::Engine::Nearest()`

回應格式完全相容標準 OSRM v5 API，確保 myosm 前端不需修改。

### 6.3 記憶體管理策略

| 策略 | 說明 |
|------|------|
| MLD 演算法 | 比 CH 節省 30-50% 記憶體 |
| Foreground Service | 提高 process 優先級，降低被 LMK 砍掉的機率 |
| Memory monitoring | 在 Java 層定期檢查 `Runtime.getRuntime().totalMemory()` |
| Graceful degradation | 記憶體不足時關閉引擎，提示使用者關閉其他 App |

### 6.4 資料管理

- **開發環境（既有圖資）**：直接將 `myosm/osrm_data/` 複製到 Android external storage
- **開發環境（機車圖資手機端編譯）**：使用 `deploy_moto.sh` 將原始 `.osm.pbf` + `motorcycle.lua` 推至手機，在手機端完成 osrm-extract → partition → customize 全流程，產出機車專屬 `.osrm.*` 圖資 (~1.1GB)
- **生產環境**：.osrm 壓縮為 ZIP 上傳至 CDN，App 首次啟動時下載並解壓
- **更新策略**：version check → 比對 `.osrm.properties` 內的 timestamp

---

## 七、PoC 驗證路徑

### PoC-A：既有圖資部署 (快速驗證 binary)

```
# 1. NDK 編譯 osrm-routed → arm64 binary

# 2. 手動 push 到裝置:
./scripts/deploy.sh
```

### PoC-B：手機端機車圖資編譯 (完整 pipeline)

```
# 1. 完整編譯 → 產出所有 osrm-* 工具
./scripts/build_osrm_android.sh

# 2. 手機端 6-phase 編譯 + 啟動
./scripts/deploy_moto.sh

# 3. 測試路由
adb forward tcp:5000 tcp:5000
curl 'http://localhost:5000/route/v1/driving/121.5,25.0;121.55,25.05'
# → {"code":"Ok","routes":[...]}
```

PoC-B 驗證了「OSRM ARM64 binary + motorcycle.lua profile 能在手機端完整編譯圖資並提供路由服務」。

---

## 八、風險與解決方案

| 風險 | 影響 | 緩解措施 |
|------|------|---------|
| 記憶體不足 (1.33GB 資料) | App 閃退 | 改用 MLD；推薦 4GB+ RAM 裝置；啟用 Swap |
| NDK 編譯 OSRM 失敗 | 專案卡關 | 先走 Termux 快速驗證 (Phase 0) |
| Boost 交叉編譯複雜 | 開發時程延長 | 使用 pre-built Boost for Android (如 mxe) |
| 圖資佔用空間過大 | 使用者不願安裝 | 支援 SD 卡；第一版先只提供下載選項 |
| Android 背景限制 (doze) | Service 被殺 | 使用 Foreground Service + 通知欄常駐 |
