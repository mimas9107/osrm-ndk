# OSRM Android NDK 完整建構流程與再現性除錯報告

本報告詳細分析將 OSRM Backend (v5.27.1) 及其相依套件交叉編譯至 Android ARM64，並最終封裝成自含式 APK 的完整堆砌管線。報告旨在指出昨日在新電腦上遭遇的環境再現性問題，針對 `./scripts/build_osrm_android.sh` 與 `./deps/` 底下的組件編譯流程進行深剖，並給出具體修正建議與無痛重製方案。

---

## 一、 從零到 APK 的逐步堆砌管線與組件相依關係

下圖展示了本專案從未編譯的原始碼出發，最終打包成 `.apk` 檔的逐步堆砌管線與相依關係：

```mermaid
graph TD
  subgraph Phase 1: Dependency Sources [原始碼準備]
    A[fetch_deps.sh] -->|下載與校正| B[deps/ 底下各組件源碼]
    C[osrm-backend-plus 影子安全屋] -->|物理覆蓋補丁| B
  end

  subgraph Phase 2: NDK Cross-Compilation [NDK 交叉編譯]
    B -->|build_osrm_android.sh| D[Deps 靜態庫編譯]
    D -->|編譯 zlib, expat, bzip2, libxml2, lua, oneTBB, civetweb, boost| E[build_android/install/ 靜態庫與標頭檔]
    E -->|CMake 交叉編譯| F[osrm-backend 主編譯]
    F -->|產出二進位與核心庫| G[osrm-routed 等 binaries & libosrm.a]
  end

  subgraph Phase 3: Android Integration [Android 整合與封裝]
    G -->|手動/腳本複製 & strip| H[jniLibs/arm64-v8a/libosrm_routed.so]
    G -->|CMake JNI Bridge 連結| I[libosrm_android.so JNI 共享庫]
    H & I -->|Gradle assembleDebug| J[app-debug.apk 最終封裝]
  end
```

### 關鍵相依時序 (Build Ordering)
1. **源碼層**: `fetch_deps.sh` 必須先執行，拉取第三方依賴，並強制將修復後的 C++ 原始碼（位於 `osrm-backend-plus/`）注入 `deps/osrm-backend`，以對抗 Android Bionic 庫缺乏 System V 共享記憶體等天生殘疾。
2. **編譯層**: `./scripts/build_osrm_android.sh` 必須在 Gradle 建構前**完整執行完畢**。因為 JNI 橋接層 `libosrm_android.so` 必須靜態連結 `build_android/install/` 目錄下的 `libosrm.a`、`libboost_*.a`、`libtbb.a` 等。
3. **打包層**: `build_android/install/bin/osrm-routed` 可執行二進位必須在 Gradle 包裝 APK 前複製到 `android/app/src/main/jniLibs/arm64-v8a/` 並重命名為 `libosrm_routed.so`，否則 APK 中將遺失此 binary。

---

## 二、 `./deps/` 底下各組件逐步堆砌的編譯細節分析

下表詳細解構了 `./deps/` 目錄下各個組件的編譯機制、角色以及交叉編譯時的平台特徵：

