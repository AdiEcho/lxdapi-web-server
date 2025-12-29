#!/bin/bash

INSTALL_DIR="/opt/lxdapi"
SERVICE_NAME="lxdapi"
SCRIPT_PATH="/usr/local/bin/lxdapi"

GREEN='\033[0;32m'
NC='\033[0m'

if [ "$(realpath "$0")" != "$SCRIPT_PATH" ]; then
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "lxdapi 命令已安装"
    echo "用法: lxdapi 或 lxdapi {start|stop|restart|status|config|machine-id}"
    exit 0
fi

wait_progress() {
    echo "等待服务响应..."
    for i in {1..10}; do
        printf "\r[%-10s] %d/10s" "$(printf '#%.0s' $(seq 1 $i))" "$i"
        sleep 1
    done
    echo
}

do_start() {
    systemctl start $SERVICE_NAME
    echo "lxdapi 已启动"
    wait_progress
    systemctl status $SERVICE_NAME --no-pager | head -5
}

do_stop() {
    systemctl stop $SERVICE_NAME
    echo "lxdapi 已停止"
    sleep 1
    systemctl status $SERVICE_NAME --no-pager | head -5
}

do_restart() {
    systemctl restart $SERVICE_NAME
    echo "lxdapi 已重启"
    wait_progress
    systemctl status $SERVICE_NAME --no-pager | head -5
}

do_status() {
    systemctl status $SERVICE_NAME --no-pager | head -5
    echo
    echo "===== 最近日志 ====="
    journalctl -u $SERVICE_NAME -n 10 --no-pager
}

do_config() {
    CONFIG_FILE="$INSTALL_DIR/configs/config.yaml"
    PORT=$(grep "port:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
    API_KEY=$(grep "api_key:" "$CONFIG_FILE" | awk -F'"' '{print $2}')
    echo "端口: $PORT"
    echo "API密钥: $API_KEY"
}

do_machine_id() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac
    $INSTALL_DIR/lxdapi-$ARCH --machine-id
}

show_menu() {
    echo
    echo "================================"
    echo "      LXDAPI 管理工具"
    echo "================================"
    echo "1. 启动"
    echo "2. 停止"
    echo "3. 重启"
    echo "4. 状态"
    echo "5. 配置"
    echo "6. 机器码"
    echo "0. 退出"
    echo "================================"
    read -rp "$(echo -e "${GREEN}请选择 [0-6]: ${NC}")" choice
    
    case "$choice" in
        1) do_start ;;
        2) do_stop ;;
        3) do_restart ;;
        4) do_status ;;
        5) do_config ;;
        6) do_machine_id ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
    show_menu
}

case "$1" in
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    status) do_status ;;
    config) do_config ;;
    machine-id) do_machine_id ;;
    "") show_menu ;;
    *)
        echo "用法: lxdapi 或 lxdapi {start|stop|restart|status|config|machine-id}"
        exit 1
        ;;
esac
