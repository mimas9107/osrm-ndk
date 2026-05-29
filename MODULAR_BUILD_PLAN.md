# OSRM Android NDK 模組化建構系統設計計畫書

本計畫書旨在將原本龐大且不易維護的單一腳本 `build_osrm_android.sh`，拆解重構為一組**「模組化、高內聚、低耦合」**的建構腳本群。透過將環境變數抽離、各組件獨立編譯，來徹底解決建構鏈難以部分排錯、除錯快取混亂以及跨電腦環境再現性差的問題。

---

## 一、 系統目錄架構規劃

模組化建構腳本將統一存放在 `scripts/build_modules/` 目錄下，其架構規劃如下：

```
osrm-ndk/
├── scripts/
│   ├── env_android.sh            # [核心] 統一環境變數設定與工具鏈配置
│   ├── build_all.sh              # [編排] 一鍵編排，按拓撲順序呼叫子腳本
│   ├── package_artifacts.sh      # [封裝] 物理矯正，負責二進位複製與 strip
│   └── build_modules/            # [模組] 各組件獨立建構腳本
│       ├── 01_build_zlib.sh
│       ├── 02_build_expat.sh
│       ├── 03_build_bzip2.sh
│       ├── 04_build_libxml2.sh
│       ├── 05_build_lua.sh
│       ├── 06_build_tbb.sh
│       ├── 07_build_civetweb.sh
│       ├── 08_build_boost.sh
│       └── 09_build_osrm.sh
```

---

## 二、 核心腳本設計藍圖

### 1. 統一環境變數設定 (`scripts/env_android.sh`)
* **職責**：集中管理所有的路徑檢測、編譯器宣告、編譯參數（`CFLAGS` 等）與系統安裝路徑定義。
* **設計要點**：
  * 提供「自動偵測」與「環境變數覆蓋」雙重機制。
  * 提供防重複載入保護機制（防止多次 `source` 造成 `PATH` 無限增長）。
  * 統一將 NDK 的 LLVM 工具鏈（`llvm-ar`、`llvm-ranlib`、`llvm-strip` 等）導出為標準環境變數（`AR`、`RANLIB`、`STRIP`）。
* **變數導出清單**：
  * `PROJECT_DIR` / `DEPS_DIR` / `BUILD_DIR` / `PREFIX`
  * `CC` / `CXX` / `AR` / `RANLIB` / `STRIP` / `SYSROOT`
  * `CFLAGS` / `CXXFLAGS` / `LDFLAGS` / `JOBS`

### 2. 獨立組件建構腳本群 (`scripts/build_modules/*.sh`)
每個子腳本的行為精神須遵循以下規範：
* **自治性**：腳本開頭必須 `source ../env_android.sh`，確保其可被單獨執行，不依賴 `build_all.sh`。
* **防重編機制**：在執行 CMake/Make 前，先檢查目標產物（如 `$PREFIX/lib/libz.a`）是否已存在。若已存在，則輸出提示並直接退出（提供 `--force` 參數覆蓋此行為）。
* **防污染機制**：統一在外部 `$BUILD_DIR/<module>` 執行 Out-of-source 建構，保持 `deps/` 源碼樹乾淨。

---

## 三、 子組件建構細節規劃

### `01_build_zlib.sh`
* **機制**：CMake
* **核心命令**：
  ```bash
  cmake -S "$DEPS_DIR/zlib" -B "$BUILD_DIR/zlib" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DBUILD_SHARED_LIBS=OFF
  ```

### `02_build_expat.sh`
* **機制**：CMake
* **特異配置**：關閉工具、測試與文檔：
  `-DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF`

### `03_build_bzip2.sh`
* **機制**：Makefile (變數覆蓋)
* **核心命令**：
  ```bash
  make -C "$DEPS_DIR/bzip2-1.0.8" -j"$JOBS" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" libbz2.a
  # 手動複製 bzlib.h 至 $PREFIX/include，libbz2.a 至 $PREFIX/lib
  ```

### `04_build_libxml2.sh`
* **機制**：CMake
* **特異配置**：`-DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_ZLIB=ON -DLIBXML2_WITH_ICONV=OFF`

### `05_build_lua.sh` (💥 關鍵修正點)
* **機制**：Makefile (變數覆蓋)
* **核心命令**：
  ```bash
  # 1. 強制指定 target 為 posix (避開無效目標與 readline 依賴)
  # 2. 修正 AR 變數拼寫錯誤
  make -C "$DEPS_DIR/lua-5.3.6" -j"$JOBS" \
    CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
    CFLAGS="$CFLAGS" MYLDFLAGS="$LDFLAGS" \
    posix
  # 手動將 src/*.h 複製至 $PREFIX/include，liblua.a 複製至 $PREFIX/lib
  ```

