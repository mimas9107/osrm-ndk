---
name:          "README.md"
description:   "OSRM Android NDK — 將 OSRM v5.27.1 路由引擎交叉編譯至 Android ARM64，手機端編譯機車 (motorcycle.lua) MLD 圖資"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/29 11:10:00"
project_version: "0.4.6"
document_version: "1.4.1"
agent_sign: ['opencode/current_agent', 'antigravity/current_agent']
---

# OSRM Android NDK 專案

將 OSRM C++ 路由引擎交叉編譯至 Android ARM64，以 APK 形式在手機端運行自含式路由服務，並透過 WebView 儀表板進行監控與管理。

## 里程碑：v0.4.6 — 模組化建構系統細節矯正與總驗證 🚀

專案已全線完成「模組化、高內聚、低耦合」的建構系統重構，實現了高再現性的 Out-of-source 編譯流程與物理隔離機制，並將 `libxml2` 靜態熔煉閉合，成功產出僅 6.7 MB 的離線導航 APK 套件。

[VOG-L29] => osrm-extract --profile motorcycle.lua => 3,998,477 edges
=> osrm-partition (4-level MLD)
=> osrm-customize
=> osrm-routed @ port 5000 ✅ API 回應 < 25ms
=> libosrm_android.so 融合大會師 ✅ BUILD SUCCESSFUL

## 前置需求

- Android NDK r30+ (精準鎖定 `/home/mimas/Android/Sdk/ndk/30.0.14904198/`)
- Debian 13 / Ubuntu 24+ 主機建構環境
- 台灣 OSM 圖資：`../myosm/osrm_data/taiwan-latest.osm.pbf` (~310MB)

## 快速開始

```bash
# 1. 下載相依原始碼並自動發動「影子安全屋」物理矯正 (100% 免疫官方死碼覆蓋)
./scripts/fetch_deps.sh

# 2. 模組化交叉編譯所有組件與 OSRM 核心大軍 (支援 Out-of-source 分步構建)
./scripts/build_all.sh

# 3. Android 前端 JNI 總裝配與 APK 打包 (絕對路徑焊死版，自動化閉環)
cd android
./gradlew clean
./gradlew assembleDebug
```

## 腳本說明

| 腳本 | 用途 | 說明 |
|------|------|------|
| `fetch_deps.sh` | 下載依賴 + 物理注入 | 拉取 Boost 1.83, TBB, Lua, 並在最尾端自動將 `osrm-backend-plus` 骨架強行灌回硬碟 |
| `build_all.sh` | 一鍵模組化編譯 | 調用 `build_modules/` 下各組件的獨立建構腳本 (01 ~ 09) 進行 Out-of-source 編譯 |
| `package_artifacts.sh`| 物理矯正封裝 | 進行二進位 Strip 符號消除與 jniLibs 目錄複製 |
| `deploy_moto.sh` | 機車圖資部署 | **Push 工具鏈 + 手機端編譯 + 啟動** (6-phase checkpoint) |

## 專案結構

```
osrm-ndk/
├── ARCHITECTURE.md          # 完整架構規劃書
├── CHANGELOG.md             # 變更記錄
├── MEMOIR.md                # 開發回顧與設計決策
├── MODULAR_BUILD_PLAN.md    # 模組化建構系統設計計畫書
├── README.md                # 本文件
├── osrm-backend-plus/       # 🏆 影子安全屋 (100% 版控正確代碼，防範官方原始碼覆蓋)
│   ├── src/storage/         # 掏空 System V 函數的空殼 storage.cpp 實作
│   ├── src/engine/datafacade# 完美咬合 NDK 參數與 vtable 簽名的 shared_memory_allocator.cpp
│   └── third_party/         # 精準單點手術修正、對齊 C++17 標準的 sol.hpp 與 rapidjson
├── scripts/
│   ├── fetch_deps.sh        # 自我修復版 — 下載相依套件原始碼並發動影子合流
│   ├── env_android.sh       # [核心] 統一環境變數設定與工具鏈配置
│   ├── build_all.sh         # [編排] 一鍵編排，按拓撲順序呼叫子腳本
│   ├── package_artifacts.sh # [封裝] 物理矯正，負責二進位複製與 strip
│   └── build_modules/       # [模組] 各組件獨立建構腳本 (01 ~ 09)
├── android/                 # Android 專案 (Gradle)
│   ├── app/
│   │   └── src/main/
│   │       ├── java/.../    # Java/Kotlin (Service + Activity)
│   │       └── jni/         # JNI bridge + CMakeLists.txt (100% 絕對路徑與降級旗標銲死版)
│   └── build.gradle.kts
└── build_android/           # 編譯產出
    ├── install/lib/         # OSRM 核心靜態庫實體大軍 (libosrm.a 等)
    └── install/android-24/arm64-v8a/lib/  # 帶有 -fPIC 裝甲的第三方靜態庫
```

## Phases

| Phase | 目標 | 狀態 |
|-------|------|------|
| **0** | NDK 交叉編譯 OSRM binary | [X] v5.27.1 for ARM64 (與 NDK r30 世紀對齊) |
| **0a** | 手機端機車圖資編譯 (MLD) | [X] 3.99M edges, 4-level partition |
| **1s** | Phase 1 Simplified (ProcessBuilder) | [X] 自含式 APK + 儀表板 |
| **1** | Android Service + JNI bridge | [X] 總裝配完美合流 (JNI bridge + 核心庫 100% 連結打包成功) |
| **2** | 離線圖資下載管理 | [ ] 待開發 |
| **3** | WebView 整合 myosm 前端 | [ ] 待開發 |
