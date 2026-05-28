#!/usr/bin/env bash
set -euo pipefail
# fetch_deps.sh — 下載所有 OSRM for Android 所需的相依原始碼
# Usage: ./fetch_deps.sh [output_dir]
# Default output: ./deps/

OUT="${1:-$(dirname "$0")/../deps}"
mkdir -p "$OUT"
cd "$OUT"

echo "=== Fetching OSRM Android dependencies ==="
echo "Output dir: $OUT"
echo ""

# ---------- versions ----------
BOOST_VER=1.83.0
TBB_VER=v2021.10.0
LUA_VER=5.3.6
ZLIB_VER=v1.3
EXPAT_VER=R_2_6_0
BZIP2_VER=1.0.8
LIBXML2_VER=v2.12.5
CIVETWEB_VER=v1.15
OSRM_VER=v5.27.1

# ---------- Boost (needs special handling) ----------
if [ ! -d "boost_${BOOST_VER//./_}" ]; then
  echo "[1/8] Downloading Boost ${BOOST_VER} ..."
  wget -q "https://archives.boost.io/release/${BOOST_VER}/source/boost_${BOOST_VER//./_}.tar.bz2"
  tar -xf "boost_${BOOST_VER//./_}.tar.bz2"
  rm "boost_${BOOST_VER//./_}.tar.bz2"
else
  echo "[1/8] Boost already present"
fi

# ---------- oneTBB ----------
if [ ! -d "oneTBB" ]; then
  echo "[2/8] Downloading oneTBB ${TBB_VER} ..."
  git clone --depth 1 --branch "$TBB_VER" https://github.com/oneapi-src/oneTBB.git
else
  echo "[2/8] oneTBB already present"
fi

# ---------- Lua ----------
if [ ! -d "lua-${LUA_VER}" ]; then
  echo "[3/8] Downloading Lua ${LUA_VER} ..."
  wget -q "https://www.lua.org/ftp/lua-${LUA_VER}.tar.gz"
  tar -xf "lua-${LUA_VER}.tar.gz"
  rm "lua-${LUA_VER}.tar.gz"
else
  echo "[3/8] Lua already present"
fi

# ---------- zlib ----------
if [ ! -d "zlib" ]; then
  echo "[4/8] Downloading zlib ${ZLIB_VER} ..."
  git clone --depth 1 --branch "$ZLIB_VER" https://github.com/madler/zlib.git
else
  echo "[4/8] zlib already present"
fi

# ---------- expat ----------
if [ ! -d "libexpat" ]; then
  echo "[5/8] Downloading expat ${EXPAT_VER} ..."
  git clone --depth 1 --branch "$EXPAT_VER" https://github.com/libexpat/libexpat.git
else
  echo "[5/8] expat already present"
fi

# ---------- bzip2 ----------
if [ ! -d "bzip2-${BZIP2_VER}" ]; then
  echo "[6/8] Downloading bzip2 ${BZIP2_VER} ..."
  wget -q "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VER}.tar.gz"
  tar -xf "bzip2-${BZIP2_VER}.tar.gz"
  rm "bzip2-${BZIP2_VER}.tar.gz"
else
  echo "[6/8] bzip2 already present"
fi

# ---------- libxml2 ----------
if [ ! -d "libxml2" ]; then
  echo "[7/8] Downloading libxml2 ${LIBXML2_VER} ..."
  git clone --depth 1 --branch "$LIBXML2_VER" https://gitlab.gnome.org/GNOME/libxml2.git
else
  echo "[7/8] libxml2 already present"
fi

# ---------- civetweb ----------
if [ ! -d "civetweb" ]; then
  echo "[8/8] Downloading civetweb ${CIVETWEB_VER} ..."
  git clone --depth 1 --branch "$CIVETWEB_VER" https://github.com/civetweb/civetweb.git
else
  echo "[8/8] civetweb already present"
fi

# ---------- OSRM ----------
if [ ! -d "osrm-backend" ]; then
  echo "[Extra] Downloading OSRM backend ${OSRM_VER} ..."
  git clone --depth 1 --branch "$OSRM_VER" https://github.com/Project-OSRM/osrm-backend.git
else
  echo "[Extra] OSRM backend already present"
fi

echo ""
echo "=== All dependencies fetched ==="

# =====================================================================
# 🔥 🔥 影子大合流戰略：強行將安全屋 (osrm-backend-plus) 的正確骨架注入硬碟！
# =====================================================================
echo "=== 步驟 [Extra 2]: 發動影子覆蓋戰略！強制注入安全屋骨架 ==="

# 取得腳本當前的專案根目錄路徑
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 物理將安全屋內的正確檔案，一字不差地強行覆蓋回剛剛被拉下來的 deps/osrm-backend 中
cp -rf "$PROJECT_ROOT/osrm-backend-plus/"* "$PROJECT_ROOT/deps/osrm-backend/"

# 一鍵物理切除 rapidjson 內部非法的 const 賦值盲腸 (第 319 行)
sed -i '319s/s = rhs.s; length = rhs.length;/s = rhs.s;/g' "$PROJECT_ROOT/deps/osrm-backend/third_party/rapidjson/include/rapidjson/document.h"

echo "=== 🎉 🎉 恭喜！影子合流成功！新筆電 OSRM 原始碼已自動物理矯正完畢！ ==="
