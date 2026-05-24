#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_msg() {
    echo -e "$1"
}

log_ok() {
    log_msg "${GREEN}[OK]${NC} $1"
}

log_info() {
    log_msg "${BLUE}[INFO]${NC} $1" 
}

log_warn() {
    log_msg "${YELLOW}[WARN]${NC} $1"
}

log_err() {
    log_msg "${RED}[ERR]${NC} $1"
    exit 1
}

check_system() {
    log_info "正在检测系统版本与架构"
    
    local sys_pretty_name=`grep -i pretty_name /etc/os-release 2>/dev/null | cut -d "\"" -f2`
    sys_pretty_name=`echo "$sys_pretty_name" | tr '[:upper:]' '[:lower:]'`
    
    SYSTEM=""
    if [[ "$sys_pretty_name" =~ "debian" ]]; then
        SYSTEM="Debian"
    elif [[ "$sys_pretty_name" =~ "ubuntu" ]]; then
        SYSTEM="Ubuntu"
    fi
    
    if [ -z "$SYSTEM" ]; then
        log_err "此脚本仅支持 Debian 和 Ubuntu 系统"
    fi
    
    SYS_ARCH=`uname -m`
    if [[ "$SYS_ARCH" != "x86_64" && "$SYS_ARCH" != "aarch64" && "$SYS_ARCH" != "arm64" ]]; then
        log_err "不支持的架构: $SYS_ARCH"
    fi
    
    log_ok "系统检测通过: $SYSTEM $SYS_ARCH"
}

check_and_update_kernel() {
    log_info "正在检测内核版本"
    
    local current_kernel=`uname -r`
    log_info "当前内核版本: $current_kernel"
    
    if [ "$SYSTEM" != "Debian" ]; then
        log_err "该内核更新策略仅支持 Debian 系统"
    fi
    
    local debian_ver=`grep VERSION_ID /etc/os-release | cut -d'"' -f2`
    local sys_arch=`dpkg --print-architecture`
    
    local expected_keep=""
    if [ "$sys_arch" = "arm64" ] && [ "$debian_ver" = "11" ]; then
        expected_keep="5.10.0-43-arm64"
    elif [ "$sys_arch" = "amd64" ] && [ "$debian_ver" = "11" ]; then
        expected_keep="5.10.0-43-amd64"
    elif [ "$sys_arch" = "arm64" ] && [ "$debian_ver" = "12" ]; then
        expected_keep="6.1.0-48-arm64"
    elif [ "$sys_arch" = "amd64" ] && [ "$debian_ver" = "12" ]; then
        expected_keep="6.1.0-48-amd64"
    elif [ "$sys_arch" = "arm64" ] && [ "$debian_ver" = "13" ]; then
        expected_keep="6.12.88+deb13-arm64"
    elif [ "$sys_arch" = "amd64" ] && [ "$debian_ver" = "13" ]; then
        expected_keep="6.12.88+deb13-amd64"
    elif [ "$sys_arch" = "amd64" ] && [ "$debian_ver" = "13" ]; then
        expected_keep="6.12.90+deb13-amd64"
    else
        log_err "不支持的组合: $sys_arch / Debian $debian_ver"
    fi
    
    if [[ "$current_kernel" =~ "$expected_keep" ]]; then
        log_ok "内核检测通过，当前已运行匹配的 ZFS 内核版本"
        return 0
    fi
    
    log_warn "当前内核不匹配，未通过内核检测"
    read -rp "是否确认安装并更新系统内核为 $expected_keep ？[y/n]: " confirm_install
    confirm_install=${confirm_install:-n}
    
    if [[ ! "$confirm_install" =~ ^[yY]$ ]]; then
        log_err "内核更新已取消，安装终止"
    fi
    
    log_info "开始更新系统内核"
    
    if [ "$debian_ver" = "13" ]; then
        if [ ! -f /etc/apt/sources.list.d/sid.list ]; then
            echo "deb http://ftp.de.debian.org/debian sid main contrib" > /etc/apt/sources.list.d/sid.list
        fi
    fi
    
    apt-get update
    
    local img_pkg="linux-image-$expected_keep"
    local headers_pkg="linux-headers-$expected_keep"
    
    if apt-get install -y "$img_pkg" "$headers_pkg"; then
        if ls /boot/vmlinuz-*$expected_keep* >/dev/null 2>&1; then
            log_info "正在清理旧内核文件"
            find /boot -maxdepth 1 -type f -name "vmlinuz-*" ! -name "*$expected_keep*" -delete
            find /boot -maxdepth 1 -type f -name "initrd.img-*" ! -name "*$expected_keep*" -delete
            find /boot -maxdepth 1 -type f -name "System.map-*" ! -name "*$expected_keep*" -delete
            find /boot -maxdepth 1 -type f -name "config-*" ! -name "*$expected_keep*" -delete
            
            update-grub
            log_ok "内核已更新为 $sys_arch 版本的 $expected_keep"
            log_warn "请手动执行 reboot 重启系统，重启后请重新运行该脚本"
            exit 0
        else
            log_err "内核文件未在 boot 目录中找到，操作已拦截"
        fi
    else
        log_err "内核包获取失败或安装未成功，操作已拦截"
    fi
}

