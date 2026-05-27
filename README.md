---
name:          "README.md"
description:   "OSRM Android NDK — 將 OSRM v5.27.1 路由引擎交叉編譯至 Android ARM64，手機端編譯機車 (motorcycle.lua) MLD 圖資"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 16:15:00"
project_version: "0.3.0"
document_version: "1.2.0"
agent_sign: ['opencode/current_agent']
---

# OSRM Android NDK 專案

將 OSRM C++ 路由引擎交叉編譯至 Android ARM64，以 APK 形式在手機端運行自含式路由服務，並透過 WebView 儀表板進行監控與管理。

## 里程碑：v0.3.0 — 自含式 Android APK 路由服務

```
[VOG-L29] => osrm-extract --profile motorcycle.lua => 3,998,477 edges
         => osrm-partition (4-level MLD)
         => osrm-customize
         => osrm-routed @ port 5000  ✅ API 回應 < 25ms
```

## 前置需求

- Android NDK r26+ (自動偵測 `$HOME/Android/Sdk/ndk/`)
- Android 裝置 (API 24+, USB 偵錯開啟)
- 台灣 OSM 圖資：`../myosm/osrm_data/taiwan-latest.osm.pbf` (~310MB)

## 快速開始

```bash
# 1. 下載所有相依原始碼 (僅需一次)
./scripts/fetch_deps.sh

# 2. 交叉編譯 OSRM for Android ARM64
./scripts/build_osrm_android.sh

# 3. 手機端編譯機車圖資 + 啟動路由引擎 (6 階段，支援斷點恢復)
./scripts/deploy_moto.sh
```

## 腳本說明

| 腳本 | 用途 | 說明 |
|------|------|------|
| `fetch_deps.sh` | 下載依賴 | Boost 1.83, TBB, Lua 5.3, zlib, expat, bzip2, libxml2, civetweb, OSRM v5.27.1 |
| `build_osrm_android.sh` | 交叉編譯 | NDK 工具鏈 → ARM64 靜態庫 + osrm-* binary |
| `deploy.sh` | 快速部署 | Push osrm-routed + 既有圖資至手機 |
| `deploy_moto.sh` | 機車圖資部署 | **Push 工具鏈 + 手機端編譯 + 啟動** (6-phase checkpoint) |
| `toolchain.cmake` | CMake 工具鏈 | Android NDK cross-compilation |

## 專案結構

```
osrm-ndk/
├── ARCHITECTURE.md          # 完整架構規劃書
├── CHANGELOG.md             # 變更記錄
├── MEMOIR.md                # 開發回顧與設計決策
├── README.md                # 本文件
├── scripts/
│   ├── fetch_deps.sh        # 下載相依套件原始碼
│   ├── build_osrm_android.sh# 交叉編譯主腳本
│   ├── deploy.sh            # 快速部署 (既有圖資)
│   ├── deploy_moto.sh       # 機車圖資手機端編譯 (checkpoint)
│   └── toolchain.cmake      # Android NDK CMake toolchain
├── android/                 # Android 專案 (Gradle)
│   ├── app/
│   │   └── src/main/
│   │       ├── java/.../    # Java/Kotlin (Service + Activity)
│   │       └── jni/         # JNI bridge + HTTP server
│   └── build.gradle.kts
├── build_android/           # 編譯產出
│   ├── install/bin/         # osrm-extract, osrm-partition, osrm-customize, osrm-routed (ARM64)
│   └── output/osrm-routed   # 部署用 binary
├── deps/osrm-backend/       # OSRM v5.27.1 原始碼
│   └── profiles/lib/        # Lua 程式庫 (含 obstacles.lua 相容層)
├── osrm_data_v5271/         # 預編譯 v5.27 圖資 (CH)
└── myosm -> ../myosm        # Docker 版專案 (motorcycle.lua, osrm_data/)
```

## Phases

| Phase | 目標 | 狀態 |
|-------|------|------|
| **0** | NDK 交叉編譯 OSRM binary | ✅ v5.27.1 for ARM64 |
| **0a** | 手機端機車圖資編譯 (MLD) | ✅ 3.99M edges, 4-level partition |
| **1** | Android Service + JNI bridge | ⬜ 待開發 |
| **2** | 離線圖資下載管理 | ⬜ 待開發 |
| **3** | WebView 整合 myosm 前端 | ⬜ 待開發 |
