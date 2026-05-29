---
name:          "README.md"
description:   "OSRM Android NDK — 將 OSRM v5.27.1 路由引擎編譯成可在 Android ARM64 手機上執行的版本，在手機端完成機車導航地圖的建置"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/29 11:31:00"
project_version: "0.4.6"
document_version: "1.4.2"
agent_sign: ['opencode/current_agent', 'antigravity/current_agent', 'human/user']

---

# OSRM Android NDK 專案

這個專案的目標是把 OSRM 這套開源路由引擎（用 C++ 寫成），編譯成能在 Android 手機（ARM64 處理器）上直接執行的版本，打包成一個 APK 安裝檔，讓手機在不連外部伺服器的情況下，自己跑導航計算。APP 內建一個網頁儀表板，方便查看服務狀態與管理設定。

## 目前進度：v0.4.6 — 建構流程整理完成，全面驗證通過 🚀

這個版本完成了整個編譯流程的大幅整理，各個組件的編譯步驟現在清楚分開、互不干擾，產出的結果也更容易重複還原。同時解決了第三方函式庫的整合問題，最終成功打包出只有 **6.7 MB** 的離線導航 APK。

實際在手機上的執行結果：

```
[VOG-L29] => osrm-extract（機車路線設定）=> 處理了 3,998,477 條道路邊
=> osrm-partition（4 層分區）
=> osrm-customize
=> osrm-routed 啟動於 port 5000 ✅ API 回應 < 25ms
=> libosrm_android.so 打包成功 ✅ BUILD SUCCESSFUL
```

## 環境需求

- Android NDK r30 以上（路徑固定在 `$HOME/Android/Sdk/ndk/30.0.14904198/`）
- Debian 13 / Ubuntu 24 以上的 Linux 編譯環境
- 台灣 OSM 地圖原始資料：`../myosm/osrm_data/taiwan-latest.osm.pbf`（約 310MB）

## 快速開始

```bash
# 1. 下載所有需要的第三方套件原始碼，並自動修補相容性問題
./scripts/fetch_deps.sh

# 2. 分模組編譯所有組件與 OSRM 核心（各步驟可單獨執行）
./scripts/build_all.sh

# 3. 組裝 Android JNI 橋接層，並打包成 APK
cd android
./gradlew clean
./gradlew assembleDebug
```

## 腳本說明

| 腳本 | 用途 | 說明 |
|------|------|------|
| `fetch_deps.sh` | 下載依賴 + 套用修補 | 下載 Boost 1.83、TBB、Lua 等套件，並自動將修正過的原始碼覆蓋回去 |
| `build_all.sh` | 一鍵分模組編譯 | 依序呼叫 `build_modules/` 底下各組件的獨立編譯腳本（01 ~ 09） |
| `package_artifacts.sh` | 打包整理 | 去除編譯產出檔案中的除錯符號，並複製到 Android 專案所需位置 |
| `deploy_moto.sh` | 機車地圖部署 | 推送工具到手機、在手機上執行地圖建置、啟動導航服務（共 6 個步驟） |

## 專案目錄結構

```
osrm-ndk/
├── ARCHITECTURE.md          # 整體架構設計說明
├── CHANGELOG.md             # 版本變更記錄
├── MEMOIR.md                # 開發過程回顧與設計決策說明
├── MODULAR_BUILD_PLAN.md    # 分模組編譯系統的設計規劃文件
├── README.md                # 本文件
├── osrm-backend-plus/       # 🏆 修補後的 OSRM 原始碼（防止被官方原始碼覆蓋）
│   ├── src/storage/         # 移除不相容 Android 的系統呼叫的 storage.cpp
│   ├── src/engine/datafacade/ # 調整過、符合 Android NDK 限制的共享記憶體管理程式
│   └── third_party/         # 針對性修正、對齊 C++17 標準的 sol.hpp 與 rapidjson
├── scripts/
│   ├── fetch_deps.sh        # 下載套件原始碼並套用修補
│   ├── env_android.sh       # 統一設定編譯環境變數與工具鏈路徑
│   ├── build_all.sh         # 按照相依順序依序呼叫各子腳本
│   ├── package_artifacts.sh # 去除除錯符號並複製到正確位置
│   └── build_modules/       # 各組件的獨立編譯腳本（01 ~ 09）
├── android/                 # Android 專案（Gradle）
│   ├── app/
│   │   └── src/main/
│   │       ├── java/.../    # Java/Kotlin 應用程式主體（背景服務 + 畫面）
│   │       └── jni/         # C++ 與 Java 的橋接層 + CMake 編譯設定
│   └── build.gradle.kts
└── build_android/           # 編譯輸出目錄
    ├── install/lib/         # OSRM 核心靜態函式庫（libosrm.a 等）
    └── install/android-24/arm64-v8a/lib/  # 支援位置無關程式碼的第三方靜態函式庫
```

## 開發階段

| 階段 | 目標 | 狀態 |
|------|------|------|
| **0** | 將 OSRM 編譯成可在 Android ARM64 上執行的工具 | [X] v5.27.1，相容 NDK r30 |
| **0a** | 在手機上執行機車地圖建置（MLD 格式） | [X] 3.99M 條道路邊，4 層分區 |
| **1s** | 簡化版 APP（用 ProcessBuilder 呼叫工具）| [X] 自含式 APK + 儀表板 |
| **1** | Android 背景服務 + C++/Java 橋接層 | [X] 橋接層整合完成，函式庫打包成功 |
| **2** | 離線地圖下載管理功能 | [ ] 待開發 |
| **3** | 整合 myosm 前端地圖介面 | [ ] 待開發 | 

