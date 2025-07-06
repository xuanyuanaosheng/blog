#!/bin/bash

# Java 微服务管理脚本
# 用法: ./service_manager.sh {start|stop|status|restart} <service_name>
# 配置: 修改下面的配置部分以适应您的环境

#======================================
# 配置部分 - 请根据实际环境修改
#======================================

# 服务基础配置
SERVICE_HOME="/opt/microservices"          # 服务根目录
JAVA_HOME="/usr/lib/jvm/java-11-openjdk"   # Java 安装路径
LOG_DIR="/var/log/microservices"           # 日志目录
PID_DIR="/var/run/microservices"           # PID 文件目录
USER="appuser"                             # 运行服务的用户

# JVM 配置
JVM_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps"

# 定义服务列表及其配置
declare -A SERVICES=(
    ["user-service"]="user-service-1.0.0.jar:8080:prod"
    ["order-service"]="order-service-1.0.0.jar:8081:prod"
    ["payment-service"]="payment-service-1.0.0.jar:8082:prod"
    ["inventory-service"]="inventory-service-1.0.0.jar:8083:prod"
    ["notification-service"]="notification-service-1.0.0.jar:8084:prod"
)

#======================================
# 函数定义
#======================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 检查用户权限
check_user() {
    if [ "$USER" != "root" ] && [ "$(whoami)" != "$USER" ]; then
        print_error "此脚本需要以 root 或 $USER 用户身份运行"
        exit 1
    fi
}

# 创建必要的目录
create_directories() {
    for dir in "$LOG_DIR" "$PID_DIR"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            if [ "$(whoami)" = "root" ]; then
                chown "$USER:$USER" "$dir"
            fi
        fi
    done
}

# 验证服务名称
validate_service() {
    local service_name="$1"
    if [ -z "$service_name" ]; then
        print_error "请指定服务名称"
        show_usage
        exit 1
    fi
    
    if [[ ! ${SERVICES[$service_name]+_} ]]; then
        print_error "未知的服务: $service_name"
        print_info "可用的服务: ${!SERVICES[@]}"
        exit 1
    fi
}

# 解析服务配置
parse_service_config() {
    local service_name="$1"
    local config="${SERVICES[$service_name]}"
    
    IFS=':' read -r JAR_FILE PORT PROFILE <<< "$config"
    SERVICE_DIR="$SERVICE_HOME/$service_name"
    JAR_PATH="$SERVICE_DIR/$JAR_FILE"
    PID_FILE="$PID_DIR/${service_name}.pid"
    LOG_FILE="$LOG_DIR/${service_name}.log"
    ERROR_LOG="$LOG_DIR/${service_name}_error.log"
}

# 获取进程ID
get_pid() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    return 1
}

# 检查服务状态
check_status() {
    local service_name="$1"
    local pid=$(get_pid "$service_name")
    
    if [ -n "$pid" ]; then
        return 0  # 运行中
    else
        return 1  # 未运行
    fi
}

# 启动服务
start_service() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    print_info "正在启动服务: $service_name"
    
    # 检查服务是否已经运行
    if check_status "$service_name"; then
        print_warning "服务 $service_name 已经在运行中"
        return 0
    fi
    
    # 检查 JAR 文件是否存在
    if [ ! -f "$JAR_PATH" ]; then
        print_error "找不到 JAR 文件: $JAR_PATH"
        return 1
    fi
    
    # 检查 Java 环境
    if [ ! -x "$JAVA_HOME/bin/java" ]; then
        print_error "找不到 Java 可执行文件: $JAVA_HOME/bin/java"
        return 1
    fi
    
    # 构建启动命令
    local start_cmd="$JAVA_HOME/bin/java $JVM_OPTS"
    start_cmd="$start_cmd -Dspring.profiles.active=$PROFILE"
    start_cmd="$start_cmd -Dserver.port=$PORT"
    start_cmd="$start_cmd -Dlogging.file.name=$LOG_FILE"
    start_cmd="$start_cmd -jar $JAR_PATH"
    
    # 启动服务
    cd "$SERVICE_DIR"
    if [ "$(whoami)" = "root" ]; then
        su - "$USER" -c "$start_cmd" >> "$LOG_FILE" 2>> "$ERROR_LOG" &
    else
        nohup $start_cmd >> "$LOG_FILE" 2>> "$ERROR_LOG" &
    fi
    
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    # 等待服务启动
    sleep 3
    
    if check_status "$service_name"; then
        print_success "服务 $service_name 启动成功 (PID: $pid)"
        return 0
    else
        print_error "服务 $service_name 启动失败"
        print_info "请检查日志文件: $ERROR_LOG"
        return 1
    fi
}

