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
    install_package lxcfs
    install_package iptables-persistent
    install_package nginx
    
    if systemctl is-active --quiet lxcfs; then
        ok "lxcfs 服务已运行"
    else
        service_manager start lxcfs
        service_manager enable lxcfs
        ok "lxcfs 服务已启动并设置为自动启动"
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
        ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >>/root/.bashrc && source /root/.bashrc
        export PATH=$PATH:/snap/bin
        ! lxc -h >/dev/null 2>&1 && err 'lxc 路径有问题，请检查修复'
        ok "LXD 安装完成"
    fi
}

configure_resources() {
   if [ "${noninteractive:-false}" = true ]; then
       available_space=$(get_available_space)
       disk_nums=$((available_space - 1))
       storage_path=""
   else
       while true; do
           reading "是否需要指定存储池的自定义路径？(y/n) [n]：" use_custom_path
           use_custom_path=${use_custom_path:-n}
           if [[ "$use_custom_path" =~ ^[yYnN]$ ]]; then
               break
           else
               warn "请输入 y 或 n"
           fi
       done
       if [[ "$use_custom_path" =~ ^[yY]$ ]]; then
           while true; do
               reading "请输入自定义存储路径，例如 /data/lxd-storage：" storage_path
               if [[ -n "$storage_path" && "$storage_path" =~ ^/.+ ]]; then
                   if [ ! -d "$storage_path" ]; then
                       mkdir -p "$storage_path" 2>/dev/null
                       if [ $? -eq 0 ]; then
                           ok "已创建目录：$storage_path"
                           break
                       else
                           warn "创建目录失败，请检查权限或尝试其他路径"
                       fi
                   else
                       break
                   fi
               else
                   warn "请输入以 / 开头的有效绝对路径"
               fi
           done
       else
           storage_path=""
       fi
       while true; do
           reading "宿主机需要开设多大的存储池？单位 GB，需要 10G 则输入 10：" disk_nums
           if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
               break
           else
               warn "输入无效，请输入一个正整数"
           fi
       done
   fi
}

get_available_space() {
    local available_space
    available_space=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    echo "$available_space"
}





create_sparse_file() {
    local file_path="$1"
    local size_gb="$2"
    if dd if=/dev/zero of="$file_path" bs=1G count=0 seek="${size_gb}" 2>/dev/null; then
        ok "使用 dd 创建稀疏文件成功: $file_path ${size_gb}GB"
        return 0
    else
        warn "dd 创建失败，尝试使用 truncate..."
        if command -v truncate >/dev/null 2>&1; then
            if truncate -s "${size_gb}G" "$file_path" 2>/dev/null; then
                ok "使用 truncate 创建稀疏文件成功: $file_path ${size_gb}GB"
                return 0
            else
                err "truncate 创建失败"
                return 1
            fi
        else
            err "truncate 命令不可用，无法创建稀疏文件"
            return 1
        fi
    fi
}

create_storage_pool_with_custom_path() {
    local backend="$1"
    local storage_path="$2"
    local disk_nums="$3"
    local loop_file temp status
    mkdir -p "$storage_path"
    loop_file="$storage_path/lvm_pool.img"
    ok "创建 LVM 存储池..."
    if [ -f "$loop_file" ]; then
        warn "检测到旧的循环文件，正在清理..."
        vgremove -f lxd_vg 2>/dev/null || true
        losetup -d $(losetup -j "$loop_file" | cut -d: -f1) 2>/dev/null || true
        rm -f "$loop_file"
    fi
    ok "创建稀疏文件：$loop_file ${disk_nums}GB..."
    if ! create_sparse_file "$loop_file" "$disk_nums"; then
        return 1
    fi
    ok "设置循环设备..."
    loop_dev=$(losetup -f)
    losetup "$loop_dev" "$loop_file"
    ok "创建 LVM 物理卷和卷组..."
    pvcreate "$loop_dev" >/dev/null 2>&1
    vgcreate lxd_vg "$loop_dev" >/dev/null 2>&1
    echo "$loop_file" > "$storage_path/lvm_loop_file.txt"
    temp=$(/snap/bin/lxc storage create default lvm source=lxd_vg 2>&1)
    status=$?
    echo "$temp"
    return $status
}