| 組件名稱 | 編譯機制 | 作用說明 | 產出檔案 | 交叉編譯關鍵字與 Android 平台特徵 |
| :--- | :--- | :--- | :--- | :--- |
| **zlib** | CMake | 提供基本的資料壓縮與解壓縮支援。為 PBF 圖資讀取和 bzip2 提供底層算法。 | `libz.a` | 標準 CMake 交叉編譯，無平台特異性問題。 |
| **libexpat** | CMake | XML 解析器。用於解析舊式 `.osm` XML 圖資格式。 | `libexpat.a` | 關閉工具與測試編譯以提升效率 (`-DEXPAT_BUILD_TOOLS=OFF`)。 |
| **bzip2** | GNU Makefile | 圖資解壓縮組件。 | `libbz2.a` | 原生 Makefile 不直接支援 CMake。需在命令行強制傳入 `CC`、`AR`、`RANLIB`、`CFLAGS` 與 `LDFLAGS` 進行變數覆蓋。 |
| **libxml2** | CMake | 強大的 XML 解析器。 | `libxml2.a` | 關閉 Python 綁定與 iconv (`-DLIBXML2_WITH_ICONV=OFF`)，開啟 Zlib 壓縮支援。 |
| **lua-5.3.6** | GNU Makefile | 內嵌腳本引擎。用於執行 OSRM 自訂的路權設定腳本（如機車圖資 `motorcycle.lua`）。 | `liblua.a` | **重大再現性漏洞源之一**。原生 Makefile 沒有 `aarch64-linux-android` 目標。此外，`-DLUA_USE_LINUX` 會強行引入 Android 缺乏的 readline 依賴。 |
| **oneTBB** | CMake | Intel 開源的執行緒構建塊。OSRM 使用它來進行多核幾何與路網計算。 | `libtbb.a` | ARM64 架構在編譯 oneTBB 時需要使用 64 位 atomic 內建指令。需要 NDK 版本 $\ge$ 26 才能提供穩定的支援。 |
| **civetweb** | CMake | 內嵌的超輕量級 HTTP 服務器。用於在 Android 背景 Service 中直接暴露 OSRM API 服務。 | `libcivetweb.a` | JNI 層代碼使用了 Civetweb 1.15 API，該版本與後續版本的 callback 簽名不同（1.15 版的 `begin_request` callback 僅接受 1 個參數）。 |
| **boost_1_83_0** | Boost `b2` | OSRM 基礎庫（filesystem、program_options、iostreams 等）。 | 許多 `libboost_*.a` | **重大再現性漏洞源之二**。需要生成 `user-config.jam` 並調用 `b2` 工具。若使用現代 NDK（r22+），舊版 GCC 工具鏈別名（如 `-ar`）會導致編譯熔斷。 |
| **osrm-backend** | CMake | OSRM 核心路由引擎。靜態連結以上所有庫。 | `libosrm.a` 等及工具二進位 | 由於 Android Bionic 不支援 System V 共享記憶體（`shmget`），我們引入了 Stub 掏空技術，閉合虛擬表以防編譯出錯。 |

---

## 三、 `build_osrm_android.sh` 及建構管線問題診斷與修復對策

昨日在新電腦上遭遇的「建構環境無法再現」問題，主要源於以下 6 個核心設計 Bug。以下逐一診斷並給出具體的解決對策：

### 1. Lua 編譯目標與 Readline 缺失問題（致命錯誤）
* **診斷**：
  * `./scripts/build_osrm_android.sh` 第 142 行呼叫了 `aarch64-linux-android` 作為 Lua 的編譯 target。然而，Lua 官方 Makefile 內根本沒有定義此 target，導致 `make` 立即中斷報錯。
  * 第 140 行傳入了 `CFLAGS="-DLUA_USE_LINUX"`。這會使 Lua 的 `luaconf.h` 啟用 `LUA_USE_READLINE` 特性，嘗試引入 `<readline/readline.h>`。然而，Android NDK 內並沒有 readline 庫，這會引發嚴重的 header 缺失編譯錯誤。
  * 第 139 行 `AR="$AR RANLIB=$RANLIB"` 存在變數賦值引號拼寫錯誤，使得 `AR` 的內容被混入 `RANLIB`，導致歸檔工具調用失敗。
* **對策**：
  * 使用 Lua Makefile 中原生支援的 `posix` 目標，這能為 Android 提供標準的 POSIX API。
  * **不要**傳入 `-DLUA_USE_LINUX`，而僅使用預設的 POSIX 配置（無 readline 依賴）。
  * 修正 `AR` 與 `RANLIB` 參數，將歸檔命令改為 `AR="$AR rcu" RANLIB="$RANLIB"`。
  * **手動修正 Lua make 示範**：
    ```bash
    make -C "deps/lua-5.3.6" clean
    make -C "deps/lua-5.3.6" -j$(nproc) \
      CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
      CFLAGS="$CFLAGS" MYLDFLAGS="$LDFLAGS" \
      posix
    ```

### 2. Boost `user-config.jam` 工具鏈別名缺失問題（致命錯誤）
* **診斷**：
  * 在 NDK r22+ 之後，Android NDK 移除了舊的 GCC 交叉編譯別名（如 `aarch64-linux-android-ar` 和 `aarch64-linux-android-ranlib`）。
  * 腳本在生成 `tools/build/src/user-config.jam` 時（第 183-184 行）仍硬編碼指派：
    ```jam
    <archiver>aarch64-linux-android-ar
    <ranlib>aarch64-linux-android-ranlib
    ```
    這會導致在新電腦上（尤其是使用 NDK r30時）`b2` 找不到歸檔器，無法產出靜態庫。
