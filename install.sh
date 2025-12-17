#!/bin/bash

cd /root >/dev/null 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REGEX=("debian|astra" "ubuntu")
RELEASE=("Debian" "Ubuntu")
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(lsb_release -sd 2>/dev/null)")
SYS="${CMD[0]}"
[[ -n $SYS ]] || exit 1

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        [[ -n $SYSTEM ]] && break
    fi
done

if [[ "$SYSTEM" != "Debian" && "$SYSTEM" != "Ubuntu" ]]; then
    echo -e "${RED}[ERR]${NC} 此脚本仅支持 Debian 和 Ubuntu 系统"
    exit 1
fi

if [[ "$SYSTEM" == "Debian" ]]; then
    OS_VERSION=$(cat /etc/debian_version | cut -d. -f1)
elif [[ "$SYSTEM" == "Ubuntu" ]]; then
    OS_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2 | cut -d. -f1)
fi

RECOMMENDED=false
if [[ "$SYSTEM" == "Debian" && ("$OS_VERSION" == "12" || "$OS_VERSION" == "13") ]]; then
    RECOMMENDED=true
elif [[ "$SYSTEM" == "Ubuntu" && ("$OS_VERSION" == "24" || "$OS_VERSION" == "25") ]]; then
    RECOMMENDED=true
fi

if [[ "$RECOMMENDED" != "true" ]]; then
    echo -e "${YELLOW}[WARN]${NC} 当前系统: $SYSTEM $OS_VERSION"
    echo -e "${YELLOW}[WARN]${NC} 推荐使用: Debian 12/13 或 Ubuntu 24/25"
    read -rp "$(echo -e "${YELLOW}是否继续安装？(y/n) [n]：${NC}")" confirm_install
    confirm_install=${confirm_install:-n}
    if [[ ! "$confirm_install" =~ ^[yY]$ ]]; then
        echo -e "${RED}[ERR]${NC} 安装已取消"
        exit 1
    fi
fi


if [ ! -d "/usr/local/bin" ]; then
    mkdir -p /usr/local/bin
fi

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; exit 1; }

print_step() {
    local step=$1
    local total=$2
    local title=$3
    echo
    echo "========================================"
    echo "      步骤 $step/$total: $title"
    echo "========================================"
    echo
}

reading() { read -rp "$(echo -e "${GREEN}$1${NC}")" "$2"; }

sed_compatible() {
    if echo "test" | sed -E 's/test/ok/' >/dev/null 2>&1; then
        sed -E "$@"
    else
        sed -r "$@"
    fi
}

service_manager() {
    local action=$1
    local service_name=$2
    case "$action" in
        enable)
            systemctl enable "$service_name" 2>/dev/null
            ;;
        disable)
            systemctl disable "$service_name" 2>/dev/null
            ;;
        start)
            systemctl start "$service_name" 2>/dev/null
            ;;
        stop)
            systemctl stop "$service_name" 2>/dev/null
            ;;
        restart)
            systemctl restart "$service_name" 2>/dev/null
            ;;
        daemon-reload)
            systemctl daemon-reload 2>/dev/null
            ;;
        is-active)
            systemctl is-active --quiet "$service_name" 2>/dev/null
            return $?
            ;;
    esac
    return 0
}


set_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
    export DEBIAN_FRONTEND=noninteractive
    if [[ -z "$utf8_locale" ]]; then
        warn "未找到 UTF-8 语言环境"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        ok "语言环境设置为 $utf8_locale"
    fi
}

install_package() {
    package_name=$1
    if dpkg -l 2>/dev/null | grep -q "^ii.*$package_name"; then
        ok "$package_name 已安装"
    else
        apt-get install -y $package_name >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            apt-get install -y $package_name --fix-missing >/dev/null 2>&1
        fi
        if dpkg -l 2>/dev/null | grep -q "^ii.*$package_name"; then
            ok "$package_name 已安装"
        else
            warn "$package_name 安装失败"
        fi
    fi
}





get_available_space() {
    local available_space
    available_space=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    echo "$available_space"
}

