#!/bin/bash

# 微服务一键管理脚本 v2.0
# 用法: ./microservices_manager.sh {start-all|stop-all|restart-all|status|status-all|details|help}
# 功能: 批量管理所有微服务，调用单服务管理脚本实现

#======================================
# 配置部分 - 请根据实际环境修改
#======================================

# 单服务管理脚本路径
SINGLE_SERVICE_SCRIPT="./service_manager.sh"

# 服务基础配置
SERVICE_HOME="/opt/microservices"          # 服务根目录
LOG_DIR="/var/log/microservices"           # 日志目录
PID_DIR="/var/run/microservices"           # PID 文件目录
USER="appuser"                             # 运行服务的用户
MANAGER_LOG="$LOG_DIR/manager.log"         # 管理脚本日志

# 定义服务列表及其配置 (服务名:端口:启动延迟秒数:健康检查路径)
declare -A SERVICES=(
    ["user-service"]="8080:0:/actuator/health"
    ["inventory-service"]="8083:3:/actuator/health"
    ["payment-service"]="8082:6:/actuator/health"
    ["order-service"]="8081:9:/actuator/health"
    ["notification-service"]="8084:12:/actuator/health"
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
HEALTH_CHECK_TIMEOUT=60   # 健康检查超时时间（秒）
HEALTH_CHECK_INTERVAL=2   # 健康检查间隔（秒）
SERVICE_START_TIMEOUT=30  # 单个服务启动超时时间（秒）
SERVICE_STOP_TIMEOUT=30   # 单个服务停止超时时间（秒）

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
WHITE='\033[1;37m'
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
    echo -e "${WHITE}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}========================================${NC}"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
    log_message "STEP" "$1"
}

