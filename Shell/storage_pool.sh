#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

reading() {
    read -rp "$(echo -e "${GREEN}[INPUT]${NC} $1")" "$2"
}

detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM="$ID"
    else
        SYSTEM="unknown"
    fi
}

check_zfs() {
    command -v zfs &>/dev/null && command -v zpool &>/dev/null
}

install_zfs() {
    if check_zfs; then
        ok "ZFS 已安装"
        info "配置 LXD 使用系统 ZFS..."
        snap set lxd zfs.external=true
        snap restart lxd
        sleep 3
        return 0
    fi
    
    detect_system
    
    if [[ "$SYSTEM" == "debian" ]]; then
        warn "Debian 系统需要编译安装 ZFS，预计耗时 10-30 分钟"
        reading "是否继续？(y/n) [n]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            return 1
        fi
        info "开始编译安装 ZFS..."
        bash <(curl -sL https://raw.githubusercontent.com/xkatld/lxdapi-web-server/refs/heads/v2.1.0-vpsm.link/Shell/debian_zfs.sh) || return 1
    else
        info "安装 ZFS..."
        apt-get update -qq && apt-get install -y zfsutils-linux -qq
    fi
    
    info "配置 LXD 使用系统 ZFS..."
    snap set lxd zfs.external=true
    snap restart lxd
    sleep 3
    
    ok "ZFS 安装完成"
    return 0
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "请使用 root 用户运行此脚本"
        exit 1
    fi
}

check_lxd() {
    if ! command -v lxc &>/dev/null; then
        err "未检测到 LXD，请先安装 LXD"
        exit 1
    fi
}

get_available_space() {
    df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}'
}

get_available_pool_name() {
    local i=1
    while lxc storage show "pool${i}" &>/dev/null; do
        ((i++))
    done
    echo "pool${i}"
}

install_package() {
    local pkg="$1"
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        info "安装 $pkg..."
        apt-get update -qq && apt-get install -y "$pkg" -qq
    fi
}

list_disks() {
    info "可用块设备 (>10GB)："
    echo
    lsblk -d -n -o NAME,SIZE,TYPE | while read name size type; do
        if [[ "$type" == "disk" ]]; then
            size_num=$(echo "$size" | sed 's/[^0-9.]//g')
            size_unit=$(echo "$size" | sed 's/[0-9.]//g')
            case "$size_unit" in
                T) size_gb=$(echo "$size_num * 1024" | bc 2>/dev/null || echo "1000") ;;
                G) size_gb=$size_num ;;
                *) size_gb=0 ;;
            esac
            if (( $(echo "$size_gb > 10" | bc -l 2>/dev/null || echo 0) )); then
                echo "  /dev/$name  ($size)"
            fi
        fi
    done
    echo
}

create_native_auto() {
    local backend="$1"
    local pool_name="$2"
    local size_gb="$3"
    
    case "$backend" in
        zfs) install_zfs || return 1 ;;
        btrfs) install_package btrfs-progs ;;
        lvm) install_package lvm2 ;;
    esac
    
    ok "创建 $backend 存储池..."
    if lxc storage create "$pool_name" "$backend" size="${size_gb}GiB"; then
        ok "$backend 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        return 1
    fi
}

create_zfs_disk() {
    local device="$1"
    local pool_name="$2"
    local zpool_name="${pool_name}_zpool"
    
    [ ! -b "$device" ] && { err "设备 $device 不存在"; return 1; }
    install_zfs || return 1
    
    ok "创建 ZFS 池..."
    zpool create -f "$zpool_name" "$device" || { err "创建 ZFS 池失败"; return 1; }
    
    ok "创建 LXD 存储池..."
    if lxc storage create "$pool_name" zfs source="$zpool_name"; then
        ok "ZFS 存储池 $pool_name 创建成功"
        return 0
    else
        zpool destroy "$zpool_name"
        return 1
    fi
}

create_btrfs_disk() {
    local device="$1"
    local pool_name="$2"
    
    [ ! -b "$device" ] && { err "设备 $device 不存在"; return 1; }
    install_package btrfs-progs
    
    ok "格式化为 Btrfs..."
    mkfs.btrfs -f "$device" || { err "格式化失败"; return 1; }
    
    if lxc storage create "$pool_name" btrfs source="$device"; then
        ok "Btrfs 存储池 $pool_name 创建成功"
        return 0
    fi
    return 1
}

