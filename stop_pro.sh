#!/bin/bash

# 要查找的进程名
process_name="cservice"



while true
do
# 查找名为 $process_name 的进程并关闭它
	process_id=$(ps aux | grep -v grep | grep -m1 "$process_name" | awk '{print $2}')

	if [ -z "$process_id" ]; then
		echo "未找到正在运行的 $process_name 进程."
		break
	else
		kill "$process_id"
		echo "$process_name 进程 (PID: $process_id) 已成功关闭."
	fi
done

redis-cli -h 127.0.0.1 -p 6380 -a Yh9GFN7j0KI7GYjo_redis flushall