install_base_packages() {
    info "更新软件包列表..."
    apt-get update >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1
    install_package wget
    install_package curl
    install_package sudo
    install_package unzip
    install_package iptables-persistent
    install_package nftables
    install_package nginx
    
    if dpkg -l lxcfs 2>/dev/null | grep -q "^ii"; then
        warn "检测到 deb 版 lxcfs，正在移除以避免与 snap 版 LXD 冲突..."
        systemctl stop lxcfs 2>/dev/null || true
        systemctl disable lxcfs 2>/dev/null || true
        apt-get remove -y lxcfs >/dev/null 2>&1
        ok "deb 版 lxcfs 已移除，将使用 snap 版 LXD 内置的 lxcfs"
    fi
    
    if systemctl is-active --quiet nginx; then
        ok "nginx 服务已运行"
    else
        service_manager start nginx
        service_manager enable nginx
        ok "nginx 服务已启动并设置为自动启动"
    fi
}

install_lxd() {
    lxd_snap=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snap)
    lxd_snapd=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snapd)
    if [[ "$lxd_snap" =~ ^snap.* ]] && [[ "$lxd_snapd" =~ ^snapd.* ]]; then
        ok "snap 已安装"
    else
        info "开始安装 snap..."
        apt-get update >/dev/null 2>&1
        install_package snapd
    fi
    snap_core=$(snap list core 2>/dev/null)
    snap_lxd=$(snap list lxd 2>/dev/null)
    if [[ "$snap_core" =~ core.* ]] && [[ "$snap_lxd" =~ lxd.* ]]; then
        ok "LXD 已安装"
        lxd_lxc_detect=$(lxc list 2>/dev/null)
        if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]; then
            service_manager restart apparmor
            snap restart lxd
        else
            ok "环境检测无问题"
        fi
    else
        info "开始安装 LXD..."
        snap install lxd --channel=latest/stable 2>/dev/null
        if [[ $? -ne 0 ]]; then
            snap remove lxd 2>/dev/null
            snap install core 2>/dev/null
            snap install lxd --channel=latest/stable 2>/dev/null
        fi
        snap alias lxd.lxc lxc 2>/dev/null
        snap alias lxd.lxd lxd 2>/dev/null
        if [ ! -f /etc/profile.d/snap.sh ]; then
            echo 'export PATH=$PATH:/snap/bin' > /etc/profile.d/snap.sh
        fi
        export PATH=$PATH:/snap/bin
        if ! command -v lxc >/dev/null 2>&1; then
            err 'lxc 路径有问题，请检查 snap alias'
        fi
        ok "LXD 安装完成"
    fi
    
    info "配置 LXD..."
    snap set lxd lxcfs.flags="-l" 2>/dev/null
    snap set lxd daemon.debug=false 2>/dev/null
    snap restart lxd 2>/dev/null
    sleep 3
    ok "LXD 已配置（lxcfs legacy 模式 + 关闭调试）"
}

setup_storage() {
    info "配置存储池..."
    
    if /snap/bin/lxc storage show default &>/dev/null; then
        ok "存储池 default 已存在"
        /snap/bin/lxc storage list
        return 0
    fi
    
    available_space=$(get_available_space)
    info "当前可用磁盘空间: ${available_space}GB"
    
    while true; do
        reading "请选择存储后端 zfs/btrfs/lvm [zfs]：" storage_driver
        storage_driver=${storage_driver:-zfs}
        if [[ "$storage_driver" =~ ^(zfs|btrfs|lvm)$ ]]; then
            break
        else
            warn "请输入 zfs、btrfs 或 lvm"
        fi
    done
    
    case "$storage_driver" in
        zfs)
            if ! command -v zpool &>/dev/null; then
                info "安装 ZFS..."
                if [[ "$SYSTEM" == "Ubuntu" ]]; then
                    install_package zfsutils-linux
                else
                    bash <(curl -sL https://raw.githubusercontent.com/xkatld/lxdapi-web-server/refs/heads/v2.0.0-main/build_zfs_on_debian.sh)
                fi
            fi
            info "配置 LXD 使用系统 ZFS..."
            snap set lxd zfs.external=true
            snap restart lxd
            sleep 3
            ;;
        btrfs)
            install_package btrfs-progs
            ;;
        lvm)
            install_package lvm2
            ;;
    esac
    
    reading "请输入存储池大小(GB) [${available_space}]：" pool_size
    pool_size=${pool_size:-$available_space}
    
    info "创建 default 存储池 (${storage_driver}, ${pool_size}GB)..."
    /snap/bin/lxc storage create default ${storage_driver} size=${pool_size}GB
    
    if [ $? -eq 0 ]; then
        ok "存储池 default 创建成功"
        if ! /snap/bin/lxc profile device show default 2>/dev/null | grep -q "root"; then
            /snap/bin/lxc profile device add default root disk path=/ pool=default
            ok "存储池已添加到 default profile"
        fi
    else
        err "存储池创建失败"
    fi
}

