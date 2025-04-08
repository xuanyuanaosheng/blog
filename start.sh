#!/bin/bash
#
# chkconfig:    2345 90 10
# description:  A generic service startup script for CentOS 6
#
# Usage:        /etc/init.d/<script_name> {start|stop|status|restart}

# 服务名称（必须修改）
SERVICE_NAME="your_service_name"
# 进程名（用于 pgrep 检查）
PROCESS_NAME="your_process_name"
# 启动命令（必须修改）
START_CMD="/path/to/your/command --args"
# 停止命令（可选，默认 killall）
STOP_CMD="killall $PROCESS_NAME"

# 检查进程是否运行
is_running() {
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# 启动服务
start() {
    if is_running; then
        echo "$SERVICE_NAME is already running"
        return 0
    fi
    echo -n "Starting $SERVICE_NAME: "
    $START_CMD &> /dev/null &
    sleep 2
    if is_running; then
        echo "OK"
    else
        echo "FAILED"
        exit 1
    fi
}

# 停止服务
stop() {
    if ! is_running; then
        echo "$SERVICE_NAME is not running"
        return 0
    fi
    echo -n "Stopping $SERVICE_NAME: "
    $STOP_CMD &> /dev/null
    sleep 2
    if is_running; then
        echo "FAILED (try manually)"
        exit 1
    else
        echo "OK"
    fi
}

# 服务状态
status() {
    if is_running; then
        echo "$SERVICE_NAME is running"
    else
        echo "$SERVICE_NAME is stopped"
    fi
}

# 主逻辑
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
esac

exit 0