install_zfs() {
    log_info "开始安装匹配版本的 ZFS"
    
    local current_kernel=`uname -r`
    local sys_arch=`dpkg --print-architecture`
    
    local modules_file=""
    if [ "$sys_arch" = "amd64" ]; then
        if [[ "$current_kernel" =~ "5.10.0-43-amd64" ]]; then
            modules_file="zfs-modules-amd64-5.10.0-43-amd64-zfs2.1.15.tgz"
        elif [[ "$current_kernel" =~ "6.1.0-48-amd64" ]]; then
            modules_file="zfs-modules-amd64-6.1.0-48-amd64-zfs2.2.7.tgz"
        elif [[ "$current_kernel" =~ "6.12.88+deb13-amd64" ]]; then
            modules_file="zfs-modules-amd64-6.12.88+deb13-amd64-zfs2.3.0.tgz"
        elif [[ "$current_kernel" =~ "6.12.90+deb13-amd64" ]]; then
            modules_file="zfs-modules-amd64-6.12.90+deb13-amd64-zfs2.3.0.tgz"
        else
            log_err "当前内核版本未在支持的 ZFS 预编译模块列表中: $current_kernel"
        fi
    elif [ "$sys_arch" = "arm64" ]; then
        if [[ "$current_kernel" =~ "5.10.0-43-arm64" ]]; then
            modules_file="zfs-modules-arm64-5.10.0-43-arm64-zfs2.1.15.tgz"
        elif [[ "$current_kernel" =~ "6.1.0-48-arm64" ]]; then
            modules_file="zfs-modules-arm64-6.1.0-48-arm64-zfs2.2.7.tgz"
        elif [[ "$current_kernel" =~ "6.12.88+deb13-arm64" ]]; then
            modules_file="zfs-modules-arm64-6.12.88+deb13-arm64-zfs2.3.0.tgz"
        else
            log_err "当前内核版本未在支持的 ZFS 预编译模块列表中: $current_kernel"
        fi
    else
        log_err "不支持的架构: $sys_arch"
    fi
    
    local download_base="https://github.com/xkatld/lxdapi-web-server/releases/download/zfs"
    
    log_info "正在从 GitHub 官方源下载匹配的 ZFS 模块文件"
    cd /tmp
    if ! wget -q --show-progress -O "$modules_file" "$download_base/$modules_file"; then
        log_err "ZFS 模块下载失败"
    fi
    
    log_info "正在解压并部署 ZFS 模块"
    mkdir -p /lib/modules/$current_kernel/updates/dkms/
    tar -xzf "$modules_file"
    cp zfs-modules/*.ko.xz /lib/modules/$current_kernel/updates/dkms/
    
    log_info "正在更新模块依赖并加载"
    depmod -a $current_kernel
    modprobe spl
    modprobe zfs
    
    if ! lsmod | grep -q zfs; then
        log_err "ZFS 模块加载失败"
    fi
    
    log_info "正在安装 ZFS 用户态工具"
    apt-get install -y zfsutils-linux --no-install-recommends
    
    log_info "正在清理临时安装文件"
    rm -f "/tmp/$modules_file"
    rm -rf /tmp/zfs-modules
    
    log_ok "ZFS 模块及工具安装部署完成"
}

view_zfs_status() {
    log_info "正在获取 ZFS 运行状态与版本信息"
    
    log_info "===== ZFS 工具与模块版本 ====="
    zfs --version
    
    log_info "===== ZFS 存储池状态 ====="
    zpool status
}

main() {
    log_msg "========================================"
    log_msg "        LXDAPI ZFS 自动安装脚本"
    log_msg "========================================"
    
    check_system
    check_and_update_kernel
    install_zfs
    view_zfs_status
    
    log_msg "========================================"
    log_msg "        ZFS 安装流程已全部完成"
    log_msg "========================================"
}

main
