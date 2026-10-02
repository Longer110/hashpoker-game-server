#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"     # 进入 libs/
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

# ========== 目录 ==========
PREFIX="$(pwd)/runtime"
JIT_DIR="$(pwd)/luajit"
LSK_DIR="$(pwd)/luasocket-3.1.0/src"
CJSON_DIR="$(pwd)/lua-cjson-2.1.0"
PB_SRC_DIR="$(pwd)/protoc-gen-lua/protobuf"
RPP_SRC_DIR="$(pwd)/redis-plus-plus-1.3.15"
SPDLOG_DIR="$(pwd)/spdlog"
HIREDIS_DIR="$(pwd)/hiredis-1.3.0"

# ========== 编译器 & flags ==========
CC="${CC:-clang}"
CFLAGS_COMMON="${CFLAGS:- -O2 -fPIC -fno-common}"
LDFLAGS_COMMON="${LDFLAGS:- }"

# ✅ LuaJIT 头文件 cflags（稍后由 pkg-config/回退逻辑决定）
INC_FLAGS=""

# macOS 动态模块（.so）打包参数（给 Lua 模块）
BUNDLE_FLAGS="-bundle -undefined dynamic_lookup"
RPATH_FLAGS="-Wl,-rpath,@loader_path/.."

# 选项：TLS 和 C++ 标准
ENABLE_REDIS_TLS="${ENABLE_REDIS_TLS:-1}"    # 1=开启 TLS（需要 openssl@3）
REDISPP_CXX_STD="${REDISPP_CXX_STD:-17}"     # 11 或 17

mkdir -p "$PREFIX/include" "$PREFIX/lib" \
         "$PREFIX/lib/socket" "$PREFIX/lib/mime"

echo ">>> [macOS] Build LuaJIT (shared)…"
pushd "$JIT_DIR" >/dev/null
make -C src clean
NPROC="$(sysctl -n hw.ncpu)"
make -j"$NPROC" CC="$CC" \
     MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"
make install PREFIX="$PREFIX"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
if pkg-config --exists luajit; then
  INC_FLAGS="$(pkg-config --cflags luajit)"
else
  INC_FLAGS="-I${PREFIX}/include/luajit-2.1"
fi
echo "Using INC_FLAGS: $INC_FLAGS"
popd >/dev/null

echo ">>> [macOS] Build LuaSocket (manual)…"
pushd "$LSK_DIR" >/dev/null
COMMON_C="luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c options.c \
          inet.c usocket.c except.c select.c tcp.c udp.c"
for f in $COMMON_C; do
  echo "  CC  $f"
  "$CC" $CFLAGS_COMMON $INC_FLAGS -c "$f"
done
echo "  LD  socket/core.so (bundle)"
"$CC" $BUNDLE_FLAGS $RPATH_FLAGS -o "$PREFIX/lib/socket/core.so" \
  $(echo $COMMON_C | sed 's/\.c/\.o/g') \
  $LDFLAGS_COMMON
echo "  CC  mime.c"
"$CC" $CFLAGS_COMMON $INC_FLAGS -c mime.c
echo "  LD  mime/core.so (bundle)"
"$CC" $BUNDLE_FLAGS $RPATH_FLAGS -o "$PREFIX/lib/mime/core.so" \
  mime.o \
  luasocket.o timeout.o buffer.o io.o auxiliar.o compat.o \
  options.o inet.o usocket.o except.o select.o tcp.o udp.o \
  $LDFLAGS_COMMON
cp -a socket.lua ltn12.lua mime.lua "$PREFIX/"
rm -f *.o
popd >/dev/null

echo ">>> [macOS] Build lua-cjson…"
pushd "$CJSON_DIR" >/dev/null
"$CC" $CFLAGS_COMMON $INC_FLAGS -c lua_cjson.c
"$CC" $CFLAGS_COMMON $INC_FLAGS -c strbuf.c
"$CC" $CFLAGS_COMMON $INC_FLAGS -c fpconv.c
"$CC" $BUNDLE_FLAGS $RPATH_FLAGS -o "$PREFIX/lib/cjson.so" \
  lua_cjson.o strbuf.o fpconv.o \
  $LDFLAGS_COMMON
rm -f *.o *.bak || true
popd >/dev/null

echo  ">>> [macOS] Build pb.so …"
mkdir -p "$PREFIX/lib"
pushd "$PB_SRC_DIR" >/dev/null
DARWIN_ENDIAN_FLAGS="-include libkern/OSByteOrder.h \
  -Dhtobe16=OSSwapHostToBigInt16   -Dbe16toh=OSSwapBigToHostInt16 \
  -Dhtole16=OSSwapHostToLittleInt16 -Dle16toh=OSSwapLittleToHostInt16 \
  -Dhtobe32=OSSwapHostToBigInt32   -Dbe32toh=OSSwapBigToHostInt32 \
  -Dhtole32=OSSwapHostToLittleInt32 -Dle32toh=OSSwapLittleToHostInt32 \
  -Dhtobe64=OSSwapHostToBigInt64   -Dbe64toh=OSSwapBigToHostInt64 \
  -Dhtole64=OSSwapHostToLittleInt64 -Dle64toh=OSSwapLittleToHostInt64"
