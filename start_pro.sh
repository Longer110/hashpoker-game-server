#!/bin/bash
set -euo pipefail
# 服务 ID 列表
server_table=(
    300 302 304 305 309
    313 550 551 562 563 565
    566
)

# 确保 tmp 目录存在
mkdir -p ./tmp
start_service() {
    local name=$1
    shift
    nohup ./cservice "$@" >> "./tmp/cservice_${name}.log" 2>&1 &
    echo $! > "./tmp/cservice_${name}.pid"
    echo "Started cservice $name with PID $(cat ./tmp/cservice_${name}.pid)"
}

stop_service() {
    local name=$1
    local pid_file="./tmp/cservice_${name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid"
            echo "Stopped cservice $name (PID $pid)"
        else
            echo "Process $pid not running for $name"
        fi
        rm -f "$pid_file"
    else
        echo "No pid file for $name"
    fi
}
start_all() {
    for id in "${server_table[@]}"; do
        if [[ "$id" == "313" ]]; then
            start_service "$id" "$id" 50043
        else
            start_service "$id" "$id"
        fi
    done
}
stop_all() {
    for id in "${server_table[@]}"; do
        stop_service "$id"
    done
}
case "${1:-}" in
    start)
        start_all
    ;;
    stop)
        stop_all
    ;;
    restart)
        stop_all
        sleep 1
        start_all
    ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
    ;;
esac