# 停止服务
stop_service() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    print_info "正在停止服务: $service_name"
    
    local pid=$(get_pid "$service_name")
    if [ -z "$pid" ]; then
        print_warning "服务 $service_name 未运行"
        return 0
    fi
    
    # 优雅停止
    print_info "发送 TERM 信号到进程 $pid"
    kill -TERM "$pid"
    
    # 等待进程结束
    local count=0
    while [ $count -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done
    
    if kill -0 "$pid" 2>/dev/null; then
        print_warning "优雅停止失败，强制终止进程"
        kill -KILL "$pid"
        sleep 2
    fi
    
    # 清理 PID 文件
    rm -f "$PID_FILE"
    
    print_success "服务 $service_name 已停止"
}

# 重启服务
restart_service() {
    local service_name="$1"
    print_info "正在重启服务: $service_name"
    
    stop_service "$service_name"
    sleep 2
    start_service "$service_name"
}

# 显示服务状态
show_status() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    local pid=$(get_pid "$service_name")
    if [ -n "$pid" ]; then
        local uptime=$(ps -o etime= -p "$pid" | tr -d ' ')
        local memory=$(ps -o rss= -p "$pid" | tr -d ' ')
        memory=$((memory / 1024))  # 转换为 MB
        
        echo "服务名称: $service_name"
        echo "状态: 运行中"
        echo "进程ID: $pid"
        echo "运行时间: $uptime"
        echo "内存使用: ${memory}MB"
        echo "端口: $PORT"
        echo "配置文件: $PROFILE"
        echo "日志文件: $LOG_FILE"
        echo "错误日志: $ERROR_LOG"
        echo "PID文件: $PID_FILE"
    else
        echo "服务名称: $service_name"
        echo "状态: 已停止"
    fi
}

# 显示所有服务状态
show_all_status() {
    echo "========================================"
    echo "           微服务状态总览"
    echo "========================================"
    printf "%-20s %-10s %-10s %-15s\n" "服务名称" "状态" "PID" "运行时间"
    echo "----------------------------------------"
    
    for service_name in "${!SERVICES[@]}"; do
        local pid=$(get_pid "$service_name")
        if [ -n "$pid" ]; then
            local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
            printf "%-20s %-10s %-10s %-15s\n" "$service_name" "运行中" "$pid" "$uptime"
        else
            printf "%-20s %-10s %-10s %-15s\n" "$service_name" "已停止" "-" "-"
        fi
    done
    echo "========================================"
}

# 显示用法
show_usage() {
    echo "用法: $0 {start|stop|status|restart|status-all} [service_name]"
    echo ""
    echo "命令:"
    echo "  start <service_name>   - 启动指定服务"
    echo "  stop <service_name>    - 停止指定服务"
    echo "  restart <service_name> - 重启指定服务"
    echo "  status <service_name>  - 查看指定服务状态"
    echo "  status-all             - 查看所有服务状态"
    echo ""
    echo "可用服务:"
    for service_name in "${!SERVICES[@]}"; do
        echo "  - $service_name"
    done
}

#======================================
# 主程序
#======================================

# 检查参数
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

# 检查用户权限
check_user

# 创建必要目录
create_directories

# 解析命令
case "$1" in
    start)
        validate_service "$2"
        start_service "$2"
        ;;
    stop)
        validate_service "$2"
        stop_service "$2"
        ;;
    restart)
        validate_service "$2"
        restart_service "$2"
        ;;
    status)
        validate_service "$2"
        show_status "$2"
        ;;
    status-all)
        show_all_status
        ;;
    *)
        print_error "未知命令: $1"
        show_usage
        exit 1
        ;;
esac