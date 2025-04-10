#!/bin/bash

# 配置参数
INSTALL_DIR="$HOME/node_exporter"          # 安装目录（可修改）
VERSION="1.7.0"                            # 指定版本（或填 "latest" 自动获取最新版）
USER=$(whoami)                             # 当前用户
SERVICE_NAME="node_exporter"               # 服务名称

# 获取最新版本号函数
get_latest_version() {
    curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | \
    grep '"tag_name":' | \
    sed -E 's/.*"v([^"]+)".*/\1/'
}

# 检查是否安装了 jq（用于解析 JSON）
if ! command -v jq &> /dev/null; then
    echo "错误：需要安装 'jq' 工具。请先运行: sudo apt install jq (Debian) 或 sudo yum install jq (RHEL)"
    exit 1
fi

# 自动获取最新版本（如果 VERSION=latest）
if [ "$VERSION" = "latest" ]; then
    VERSION=$(get_latest_version)
    echo "检测到最新版本: $VERSION"
fi

# 创建安装目录
mkdir -p "$INSTALL_DIR"

# 检查现有版本
CURRENT_VERSION=""
if [ -f "$INSTALL_DIR/node_exporter" ]; then
    CURRENT_VERSION=$("$INSTALL_DIR/node_exporter" --version 2>&1 | grep -oP 'version \K\S+')
    echo "当前安装版本: $CURRENT_VERSION"
fi

# 版本比较函数（semver 格式）
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# 如果当前版本 >= 目标版本，则退出
if [ -n "$CURRENT_VERSION" ] && ! version_gt "$VERSION" "$CURRENT_VERSION"; then
    echo "当前版本已是最新，无需升级。"
    exit 0
fi

# 下载并安装
echo "正在下载 node_exporter v$VERSION..."
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v$VERSION/node_exporter-$VERSION.linux-amd64.tar.gz"
curl -L "$DOWNLOAD_URL" -o "/tmp/node_exporter.tar.gz" || {
    echo "下载失败！请检查网络或版本号。"
    exit 1
}

# 解压并安装
echo "安装到目录: $INSTALL_DIR"
tar -xzf "/tmp/node_exporter.tar.gz" -C "/tmp/" --strip-components=1
mv "/tmp/node_exporter" "$INSTALL_DIR/"
rm -f "/tmp/node_exporter.tar.gz"

# 设置用户权限
chown -R "$USER:$USER" "$INSTALL_DIR"

# 创建用户级 systemd 服务（如果 systemd 可用）
if command -v systemctl &> /dev/null; then
    echo "配置 systemd 服务..."
    SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME.service"
    mkdir -p "$(dirname "$SERVICE_FILE")"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=$INSTALL_DIR/node_exporter
User=$USER
Restart=always

[Install]
WantedBy=default.target
EOF

    # 启用并启动服务
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    systemctl --user restart "$SERVICE_NAME"
    echo "服务已启动。管理命令:"
    echo " 启动: systemctl --user start $SERVICE_NAME"
    echo " 状态: systemctl --user status $SERVICE_NAME"
else
    echo "提示：未检测到 systemd，请手动运行: $INSTALL_DIR/node_exporter"
fi

echo "安装完成！版本: $VERSION"