### `06_build_tbb.sh`
* **機制**：CMake
* **核心命令**：追加 `-DTBB_TEST=OFF -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-error=attribute-alias"`。

### `07_build_civetweb.sh`
* **機制**：CMake
* **特異配置**：`-DCIVETWEB_ENABLE_SSL=OFF -DCIVETWEB_ENABLE_WEBSOCKETS=OFF -DCIVETWEB_BUILD_TESTING=OFF`

### `08_build_boost.sh` (💥 關鍵修正點)
* **機制**：Boost `b2` (手動生成 `user-config.jam`)
* **核心命令**：
  * 生成 `user-config.jam` 時，將 `<archiver>` 與 `<ranlib>` 改為 `llvm-ar` 和 `llvm-ranlib`（而非舊的 GCC 別名）。
  * 呼叫 `./b2` 進行編譯，輸出目錄指定為 `$PREFIX`。

### `09_build_osrm.sh`
* **機制**：CMake
* **設計要點**：
  * 在執行前，腳本會對前 8 個依賴項進行**「門檻檢查 (Gatekeeper Check)」**，確保所有需要的 `.a` 與 `.h` 檔案都在 `$PREFIX` 內，否則報錯退出。
  * 傳入所有 `Boost_INCLUDE_DIR`、`TBB_LIBRARY` 等路徑參數，確保 CMake 不會尋找宿主機的 x86 依賴。

---

## 四、 編排與封裝腳本設計