init_lxd_network() {
    if ! /snap/bin/lxc network show lxdbr0 &>/dev/null; then
        info "创建默认网络 lxdbr0..."
        /snap/bin/lxc network create lxdbr0
        ok "网络 lxdbr0 创建成功"
    else
        ok "网络 lxdbr0 已存在"
    fi
    
    if ! /snap/bin/lxc profile device show default 2>/dev/null | grep -q "eth0"; then
        info "配置 default profile 网络设备..."
        /snap/bin/lxc profile device add default eth0 nic network=lxdbr0 name=eth0
        ok "网络设备已添加到 default profile"
    fi
}

import_container_images() {
    bash <(curl -sL https://raw.githubusercontent.com/xkatld/lxdapi-web-server/refs/heads/v2.0.0-main/image_import.sh)
}

deploy_lxdapi() {
    info "检测系统架构..."
    sys_arch=$(uname -m)
    case $sys_arch in
        x86_64)
            arch="amd64"
            ok "检测到架构: x86_64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ok "检测到架构: $sys_arch"
            ;;
        *)
            err "不支持的架构: $sys_arch"
            ;;
    esac
    
    while true; do
        reading "请选择下载源 github/gitee [github]：" download_source
        download_source=${download_source:-github}
        if [[ "$download_source" =~ ^(github|gitee)$ ]]; then
            break
        else
            warn "请输入 github 或 gitee"
        fi
    done
    
    info "获取最新版本..."
    
    if [[ "$download_source" == "github" ]]; then
        latest_tag=$(curl -s https://api.github.com/repos/xkatld/lxdapi-web-server/releases/latest | grep '"tag_name"' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
        base_url="https://github.com/xkatld/lxdapi-web-server/releases/download"
    else
        latest_tag=$(curl -s https://gitee.com/api/v5/repos/xkatld/lxdapi-web-server/releases/latest | grep '"tag_name"' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
        base_url="https://gitee.com/xkatld/lxdapi-web-server/releases/download"
    fi
    
    if [ -z "$latest_tag" ]; then
        err "无法获取最新版本信息"
    fi
    
    ok "最新版本: $latest_tag"
    
    download_url="${base_url}/${latest_tag}/lxdapi-linux-${arch}.tar.gz"
    
    info "下载 lxdapi..."
    info "下载地址: $download_url"
    
    temp_file=$(mktemp)
    if wget -q --show-progress -O "$temp_file" "$download_url" 2>&1; then
        ok "下载完成"
    else
        rm -f "$temp_file"
        err "下载失败"
    fi
    
    info "解压到 /opt/lxdapi..."
    mkdir -p /opt/lxdapi
    tar -xzf "$temp_file" -C /opt/lxdapi --strip-components=1
    rm -f "$temp_file"
}

configure_lxdapi() {
    info "配置 lxdapi..."
    
    config_file="/opt/lxdapi/configs/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        err "配置文件不存在: $config_file"
    fi
    
    reading "请输入服务端口 [8443]：" server_port
    server_port=${server_port:-8443}
    
    reading "请输入API密钥 [随机生成]：" api_hash
    if [ -z "$api_hash" ]; then
        api_hash=$(openssl rand -hex 16)
        ok "API密钥已生成: $api_hash"
    fi
    
    reading "请输入流量采集间隔秒数 [30]：" traffic_interval
    traffic_interval=${traffic_interval:-30}
    
    reading "请输入流量批量更新数量 [5]：" traffic_batch_size
    traffic_batch_size=${traffic_batch_size:-5}
    
    while true; do
        reading "请选择数据库类型 sqlite/mysql/postgres [sqlite]：" db_type
        db_type=${db_type:-sqlite}
        if [[ "$db_type" =~ ^(sqlite|mysql|postgres)$ ]]; then
            break
        else
            warn "请输入 sqlite、mysql 或 postgres"
        fi
    done
    
    if [[ "$db_type" == "mysql" ]]; then
        while true; do
            reading "使用本地安装还是远程配置？local/remote [local]：" mysql_location
            mysql_location=${mysql_location:-local}
            if [[ "$mysql_location" =~ ^(local|remote)$ ]]; then
                break
            else
                warn "请输入 local 或 remote"
            fi
        done
        
        if [[ "$mysql_location" == "local" ]]; then
            info "安装 MariaDB..."
            install_package mariadb-server
            service_manager start mariadb
            service_manager enable mariadb
            
            mysql_host="localhost"
            mysql_port="3306"
            mysql_user="lxdapi"
            mysql_password=$(openssl rand -hex 8)
            mysql_database="lxdapi"
            
            info "创建数据库和用户..."
            mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS ${mysql_database};
CREATE USER IF NOT EXISTS '${mysql_user}'@'localhost' IDENTIFIED BY '${mysql_password}';
GRANT ALL PRIVILEGES ON ${mysql_database}.* TO '${mysql_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
            ok "MariaDB 数据库已创建"
            ok "用户: $mysql_user"
            ok "密码: $mysql_password"
        else
            reading "请输入 MySQL 主机地址：" mysql_host
            reading "请输入 MySQL 端口 [3306]：" mysql_port
            mysql_port=${mysql_port:-3306}
            reading "请输入 MySQL 用户名：" mysql_user
            reading "请输入 MySQL 密码：" mysql_password
            reading "请输入 MySQL 数据库名：" mysql_database
        fi
        
        sed -i "s|__MYSQL_HOST__|$mysql_host|g" "$config_file"
        sed -i "s|__MYSQL_PORT__|$mysql_port|g" "$config_file"
        sed -i "s|__MYSQL_USER__|$mysql_user|g" "$config_file"
        sed -i "s|__MYSQL_PASSWORD__|$mysql_password|g" "$config_file"
        sed -i "s|__MYSQL_DATABASE__|$mysql_database|g" "$config_file"
        
    elif [[ "$db_type" == "postgres" ]]; then
        while true; do
            reading "使用本地安装还是远程配置？local/remote [local]：" postgres_location
            postgres_location=${postgres_location:-local}
            if [[ "$postgres_location" =~ ^(local|remote)$ ]]; then
                break
            else
                warn "请输入 local 或 remote"
            fi
        done
        
        if [[ "$postgres_location" == "local" ]]; then
            info "安装 PostgreSQL..."
            install_package postgresql
            service_manager start postgresql
            service_manager enable postgresql
            
            postgres_host="localhost"
            postgres_port="5432"
            postgres_user="lxdapi"
            postgres_password=$(openssl rand -hex 8)
            postgres_database="lxdapi"
            postgres_sslmode="disable"
            
            info "创建数据库和用户..."
            sudo -u postgres psql << EOF
CREATE DATABASE ${postgres_database};
CREATE USER ${postgres_user} WITH PASSWORD '${postgres_password}';
GRANT ALL PRIVILEGES ON DATABASE ${postgres_database} TO ${postgres_user};
EOF
            ok "PostgreSQL 数据库已创建"
            ok "用户: $postgres_user"
            ok "密码: $postgres_password"
        else
            reading "请输入 PostgreSQL 主机地址：" postgres_host
            reading "请输入 PostgreSQL 端口 [5432]：" postgres_port
            postgres_port=${postgres_port:-5432}
            reading "请输入 PostgreSQL 用户名：" postgres_user
            reading "请输入 PostgreSQL 密码：" postgres_password
            reading "请输入 PostgreSQL 数据库名：" postgres_database
            reading "请输入 PostgreSQL SSL模式 [disable]：" postgres_sslmode
            postgres_sslmode=${postgres_sslmode:-disable}
        fi
        
        sed -i "s|__POSTGRES_HOST__|$postgres_host|g" "$config_file"
        sed -i "s|__POSTGRES_PORT__|$postgres_port|g" "$config_file"
        sed -i "s|__POSTGRES_USER__|$postgres_user|g" "$config_file"
        sed -i "s|__POSTGRES_PASSWORD__|$postgres_password|g" "$config_file"
        sed -i "s|__POSTGRES_DATABASE__|$postgres_database|g" "$config_file"
        sed -i "s|__POSTGRES_SSLMODE__|$postgres_sslmode|g" "$config_file"
    fi
    
    while true; do
        reading "请选择任务队列后端 memory/redis [memory]：" task_backend
        task_backend=${task_backend:-memory}
        if [[ "$task_backend" =~ ^(memory|redis)$ ]]; then
            break
        else
            warn "请输入 memory 或 redis"
        fi
    done
    
    if [[ "$task_backend" == "redis" ]]; then
        info "安装 Redis..."
        install_package redis-server
        service_manager start redis-server
        service_manager enable redis-server
        
        redis_host="localhost"
        redis_port="6379"
        redis_password=""
        redis_db="0"
        
        ok "Redis 已安装并启动"
        
        sed -i "s|__REDIS_HOST__|$redis_host|g" "$config_file"
        sed -i "s|__REDIS_PORT__|$redis_port|g" "$config_file"
        sed -i "s|__REDIS_PASSWORD__|$redis_password|g" "$config_file"
        sed -i "s|__REDIS_DB__|$redis_db|g" "$config_file"
    fi
    
    reading "请输入管理员用户名 [admin]：" admin_user
    admin_user=${admin_user:-admin}
    
    reading "请输入管理员密码 [随机生成]：" admin_pass
    if [ -z "$admin_pass" ]; then
        admin_pass=$(openssl rand -hex 4)
        ok "管理员密码已生成: $admin_pass"
    fi
    
    reading "请输入Session密钥 [随机生成]：" session_secret
    if [ -z "$session_secret" ]; then
        session_secret=$(openssl rand -hex 16)
        ok "Session密钥已生成: $session_secret"
    fi
    
    info "写入配置文件..."
    sed -i "s|__SERVER_PORT__|$server_port|g" "$config_file"
    sed -i "s|__API_HASH__|$api_hash|g" "$config_file"
    sed -i "s|__TRAFFIC_INTERVAL__|$traffic_interval|g" "$config_file"
    sed -i "s|__TRAFFIC_BATCH_SIZE__|$traffic_batch_size|g" "$config_file"
    sed -i "s|__DB_TYPE__|$db_type|g" "$config_file"
    sed -i "s|__TASK_BACKEND__|$task_backend|g" "$config_file"
    sed -i "s|__ADMIN_USER__|$admin_user|g" "$config_file"
    sed -i "s|__ADMIN_PASS__|$admin_pass|g" "$config_file"
    sed -i "s|__SESSION_SECRET__|$session_secret|g" "$config_file"
    
    sed -i "s|__MYSQL_HOST__|localhost|g" "$config_file"
    sed -i "s|__MYSQL_PORT__|3306|g" "$config_file"
    sed -i "s|__MYSQL_USER__|lxdapi|g" "$config_file"
    sed -i "s|__MYSQL_PASSWORD__|password|g" "$config_file"
    sed -i "s|__MYSQL_DATABASE__|lxdapi|g" "$config_file"
    
    sed -i "s|__POSTGRES_HOST__|localhost|g" "$config_file"
    sed -i "s|__POSTGRES_PORT__|5432|g" "$config_file"
    sed -i "s|__POSTGRES_USER__|lxdapi|g" "$config_file"
    sed -i "s|__POSTGRES_PASSWORD__|password|g" "$config_file"
    sed -i "s|__POSTGRES_DATABASE__|lxdapi|g" "$config_file"
    sed -i "s|__POSTGRES_SSLMODE__|disable|g" "$config_file"
    
    sed -i "s|__REDIS_HOST__|localhost|g" "$config_file"
    sed -i "s|__REDIS_PORT__|6379|g" "$config_file"
    sed -i "s|__REDIS_PASSWORD__||g" "$config_file"
    sed -i "s|__REDIS_DB__|0|g" "$config_file"
    
    ok "配置文件已更新"
}

setup_lxdapi_service() {
    info "配置 lxdapi 系统服务..."
    
    config_file="/opt/lxdapi/configs/config.yaml"
    if [ ! -f "$config_file" ]; then
        err "配置文件不存在: $config_file"
    fi
    
    if grep -q "__SERVER_PORT__" "$config_file"; then
        err "配置文件未完成配置"
    fi
    
    sys_arch=$(uname -m)
    case $sys_arch in
        x86_64)
            exec_bin="/opt/lxdapi/lxdapi-amd64"
            ;;
        aarch64|arm64)
            exec_bin="/opt/lxdapi/lxdapi-arm64"
            ;;
        *)
            err "不支持的架构: $sys_arch"
            ;;
    esac
    
    service_file="/etc/systemd/system/lxdapi.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=LXD API Server