execute_storage_init() {
    local backend="$1"
    local temp
    local status
    if [ -n "$storage_path" ]; then
        if create_storage_pool_with_custom_path "$backend" "$storage_path" "$disk_nums"; then
            ok "LVM 存储池创建成功"
            
            /snap/bin/lxd init --auto >/dev/null 2>&1 || true
            
            temp="Storage pool created successfully"
            status=0
        else
            temp="Failed to create LVM storage pool"
            status=1
        fi
    else
        temp=$(/snap/bin/lxd init --storage-backend "$backend" --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
        status=$?
    fi
    echo "$temp"
    return $status
}

init_storage_backend() {
    local backend="lvm"
    ok "使用 lvm 类型，存储池大小为 $disk_nums GB"
    local need_reboot=false
    if ! command -v lvm >/dev/null; then
        warn "正在安装 lvm2..."
        install_package lvm2
        modprobe dm-mod || true
        ok "LVM 模块加载。如果失败请重启系统后再次执行脚本"
        echo "lvm" >/usr/local/bin/lxd_reboot
        need_reboot=true
    fi
    if ! grep -q dm-mod /proc/modules; then
        modprobe dm-mod || true
    fi
    if [ "$need_reboot" = true ]; then
        exit 1
    fi
    local temp
    temp=$(execute_storage_init "$backend")
    local status=$?
    info "初始化存储："
    echo "$temp"
    if echo "$temp" | grep -q "lxd.migrate" && [ $status -ne 0 ]; then
        /snap/bin/lxd.migrate
        temp=$(execute_storage_init "$backend")
        status=$?
        echo "$temp"
    fi
    if [ $status -eq 0 ]; then
        ok "使用 lvm 初始化成功"
        echo "lvm" >/usr/local/bin/lxd_storage_type
        return 0
    else
        err "使用 lvm 初始化失败"
        return 1
    fi
}

setup_storage() {
    if [ -f "/usr/local/bin/lxd_reboot" ]; then
        ok "检测到系统重启，尝试继续使用 lvm"
        rm -f /usr/local/bin/lxd_reboot
        modprobe dm-mod || true
        if init_storage_backend "lvm"; then
            return 0
        fi
    fi
    init_storage_backend "lvm"
}

download_and_import_image() {
    local image_name="$1"
    local arch="$2"
    local base_url="$3"
    local image_url="${base_url}/${image_name}-${arch}.tar.gz"
    
    info "下载: ${image_name}-${arch}.tar.gz"
    
    local temp_file=$(mktemp)
    if wget -q --show-progress -O "$temp_file" "$image_url" 2>&1; then
        info "导入到 LXD..."
        if lxc image import "$temp_file" --alias "$image_name" 2>/dev/null; then
            ok "成功导入: $image_name"
        else
            warn "导入失败: $image_name"
        fi
        rm -f "$temp_file"
    else
        warn "下载失败: ${image_name}"
        rm -f "$temp_file"
    fi
}

import_container_images() {
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
            err "不支持的架构: $sys_arch，仅支持 amd64 和 arm64"
            ;;
    esac
    
    IMAGES_BASE_URL="https://github.com/xkatld/zjmf-lxd-server/releases/download/images"
    
    declare -A IMAGE_MAP
    IMAGE_MAP=(
        [1]="alma8" [2]="alma9" [3]="alma10"
        [4]="alpine319" [5]="alpine320" [6]="alpine321" [7]="alpine322" [8]="alpineEdge"
        [9]="amazon2023"
        [10]="centos9" [11]="centos10"
        [12]="debian11" [13]="debian12" [14]="debian13"
        [15]="fedora41" [16]="fedora42"
        [17]="oracle8" [18]="oracle9"
        [19]="rocky8" [20]="rocky9" [21]="rocky10"
        [22]="suse155" [23]="suse156" [24]="suseTumbleweed"
        [25]="ubuntu2204" [26]="ubuntu2404" [27]="ubuntu2410"
    )
    
    echo
    echo "============================================================================================================"
    echo " 1) alma8          2) alma9         3) alma10        4) alpine319     5) alpine320                       "
    echo " 6) alpine321      7) alpine322     8) alpineEdge    9) amazon2023   10) centos9                         "
    echo "11) centos10      12) debian11     13) debian12     14) debian13     15) fedora41                        "
    echo "16) fedora42      17) oracle8      18) oracle9      19) rocky8       20) rocky9                          "
    echo "21) rocky10       22) suse155      23) suse156      24) suseTumbleweed                                   "
    echo "25) ubuntu2204    26) ubuntu2404   27) ubuntu2410                                                        "
    echo "============================================================================================================"
    echo
    
    reading "请输入镜像编号，多个用逗号分隔如 1,2,3 或输入 all 全部导入 [默认: 2,5,13,26]：" image_choices
    
    image_choices=${image_choices:-"2,5,13,26"}
    
    if [[ "$image_choices" == "all" ]]; then
        selected_images=(${IMAGE_MAP[@]})
    else
        IFS=',' read -ra choices <<< "$image_choices"
        selected_images=()
        for choice in "${choices[@]}"; do
            choice=$(echo "$choice" | xargs)
            if [[ -n "${IMAGE_MAP[$choice]}" ]]; then
                selected_images+=("${IMAGE_MAP[$choice]}")
            fi
        done
    fi
    
    if [[ ${#selected_images[@]} -eq 0 ]]; then
        warn "未选择任何镜像"
        return
    fi
    
    echo
    ok "已选择 ${#selected_images[@]} 个镜像"
    echo
    
    current=0
    for img in "${selected_images[@]}"; do
        ((current++))
        echo "[$current/${#selected_images[@]}]"
        download_and_import_image "$img" "$arch" "$IMAGES_BASE_URL"
        echo
    done
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
    
    info "获取最新版本..."
    latest_tag=$(curl -s https://api.github.com/repos/xkatld/lxdapi-web-server/releases/latest | grep '"tag_name"' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
    
    if [ -z "$latest_tag" ]; then
        err "无法获取最新版本信息"
    fi
    
    ok "最新版本: $latest_tag"
    
    download_url="https://github.com/xkatld/lxdapi-web-server/releases/download/${latest_tag}/lxdapi-linux-${arch}.tar.gz"
    
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
    
    reading "请输入服务端口 [8848]：" server_port
    server_port=${server_port:-8848}
    
    reading "请输入API密钥 [随机生成]：" api_hash
    if [ -z "$api_hash" ]; then
        api_hash=$(openssl rand -hex 16)
        ok "API密钥已生成: $api_hash"
    fi
    
    reading "请输入流量采集间隔秒数 [20]：" traffic_interval
    traffic_interval=${traffic_interval:-20}
    
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
    print_step "1" "5" "初始化环境"
    set_locale
    install_base_packages
    ok "环境初始化完成"

    print_step "2" "5" "安装 LXD"
    install_lxd

    print_step "3" "5" "配置存储资源"
    configure_resources
    setup_storage
    ok "存储配置完成"

    print_step "4" "5" "导入容器镜像"
    import_container_images
    ok "镜像导入完成"

    print_step "5" "5" "部署 lxdapi"
    deploy_lxdapi
    configure_lxdapi
    setup_lxdapi_service
    ok "lxdapi 部署完成"

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
    
    info "===== 3. 镜像配置 ====="
    lxc image list
    echo
    
    info "===== 4. 后端配置 ====="
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