### 1. 一鍵編排器 (`scripts/build_all.sh`)
* **邏輯描述**：
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  
  # 1. 載入統一環境
  source "$(dirname "$0")/env_android.sh"
  
  # 2. 依次執行子模組腳本
  MODULES_DIR="$(dirname "$0")/build_modules"
  
  for script in "$MODULES_DIR"/*.sh; do
    echo "============================================="
    echo "  Running: $(basename "$script")"
    echo "============================================="
    bash "$script"
  done
  
  # 3. 呼叫物理矯正封裝
  bash "$(dirname "$0")/package_artifacts.sh"
  ```

### 2. 物理矯正封裝器 (`scripts/package_artifacts.sh`) (💥 關鍵修正點)
* **職責**：將編譯出來的 `osrm-routed` 二進位程式，轉換為 Android APK 包裝所需的動態庫與 assets 形式，實現構建閉環。
* **主要任務**：
  1. 建立 `android/app/src/main/jniLibs/arm64-v8a/` 與 `android/app/src/main/assets/` 目錄。
  2. 將 `build_android/install/bin/osrm-routed` 複製到 jniLibs 目錄並重命名為 `libosrm_routed.so`。
  3. 將其複製到 assets 目錄重命名為 `osrm-routed`。
  4. 呼叫 `$STRIP` 對這兩個檔案進行符號消除（Strip），將二進位檔大小從 ~140MB 降至 ~3MB，大幅縮小 APK 體積。

---

## 五、 路徑解耦與 CMakeLists 引用策略

為實現 100% 的建構環境再現性，腳本群對路徑的處理必須遵循**「物理隔離、動態生成、絕對路徑化」**的原則，徹底切斷任何隱性路徑相依。

### 1. 三維路徑物理隔離設計
在 `env_android.sh` 中，我們定義三個核心維度的路徑，且全部在執行時被解析為**絕對路徑**：
* **來源套件代碼路徑 (`SRC_DIR`)**：指向第三方下載的原生代碼（例如 `$DEPS_DIR/lua-5.3.6`）。此處僅供讀取，不允許在其中產生任何臨時編譯檔。
* **中間建構暫存路徑 (`BLD_DIR`)**：用於 CMake 執行 `out-of-source` 編譯的暫存目錄（例如 `$BUILD_DIR/lua`）。每次編譯前可安全清理，不影響源碼。
* **安裝目的地路徑 (`PREFIX` / `INSTALL_DIR`)**：所有編譯完成的 `.a`、`.so`、標頭檔及二進位裝配的目的地。所有後續的組件與 JNI 橋接層，皆僅在此目錄中尋找相依項。

其定義範例如下（全部轉化為絕對路徑）：
```bash
# env_android.sh 中動態導出絕對路徑
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEPS_DIR="${PROJECT_DIR}/deps"
export BUILD_DIR="${PROJECT_DIR}/build_android"
export INSTALL_DIR="${BUILD_DIR}/install"
export PREFIX="${INSTALL_DIR}/android-24/arm64-v8a"
```

### 2. 工具鏈與安裝路徑「絕對路徑化」
* **工具鏈路徑**：為了防止編譯過程中，因為環境變數 `PATH` 優先權混亂而誤調用宿主機（x86_64 Linux）的 `gcc`、`ar` 或 `ld`，我們在 `env_android.sh` 中將所有 NDK 建構工具鏈宣告為**絕對路徑**：
  ```bash
  TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
  export CC="${TOOLCHAIN}/bin/aarch64-linux-android24-clang"
  export CXX="${TOOLCHAIN}/bin/aarch64-linux-android24-clang++"
  export AR="${TOOLCHAIN}/bin/llvm-ar"
  export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
  export STRIP="${TOOLCHAIN}/bin/llvm-strip"
  export SYSROOT="${TOOLCHAIN}/sysroot"
  ```
* **安裝目的地路徑**：在使用 CMake 與 Make 安裝時，統一使用絕對路徑傳入：
  * **CMake**：`-DCMAKE_INSTALL_PREFIX="$PREFIX"`
  * **Lua/bzip2 Make**：`INSTALL_TOP="$PREFIX"` / `PREFIX="$PREFIX"`

---

### 3. JNI `CMakeLists.txt` 的解耦與引用編寫策略
為防止在新舊電腦上因路徑改變而造成 JNI 共享庫編譯崩潰，JNI 的 `CMakeLists.txt` 應採用以下高再現性寫法：

#### 策略 A：動態絕對路徑定位
避免在 CMake 內寫死如 `/home/mimas/...` 的字串。應利用 CMake 原生的變數定位，於設定期將專案目錄動態轉化為宿主機上的絕對路徑：
```cmake
# 利用 CMakeLists.txt 的所在目錄往上追溯，動態生成宿主機的絕對路徑
get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)

# 將依賴尋找範圍縮小在安裝目的地 (PREFIX) 與 OSRM 源碼樹中
set(OSRM_PREFIX "${PROJECT_ROOT}/build_android/install")
set(OSRM_SOURCE_DIR "${PROJECT_ROOT}/deps/osrm-backend")
```

#### 策略 B：焊死依賴庫的「絕對路徑清單」
不要使用 CMake 的模糊全域搜索（如 `find_library`），因為那會引入宿主機 `/usr/lib/` 下的 x86 靜態庫污染。
應將依賴庫以**精確的絕對路徑**硬編碼指派：
```cmake
# 1. 核心庫絕對路徑指派
set(OSRM_CORE_LIBS
  "${OSRM_PREFIX}/lib/libosrm.a"
  "${OSRM_PREFIX}/lib/libosrm_guidance.a"
  # ... 其他核心庫
)

# 2. 系統依賴庫絕對路徑指派
set(DEPS_LIB_DIR "${OSRM_PREFIX}/android-24/arm64-v8a/lib")
set(DEPS_LIBS
  "${DEPS_LIB_DIR}/libboost_program_options.a"
  "${DEPS_LIB_DIR}/libboost_filesystem.a"
  "${DEPS_LIB_DIR}/libtbb.a"
  "${DEPS_LIB_DIR}/liblua.a"
  # ... 其他系統庫
)

# 連結時直接引入上述絕對路徑陣列，確保編譯連結期絕不外洩至系統預設路徑
target_link_libraries(osrm_android PRIVATE
  ${OSRM_CORE_LIBS}
  ${DEPS_LIBS}
  log dl z m atomic
)
```

---

## 六、 本計畫之效益評估

1. **秒級排錯**：如果 OSRM 編譯失敗，開發者只需反覆修改並執行 `09_build_osrm.sh`，不用每次都等待 Boost/TBB 慢速掃描。
2. **零環境污染**：`env_android.sh` 不會將環境變數寫死在宿主機的 `~/.bashrc`，完全靠 `source` 傳遞，乾淨利落。
3. **明確的 Patch Registry**：因為有了 `package_artifacts.sh`，原本「手動複製二進位並重新命名」的隱性人工步驟被轉化為白紙黑字的代碼，排除了人為遺漏導致的 APK 執行崩潰。
4. **絕對路徑隔離**：透過絕對路徑鎖死工具鏈與依賴庫，100% 避免宿主機（x86_64）函式庫洩漏或污染，達成跨作業系統、跨帳號的安全再現。
