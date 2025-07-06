#!/bin/bash

# 微服务一键管理脚本
# 用法: ./microservices_manager.sh {start|stop|restart|status|start-all|stop-all|restart-all|status-all}
# 功能: 批量管理所有微服务或按依赖顺序启动/停止

#======================================
# 配置部分 - 请根据实际环境修改
#======================================

# 服务基础配置
SERVICE_HOME="/opt/microservices"          # 服务根目录
JAVA_HOME="/usr/lib/jvm/java-11-openjdk"   # Java 安装路径
LOG_DIR="/var/log/microservices"           # 日志目录
PID_DIR="/var/run/microservices"           # PID 文件目录
USER="appuser"                             # 运行服务的用户
MANAGER_LOG="$LOG_DIR/manager.log"         # 管理脚本日志

# JVM 配置
JVM_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps"

# 定义服务列表及其配置 (服务名:JAR文件:端口:环境:启动延迟秒数)
declare -A SERVICES=(
    ["user-service"]="user-service-1.0.0.jar:8080:prod:0"
    ["inventory-service"]="inventory-service-1.0.0.jar:8083:prod:2"
    ["payment-service"]="payment-service-1.0.0.jar:8082:prod:4"
    ["order-service"]="order-service-1.0.0.jar:8081:prod:6"
    ["notification-service"]="notification-service-1.0.0.jar:8084:prod:8"
)

# 定义服务启动顺序（按依赖关系）
START_ORDER=(
    "user-service"
    "inventory-service"
    "payment-service"
    "order-service"
    "notification-service"
)

# 定义服务停止顺序（启动顺序的反向）
STOP_ORDER=(
    "notification-service"
    "order-service"
    "payment-service"
    "inventory-service"
    "user-service"
)

# 健康检查配置
HEALTH_CHECK_TIMEOUT=60  # 健康检查超时时间（秒）
HEALTH_CHECK_INTERVAL=2  # 健康检查间隔（秒）

#======================================
# 函数定义
#======================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印函数
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

print_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
    log_message "STEP" "$1"
}

# 日志记录函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$MANAGER_LOG"
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
    
    # 确保管理日志文件存在
    touch "$MANAGER_LOG"
    if [ "$(whoami)" = "root" ]; then
        chown "$USER:$USER" "$MANAGER_LOG"
    fi
}

# 检查用户权限
check_user() {
    if [ "$USER" != "root" ] && [ "$(whoami)" != "$USER" ]; then
        print_error "此脚本需要以 root 或 $USER 用户身份运行"
        exit 1
    fi
}

# 解析服务配置
parse_service_config() {
    local service_name="$1"
    local config="${SERVICES[$service_name]}"
    
    IFS=':' read -r JAR_FILE PORT PROFILE START_DELAY <<< "$config"
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

# 健康检查（通过HTTP端点）
health_check() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    local health_url="http://localhost:${PORT}/actuator/health"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -f "$health_url" >/dev/null 2>&1
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null "$health_url" >/dev/null 2>&1
        return $?
    else
        # 如果没有curl和wget，只检查端口是否监听
        if command -v netstat >/dev/null 2>&1; then
            netstat -tuln | grep ":${PORT} " >/dev/null 2>&1
            return $?
        else
            # 最后使用进程检查
            check_status "$service_name"
            return $?
        fi
    fi
}

# 等待服务健康
wait_for_health() {
    local service_name="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    local start_time=$(date +%s)
    
    print_info "等待 $service_name 服务健康检查..."
    
    while true; do
        if health_check "$service_name"; then
            print_success "$service_name 服务健康检查通过"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_warning "$service_name 服务健康检查超时"
            return 1
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
    done
}

# 启动单个服务
start_single_service() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    print_step "正在启动服务: $service_name"
    
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
        
        # 进行健康检查
        if wait_for_health "$service_name" 30; then
            return 0
        else
            print_warning "服务 $service_name 启动但健康检查失败"
            return 1
        fi
    else
        print_error "服务 $service_name 启动失败"
        print_info "请检查日志文件: $ERROR_LOG"
        return 1
    fi
}

# 停止单个服务
stop_single_service() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    print_step "正在停止服务: $service_name"
    
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

