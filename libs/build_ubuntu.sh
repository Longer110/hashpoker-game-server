#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"     # 进入 libs/

PREFIX="$(pwd)/runtime"
JIT_DIR="$(pwd)/luajit"
LSK_DIR="$(pwd)/luasocket-3.1.0/src"
CJSON_DIR="$(pwd)/lua-cjson-2.1.0"
PB_SRC_DIR="$(pwd)/protoc-gen-lua/protobuf"
HIREDIS_DIR="${HIREDIS_DIR:-$(pwd)/hiredis-1.3.0}"

# 默认开启 TLS
ENABLE_REDIS_TLS="${ENABLE_REDIS_TLS:-1}"

# 可覆写：CC/CFLAGS/LDFLAGS
CC="${CC:-gcc}"
CFLAGS_COMMON="${CFLAGS:- -O2 -fPIC -fno-common}"
LDFLAGS_COMMON="${LDFLAGS:- }"

# LuaJIT 头可能在 include/ 或 include/luajit-2.1
INC_FLAGS="-I${PREFIX}/include -I${PREFIX}/include/luajit-2.1"

mkdir -p "$PREFIX/include" "$PREFIX/lib" \
         "$PREFIX/lib/socket" "$PREFIX/lib/mime"

echo ">>> [linux] Build LuaJIT (shared)…"
pushd "$JIT_DIR" >/dev/null
make -C src clean
make -j"$(nproc)" CC="$CC"
make install PREFIX="$PREFIX"
popd >/dev/null

echo ">>> [linux] Build LuaSocket (manual)…"
pushd "$LSK_DIR" >/dev/null
COMMON_C="luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c options.c \
          inet.c usocket.c except.c select.c tcp.c udp.c"
for f in $COMMON_C; do
  echo "  CC  $f"
  "$CC" $CFLAGS_COMMON $INC_FLAGS -c "$f"
done
echo "  LD  socket/core.so"
"$CC" -shared -o "$PREFIX/lib/socket/core.so" \
  $(echo $COMMON_C | sed 's/\.c/\.o/g') \
  -L"$PREFIX/lib" -lluajit-5.1 \
  -Wl,-rpath,'$ORIGIN/..' \
  $LDFLAGS_COMMON

echo "  CC  mime.c"
"$CC" $CFLAGS_COMMON $INC_FLAGS -c mime.c
echo "  LD  mime/core.so"
"$CC" -shared -o "$PREFIX/lib/mime/core.so" \
  mime.o \
  luasocket.o timeout.o buffer.o io.o auxiliar.o compat.o \
  options.o inet.o usocket.o except.o select.o tcp.o udp.o \
  -L"$PREFIX/lib" -lluajit-5.1 \
  -Wl,-rpath,'$ORIGIN/..' \
  $LDFLAGS_COMMON
cp -a socket.lua ltn12.lua mime.lua "$PREFIX/"
rm -f *.o
popd >/dev/null

echo ">>> [linux] Build lua-cjson…"
pushd "$CJSON_DIR" >/dev/null
"$CC" $CFLAGS_COMMON $INC_FLAGS -c lua_cjson.c
"$CC" $CFLAGS_COMMON $INC_FLAGS -c strbuf.c
"$CC" $CFLAGS_COMMON $INC_FLAGS -c fpconv.c
"$CC" -shared -o "$PREFIX/lib/cjson.so" \
  lua_cjson.o strbuf.o fpconv.o \
  -L"$PREFIX/lib" -lluajit-5.1 \
  -Wl,-rpath,'$ORIGIN/..' \
  $LDFLAGS_COMMON
rm -f *.o *.bak || true
popd >/dev/null

echo  ">>> [linux] Build pb.so …"
mkdir -p "$PREFIX/lib"
pushd "$PB_SRC_DIR" >/dev/null
"$CC" $CFLAGS_COMMON $INC_FLAGS \
  -shared -o "$PREFIX/lib/pb.so" pb.c \
  -L"$PREFIX/lib" -lluajit-5.1 \
  -Wl,-rpath,'$ORIGIN/..' \
  $LDFLAGS_COMMON
popd >/dev/null

