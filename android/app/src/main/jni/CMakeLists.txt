cmake_minimum_required(VERSION 3.22)
project(osrm_android CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- Find the cross-compiled OSRM and its deps ----
set(OSRM_PREFIX "${CMAKE_SOURCE_DIR}/../../../../build_android/install")

# OSRM includes
find_path(OSRM_INCLUDE_DIR osrm/osrm.hpp
  PATHS "${OSRM_PREFIX}/include"
  NO_DEFAULT_PATH)

# OSRM libs
set(OSRM_LIBS
  "${OSRM_PREFIX}/lib/libosrm.a"
  "${OSRM_PREFIX}/lib/libosrm_extras.a"
)

# Dependencies
set(DEPS_LIB_DIR "${OSRM_PREFIX}/android-24/arm64-v8a/lib")

set(DEPS_LIBS
  "${DEPS_LIB_DIR}/libboost_program_options.a"
  "${DEPS_LIB_DIR}/libboost_filesystem.a"
  "${DEPS_LIB_DIR}/libboost_system.a"
  "${DEPS_LIB_DIR}/libboost_thread.a"
  "${DEPS_LIB_DIR}/libboost_iostreams.a"
  "${DEPS_LIB_DIR}/libboost_date_time.a"
  "${DEPS_LIB_DIR}/libtbb.a"
  "${DEPS_LIB_DIR}/libtbbmalloc.a"
  "${DEPS_LIB_DIR}/liblua.a"
  "${DEPS_LIB_DIR}/libcivetweb.a"
  "${DEPS_LIB_DIR}/libz.a"
  "${DEPS_LIB_DIR}/libexpat.a"
  "${DEPS_LIB_DIR}/libxml2.a"
  "${DEPS_LIB_DIR}/libbz2.a"
)

# ---- Source files ----
set(SOURCES
  osrm_bridge.cpp
  http_server.cpp
)

add_library(osrm_android SHARED ${SOURCES})

target_include_directories(osrm_android PRIVATE
  ${OSRM_INCLUDE_DIR}
  ${OSRM_PREFIX}/android-24/arm64-v8a/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(osrm_android PRIVATE
  ${OSRM_LIBS}
  ${DEPS_LIBS}
  log
  dl
  z
)

# Strip in release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_command(TARGET osrm_android POST_BUILD
    COMMAND ${CMAKE_STRIP} $<TARGET_FILE:osrm_android>)
endif()