After=network.target lxd.service
Wants=lxd.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lxdapi
ExecStart=$exec_bin
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    ok "服务文件已创建: $service_file"
    
    info "重载 systemd 配置..."
    systemctl daemon-reload
    
    info "启用开机自启..."
    systemctl enable lxdapi
    
    info "启动 lxdapi 服务..."
    systemctl start lxdapi
    
    sleep 2
    
    if systemctl is-active --quiet lxdapi; then
        ok "lxdapi 服务已启动"
        echo
        info "===== 服务状态 ====="
        systemctl status lxdapi --no-pager | head -10
    else
        warn "lxdapi 服务启动失败"
        echo
        info "===== 错误日志 ====="
        journalctl -u lxdapi -n 20 --no-pager
    fi
}

main() {
    echo
    echo "========================================"
    echo "        LXDAPI 安装脚本"
    echo "        by Github-xkatld"
    echo "========================================"
    echo
    print_step "1" "4" "初始化环境"
    reading "是否执行环境初始化？(y/n) [y]：" step1_confirm
    step1_confirm=${step1_confirm:-y}
    if [[ "$step1_confirm" =~ ^[yY]$ ]]; then
        set_locale
        install_base_packages
        ok "环境初始化完成"
    else
        info "已跳过环境初始化"
    fi

    print_step "2" "4" "安装 LXD"
    reading "是否执行 LXD 安装？(y/n) [y]：" step2_confirm
    step2_confirm=${step2_confirm:-y}
    if [[ "$step2_confirm" =~ ^[yY]$ ]]; then
        install_lxd
        init_lxd_network
        ok "LXD 安装完成"
    else
        info "已跳过 LXD 安装"
    fi

    print_step "3" "4" "配置存储资源"
    reading "是否执行存储配置？(y/n) [y]：" step3_confirm
    step3_confirm=${step3_confirm:-y}
    if [[ "$step3_confirm" =~ ^[yY]$ ]]; then
        setup_storage
        ok "存储配置完成"
    else
        info "已跳过存储配置"
    fi

    print_step "4" "4" "部署 lxdapi"
    reading "是否执行 lxdapi 部署？(y/n) [y]：" step5_confirm
    step5_confirm=${step5_confirm:-y}
    if [[ "$step5_confirm" =~ ^[yY]$ ]]; then
        deploy_lxdapi
        configure_lxdapi
        setup_lxdapi_service
        ok "lxdapi 部署完成"
    else
        info "已跳过 lxdapi 部署"
    fi

    echo
    echo "========================================"
    echo "        lxdapi 安装完成"
    echo "========================================"
    echo
    
    info "LXD 版本: $(lxd --version)"
    info "LXC 版本: $(lxc --version)"
    echo
    
    info "===== 1. 网络配置 ====="
    lxc network list
    echo
    
    info "===== 2. 存储配置 ====="
    lxc storage list
    echo
    
    info "===== 3. 后端配置 ====="
    info "服务端口: $server_port"
    info "API密钥: $api_hash"
    info "流量间隔: $traffic_interval 秒"
    info "批量大小: $traffic_batch_size"
    info "数据库: $db_type"
    if [[ "$db_type" == "mysql" ]]; then
        info "MySQL: $mysql_user@$mysql_host:$mysql_port/$mysql_database"
        info "MySQL密码: $mysql_password"
    elif [[ "$db_type" == "postgres" ]]; then
        info "PostgreSQL: $postgres_user@$postgres_host:$postgres_port/$postgres_database"
        info "PostgreSQL密码: $postgres_password"
    fi
    info "任务队列: $task_backend"
    if [[ "$task_backend" == "redis" ]]; then
        info "Redis: localhost:6379"
    fi
    info "管理员: $admin_user"
    info "管理员密码: $admin_pass"
    info "Session密钥: $session_secret"
    echo
    
    info "===== 5. lxdapi 服务状态 ====="
    info "等待服务启动..."
    sleep 5
    systemctl status lxdapi --no-pager -l
}

main
