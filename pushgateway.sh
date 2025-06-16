#!/bin/bash
set -eo pipefail

# 配置区域 - 可修改
PUSHGATEWAY_USER="utils"
PUSHGATEWAY_HOME="/opt/pushgateway"
PUSHGATEWAY_VERSION="1.6.2"
DOWNLOAD_URL="https://github.com/prometheus/pushgateway/releases/download/v${PUSHGATEWAY_VERSION}/pushgateway-${PUSHGATEWAY_VERSION}.linux-amd64.tar.gz"
LISTEN_PORT=9091

# 运行时变量
CURRENT_USER=$(id -un)
PID_FILE="${PUSHGATEWAY_HOME}/pushgateway.pid"
LOG_FILE="${PUSHGATEWAY_HOME}/pushgateway.log"
DATA_FILE="${PUSHGATEWAY_HOME}/metrics.store"

##############################################
# 工具函数
##############################################

check_user() {
  if [[ "$CURRENT_USER" != "$PUSHGATEWAY_USER" ]]; then
    echo "ERROR: Must run as $PUSHGATEWAY_USER, current user is $CURRENT_USER" >&2
    exit 1
  fi
}

check_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Pushgateway is running (PID: $pid)"
      return 0
    else
      rm -f "$PID_FILE"
    fi
  fi
  return 1
}

##############################################
# 主功能函数
##############################################

install() {
  echo "Installing Pushgateway v${PUSHGATEWAY_VERSION}..."
  mkdir -p "$PUSHGATEWAY_HOME"
  
  local temp_dir=$(mktemp -d)
  curl -L "$DOWNLOAD_URL" | tar -xz -C "$temp_dir" --strip-components=1
  
  # 原子化安装
  mv "$temp_dir/pushgateway" "$PUSHGATEWAY_HOME/pushgateway-${PUSHGATEWAY_VERSION}"
  ln -sfn "$PUSHGATEWAY_HOME/pushgateway-${PUSHGATEWAY_VERSION}" "$PUSHGATEWAY_HOME/pushgateway"
  
  # 创建管理脚本
  cat > "$PUSHGATEWAY_HOME/control.sh" <<'EOF'
#!/bin/bash
set -e

case "$1" in
  start)
    nohup ./pushgateway --web.listen-address=:$LISTEN_PORT \
      --persistence.file=metrics.store \
      --persistence.interval=5m > pushgateway.log 2>&1 &
    echo $! > pushgateway.pid
    ;;
  stop)
    if [ -f pushgateway.pid ]; then
      kill -TERM $(cat pushgateway.pid)
      rm -f pushgateway.pid
    fi
    ;;
  restart)
    ./control.sh stop
    sleep 2
    ./control.sh start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac
EOF

  chmod +x "$PUSHGATEWAY_HOME/control.sh"
  echo "Installation complete. Management script: $PUSHGATEWAY_HOME/control.sh"
}

upgrade() {
  if check_running; then
    echo "Stopping current instance..."
    "$PUSHGATEWAY_HOME/control.sh" stop
  fi

  # 备份旧数据
  if [[ -f "$DATA_FILE" ]]; then
    cp "$DATA_FILE" "$DATA_FILE.bak"
  fi

  echo "Upgrading to v${PUSHGATEWAY_VERSION}..."
  install

  if [[ -f "$DATA_FILE.bak" ]]; then
    mv "$DATA_FILE.bak" "$DATA_FILE"
  fi

  echo "Upgrade complete. You can start it with: $PUSHGATEWAY_HOME/control.sh start"
}

##############################################
# 主逻辑
##############################################

check_user

case "$1" in
  install)
    install
    ;;
  upgrade)
    upgrade
    ;;
  *)
    echo "Usage: $0 {install|upgrade}"
    echo "Environment variables you can set:"
    echo "  PUSHGATEWAY_VERSION - Target version (default: ${PUSHGATEWAY_VERSION})"
    echo "  LISTEN_PORT         - Listening port (default: ${LISTEN_PORT})"
    exit 1
    ;;
esac

echo "Operation completed"




#!/bin/bash
set -eo pipefail

# 配置区域（需与安装脚本保持一致）
PUSHGATEWAY_USER="utils"
PUSHGATEWAY_HOME="/opt/pushgateway"
CONTROL_SCRIPT="${PUSHGATEWAY_HOME}/control.sh"
PID_FILE="${PUSHGATEWAY_HOME}/pushgateway.pid"
LISTEN_PORT=9091

##############################################
# 工具函数
##############################################

# 检查当前用户
check_user() {
  if [[ "$(id -un)" != "$PUSHGATEWAY_USER" ]]; then
    echo "ERROR: Must run as $PUSHGATEWAY_USER" >&2
    exit 1
  fi
}

# 检查进程是否运行
check_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      # 检查端口监听状态
      if netstat -tuln | grep -q ":$LISTEN_PORT "; then
        echo "Pushgateway is running (PID: $pid, Port: $LISTEN_PORT)"
        return 0
      else
        echo "WARN: Process exists but port not listening" >&2
        return 1
      fi
    else
      rm -f "$PID_FILE"
    fi
  fi
  return 1
}

# 获取进程状态详情
get_status() {
  if check_running; then
    local pid=$(cat "$PID_FILE")
    echo "=== Process Status ==="
    ps -fp "$pid"
    echo -e "\n=== Port Listening ==="
    netstat -tuln | grep ":$LISTEN_PORT " || true
    echo -e "\n=== Recent Logs ==="
    tail -n 10 "${PUSHGATEWAY_HOME}/pushgateway.log" 2>/dev/null || echo "No log file found"
  else
    echo "Pushgateway is NOT running"
    return 1
  fi
}

##############################################
# 主逻辑
##############################################

check_user

if ! check_running; then
  echo "Pushgateway is not running. Attempting to start..."
  "$CONTROL_SCRIPT" start
  sleep 2  # 等待启动完成
  
  if check_running; then
    echo "Startup successful"
    get_status
  else
    echo "ERROR: Failed to start Pushgateway" >&2
    echo "Check logs: ${PUSHGATEWAY_HOME}/pushgateway.log" >&2
    exit 1
  fi
else
  get_status
fi
