---
name:          "DISCUSSION.md"
description:   "MyOSM 離線手機 APP 轉型架構評估與討論"
created_date:  "2026/05/27 12:00:00"
modified_date: "2026/05/27 16:50:00"
project_version: "0.3.0"
document_version: "1.1.0"
agent_sign: ['opencode/current_agent']
---

# MyOSM 離線手機 APP 轉型架構評估與討論

此文件紀錄了將 MyOSM (基於 OSRM 與 Leaflet 的台灣機車多點配送系統) 從 Web 網頁應用轉型為**完全離線的手機 APP (iOS/Android)** 的技術評估與實作策略。

## 一、 核心概念與關鍵挑戰

要讓手機在「斷網」的情況下還能做多點配送 (TSP) 與路徑規劃，核心概念是：**將伺服器端執行的 OSRM 路由引擎搬進手機的本地端 (Localhost) 執行。**

### 1. 記憶體消耗 (Memory Limit)
OSRM 為了追求極致的計算速度，會將大量路網資料載入記憶體。台灣全島資料處理後可能膨脹至數百 MB 甚至超過 1GB。
* **策略**：在手機上強烈建議改用 **MLD (Multi-Level Dijkstra)** 演算法取代 CH (Contraction Hierarchies)，以大幅降低記憶體佔用。
* **風險**：若瞬間記憶體消耗過大，容易觸發 iOS/Android 作業系統的 Low Memory Killer 導致 APP 閃退。

### 2. 圖資預處理 (Pre-processing)
手機的 CPU 不適合執行繁重的圖資建置作業 (`osrm-extract` 或 `osrm-contract`)。
* **策略**：所有圖資處理、Lua 腳本解析，都必須在雲端或電腦端提前完成。APP 啟動後只需下載建置好的 `.osrm` 二進制資料檔。

### 3. 離線底圖顯示 (Offline Map Tiles)
純離線狀態下無法使用線上的 OpenStreetMap 圖塊。
* **策略 1**：將地圖轉為 `.mbtiles`，搭配 Leaflet 外掛讀取本地圖塊。
* **策略 2 (推薦)**：改用 **MapLibre GL Native** 並載入離線的向量圖塊 (Vector Tiles)，以獲得如原生 APP 般的流暢度與 3D 視角。

---

## 二、 應用程式架構方案

要讓前端能跟 OSRM 溝通，有以下幾種主要架構：

### 方案 A：Local HTTP Server (最容易移植現有 Web 專案)
在手機 App 的背景啟動一個微型的 HTTP Server，內部整合 `libosrm` 並暴露與原本相同的 HTTP API。前端透過 WebView (如 Capacitor/Cordova) 直接打 API 給 `http://localhost:5000`。
* **優缺點**：前端幾乎不用改，但背景 Server 容易有耗電與被系統砍掉的風險。

### 方案 B：Native Bridge 整合 (效能最好，推薦商業應用)
直接將 `libosrm` 編譯給 Android (JNI) 與 iOS (Objective-C++) 使用。前端透過 React Native、Flutter 或原生開發，呼叫 Bridge 方法直接獲取 JSON 結果。
* **優缺點**：效能最佳、無網路層開銷，但需撰寫 C++ 與 Java/Swift 之間的串接層。

### 方案 C：WebAssembly (WASM) (實驗性質)
將 `libosrm` 編譯成 WebAssembly，完全在前端瀏覽器執行。
* **優缺點**：純前端方案，但載入數百 MB 圖資極易導致 WebView 記憶體崩潰，不適合全台灣等級的大型圖資。

---

## 三、 開發部署流程與 PoC 策略

將 `libosrm` C++ 庫成功運行於 ARM 架構的手機上，是整個專案的**生死線 (Make or Break)**。必須採用 **由底層到上層 (Bottom-Up)** 的開發順序，優先進行概念驗證 (PoC)。

### PoC (概念驗證) 步驟建議

為了驗證交叉編譯可行性與記憶體消耗，建議分階段進行：

#### 階段一：Termux 快速驗證 [X] → 跳過（直接使用 NDK 交叉編譯）
1. 在 Android 手機安裝 Termux。
2. 安裝必要的編譯工具 (`clang`, `cmake`, `boost` 等)。
3. 在手機上直接編譯 OSRM 原始碼，產出 `osrm-routed`。
4. 放入預先建置好的台灣 `.osrm` 資料 (MLD)。
5. 執行 `osrm-routed --algorithm mld taiwan.osrm`，觀察是否能成功啟動並監控記憶體消耗。
> 最終選擇跳過 Termux，直接以 NDK 交叉編譯產出 v5.27.1 的 `osrm-routed` binary。

#### 階段二：Android NDK 最小化測試 [X] → 改採 Phase 1s (ProcessBuilder)
1. 建立最小化的 Android NDK 專案。
2. 配置 CMake 進行 ARM64 交叉編譯 (處理 Boost, TBB 等依賴)。
3. 撰寫簡易 JNI 函式，使用 `#include <osrm/osrm.hpp>` 初始化引擎並進行單次路徑規劃。
4. 透過簡單的 Android 按鈕觸發，測試在作業系統限制下是否能順利算出路線且不閃退。
> 最終改以 ProcessBuilder 啟動獨立 binary (Phase 1s)，跳過 JNI bridge 的 C++ 相容性問題。

### 後續移植路徑

1. [/] 完善 Bridge 介面 → 以 ProcessBuilder 替換 JNI bridge (Phase 1s 已完成)
2. [ ] 實作離線圖塊下載與渲染 (MBTiles/MapLibre) → Phase 2
3. [ ] 將 Web 端的多點配送 (TSP) 互動邏輯移植為 APP UI → Phase 3

> **替代方案備忘**：若 PoC 發現 OSRM 在手機上過於耗用資源，可評估轉向其他對行動裝置與記憶體更友善的開源引擎，如 **Valhalla** (C++) 或 **GraphHopper** (Java)。