# 启动所有服务
start_all_services() {
    print_header "启动所有微服务"
    
    local failed_services=()
    local total_services=${#START_ORDER[@]}
    local success_count=0
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        
        print_info "[$((success_count + 1))/$total_services] 准备启动 $service_name..."
        
        # 启动延迟
        if [ "$START_DELAY" -gt 0 ]; then
            print_info "等待 $START_DELAY 秒后启动..."
            sleep "$START_DELAY"
        fi
        
        if start_single_service "$service_name"; then
            success_count=$((success_count + 1))
        else
            failed_services+=("$service_name")
        fi
        
        echo # 空行分隔
    done
    
    print_header "启动完成统计"
    print_info "成功启动: $success_count/$total_services"
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "启动失败的服务: ${failed_services[*]}"
        return 1
    else
        print_success "所有服务启动成功！"
        return 0
    fi
}

# 停止所有服务
stop_all_services() {
    print_header "停止所有微服务"
    
    local failed_services=()
    local total_services=${#STOP_ORDER[@]}
    local success_count=0
    
    for service_name in "${STOP_ORDER[@]}"; do
        print_info "[$((success_count + 1))/$total_services] 准备停止 $service_name..."
        
        if stop_single_service "$service_name"; then
            success_count=$((success_count + 1))
        else
            failed_services+=("$service_name")
        fi
        
        # 停止间隔
        sleep 1
        echo # 空行分隔
    done
    
    print_header "停止完成统计"
    print_info "成功停止: $success_count/$total_services"
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "停止失败的服务: ${failed_services[*]}"
        return 1
    else
        print_success "所有服务停止成功！"
        return 0
    fi
}

# 重启所有服务
restart_all_services() {
    print_header "重启所有微服务"
    
    print_info "第一阶段: 停止所有服务"
    stop_all_services
    
    print_info "等待 5 秒后开始启动..."
    sleep 5
    
    print_info "第二阶段: 启动所有服务"
    start_all_services
}

# 显示所有服务状态
show_all_status() {
    print_header "微服务状态总览"
    
    printf "%-20s %-10s %-10s %-15s %-10s %-8s\n" "服务名称" "状态" "PID" "运行时间" "内存(MB)" "端口"
    echo "--------------------------------------------------------------------------------"
    
    local running_count=0
    local total_count=${#SERVICES[@]}
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        local pid=$(get_pid "$service_name")
        
        if [ -n "$pid" ]; then
            local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
            local memory=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
            memory=$((memory / 1024))  # 转换为 MB
            
            local health_status=""
            if health_check "$service_name"; then
                health_status="✓"
            else
                health_status="✗"
            fi
            
            printf "%-20s %-10s %-10s %-15s %-10s %-8s\n" "$service_name" "运行中$health_status" "$pid" "$uptime" "${memory}MB" "$PORT"
            running_count=$((running_count + 1))
        else
            printf "%-20s %-10s %-10s %-15s %-10s %-8s\n" "$service_name" "已停止" "-" "-" "-" "$PORT"
        fi
    done
    
    echo "--------------------------------------------------------------------------------"
    print_info "运行状态: $running_count/$total_count 个服务正在运行"
    
    if [ $running_count -eq $total_count ]; then
        print_success "所有服务运行正常"
    elif [ $running_count -eq 0 ]; then
        print_warning "所有服务已停止"
    else
        print_warning "部分服务未运行"
    fi
}

# 显示服务详细信息
show_service_details() {
    print_header "微服务详细信息"
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        echo "----------------------------------------"
        echo "服务名称: $service_name"
        echo "JAR文件: $JAR_FILE"
        echo "端口: $PORT"
        echo "环境: $PROFILE"
        echo "启动延迟: ${START_DELAY}秒"
        echo "服务目录: $SERVICE_DIR"
        echo "日志文件: $LOG_FILE"
        echo "错误日志: $ERROR_LOG"
        echo "PID文件: $PID_FILE"
        
        local pid=$(get_pid "$service_name")
        if [ -n "$pid" ]; then
            echo "状态: 运行中 (PID: $pid)"
            if health_check "$service_name"; then
                echo "健康检查: 通过 ✓"
            else
                echo "健康检查: 失败 ✗"
            fi
        else
            echo "状态: 已停止"
        fi
        echo
    done
}

# 显示用法
show_usage() {
    echo "微服务一键管理脚本"
    echo "用法: $0 {start-all|stop-all|restart-all|status|status-all|details|help}"
    echo ""
    echo "批量操作命令:"
    echo "  start-all     - 按依赖顺序启动所有服务"
    echo "  stop-all      - 按依赖顺序停止所有服务"
    echo "  restart-all   - 重启所有服务"
    echo ""
    echo "状态查看命令:"
    echo "  status        - 显示所有服务状态概览"
    echo "  status-all    - 显示详细状态信息"
    echo "  details       - 显示服务详细配置信息"
    echo ""
    echo "其他命令:"
    echo "  help          - 显示帮助信息"
    echo ""
    echo "服务列表:"
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        echo "  - $service_name (端口: $PORT)"
    done
    echo ""
    echo "启动顺序: ${START_ORDER[*]}"
    echo "停止顺序: ${STOP_ORDER[*]}"
}

# 检查系统环境
check_environment() {
    print_info "检查系统环境..."
    
    # 检查Java环境
    if [ ! -x "$JAVA_HOME/bin/java" ]; then
        print_error "Java环境检查失败: $JAVA_HOME/bin/java"
        return 1
    fi
    
    # 检查服务目录
    if [ ! -d "$SERVICE_HOME" ]; then
        print_error "服务目录不存在: $SERVICE_HOME"
        return 1
    fi
    
    # 检查各服务的JAR文件
    local missing_jars=()
    for service_name in "${!SERVICES[@]}"; do
        parse_service_config "$service_name"
        if [ ! -f "$JAR_PATH" ]; then
            missing_jars+=("$service_name:$JAR_PATH")
        fi
    done
    
    if [ ${#missing_jars[@]} -gt 0 ]; then
        print_error "以下服务的JAR文件缺失:"
        for missing in "${missing_jars[@]}"; do
            echo "  - $missing"
        done
        return 1
    fi
    
    print_success "系统环境检查通过"
    return 0
}

#======================================
# 主程序
#======================================

# 显示脚本信息
echo "微服务一键管理脚本 v1.0"
echo "管理 ${#SERVICES[@]} 个微服务实例"
echo ""

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
    start-all)
        check_environment && start_all_services
        ;;
    stop-all)
        stop_all_services
        ;;
    restart-all)
        check_environment && restart_all_services
        ;;
    status|status-all)
        show_all_status
        ;;
    details)
        show_service_details
        ;;
    help)
        show_usage
        ;;
    *)
        print_error "未知命令: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac

# 记录操作完成
log_message "OPERATION" "命令 '$1' 执行完成"