create_lvm_disk() {
    local device="$1"
    local pool_name="$2"
    
    [ ! -b "$device" ] && { err "设备 $device 不存在"; return 1; }
    install_package lvm2
    
    if lxc storage create "$pool_name" lvm source="$device"; then
        ok "LVM 存储池 $pool_name 创建成功"
        return 0
    fi
    return 1
}

create_dir_pool() {
    local dir_path="$1"
    local pool_name="$2"
    
    mkdir -p "$dir_path"
    if lxc storage create "$pool_name" dir source="$dir_path"; then
        ok "目录存储池 $pool_name 创建成功"
        return 0
    fi
    return 1
}

delete_storage_pool() {
    local pool_name="$1"
    
    lxc storage show "$pool_name" &>/dev/null || { err "存储池 $pool_name 不存在"; return 1; }
    
    if lxc storage delete "$pool_name"; then
        ok "存储池 $pool_name 已删除"
        return 0
    fi
    return 1
}

menu_native() {
    echo
    info "=== Loop 设备 (自动创建) ==="
    echo "1. ZFS"
    echo "2. Btrfs"
    echo "3. LVM"
    echo "4. Dir (目录)"
    echo "0. 返回"
    echo
    reading "请选择 [0-4]: " choice
    
    local default_pool=$(get_available_pool_name)
    local default_size=$(get_available_space)
    
    case "$choice" in
        1|2|3)
            info "当前可用磁盘空间: ${default_size}GB"
            reading "存储池名称 [$default_pool]: " pool_name
            pool_name=${pool_name:-$default_pool}
            reading "存储大小 GB [$default_size]: " size_gb
            size_gb=${size_gb:-$default_size}
            
            case "$choice" in
                1) create_native_auto "zfs" "$pool_name" "$size_gb" ;;
                2) create_native_auto "btrfs" "$pool_name" "$size_gb" ;;
                3) create_native_auto "lvm" "$pool_name" "$size_gb" ;;
            esac
            ;;
        4)
            reading "存储池名称 [$default_pool]: " pool_name
            pool_name=${pool_name:-$default_pool}
            reading "目录路径 [/opt/lxd-dir]: " dir_path
            dir_path=${dir_path:-/opt/lxd-dir}
            create_dir_pool "$dir_path" "$pool_name"
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
}

menu_disk() {
    echo
    info "=== 块设备 (磁盘/分区) ==="
    list_disks
    echo "1. ZFS"
    echo "2. Btrfs"
    echo "3. LVM"
    echo "0. 返回"
    echo
    reading "请选择 [0-3]: " choice
    
    local default_pool=$(get_available_pool_name)
    
    case "$choice" in
        1|2|3)
            reading "存储池名称 [$default_pool]: " pool_name
            pool_name=${pool_name:-$default_pool}
            reading "设备路径: " device
            [ -z "$device" ] && { warn "设备路径不能为空"; return; }
            
            warn "将使用 $device 创建存储池，数据将被清除！"
            reading "确认继续？(y/n) [n]: " confirm
            [[ ! "$confirm" =~ ^[yY]$ ]] && { info "已取消"; return; }
            
            case "$choice" in
                1) create_zfs_disk "$device" "$pool_name" ;;
                2) create_btrfs_disk "$device" "$pool_name" ;;
                3) create_lvm_disk "$device" "$pool_name" ;;
            esac
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
}

menu_delete() {
    echo
    info "=== 删除存储池 ==="
    lxc storage list
    echo
    reading "输入要删除的存储池名称: " pool_name
    [ -z "$pool_name" ] && return
    
    warn "确认删除存储池 $pool_name？"
    reading "确认？(y/n) [n]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] && delete_storage_pool "$pool_name" || info "已取消"
}

main_menu() {
    while true; do
        echo
        echo "================================"
        echo "    LXD 存储池管理脚本"
        echo "    LXDAPI by Github-xkatld"
        echo "================================"
        echo "1. Loop 设备 (自动创建)"
        echo "2. 块设备 (磁盘/分区)"
        echo "3. 查看存储池"
        echo "4. 删除存储池"
        echo "0. 退出"
        echo "================================"
        reading "请选择 [0-4]: " choice
        
        case "$choice" in
            1) menu_native ;;
            2) menu_disk ;;
            3) echo; lxc storage list ;;
            4) menu_delete ;;
            0) ok "退出"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

check_root
check_lxd
install_package bc
main_menu
