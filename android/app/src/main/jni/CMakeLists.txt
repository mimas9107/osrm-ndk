cmake_minimum_required(VERSION 3.22)
project(osrm_android CXX)

# 🔥 核心解鎖：焊死全局寬容警告旗標與 C++17 標準
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w -Wno-error -Wno-deprecated-declarations -Wno-error=deprecated-declarations")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w -Wno-error")

get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
set(OSRM_PREFIX "${PROJECT_ROOT}/build_android/install")
set(OSRM_SOURCE_DIR "${PROJECT_ROOT}/deps/osrm-backend")

# 1. 核心大軍：精準編碼指派 OSRM 官方產出的 8 大核心庫（位於 install/lib/）
set(OSRM_CORE_LIBS
  "${OSRM_PREFIX}/lib/libosrm.a"
  "${OSRM_PREFIX}/lib/libosrm_guidance.a"
  "${OSRM_PREFIX}/lib/libosrm_extract.a"
  "${OSRM_PREFIX}/lib/libosrm_partition.a"
  "${OSRM_PREFIX}/lib/libosrm_store.a"
  "${OSRM_PREFIX}/lib/libosrm_update.a"
  "${OSRM_PREFIX}/lib/libosrm_customize.a"
  "${OSRM_PREFIX}/lib/libosrm_contract.a"
)

# 2. 依賴大軍：精準編碼指派你今天打通的 8 大系統庫（位於 install/android-24/arm64-v8a/lib/）
set(DEPS_LIB_DIR "${OSRM_PREFIX}/android-24/arm64-v8a/lib")
set(DEPS_LIBS
  "${DEPS_LIB_DIR}/libboost_program_options.a"
  "${DEPS_LIB_DIR}/libboost_filesystem.a"
  "${DEPS_LIB_DIR}/libboost_system.a"
  "${DEPS_LIB_DIR}/libboost_thread.a"
  "${DEPS_LIB_DIR}/libboost_iostreams.a"
  "${DEPS_LIB_DIR}/libboost_date_time.a"
  "${DEPS_LIB_DIR}/libboost_chrono.a"
  "${DEPS_LIB_DIR}/libboost_regex.a"
  "${DEPS_LIB_DIR}/libboost_atomic.a"
  "${DEPS_LIB_DIR}/libtbb.a"
  "${DEPS_LIB_DIR}/liblua.a"
  "${DEPS_LIB_DIR}/libcivetweb.a"
  "${DEPS_LIB_DIR}/libz.a"
  "${DEPS_LIB_DIR}/libbz2.a"
  "${DEPS_LIB_DIR}/libexpat.a"
  "${DEPS_LIB_DIR}/libxml2.a"
)

# 3. 原始碼清單
set(SOURCES
  osrm_bridge.cpp
  http_server.cpp
  "${OSRM_SOURCE_DIR}/third_party/fmt-9.1.0/src/format.cc"
)

add_library(osrm_android SHARED ${SOURCES})

# 4. 標頭檔搜尋路徑閉合
target_include_directories(osrm_android PRIVATE
  "${OSRM_SOURCE_DIR}/third_party/variant/include"
  "${OSRM_SOURCE_DIR}/third_party/flatbuffers/include"
  "${OSRM_PREFIX}/include"
  "${OSRM_PREFIX}/android-24/arm64-v8a/include"
  "${OSRM_SOURCE_DIR}/include"
  "${OSRM_SOURCE_DIR}/third_party/fmt-9.1.0/include"
  ${CMAKE_CURRENT_SOURCE_DIR}
)

# 5. 🔥 鋼鐵連結：強制將 OSRM 核心大軍與依賴大軍無縫打包熔煉！
target_link_libraries(osrm_android PRIVATE
  ${OSRM_CORE_LIBS}
  ${DEPS_LIBS}
  log
  dl
  z
  m
  atomic
)
