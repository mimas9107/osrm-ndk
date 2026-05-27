---
name:             "MEMOIR.md"
description:      "OSRM Android NDK — 自含式 APK 路由服務完整工程回顧"
created_date:     "2026/05/27 15:00:00"
modified_date:    "2026/05/27 17:20:00"
project_version:  "0.4.0"
document_version: "1.3.0"
agent_sign: ['opencode/current_agent']
---

# MEMOIR — 完整工程回顧

## 跨架構手機端機車圖資編譯：從版本鴻溝到 21ms 路由回應

> 本文件記錄將 OSRM v5.27.1 交叉編譯為 Android ARM64，並在手機 (VOG-L29) 上以 `motorcycle.lua` profile 完成 MLD 圖資全流程編譯的工程歷程。每一步遇到的障礙、根因分析、解法與教訓，按時間順序列舉。

---

## 目錄

1. [問題根源：Docker v26 與 binary v5.27 版本鴻溝](#1-版本鴻溝)
2. [NDK 交叉編譯：ARM64 工具鏈的建構](#2-交叉編譯)
3. [資料目錄謎團：CH vs MLD 格式不相容](#3-資料目錄)
4. [Lua Profile 的版本依賴：從 v26 向後相容 v5.27](#4-lua-profile-相容層)
5. [最隱蔽的 Bug：ipairs 遇 nil 截斷 handler chain](#5-ipairs-截斷)
6. [obstacles.lua 的 Global 作用域陷阱](#6-obstacles-全域)
7. [手機端編譯的完整錯誤歷程](#7-錯誤歷程)
8. [驗證與效能數據](#8-驗證)
9. [教訓與工程原則](#9-教訓)

---

## 1. 版本鴻溝

### 1.1 問題敘述

```
既有流程:
  Docker (osrm/osrm-backend) → 編譯圖資 → push 到手機 → osrm-routed (v5.27.1) 服務

現實:
  Docker image 已升級至 v26.x
  ├── .osrm 內部二進位格式與 v5.27 不相容
  └── Lua profile API 層級不同 (obstacles API 僅 v26+ 有)
  
  手機端 binary: v5.27.1 (NDK 交叉編譯)
  無法讀取 Docker v26 產出的 .osrm 檔案
```

**證據** — `./osrm_data_v5271/` 目錄僅有 7 個檔案，且是 CH (Contraction Hierarchies) 格式：

```
osrm_data_v5271/                          myosm/osrm_data/ (v5.27 Docker)
  taiwan-latest.osrm.cnbg      18M           taiwan-latest.osrm.cell_metrics  382M  ← MLD only
  taiwan-latest.osrm.cnbg_to_ebg 18M         taiwan-latest.osrm.cells         2.4M  ← MLD only
  taiwan-latest.osrm.names     2.9M          taiwan-latest.osrm.ebg           99M   ← MLD only
  taiwan-latest.osrm.nbg_nodes  45M          taiwan-latest.osrm.mldgr        102M   ← MLD only
  taiwan-latest.osrm.properties 6K           taiwan-latest.osrm.partition     17M   ← MLD only
  taiwan-latest.osrm.timestamp  3.5K         ... (28 files total, vs 7)
```

`.cnbg` / `.cnbg_to_ebg` / `.nbg_nodes` 是 CH 演算法的產物。我們的 binary 跑 `--algorithm mld`，需要 `.mldgr`、`.cell_metrics`、`.partition` 等檔案，這些在 `osrm_data_v5271/` 中完全不存在。

### 1.2 解法決策

| 方案 | 分析 | 決定 |
|------|------|------|
| 重建 Docker v5.27 image | 需維護舊版 Dockerfile，且版本鎖定 | ❌ |
| 重跑 Docker v26 編譯 | 格式不相容，讀取時 crash | ❌ |
| **手機端 native 編譯** | 不需 Docker；ARM64 binary 已編好；profile 在手機執行完全相容 | ✅ |

**關鍵洞察**：既然 `build_osrm_android.sh` 已經成功編譯出 `osrm-extract`、`osrm-partition`、`osrm-customize` 等 ARM64 工具，為什麼不直接在手機上跑整條 pipeline？

---

## 2. 交叉編譯

### 2.1 工具鏈

```
Host: x86_64 Linux
NDK: r30-beta1
Target: arm64-v8a, API 24 (Android 7.0+)
Toolchain: llvm/prebuilt/linux-x86_64
```

### 2.2 編譯產物

```
build_android/install/bin/
  osrm-extract     82 MB    ← 靜態連結 Lua 5.3.6, zlib, expat, bzip2, libxml2, TBB, Boost
  osrm-partition    15 MB    ← 只依賴 TBB + Boost
  osrm-customize    38 MB    ← 只依賴 TBB + Boost
  osrm-routed      2.9 MB    ← 只依賴 civetweb (strip 後)

所有 binary 共用同一組動態連結需求:
  $ readelf -d osrm-extract | grep NEEDED
    libm.so    ← Android 系統內建
    libdl.so   ← Android 系統內建
    libc.so    ← Android 系統內建

無 root 需求，無 APK 包裝，直接 adb push 即可執行。
```

### 2.3 依賴地圖

```
deps/
├── boost_1_83_0/        → libboost_program_options.a, libboost_filesystem.a, ...
├── oneTBB/              → libtbb.a
├── lua-5.3.6/           → liblua.a (嵌入式於 osrm-extract)
├── zlib/                → libz.a
├── libexpat/            → libexpat.a
├── bzip2-1.0.8/         → libbz2.a
├── libxml2/             → libxml2.a
├── civetweb/            → libcivetweb.a (嵌入式 HTTP 伺服器)
└── osrm-backend/        → v5.27.1, profiles/lib/ (14 個 Lua 模組)
```

**注意**：`osrm-backend/` 內的 `profiles/lib/` 僅有 14 個標準模組，沒有 `obstacles.lua`（該檔案是 v26+ 新增）。

---

## 3. 資料目錄

### 3.1 第一個 deploy 腳本的 Bug

原始的 `deploy.sh` 第 19 行：

```bash
OSRM_DATA="${OSRM_DATA_DIR:-$PROJECT_DIR/../myosm/osrm_data}"
```

這指向的是 `myosm/osrm_data/` — 該目錄包含的資料是由 Docker v26 編譯的（注意 `.mldgr`、`.cell_metrics` 等 MLD 檔案的時間戳都是 `May 26`，而我們 v5.27 binary 是 `May 27` 編譯的）。

但 `osrm_data_v5271/` 是空殼 — 只有 7 個 CH 檔案，無法用於 MLD。

### 3.2 資料檔案對照表

| 檔案 | MLD 必要 | osrm_data_v5271 | myosm/osrm_data | 手機端編譯產出 |
|------|----------|-----------------|-----------------|---------------|
| `.osm.pbf` (原始) | ✅ | ✅ | ✅ | ✅ (sideload) |
| `.osrm.ebg` | ✅ EdgeBasedGraph | ❌ | ✅ 99MB | ✅ 99MB |
| `.osrm.ebg_nodes` | ✅ | ❌ | ✅ 26MB | ✅ 26MB |
| `.osrm.partition` | ✅ MLD | ❌ | ✅ 17MB | ✅ 16MB |
| `.osrm.cells` | ✅ MLD | ❌ | ✅ 2.4MB | ✅ 2.3MB |
| `.osrm.mldgr` | ✅ MLD | ❌ | ✅ 102MB | ✅ 102MB |
| `.osrm.cell_metrics` | ✅ MLD | ❌ | ✅ 382MB | ✅ 381MB |
| `.osrm.cnbg` | ❌ CH only | ✅ 18MB | ✅ 18MB | ✅ 17MB |
| `.osrm.nbg_nodes` | ❌ CH only | ✅ 45MB | ✅ 45MB | ✅ 44MB |

**教訓**：`osrm_data_v5271/` 是 CH 編譯的殘留產物，不能用於 MLD。真正的 v5.27 資料在 `myosm/osrm_data/`，但那也是 Docker 編譯的，而 Docker 已是 v26。

唯一可靠的解法：**從原始 `.osm.pbf` 開始，用手機端的 v5.27 binary 重新編譯**。

---

## 4. Lua Profile 相容層

### 4.1 問題

`motorcycle.lua` 是為 OSRM v26+ 撰寫的，使用了 v26+ C++ glue 層注入的全域變數：

```lua
-- motorcycle.lua 依賴的全域變數 (v26+ C++ glue 注入)
obstacle_type      → enum { barrier=1, gate=2, traffic_signals=3, stop=4, ... }
obstacle_direction → enum { none=0, forward=1, backward=2, both=3 }
Obstacle           → class (建構子 new)
obstacle_map       → 全域物件 (add/get 方法)

-- v5.27 完全沒有這些變數
```

### 4.2 obstacles.lua 相容層設計

在 `myosm/obstacles.lua` 中模擬 C++ 注入行為：

```lua
-- obstacles.lua (相容層)
-- 不在 v5.27 的 profiles/lib/ 中 → 手動新增

-- 模擬 C++ 注入的全域變數
obstacle_type = { barrier=1, gate=2, ... }
obstacle_direction = { none=0, forward=1, backward=2, both=3 }

Obstacle = {}  -- 全域 (非 local!)
Obstacle.__index = Obstacle
function Obstacle.new(otype, direction, duration, weight)
  return setmetatable({...}, Obstacle)
end

obstacle_map = { _obstacles = {} }
function obstacle_map:add(node, obstacle) ... end
function obstacle_map:get(from, via)
  -- 防衛：from/via 在邊界節點可能為 nil
  if not from or not via then return {} end    ← 關鍵修復
  ...
end
```

**來源**：從 OSRM GitHub master branch 的 `profiles/lib/obstacles.lua` 移植，再補上 v5.27 缺少的全域變數定義。

### 4.3 檔案位置

```
deps/osrm-backend/profiles/lib/
├── obstacles.lua          ← 新增 (v26+ 原始碼 + v5.27 相容補丁)
├── set.lua
├── sequence.lua
├── way_handlers.lua
├── access.lua
├── maxspeed.lua
├── utils.lua
├── measure.lua
└── ... (15 files total)
```

---

## 5. ipairs 遇 nil 截斷

### 5.1 根因

`motorcycle.lua` 的 `process_way` handler chain 包含了在 v5.27 中不存在的函數：

```lua
handlers = Sequence {
  WayHandlers.default_mode,        -- index 1  ✅
  WayHandlers.blocked_ways,        -- index 2  ✅
  ...
  WayHandlers.speed,               -- index 15 ✅
  WayHandlers.maxspeed,            -- index 16 ✅
  WayHandlers.surface,             -- index 17 ✅
  WayHandlers.vehicle_speed_cap,   -- index 18 → nil (不存在於 v5.27!)
  WayHandlers.penalties,           -- index 19 → ipairs 永遠不會到達！
  WayHandlers.classes,             -- index 20
  WayHandlers.turn_lanes,          -- index 21
  WayHandlers.classification,      -- index 22
  WayHandlers.roundabouts,         -- index 23
  WayHandlers.startpoint,          -- index 24 ← 沒有此 handler，way 不能當起點！
  WayHandlers.driving_side,        -- index 25
  WayHandlers.names,               -- index 26 ← 沒有此 handler，way 無名稱！
  WayHandlers.weights,             -- index 27 ← 沒有此 handler，way 無權重！
  WayHandlers.way_classification_for_turn,  -- index 28
}
```

### 5.2 Lua ipairs 行為

```lua
-- 在 Lua 中：
local t = { "a", "b", nil, "d", "e" }
for i, v in ipairs(t) do
  print(i, v)
end
-- 輸出：
-- 1 a
-- 2 b
-- ← ipairs 在 index 3 遇到 nil，立即停止！"d" 和 "e" 永遠不會被迭代

-- 且 "d" 和 "e" 仍然在 table 中！
print(t[4])  -- "d"
print(t[5])  -- "e"
-- 但 ipairs 看不到它們
```

### 5.3 影響分析

被跳過的 handler 及其影響：

| 跳過的 Handler | 影響 |
|---------------|------|
| `WayHandlers.penalties` | `forward_rate` / `backward_rate` 未設定 → **無 edges 產出** |
| `WayHandlers.startpoint` | way 不能被設為起點 → 路由請求找不到起點 |
| `WayHandlers.names` | way 的 name/ref 未設定 → 導航指令無路段名稱 |
| `WayHandlers.weights` | edge weight 為預設值 → 路徑計算可能異常 |
| `WayHandlers.roundabouts` | 圓環邏輯未套用 → 導航指令錯誤 |

**最嚴重的影響**：`penalties` handler 負責計算 `forward_rate` 和 `backward_rate`（公式：`speed × penalty / 3.6`）。在 'routability' 權重模式下，若 rate 未設定（保留預設值 -1），`ExtractorCallbacks::ProcessWay()` 中的邊緣建立邏輯會因 rate 無效而跳過，導致 **0 edges 被建立**。

### 5.4 錯誤訊息

```
[info] Raw input contains 24906531 nodes, 1834530 ways, and 7656 relations, 2481 restrictions
libc++abi: terminating due to uncaught exception of type N4osrm4util9exceptionE:
  There are no edges remaining after parsing.
src/extractor/extractor.cpp:612
```

注意：parsing 本身成功（65 秒，1.8M ways），但 edge 建立階段發現 `all_edges_list` 為空。

### 5.5 解法

```lua
-- 在 motorcycle.lua 中，與 way_handlers.lua 加載之後：
if not WayHandlers.vehicle_speed_cap then
  function WayHandlers.vehicle_speed_cap(profile, way, result, data, relations)
    -- v5.27 相容：空函數，確保 handler chain 不被截斷
  end
end
```

### 5.6 工程教訓

**`ipairs` 遇 nil 截斷是 Lua 中已知但容易被忽略的行為**。在 handler chain pattern 中，任何一個 handler 為 nil 都會導致 chain 在無任何錯誤訊息的情況下被截斷。

OSRM 的 `WayHandlers.run()` 沒有對 `nil handler` 做防衛：

```lua
function WayHandlers.run(profile, way, result, data, handlers, relations)
  for i,handler in ipairs(handlers) do
    if handler(profile, way, result, data, relations) == false then
      return false
    end
  end
end
```

若 `handler` 為 nil，Lua 在 `nil(...)` 時會拋出 "attempt to call a nil value" — 但 **`ipairs` 在到達 nil index 時就停止了，根本不會嘗試呼叫它**。錯誤不會發生，只是 chain 斷了。

---

## 6. obstacles.lua 作用域陷阱

### 6.1 問題

第一次撰寫 `obstacles.lua` 時，將 `Obstacle` 定義為 `local`：

```lua
local Obstacle = {}           ← local！只在 obstacles.lua 模組內可見
Obstacle.__index = Obstacle
function Obstacle.new(...) ... end

-- motorcycle.lua 中：
Obstacle.new(obstacle_type.barrier)  ← 錯誤：Obstacle 是 nil！
```

### 6.2 錯誤訊息

```
lua: error: /data/local/tmp/moto_data/taiwan-moto.lua:406:
  attempt to index a nil value (global 'Obstacle')
```

### 6.3 全域 vs 模組區域

原始 v26+ 的設計中，`Obstacle`、`obstacle_map`、`obstacle_type`、`obstacle_direction` 是由 **C++ 引擎注入為全域變數**，不是透過 `require("lib/obstacles")` 回傳的。

`obstacles.lua` 模組只是使用了這些全域變數，並沒有定義它們。

我們的相容層必須同時做到：

```lua
-- 1. 定義全域變數 (模擬 C++ 注入)
Obstacle = {}
obstacle_map = { ... }
obstacle_type = { ... }
obstacle_direction = { ... }

-- 2. 回傳模組函數 (給 require 使用)
local Obstacles = {}
function Obstacles.process_node(profile, node) ... end
function Obstacles.entering_by_minor_road(turn) ... end

return Obstacles
```

---

## 7. 完整錯誤歷程

以下按時間順序列出每一輪部署的遭遇、根因與修復：

### Run 1: lib/ 目錄巢狀錯誤

```
$ adb push deps/osrm-backend/profiles/lib/ /data/local/tmp/moto_data/lib/

→ 手機端變成 /data/local/tmp/moto_data/lib/lib/set.lua
  (adb push 行為：source 目錄名為 lib，自動在 dst 下建立 lib/ 並放入內容)

錯誤: module 'lib/set' not found
```

**根因**：`adb push src/ dst/` 的目錄語意。source 為 `/path/lib/` (trailing slash)，dst 為 `/data/.../lib/` → adb 在 dst 下建立 `lib/lib/`。

**修復**：先 `rm -rf /data/.../lib`，再 `adb push profiles/lib /data/.../moto_data/` (無 trailing slash)。

---

### Run 2: Obstacle 為 nil

```
錯誤: attempt to index a nil value (global 'Obstacle')
```

**根因**：`obstacles.lua` 中定義了 `local Obstacle = {}`，但 `motorcycle.lua` 期望它是全域變數。

**修復**：移除 `local`，改為 `Obstacle = {}`。

---

### Run 3: 0 edges (ipairs 截斷)

```
Parsing finished → 1.8M ways processed → 0 edges
libc++abi: There are no edges remaining after parsing.
```

**根因**：`WayHandlers.vehicle_speed_cap` 為 nil → `ipairs` 於 index 18 停止 → `penalties` handler 未執行 → `forward_rate` 未設定 → 0 edges。

**修復**：補上 `WayHandlers.vehicle_speed_cap` 空函數。

---

### Run 4: obstacles.lua nil node

```
osrm-extract 成功！3,998,477 edges 建立
→ Generating edge-expanded edges
→ lua: error: obstacles.lua:48: attempt to index a nil value (local 'from')
```

**根因**：`process_turn` 階段，邊界節點的 `turn.from` 或 `turn.via` 可能為 nil。`obstacle_map:get(from, via)` 直接對 nil 呼叫 `from:id()`。

**修復**：在 `get()` 中加入 nil 防衛：

```lua
function obstacle_map:get(from, via)
  if not from or not via then return {} end  ← 防衛
  ...
end
```

---

### Run 5: ✅ 成功

```
extraction finished after 68.568s → 3,998,477 edges
osrm-partition → 4-level MLD (10382/805/51/4 cells), 41s
osrm-customize → MLD complete, 27s
osrm-routed → listening on 0.0.0.0:5000

curl http://localhost:5000/route/v1/driving/121.5,25.0;121.55,25.05
→ {"code":"Ok","routes":[{"legs":[{"distance":9297.7,"duration":1004.5}]}]}
→ 21ms latency
```

---

## 8. 驗證與效能

### 8.1 最終手機端資料

```
/data/local/tmp/moto_data/
├── taiwan-moto.lua                  (motorcycle.lua, 17KB)
├── taiwan-moto.osm.pbf              (原始圖資, 310MB)
├── lib/                             (15 Lua 模組, 含 obstacles.lua)
└── taiwan-moto.osrm.*               (26 個二進位檔, ~1.1GB)
    ├── .cell_metrics  381MB         ← MLD cell 權重
    ├── .mldgr         102MB         ← MLD 圖層
    ├── .ebg            99MB         ← EdgeBasedGraph
    ├── .geometry       88MB         ← 道路幾何
    ├── .fileIndex      76MB         ← R-tree 空間索引
    ├── .turn_penalties_index 49MB   ← 轉向罰則
    └── ...
```

### 8.2 資源使用

| 階段 | 時間 | RAM 峰值 | 核心數 |
|------|------|----------|--------|
| osrm-extract | 68.6s | 1,538 MB | 8 |
| osrm-partition | 41.3s | 555 MB | 8 |
| osrm-customize | 27.0s | 1,060 MB | 8 |
| osrm-routed (運行) | — | ~600–1,000 MB | 1–2 |

### 8.3 路由品質

```
Request:  121.5,25.0 → 121.55,25.05 (台北市中心, ~5km 直線)
Response: 9,297.7m, 1,004.5s (~16.7 min)
Latency:  21.3ms

特徵:
  - 無高速公路 (motorway speed=0, avoid set)
  - 市區低速 (residential=20km/h, primary=40km/h)
  - Taiwan 速限表生效 (maxspeed_table["tw:urban"]=50, ["tw:rural"]=60)
  - 迴轉罰則 20s, 轉向罰則 7.5s
```

---

## 9. 工程教訓

### 9.1 技術教訓

| # | 教訓 | 情境 |
|---|------|------|
| 1 | **Lua `ipairs` 遇 nil 截斷** | Handler chain 中缺失函數導致 chain 靜默截斷，無任何錯誤訊息 |
| 2 | **C++ glue 層的全域變數不可假設存在** | v5.27 無 `Obstacle`、`obstacle_map` 等全域變數，需手動定義 |
| 3 | **`adb push` 目錄語意** | trailing slash 會改變目錄結構 (`lib/` → `lib/lib/`) |
| 4 | **`.osrm` 不存在獨立的 marker file** | OSRM v5.27 不產出 `*.osrm` 檔案，檢查應用 `.osrm.properties` |
| 5 | **手機端 RAM 峰值 1.5GB** | extract 階段最吃記憶體，手機需 ≥4GB |
| 6 | **profile debug 佔 65% 時間** | 應先在 x86 環境驗證 Lua profile 語法 |

### 9.2 流程教訓

```
時間分佈:
  ┌─────────────────────────────────────────────┐
  │  環境檢查/授權        2min   (  5%)          │
  │  Push 工具 (140MB)    3s     ( <1%)          │
  │  Push 圖資 (310MB)    8s     (  2%)          │
  │  osrm-extract (run 1) 65s    ( 15%)          │
  │  ├─ debug profile ×3  ~5min  ( 65%)  ← 瓶頸 │
  │  osrm-partition       41s    ( 10%)          │
  │  osrm-customize       27s    (  7%)          │
  │  啟動驗證             3s     (  1%)          │
  └─────────────────────────────────────────────┘
```

65% 的時間花在 profile debug iteration。若有 x86 的 `osrm-extract` 可先在筆電驗證 Lua profile，再推到手機跑完整 pipeline，可將 debug 時間從 5 分鐘降至數秒。

### 9.3 Checkpoint 設計驗證

`deploy_moto.sh` 的 6-phase checkpoint 在這次開發中證明了價值：

- **筆電當機**: phase state 寫在 `/tmp/` (非同步至磁碟)，重開後需要 `--reset`
- **手機 crash**: extract 階段失敗 3 次，每次修正後 `--phase 2` 恢復，不需重新 push 310MB PBF
- **Phase file 存在性檢查**: `osrm.properties` → extract 完成；`.osrm.partition` → partition 完成；`.osrm.mldgr` → customize 完成。比 state file 更可靠，因為即使 state file 消失也可恢復

### 9.4 未來建議

1. **Profile 先行驗證**：在 x86 開發機上安裝 `osrm-extract`，先用小型 PBF 驗證 profile 語法
2. **`ipairs` 防衛**：在 `WayHandlers.run()` 中加入 nil handler 檢查並拋出明確錯誤
3. **Memory profiling**：記錄 extract/partition/customize 的記憶體使用，建立手機紅線指標
4. **USB tether fallback**：當 `adb` 不可用時，可透過 HTTP 上傳 PBF 到手機端 web service 觸發編譯

---

## 10. Phase 1 Simplified — 自含式 APK + 儀表板

### 10.1 問題：二進位部署路徑

OSRM 的二進位 (`osrm-routed`) 需打包進 APK，但 Android 的 .so 部署有兩種機制：

| 機制 | 路徑 | 可執行？ | 問題 |
|------|------|---------|------|
| jniLibs (AGP) | `<nativeLibDir>/libosrm_routed.so` | ✅ | AGP 8.2+ 預設不展開未載入的 .so |
| assets (自解) | `getFilesDir()/osrm-routed` | ❌ SELinux | `files/` 子目錄為 noexec |

**嘗試歷程：**

1. **jniLibs** → AGP 在 debug build 不展開 .so（`useLegacyPackaging=true` 無效）
2. **assets 解壓到 `files/`** → SELinux noexec → `error=13, Permission denied`
3. **assets 解壓到 app 根目錄** → 手動測試 `/data/user/0/com.osrm.android/libosrm_routed.so` 可執行 → 但 PackageManager 已劫持 `.so` 副檔名
4. **最終方案**: 二進位移到 `jniLibs/arm64-v8a/libosrm_routed.so` → PackageManager 在安裝時展開到 `<nativeLibDir>/libosrm_routed.so`

### 10.2 問題：WebView CORS

WebView 從 `file:///android_asset/www/dashboard.html` 載入內容，XHR 到 `http://127.0.0.1:5001/status` 被瀏覽器安全策略阻擋（`Access to XMLHttpRequest at 'http://127.0.0.1:5001/status' from origin 'null' has been blocked by CORS policy`）。

三種解法考量：

| 解法 | 複雜度 | 可靠性 |
|------|--------|--------|
| `setAllowUniversalAccessFromFileURLs(true)` | 低 | Android 29+ 可能不支援 |
| `usesCleartextTraffic="true"` | 低 | 只解 HTTPS 限制，不解 file→http 跨域 |
| **MonitorServer 同源提供靜態檔案** | 中 | 最可靠，同源無 CORS |

選擇第三種：MonitorServer 讀取 AssetManager 中的 dashboard.html/css/js，WebView 載入 `http://127.0.0.1:5001/`。

### 10.3 問題：按鈕無反應

兩個獨立問題：

1. **`showMsg` 未定義**: `doStart()`、`doStop()`、`doRestart()` 呼叫的 `showMsg()` 不曾定義 → ReferenceError
2. **JS 自動重啟迴圈**: `updateStatus()` 尾端有 `if (status === 'stopped' && auto_start) doStart()` → 使用者按停止後 3 秒 polling 看到 `stopped` 又自動啟動

修正：
- 加入 `showMsg()` 函數
- 改用一次性 `maybeAutoStart()`，首次載入只觸發一次

### 10.4 時序競爭：MonitorServer 重複綁定

`onStartCommand()` 在 Activity 重建（螢幕旋轉等）時被再次呼叫，`startMonitorServer()` 嘗試重新綁定 port 5001 造成 `EADDRINUSE`。修正：加入 `if (monitorServer == null || !monitorServer.isRunning())` 保護。

### 10.5 時序競爭：stopEngine → auto-restart

`stopEngine()` 和 `readEngineOutput()` 共享 `synchronized(this)` 鎖。`stopEngine()` 設定 `engineStopRequested=true` 並摧毀 process，`readEngineOutput()` 偵測到 process 退出後檢查此旗標。修正：在 `readEngineOutput()` 的 auto-restart 邏輯中加入二次 `synchronized(this)` 驗證 `!engineStopRequested`。

### 10.6 關鍵教訓

1. **AGP .so 行為**: AGP 8.2+ 在 debug build 不會展開 jniLibs（透過 `nativeLibraryDir` 可讀寫但檔案由 PackageManager 管理）。若需自訂 .so 部署路徑，需使用 `packaging.jniLibs.useLegacyPackaging = true`（API 23+ 有效）或直接從 assets 解壓。
2. **SELinux 上下文**: `getFilesDir()` 回傳的 `files/` 目錄有 `u:object_r:app_data_file:s0` context，標記為 noexec。app 資料根目錄則允許執行。
3. **WebView 跨域**: `file://` origin 的 XHR 到 `http://` 被視為跨域請求，`Access-Control-Allow-Origin: *` 無效。解決方案：同源提供資源。
4. **ForegroundService 生命週期**: `startForegroundService()` 是非同步的，`onStartCommand()` 在 `onCreate()` 之後執行。WebView 載入需要延遲或重試機制。
5. **JS polling 副作用**: 輪詢邏輯中的條件判斷（如自動啟動）若放在 `updateStatus()` 中，每輪都會觸發。直接副作用應只觸發一次。

### 10.7 最終結果

| 量測 | 數值 |
|------|------|
| APK 大小 | 4.3 MB |
| 首次啟動至監控 API 就緒 | ~1.5s |
| 引擎啟動至路由就緒 | ~1s |
| 路由回應 (9.3km) | ~12ms |
| 儀表板輪詢間隔 | 3s |
| WebView 重試上限 | 20 次 (每次 1s) |

---

## 11. Phase 1 Standard — JNI Bridge CMake 編譯障礙

### 11.1 背景

Phase 1 Standard 將 ProcessBuilder 模式升級為 JNI bridge：`libosrm_android.so` 直接載入 OSRM engine，在 native 層嵌入 civetweb HTTP server。CMake 編譯過程中遇到一系列障礙，記錄如下。

### 11.2 障礙與解決

#### 11.2.1 Civetweb 1.15 callback 簽名

```
錯誤: assigning to 'int (*)(struct mg_connection *)' from incompatible
       type 'int (struct mg_connection *, void *)'
```

```cpp
// 舊程式碼 (假設新版 civetweb):
callbacks.begin_request = route_handler;
static int route_handler(struct mg_connection* conn, void* cbdata);

// 事實: civetweb 1.15 的 begin_request 只接受 1 個參數
int (*begin_request)(struct mg_connection *);
```

**根因**: OSRM v5.27 bundle 的 civetweb 1.15 與後續版本 API 不同。新版 civetweb 的 `begin_request` 可有 `void*` 第二參數，但 1.15 版沒有。

**解決**: callback 改為 1-arg signature，透過 `mg_request_info` 取得 user data：
```cpp
static int route_handler(struct mg_connection* conn) {
    const auto* ri = mg_get_request_info(conn);
    auto* server = static_cast<HttpServer*>(ri->user_data);  // mg_start() 傳入的 this
    ...
}
```

#### 11.2.2 `osrm::util::Alias` 無隱含建構子

```
錯誤: no matching conversion for functional-style cast from 'double' to
       'osrm::util::FloatLongitude'
```

`FloatLongitude` / `FloatLatitude` 是 `Alias<double, Tag>` 強型別包裝，`Alias` **沒有**接受原始型別的建構子 — 只有 public member `__value` 可聚合初始化。

```cpp
// ❌ 錯誤：Alias 沒有 Alias(double) 建構子
coords.emplace_back(osrm::util::FloatLongitude(lon), ...);

// ✅ 正確：使用聚合初始化
coords.emplace_back(osrm::util::FloatLongitude{lon}, ...);
```

#### 11.2.3 `osrm::Algorithm` 命名空間

```
錯誤: no member named 'Algorithm' in namespace 'osrm'
```

`Algorithm` 列舉定義在 `osrm::EngineConfig` 內部，不是 `osrm` 直接子成員。

```cpp
config.algorithm = osrm::EngineConfig::Algorithm::MLD;  // ✅ 正確
// config.algorithm = osrm::Algorithm::MLD;              // ❌ 不存在
```

#### 11.2.4 `util::json::render` 雙引數

```
錯誤: candidate function not viable: requires 2 arguments, but 1 was provided
```

`render()` 的 signature 是 `render(std::string& out, const Object& object)` — 將 JSON 寫入指定的 string，而非回傳。

```cpp
std::string body;
osrm::util::json::render(body, json_result);  // ✅ body 被填入 JSON
```

#### 11.2.5 fmt 9.1 標頭與符號遺失

```
fatal error: 'fmt/compile.h' file not found
→ 加入 third_party/fmt-9.1.0/include 至 include_directories

undefined symbol: fmt::v9::detail::decimal_point_impl<char>(...)
→ 加入 third_party/fmt-9.1.0/src/format.cc 至 SOURCES
```

`json_renderer.hpp` 引入 `<fmt/compile.h>` 格式化浮點數。OSRM 主庫 (`libosrm.a`) 未包含 fmt 符號（可能是 header-only 或 strip 掉），需自行編譯 fmt。

#### 11.2.6 Java 25 與 Gradle 8.9 不相容

```
FAILURE: Build failed with an exception.
25.0.3
```

系統預設 JDK 為 Java 25.0.3 (Debian 13)，Gradle 8.9 無法正確解析此版本，僅輸出 `25.0.3` 作為錯誤訊息。需使用 `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` 指定 Java 21。

#### 11.2.7 健康監視器競爭條件

在模式切換時（例如從 ProcessBuilder 切換到 JNI native），原來的健康監視線程 (`monitorProcessHealth` 或 `monitorNativeHealth`）可能在新引擎啟動後仍在運行，檢查錯誤的進程狀誤將 `engineStatus` 錯誤設為 `crashed`。修正：在各健康監視器迴圈開頭立即檢查 `configUseNative` 與監視器類型是否匹配，不匹配則直接 `break` 退出迴圈，避免產生假警報。

#### 11.2.8 stopEngine() 未殺死 ProcessBuilder

在模式切換時若 `configUseNative` 已設為 true，`stopEngine()` 只會執行 native 分支，導致舊的 `osrm-routed` 進程殘留佔用 port 5747；現改為無論何種模式均嘗試殺死 `engineProcess` 再停止 native engine

#### 11.2.9 binaryPath 為 null

當從 native 模式切換回 ProcessBuilder 時，因 `onCreate()` 中僅在 `!configUseNative` 時解析 binary 路徑，導致切換回去後 `binaryPath` 為 null；現改為在 `onCreate()` 無條件解析，並在 `updateConfig()` 重啟/啟動引擎前再次確認

#### 11.2.10 ABI 未指定導致連結失敗

```
ld.lld: error: libosrm.a(hint.cpp.o) is incompatible with armelf_linux_eabi
```

Gradle 預設同時為 `armeabi-v7a` (32-bit) 與 `arm64-v8a` (64-bit) 編譯，但 OSRM 靜態庫僅有 arm64-v8a 版本。需限定 ABI：

```kotlin
defaultConfig { ndk { abiFilters += "arm64-v8a" } }
```

### 11.3 最終編譯產出

```
app-debug.apk
  ├── lib/arm64-v8a/libosrm_android.so   3.4 MB  ← JNI bridge (新增)
  └── lib/arm64-v8a/libosrm_routed.so    3.0 MB  ← ProcessBuilder binary (既有)

APK 總大小: 6.6 MB
```

### 11.4 教訓

1. **Civetweb API 版本敏感**：OSRM 捆綁的 civetweb 1.15 與後續版本 callback 簽名不同，不能直接參考 upstream 範例。
2. **強型別 alias 需用聚合初始化**：OSRM 的 `Alias<T, Tag>` 採用 C 風格 struct 設計，無建構子，只能用 `{value}`。
3. **fmt 非 header-only**：OSRM 的 `json_renderer` 依賴 fmt 實作檔，連結時需提供 `format.cc`。
4. **Java 版本兼容性**：Gradle 8.9 不支援 Java 25，需確保 `JAVA_HOME` 指向 Java 21。

| 量測 | 數值 |
|------|------|
| APK 大小 | 4.3 MB |
| 首次啟動至監控 API 就緒 | ~1.5s |
| 引擎啟動至路由就緒 | ~1s |
| 路由回應 (9.3km) | ~12ms |
| 儀表板輪詢間隔 | 3s |
| WebView 重試上限 | 20 次 (每次 1s) |