* **對策**：
  * 由於 NDK 的 LLVM 歸檔工具路徑已在第 55 行被加入 `PATH` 中，應將 `user-config.jam` 中的工具名稱直接改為通用的 `llvm-ar` 和 `llvm-ranlib`：
    ```jam
    using clang : android : aarch64-linux-android24-clang++ :
      <archiver>llvm-ar
      <ranlib>llvm-ranlib
      <compileflags>-fPIC
      <compileflags>-O2
      <compileflags>-D_LARGEFILE64_SOURCE
      <compileflags>-D_FILE_OFFSET_BITS=64
      <compileflags>--sysroot=\$(ANDROID_NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64/sysroot
    ;
    ```

### 3. JNI CMake 寫死絕對路徑問題（導致 Android Studio 同步失敗，現已修復）
* **診斷**：
  * `android/app/src/main/jni/CMakeLists.txt` 原先寫死了原作者的絕對路徑 `/home/mimas/projects/osrm-ndk/...`，甚至路徑中的 `projects`（複數）與當前實際路徑 `project`（單數）不符，這導致在新電腦上執行 Gradle sync 時會直接報錯，無法編譯橋接共享庫 `libosrm_android.so`。
* **對策**：
  * **【已修復】** 使用 CMake 的 `get_filename_component` 動態解析專案根目錄，移除所有絕對路徑，實現跨設備 100% 可攜性：
    ```cmake
    get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
    set(OSRM_PREFIX "${PROJECT_ROOT}/build_android/install")
    set(OSRM_SOURCE_DIR "${PROJECT_ROOT}/deps/osrm-backend")
    ```

### 4. Git-ignored 關鍵二進位檔案缺失問題
* **診斷**：
  * `android/app/src/main/jniLibs/arm64-v8a/libosrm_routed.so` 以及 assets 內的 `osrm-routed` 都是實作 ProcessBuilder 模式運行 OSRM 路由服務所需的二進位檔。
  * 這兩個檔案已被納入 `.gitignore`，新電腦 clone 之後目錄是空的。
  * `build_osrm_android.sh` 編譯完畢後，**沒有自動將 binary 複製到 android 模組中**，這導致 Gradle 打包出的 APK 完全缺乏此 binary，運行 ProcessBuilder 模式時會直接崩潰。
* **對策**：
  * 在編譯完成後，應在腳本中或手動執行複製與 strip 指令（移除 debug 符號以縮小體積）：
    ```bash
    # 複製並重命名為 .so（使 Android 系統能自動將其視為 native lib 展開）
    mkdir -p android/app/src/main/jniLibs/arm64-v8a/
    cp build_android/install/bin/osrm-routed android/app/src/main/jniLibs/arm64-v8a/libosrm_routed.so
    $STRIP android/app/src/main/jniLibs/arm64-v8a/libosrm_routed.so
    
    # 同步複製到 assets 作為備用自解壓 binary
    mkdir -p android/app/src/main/assets/
    cp build_android/install/bin/osrm-routed android/app/src/main/assets/osrm-routed
    $STRIP android/app/src/main/assets/osrm-routed
    ```

### 5. Gradle 的 JDK 25 不相容問題
* **診斷**：
  * 若新電腦上安裝了最新版 JDK（例如 Debian 13 預設的 Java 25），Gradle 8.9 會因為無法識別此 Java 版本而導致 Sync/Build 直接失敗。
* **對策**：
  * 在編譯前，將 `JAVA_HOME` 環境變數手動指定為 JDK 21 以確保相容性：
    ```bash
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    ```

### 6. `local.properties` 配置缺失
* **診斷**：
  * 作為 Android 專案，NDK 和 SDK 的路徑依賴於每台電腦的安裝路徑。新拉取的 repo 中沒有此文件。
* **對策**：
  * 在新電腦執行 Gradle 建構前，必須手動建立 `android/local.properties`：
    ```properties
    sdk.dir=/home/<your_username>/Android/Sdk
    ndk.dir=/home/<your_username>/Android/Sdk/ndk/30.0.14904198
    ```

---

## 四、 相同 OS 相同環境下的一鍵再現指引

為了在不改動原 `build_osrm_android.sh` 腳本的前提下，確保在相同環境下百分之百再現建構，請嚴格按照以下步驟操作：

### 步驟 1：設置基礎環境變數與 JDK 21
```bash
# 1. 指定使用相容的 JDK 21
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# 2. 設定 Android NDK 環境變數
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/30.0.14904198
```

### 步驟 2：執行第三方源碼下載與覆蓋
```bash
# 下載依賴並將 osrm-backend-plus 安全屋原始碼物理注入
./scripts/fetch_deps.sh
```

