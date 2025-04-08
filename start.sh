#!/bin/bash

# 检查参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <process_name>"
    echo "Example: $0 nginx"
    exit 1
fi

PROCESS_NAME=$1
# 这里预设启动命令（根据实际需求修改）
START_COMMAND="systemctl start $PROCESS_NAME"  # 示例：系统服务
# 或者 START_COMMAND="/path/to/binary"       # 示例：直接启动二进制文件

# 检查进程是否存在
check_process() {
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
        echo "$PROCESS_NAME, RUNNING"
        return 0
    else
        echo "$PROCESS_NAME, STOP"
        return 1
    fi
}

# 主逻辑
if ! check_process; then
    echo "Starting $PROCESS_NAME..."
    eval "$START_COMMAND"
    
    # 验证是否启动成功
    sleep 2
    if check_process; then
        echo "$PROCESS_NAME started successfully"
    else
        echo "Failed to start $PROCESS_NAME"
        exit 1
    fi
fi

exit 0