print_progress() {
    echo -e "${PURPLE}[PROGRESS]${NC} $1"
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

# 检查单服务管理脚本
check_single_service_script() {
    if [ ! -f "$SINGLE_SERVICE_SCRIPT" ]; then
        print_error "单服务管理脚本不存在: $SINGLE_SERVICE_SCRIPT"
        print_info "请确保 service_manager.sh 脚本在当前目录或修改 SINGLE_SERVICE_SCRIPT 变量"
        return 1
    fi
    
    if [ ! -x "$SINGLE_SERVICE_SCRIPT" ]; then
        print_warning "单服务管理脚本不可执行，正在设置执行权限..."
        chmod +x "$SINGLE_SERVICE_SCRIPT"
        if [ $? -ne 0 ]; then
            print_error "无法设置执行权限: $SINGLE_SERVICE_SCRIPT"
            return 1
        fi
    fi
    
    return 0
}

# 解析服务配置
parse_service_config() {
    local service_name="$1"
    local config="${SERVICES[$service_name]}"
    
    IFS=':' read -r PORT START_DELAY HEALTH_PATH <<< "$config"
    PID_FILE="$PID_DIR/${service_name}.pid"
}

# 调用单服务脚本
call_single_service_script() {
    local action="$1"
    local service_name="$2"
    local timeout="${3:-30}"
    
    print_info "调用单服务脚本: $action $service_name"
    
    # 使用超时机制调用单服务脚本
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" "$SINGLE_SERVICE_SCRIPT" "$action" "$service_name"
        local exit_code=$?
        
        if [ $exit_code -eq 124 ]; then
            print_error "操作超时: $action $service_name (${timeout}秒)"
            return 1
        elif [ $exit_code -ne 0 ]; then
            print_error "操作失败: $action $service_name (退出代码: $exit_code)"
            return 1
        fi
    else
        "$SINGLE_SERVICE_SCRIPT" "$action" "$service_name"
        local exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            print_error "操作失败: $action $service_name (退出代码: $exit_code)"
            return 1
        fi
    fi
    
    return 0
}

# 获取服务状态（通过单服务脚本）
get_service_status() {
    local service_name="$1"
    
    # 通过单服务脚本获取状态
    local status_output=$("$SINGLE_SERVICE_SCRIPT" status "$service_name" 2>/dev/null)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$status_output" | grep -q "运行中"; then
        return 0  # 运行中
    else
        return 1  # 未运行
    fi
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
        fi
    fi
    return 1
}

# 健康检查（通过HTTP端点）
health_check() {
    local service_name="$1"
    parse_service_config "$service_name"
    
    local health_url="http://localhost:${PORT}${HEALTH_PATH}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -f --connect-timeout 5 --max-time 10 "$health_url" >/dev/null 2>&1
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null --timeout=10 "$health_url" >/dev/null 2>&1
        return $?
    else
        # 如果没有curl和wget，只检查端口是否监听
        if command -v netstat >/dev/null 2>&1; then
            netstat -tuln | grep ":${PORT} " >/dev/null 2>&1
            return $?
        else
            # 最后使用进程检查
            get_service_status "$service_name"
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
            print_warning "$service_name 服务健康检查超时 (${timeout}秒)"
            return 1
        fi
        
        printf "."
        sleep $HEALTH_CHECK_INTERVAL
    done
}

# 等待服务启动
wait_for_service_start() {
    local service_name="$1"
    local timeout="${2:-$SERVICE_START_TIMEOUT}"
    local start_time=$(date +%s)
    
    print_info "等待 $service_name 服务启动..."
    
    while true; do
        if get_service_status "$service_name"; then
            print_success "$service_name 服务启动成功"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "$service_name 服务启动超时 (${timeout}秒)"
            return 1
        fi
        
        printf "."
        sleep 2
    done
}

# 等待服务停止
wait_for_service_stop() {
    local service_name="$1"
    local timeout="${2:-$SERVICE_STOP_TIMEOUT}"
    local start_time=$(date +%s)
    
    print_info "等待 $service_name 服务停止..."
    
    while true; do
        if ! get_service_status "$service_name"; then
            print_success "$service_name 服务停止成功"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "$service_name 服务停止超时 (${timeout}秒)"
            return 1
        fi
        
        printf "."
        sleep 2
    done
}

# 启动所有服务
start_all_services() {
    print_header "启动所有微服务"
    
    local failed_services=()
    local total_services=${#START_ORDER[@]}
    local success_count=0
    local start_time=$(date +%s)
    
    print_info "启动顺序: ${START_ORDER[*]}"
    echo
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        
        print_step "[$((success_count + 1))/$total_services] 准备启动 $service_name"
        
        # 检查服务是否已经运行
        if get_service_status "$service_name"; then
            print_warning "$service_name 已经在运行中，跳过启动"
            success_count=$((success_count + 1))
            continue
        fi
        
        # 启动延迟
        if [ "$START_DELAY" -gt 0 ]; then
            print_info "等待 $START_DELAY 秒后启动 $service_name..."
            sleep "$START_DELAY"
        fi
        
        # 调用单服务脚本启动服务
        if call_single_service_script "start" "$service_name" "$SERVICE_START_TIMEOUT"; then
            # 等待服务完全启动
            if wait_for_service_start "$service_name" 15; then
                # 进行健康检查
                if wait_for_health "$service_name" 30; then
                    success_count=$((success_count + 1))
                    print_success "[$((success_count))/$total_services] $service_name 启动并健康检查通过"
                else
                    failed_services+=("$service_name (健康检查失败)")
                    print_warning "$service_name 启动成功但健康检查失败"
                fi
            else
                failed_services+=("$service_name (启动超时)")
            fi
        else
            failed_services+=("$service_name (启动失败)")
        fi
        
        echo # 空行分隔
    done
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    print_header "启动完成统计"
    print_info "总耗时: ${total_time}秒"
    print_info "成功启动: $success_count/$total_services"
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "启动失败的服务:"
        for failed in "${failed_services[@]}"; do
            echo "  - $failed"
        done
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
    local start_time=$(date +%s)
    
    print_info "停止顺序: ${STOP_ORDER[*]}"
    echo
    
    for service_name in "${STOP_ORDER[@]}"; do
        print_step "[$((success_count + 1))/$total_services] 准备停止 $service_name"
        
        # 检查服务是否在运行
        if ! get_service_status "$service_name"; then
            print_warning "$service_name 未运行，跳过停止"
            success_count=$((success_count + 1))
            continue
        fi
        
        # 调用单服务脚本停止服务
        if call_single_service_script "stop" "$service_name" "$SERVICE_STOP_TIMEOUT"; then
            # 等待服务完全停止
            if wait_for_service_stop "$service_name" 15; then
                success_count=$((success_count + 1))
                print_success "[$((success_count))/$total_services] $service_name 停止成功"
            else
                failed_services+=("$service_name (停止超时)")
            fi
        else
            failed_services+=("$service_name (停止失败)")
        fi
        
        # 停止间隔
        sleep 1
        echo # 空行分隔
    done
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    print_header "停止完成统计"
    print_info "总耗时: ${total_time}秒"
    print_info "成功停止: $success_count/$total_services"
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "停止失败的服务:"
        for failed in "${failed_services[@]}"; do
            echo "  - $failed"
        done
        return 1
    else
        print_success "所有服务停止成功！"
        return 0
    fi
}

# 重启所有服务
restart_all_services() {
    print_header "重启所有微服务"
    
    local overall_start_time=$(date +%s)
    
    print_info "第一阶段: 停止所有服务"
    echo "----------------------------------------"
    local stop_result=0
    stop_all_services
    stop_result=$?
    
    print_info "等待 5 秒后开始启动..."
    sleep 5
    
    print_info "第二阶段: 启动所有服务"
    echo "----------------------------------------"
    local start_result=0
    start_all_services
    start_result=$?
    
    local overall_end_time=$(date +%s)
    local total_time=$((overall_end_time - overall_start_time))
    
    print_header "重启完成统计"
    print_info "总耗时: ${total_time}秒"
    
    if [ $stop_result -eq 0 ] && [ $start_result -eq 0 ]; then
        print_success "所有服务重启成功！"
        return 0
    else
        print_error "重启过程中出现错误"
        return 1
    fi
}

# 显示所有服务状态
show_all_status() {
    print_header "微服务状态总览"
    
    printf "%-20s %-12s %-8s %-15s %-10s %-8s %-10s\n" "服务名称" "状态" "PID" "运行时间" "内存(MB)" "端口" "健康检查"
    echo "--------------------------------------------------------------------------------------------"
    
    local running_count=0
    local healthy_count=0
    local total_count=${#SERVICES[@]}
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        local pid=$(get_pid "$service_name")
        
        if [ -n "$pid" ]; then
            local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
            local memory=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
            memory=$((memory / 1024))  # 转换为 MB
            
            local health_status="检查中..."
            if health_check "$service_name"; then
                health_status="通过 ✓"
                healthy_count=$((healthy_count + 1))
            else
                health_status="失败 ✗"
            fi
            
            printf "%-20s %-12s %-8s %-15s %-10s %-8s %-10s\n" "$service_name" "运行中" "$pid" "$uptime" "${memory}MB" "$PORT" "$health_status"
            running_count=$((running_count + 1))
        else
            printf "%-20s %-12s %-8s %-15s %-10s %-8s %-10s\n" "$service_name" "已停止" "-" "-" "-" "$PORT" "-"
        fi
    done
    
    echo "--------------------------------------------------------------------------------------------"
    print_info "运行状态: $running_count/$total_count 个服务正在运行"
    print_info "健康状态: $healthy_count/$running_count 个运行中的服务健康"
    
    if [ $running_count -eq $total_count ]; then
        if [ $healthy_count -eq $running_count ]; then
            print_success "所有服务运行正常且健康"
        else
            print_warning "所有服务运行但部分不健康"
        fi
    elif [ $running_count -eq 0 ]; then
        print_warning "所有服务已停止"
    else
        print_warning "部分服务未运行"
    fi
}

# 显示详细状态（调用单服务脚本）
show_detailed_status() {
    print_header "微服务详细状态"
    
    for service_name in "${START_ORDER[@]}"; do
        echo "----------------------------------------"
        print_info "服务: $service_name"
        
        # 调用单服务脚本获取详细状态
        if ! call_single_service_script "status" "$service_name" 10; then
            print_error "无法获取 $service_name 的详细状态"
        fi
        echo
    done
}

# 显示服务详细配置信息
show_service_details() {
    print_header "微服务详细配置"
    
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        echo "----------------------------------------"
        echo "服务名称: $service_name"
        echo "端口: $PORT"
        echo "启动延迟: ${START_DELAY}秒"
        echo "健康检查路径: $HEALTH_PATH"
        echo "PID文件: $PID_FILE"
        
        local pid=$(get_pid "$service_name")
        if [ -n "$pid" ]; then
            echo "当前状态: 运行中 (PID: $pid)"
            if health_check "$service_name"; then
                echo "健康检查: 通过 ✓"
            else
                echo "健康检查: 失败 ✗"
            fi
        else
            echo "当前状态: 已停止"
        fi
        echo
    done
}

# 显示用法
show_usage() {
    cat << EOF
微服务一键管理脚本 v2.0

用法: $0 {start-all|stop-all|restart-all|status|status-all|details|help}

批量操作命令:
  start-all     - 按依赖顺序启动所有服务
  stop-all      - 按依赖顺序停止所有服务
  restart-all   - 重启所有服务

状态查看命令:
  status        - 显示所有服务状态概览
  status-all    - 显示详细状态信息（调用单服务脚本）
  details       - 显示服务详细配置信息

其他命令:
  help          - 显示帮助信息

服务列表:
EOF
    for service_name in "${START_ORDER[@]}"; do
        parse_service_config "$service_name"
        echo "  - $service_name (端口: $PORT, 延迟: ${START_DELAY}秒)"
    done
    
    echo ""
    echo "启动顺序: ${START_ORDER[*]}"
    echo "停止顺序: ${STOP_ORDER[*]}"
    echo ""
    echo "依赖脚本: $SINGLE_SERVICE_SCRIPT"
}

# 检查系统环境
check_environment() {
    print_info "检查系统环境..."
    
    # 检查单服务管理脚本
    if ! check_single_service_script; then
        return 1
    fi
    
    # 通过单服务脚本检查系统环境
    print_info "通过单服务脚本验证系统环境..."
    
    # 检查各服务的配置
    local config_errors=0
    for service_name in "${!SERVICES[@]}"; do
        if [[ ! ${SERVICES[$service_name]} =~ ^[0-9]+:[0-9]+:/.* ]]; then
            print_error "服务 $service_name 配置格式错误: ${SERVICES[$service_name]}"
            config_errors=$((config_errors + 1))
        fi
    done
    
    if [ $config_errors -gt 0 ]; then
        print_error "配置验证失败，请检查服务配置格式"
        return 1
    fi
    
    print_success "系统环境检查通过"
    return 0
}

# 实时监控模式
monitor_services() {
    print_header "实时监控模式 (按 Ctrl+C 退出)"
    
    while true; do
        clear
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 微服务状态监控"
        echo "========================================"
        
        show_all_status
        
        echo ""
        echo "自动刷新间隔: 10秒 (按 Ctrl+C 退出)"
        sleep 10
    done
}

#======================================
# 主程序
#======================================

# 显示脚本信息
echo "微服务一键管理脚本 v2.0"
echo "管理 ${#SERVICES[@]} 个微服务实例"
echo "依赖脚本: $SINGLE_SERVICE_SCRIPT"
echo ""

# 检查参数
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

# 创建必要目录
create_directories

# 检查单服务脚本
if ! check_single_service_script; then
    exit 1
fi

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
    status)
        show_all_status
        ;;
    status-all)
        show_detailed_status
        ;;
    details)
        show_service_details
        ;;
    monitor)
        monitor_services
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