echo ">>> [linux] Install spdlog (header-only)…"
SPDLOG_DIR="$(pwd)/spdlog"
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

echo ">>> [linux] Build hiredis …"
pushd "$HIREDIS_DIR" >/dev/null
make clean

if [ "$ENABLE_REDIS_TLS" = "1" ]; then
  if ! command -v pkg-config >/dev/null 2>&1; then
    echo "!! 需要 pkg-config；请先安装：sudo apt-get install -y pkg-config"
    exit 2
  fi
  if ! pkg-config --exists openssl; then
    echo "!! 未找到 OpenSSL。请安装：sudo apt-get install -y libssl-dev"
    exit 2
  fi
  OPENSSL_CFLAGS="$(pkg-config --cflags openssl)"
  OPENSSL_LDFLAGS="$(pkg-config --libs openssl)"
  export CFLAGS="${OPENSSL_CFLAGS} ${CFLAGS:-}"
  export LDFLAGS="${OPENSSL_LDFLAGS} ${LDFLAGS:-}"
  echo "Using OpenSSL via pkg-config"
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
cp -a libhiredis*.so* "$PREFIX/lib/" || true
popd >/dev/null

echo ">>> Done. 输出在 $PREFIX"




echo ">>> [Linux] Build LuaSec (with OpenSSL)…"
LSEC_DIR="$(pwd)/luasec"
pushd "$LSEC_DIR/src" >/dev/null

make clean || true

LUA_INC_DIR="$PREFIX/include/luajit-2.1"
LUA_LIB_DIR="$PREFIX/lib"

# 先编出 LuaSec 自带的 libluasocket.a
echo ">>> build bundled libluasocket.a"
make -C luasocket clean || true
make -C luasocket \
  CC="${CC:-gcc}" \
  CFLAGS="-fPIC -O2 -I${LUA_INC_DIR}"

# OpenSSL：优先用 pkg-config，兜底用系统路径
if pkg-config --exists openssl; then
  OPENSSL_CFLAGS="$(pkg-config --cflags openssl)"
  OPENSSL_LIBS="$(pkg-config --libs openssl)"   # 一般是 -lssl -lcrypto
else
  OPENSSL_INCDIR="${OPENSSL_INCDIR:-/usr/include}"
  if [ -d /usr/lib/x86_64-linux-gnu ]; then
    OPENSSL_LIBDIR="${OPENSSL_LIBDIR:-/usr/lib/x86_64-linux-gnu}"
  else
    OPENSSL_LIBDIR="${OPENSSL_LIBDIR:-/usr/lib64}"
  fi
  OPENSSL_CFLAGS="-I${OPENSSL_INCDIR}"
  OPENSSL_LIBS="-L${OPENSSL_LIBDIR} -lssl -lcrypto"
fi

# 关键：包含头、库路径，并显式链接 LuaJIT 和本地 luasocket
CPPFLAGS="-I${LUA_INC_DIR} -I. -I./luasocket"
CFLAGS="-fPIC -O2 ${CPPFLAGS} ${OPENSSL_CFLAGS}"
LDFLAGS_EXTRA="-shared -fPIC -L./luasocket -L${LUA_LIB_DIR}"
LIBS_EXTRA="-lluasocket -lluajit-5.1 ${OPENSSL_LIBS}"

echo ">>> make ssl.so"
make linux V=1 \
  CC="${CC:-gcc}" \
  WITH_LUASOCKET=1 \
  LUAINC="-I${LUA_INC_DIR}" \
  CFLAGS="$CFLAGS" \
  LIB_OPTION="-shared -fPIC" \
  LDFLAGS="${LDFLAGS:-} ${LDFLAGS_EXTRA}" \
  LIBS="${LIBS:-} ${LIBS_EXTRA}"

echo ">>> [Linux] Install LuaSec (manual move)…"
rm -rf "$PREFIX/lib/ssl.so" 

# 移动 .so（就在 luasec/src 里）
if [ -f "ssl.so" ]; then
  mv ssl.so "$PREFIX/lib" 
else
  echo "!! 未找到 ssl.so（期待在 luasec/src），请上翻查看 make 输出"
  popd >/dev/null
  exit 3
fi
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