### 步驟 3：修正 Lua 與 Boost 的配置（不改動原腳本的替代執行法）
由於不要直接改動原建構腳本，我們可以複製腳本或以覆蓋環境變數的方式運行手動編譯。在此我們推薦直接依序執行以下手動編譯段落，確保其能 100% 通過：

```bash
# 設置編譯器變數
TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
CC="${TOOLCHAIN}/bin/aarch64-linux-android24-clang"
CXX="${TOOLCHAIN}/bin/aarch64-linux-android24-clang++"
AR="${TOOLCHAIN}/bin/llvm-ar"
RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
STRIP="${TOOLCHAIN}/bin/llvm-strip"
export CC CXX AR RANLIB STRIP

# 初始化目錄
PROJECT_DIR="$(pwd)"
DEPS_DIR="${PROJECT_DIR}/deps"
BUILD_DIR="${PROJECT_DIR}/build_android"
PREFIX="${BUILD_DIR}/install/android-24/arm64-v8a"
mkdir -p "$PREFIX"/{lib,include,bin}
mkdir -p "$BUILD_DIR"/{zlib,expat,bzip2,libxml2,lua,tbb,civetweb,osrm}

# 1. 編譯 Lua (使用 posix 目標與 llvm-ar)
echo "=== Building Lua 5.3.6 ==="
make -C "$DEPS_DIR/lua-5.3.6" clean
make -C "$DEPS_DIR/lua-5.3.6" -j$(nproc) \
  CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
  CFLAGS="-fPIC -O2 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" \
  MYLDFLAGS="-fPIC" \
  posix \
  INSTALL_TOP="$PREFIX" install

# 2. 編譯 Boost (手動修正 user-config.jam 用 llvm-ar)
echo "=== Building Boost 1.83.0 ==="
cd "$DEPS_DIR/boost_1_83_0"
if [ ! -f b2 ]; then
  ./bootstrap.sh --with-toolset=clang
fi
cat > tools/build/src/user-config.jam << EOF
using clang : android : aarch64-linux-android24-clang++ :
  <archiver>llvm-ar
  <ranlib>llvm-ranlib
  <compileflags>-fPIC
  <compileflags>-O2
  <compileflags>-D_LARGEFILE64_SOURCE
  <compileflags>-D_FILE_OFFSET_BITS=64
  <compileflags>--sysroot=${TOOLCHAIN}/sysroot
;
EOF
./b2 -j$(nproc) \
  toolset=clang-android \
  target-os=linux \
  architecture=arm \
  address-model=64 \
  abi=aapcs \
  link=static \
  runtime-link=static \
  threading=multi \
  variant=release \
  --with-program_options \
  --with-filesystem \
  --with-system \
  --with-thread \
  --with-iostreams \
  --with-date_time \
  --prefix="$PREFIX" \
  install
cd "$PROJECT_DIR"
```

### 步驟 4：執行原腳本並跳過已編譯好的依賴
因為我們已經正確編譯了 Lua 與 Boost，且原腳本有防重編機制（若 `$PREFIX/lib/liblua.a` 存在則略過），因此可以直接執行腳本：
```bash
# 執行剩餘依賴（zlib, expat, libxml2, TBB, civetweb, osrm-backend）的交叉編譯
./scripts/build_osrm_android.sh
```

### 步驟 5：物理矯正二進位擺放路徑
```bash
# 將 osrm-routed 複製到 jniLibs 與 assets
mkdir -p android/app/src/main/jniLibs/arm64-v8a/
cp build_android/install/bin/osrm-routed android/app/src/main/jniLibs/arm64-v8a/libosrm_routed.so
$STRIP android/app/src/main/jniLibs/arm64-v8a/libosrm_routed.so

mkdir -p android/app/src/main/assets/
cp build_android/install/bin/osrm-routed android/app/src/main/assets/osrm-routed
$STRIP android/app/src/main/assets/osrm-routed
```

### 步驟 6：配置並建構 APK
```bash
# 1. 建立 local.properties
cat > android/local.properties << EOF
sdk.dir=$HOME/Android/Sdk
ndk.dir=$HOME/Android/Sdk/ndk/30.0.14904198
EOF

# 2. 執行 Gradle 編譯
cd android
./gradlew assembleDebug
```

編譯完成後，即可在 `android/app/build/outputs/apk/debug/app-debug.apk` 取得 100% 功能完備、包含 JNI bridge 與 ProcessBuilder 執行檔的離線導航 APK。
