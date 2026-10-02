#!/bin/bash
# =========================================
# 使用 protoc-gen-lua 编译 proto 为 Lua
# 用法: ./gen_pb.sh input.proto
# =========================================

# 检查参数
if [ $# -ne 1 ]; then
  echo "用法: $0 input.proto"
  exit 1
fi

PROTO_ROOT="./lua/protocol/proto"
PB_ROOT="./lua/protocol/pb"

PROTO_FILE="$PROTO_ROOT/$1"
# 判断 proto 文件是否存在
if [ ! -f "$PROTO_FILE" ]; then
  echo "错误: 找不到文件 $PROTO_FILE"
  exit 1
fi

OUTPUT_DIR="$PB_ROOT"

protoc --lua_out="$OUTPUT_DIR" "$PROTO_FILE"

# 检查是否成功
if [ $? -eq 0 ]; then
  echo "✅ 成功生成 Lua 文件到: $OUTPUT_DIR"
else
  echo "❌ 编译失败"
  exit 3
fi