"$CC" $CFLAGS_COMMON $INC_FLAGS $DARWIN_ENDIAN_FLAGS \
  $BUNDLE_FLAGS $RPATH_FLAGS \
  -o "$PREFIX/lib/pb.so" pb.c \
  $LDFLAGS_COMMON
popd >/dev/null

echo ">>> [macOS] Install spdlog (header-only)…"
if [ ! -d "$SPDLOG_DIR/include/spdlog" ]; then
  echo "!!! ERROR: $SPDLOG_DIR/include/spdlog 不存在"
  exit 2
fi
mkdir -p "$PREFIX/include"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SPDLOG_DIR/include/spdlog" "$PREFIX/include/"
else
  rm -rf "$PREFIX/include/spdlog"
  cp -r "$SPDLOG_DIR/include/spdlog" "$PREFIX/include/"
fi
echo ">>> spdlog headers installed to: $PREFIX/include/spdlog"

# ========================
# hiredis (with OpenSSL)
# ========================
echo ">>> [macOS] Build hiredis …"
pushd "$HIREDIS_DIR" >/dev/null
make clean
if [ "$ENABLE_REDIS_TLS" = "1" ]; then
  if command -v brew >/dev/null 2>&1; then
    OPENSSL_PREFIX="$(brew --prefix openssl@3 || true)"
    if [ -n "$OPENSSL_PREFIX" ]; then
      export CFLAGS="-I${OPENSSL_PREFIX}/include ${CFLAGS:-}"
      export LDFLAGS="-L${OPENSSL_PREFIX}/lib ${LDFLAGS:-}"
      echo "Using OpenSSL from: $OPENSSL_PREFIX"
    else
      echo "!! 未找到 openssl@3，TLS 也许会失败，可设置 ENABLE_REDIS_TLS=0"
    fi
  fi
  make USE_SSL=1 static
else
  make static
fi
make PREFIX="$PREFIX" install
# 兜底拷贝，保证头&库都在
mkdir -p "$PREFIX/include/hiredis" "$PREFIX/include/adapters" "$PREFIX/lib"
cp -a adapters/* "$PREFIX/include/adapters/" || true
cp -a hiredis.h hiredis_ssl.h async.h alloc.h read.h sds.h "$PREFIX/include/hiredis/" || true
cp -a libhiredis*.a "$PREFIX/lib/" || true
cp -a libhiredis*.dylib "$PREFIX/lib/" || true
popd >/dev/null



echo ">>> [Linux] Build librdkafka …"
KAFKA_DIR="$(pwd)/librdkafka"
pushd "$KAFKA_DIR" >/dev/null
# 清理旧构建
make clean || true
# 配置 + 构建
./configure --prefix="$PREFIX" --enable-static --enable-shared
make -j$(nproc)
make install
popd >/dev/null



echo ">>> [macOS] Build LuaSec (with OpenSSL)…"
LSEC_DIR="$(pwd)/luasec"
pushd "$LSEC_DIR" >/dev/null
make clean || true

# OpenSSL (Homebrew)
if command -v brew >/dev/null 2>&1; then
  OPENSSL_PREFIX="$(brew --prefix openssl@3 || true)"
fi
if [ -z "${OPENSSL_PREFIX:-}" ] || [ ! -d "$OPENSSL_PREFIX" ]; then
  echo "!! 未找到 openssl@3（Homebrew），请安装：brew install openssl@3"
  echo "!! 或显式设置 OPENSSL_PREFIX=/path/to/openssl"
  exit 2
fi

# 关键：把 LuaJIT 的 include 强行加进编译器标志，避免被 Makefile 覆盖
CFLAGS_SAVE="${CFLAGS:-}"
CPPFLAGS_SAVE="${CPPFLAGS:-}"
export CFLAGS="-I$PREFIX/include/luajit-2.1 ${CFLAGS_SAVE}"
export CPPFLAGS="-I$PREFIX/include/luajit-2.1 ${CPPFLAGS_SAVE}"

# V=1 打印完整命令，方便确认有 -I.../luajit-2.1
make macosx V=1 \
  CC="$CC" \
  LUALIB="-L$PREFIX/lib -lluajit-5.1" \
  OPENSSL_INCDIR="$OPENSSL_PREFIX/include" \
  OPENSSL_LIBDIR="$OPENSSL_PREFIX/lib" \
  WITH_LUASOCKET=1

echo ">>> [Mac] Install LuaSec (manual move)…"
rm -rf "$PREFIX/lib/ssl.so" 

# 移动 .so（就在 luasec/src 里）
if [ -f "ssl.so" ]; then
  mv ssl.so "$PREFIX/lib/" 
else
  echo "!! 未找到 ssl.so（期待在 luasec/src），请上翻查看 make 输出"
  popd >/dev/null
  exit 3
fi

# ========================
# librdkafka
# ========================