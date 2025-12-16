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
    if command -v zfs &>/dev/null && command -v zpool &>/dev/null; then
        return 0
    fi
    return 1
}

install_zfs() {
    if check_zfs; then
        ok "ZFS 已安装"
        return 0
    fi
    
    detect_system
    
    if [[ "$SYSTEM" == "debian" ]]; then
        warn "Debian 系统需要编译安装 ZFS，预计耗时 10-30 分钟"
        reading "是否继续？(y/n) [n]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            info "已取消"
            return 1
        fi
        info "开始编译安装 ZFS..."
        if ! bash <(curl -sL https://raw.githubusercontent.com/xkatld/lxdapi-web-server/refs/heads/v2.0.0-main/build_zfs_on_debian.sh); then
            err "ZFS 编译安装失败"
            return 1
        fi
    else
        info "安装 ZFS..."
        install_package zfs-dkms
        install_package zfsutils-linux
    fi
    
    info "配置 LXD 使用系统 ZFS..."
    snap set lxd zfs.external=true 2>/dev/null
    snap restart lxd 2>/dev/null
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

install_package() {
    local pkg="$1"
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        info "安装 $pkg..."
        apt-get update -qq
        apt-get install -y "$pkg" -qq
    fi
}

list_disks() {
    info "可用磁盘列表："
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "disk|NAME"
    echo
    info "可用分区列表："
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "part|NAME"
}

create_sparse_file() {
    local file="$1"
    local size_gb="$2"
    truncate -s "${size_gb}G" "$file"
    return $?
}

create_lvm_loop() {
    local storage_path="$1"
    local size_gb="$2"
    local pool_name="$3"
    local loop_file="$storage_path/${pool_name}_lvm.img"
    
    mkdir -p "$storage_path"
    
    if [ -f "$loop_file" ]; then
        warn "检测到旧文件，正在清理..."
        losetup -d $(losetup -j "$loop_file" | cut -d: -f1) 2>/dev/null || true
        rm -f "$loop_file"
    fi
    
    ok "创建稀疏文件 ${size_gb}GB..."
    if ! create_sparse_file "$loop_file" "$size_gb"; then
        err "创建文件失败"
        return 1
    fi
    
    install_package lvm2
    
    ok "创建 LVM 存储池..."
    if lxc storage create "$pool_name" lvm source="$loop_file"; then
        echo "$loop_file" > "$storage_path/${pool_name}_loop.txt"
        ok "LVM 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        rm -f "$loop_file"
        return 1
    fi
}

create_zfs_loop() {
    local storage_path="$1"
    local size_gb="$2"
    local pool_name="$3"
    local loop_file="$storage_path/${pool_name}_zfs.img"
    local zpool_name="${pool_name}_zpool"
    
    if ! install_zfs; then
        return 1
    fi
    
    mkdir -p "$storage_path"
    
    if zpool list "$zpool_name" &>/dev/null; then
        warn "检测到旧 ZFS 池，正在清理..."
        zpool destroy "$zpool_name" 2>/dev/null || true
    fi
    
    if [ -f "$loop_file" ]; then
        rm -f "$loop_file"
    fi
    
    ok "创建稀疏文件 ${size_gb}GB..."
    if ! dd if=/dev/zero of="$loop_file" bs=1G count=0 seek="$size_gb" 2>/dev/null; then
        err "创建文件失败"
        return 1
    fi
    
    local loop_dev=$(losetup -f --show "$loop_file")
    if [ -z "$loop_dev" ]; then
        err "创建 loop 设备失败"
        return 1
    fi
    
    ok "创建 ZFS 池..."
    if ! zpool create -f "$zpool_name" "$loop_dev"; then
        err "创建 ZFS 池失败"
        losetup -d "$loop_dev"
        rm -f "$loop_file"
        return 1
    fi
    
    echo "$loop_file" > "$storage_path/${pool_name}_loop.txt"
    echo "$loop_dev" > "$storage_path/${pool_name}_loopdev.txt"
    
    ok "创建 LXD 存储池..."
    if lxc storage create "$pool_name" zfs source="$zpool_name"; then
        ok "ZFS 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        zpool destroy "$zpool_name"
        losetup -d "$loop_dev"
        rm -f "$loop_file"
        return 1
    fi
}

create_btrfs_loop() {
    local storage_path="$1"
    local size_gb="$2"
    local pool_name="$3"
    local loop_file="$storage_path/${pool_name}_btrfs.img"
    
    mkdir -p "$storage_path"
    
    if [ -f "$loop_file" ]; then
        warn "检测到旧文件，正在清理..."
        losetup -d $(losetup -j "$loop_file" | cut -d: -f1) 2>/dev/null || true
        rm -f "$loop_file"
    fi
    
    ok "创建稀疏文件 ${size_gb}GB..."
    if ! create_sparse_file "$loop_file" "$size_gb"; then
        err "创建文件失败"
        return 1
    fi
    
    install_package btrfs-progs
    
    ok "创建 Btrfs 存储池..."
    if lxc storage create "$pool_name" btrfs source="$loop_file"; then
        echo "$loop_file" > "$storage_path/${pool_name}_loop.txt"
        ok "Btrfs 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        rm -f "$loop_file"
        return 1
    fi
}

create_lvm_disk() {
    local device="$1"
    local pool_name="$2"
    
    if [ ! -b "$device" ]; then
        err "设备 $device 不存在"
        return 1
    fi
    
    install_package lvm2
    
    ok "创建 LVM 存储池..."
    if lxc storage create "$pool_name" lvm source="$device"; then
        ok "LVM 存储池 $pool_name 创建成功"
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
    
    if [ ! -b "$device" ]; then
        err "设备 $device 不存在"
        return 1
    fi
    
    if ! install_zfs; then
        return 1
    fi
    
    ok "创建 ZFS 池..."
    if ! zpool create -f "$zpool_name" "$device"; then
        err "创建 ZFS 池失败"
        return 1
    fi
    
    ok "创建 LXD 存储池..."
    if lxc storage create "$pool_name" zfs source="$zpool_name"; then
        ok "ZFS 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        zpool destroy "$zpool_name"
        return 1
    fi
}

create_btrfs_disk() {
    local device="$1"
    local pool_name="$2"
    
    if [ ! -b "$device" ]; then
        err "设备 $device 不存在"
        return 1
    fi
    
    install_package btrfs-progs
    
    ok "格式化为 Btrfs..."
    if ! mkfs.btrfs -f "$device"; then
        err "格式化失败"
        return 1
    fi
    
    ok "创建 Btrfs 存储池..."
    if lxc storage create "$pool_name" btrfs source="$device"; then
        ok "Btrfs 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        return 1
    fi
}

create_dir_pool() {
    local dir_path="$1"
    local pool_name="$2"
    
    mkdir -p "$dir_path"
    
    ok "创建目录存储池..."
    if lxc storage create "$pool_name" dir source="$dir_path"; then
        ok "目录存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        return 1
    fi
}

delete_storage_pool() {
    local pool_name="$1"
    
    if ! lxc storage show "$pool_name" &>/dev/null; then
        err "存储池 $pool_name 不存在"
        return 1
    fi
    
    local used_by=$(lxc storage show "$pool_name" | grep -c "used_by" || echo "0")
    if [ "$used_by" -gt 1 ]; then
        warn "存储池正在被使用，无法删除"
        lxc storage show "$pool_name" | grep -A 100 "used_by:"
        return 1
    fi
    
    if lxc storage delete "$pool_name"; then
        ok "存储池 $pool_name 已删除"
        return 0
    else
        err "删除失败"
        return 1
    fi
}

menu_loop_file() {
    echo
    info "=== 稀疏文件方式 ==="
    echo "1. LVM"
    echo "2. ZFS"
    echo "3. Btrfs"
    echo "0. 返回"
    echo
    reading "请选择 [0-3]: " choice
    
    case "$choice" in
        1|2|3)
            reading "存储池名称 [pool1]: " pool_name
            pool_name=${pool_name:-pool1}
            
            reading "存储路径 [/opt/lxd-pools]: " storage_path
            storage_path=${storage_path:-/opt/lxd-pools}
            
            reading "存储大小 GB [50]: " size_gb
            size_gb=${size_gb:-50}
            
            case "$choice" in
                1) create_lvm_loop "$storage_path" "$size_gb" "$pool_name" ;;
                2) create_zfs_loop "$storage_path" "$size_gb" "$pool_name" ;;
                3) create_btrfs_loop "$storage_path" "$size_gb" "$pool_name" ;;
            esac
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
}

create_native_auto() {
    local backend="$1"
    local pool_name="$2"
    local size_gb="$3"
    
    if [[ "$backend" == "zfs" ]]; then
        if ! install_zfs; then
            return 1
        fi
    fi
    
    ok "创建 $backend 存储池..."
    if lxc storage create "$pool_name" "$backend" size="${size_gb}GiB"; then
        ok "$backend 存储池 $pool_name 创建成功"
        return 0
    else
        err "创建失败"
        return 1
    fi
}

menu_native() {
    echo
    info "=== LXD 自动管理 ==="
    echo "1. LVM"
    echo "2. ZFS"
    echo "3. Btrfs"
    echo "4. 目录"
    echo "0. 返回"
    echo
    reading "请选择 [0-4]: " choice
    
    case "$choice" in
        1|2|3)
            reading "存储池名称 [pool1]: " pool_name
            pool_name=${pool_name:-pool1}
            
            reading "存储大小 GB [50]: " size_gb
            size_gb=${size_gb:-50}
            
            case "$choice" in
                1) create_native_auto "lvm" "$pool_name" "$size_gb" ;;
                2) create_native_auto "zfs" "$pool_name" "$size_gb" ;;
                3) create_native_auto "btrfs" "$pool_name" "$size_gb" ;;
            esac
            ;;
        4)
            reading "存储池名称 [pool1]: " pool_name
            pool_name=${pool_name:-pool1}
            
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
    info "=== 指定磁盘/分区 ==="
    list_disks
    echo "1. LVM"
    echo "2. ZFS"
    echo "3. Btrfs"
    echo "0. 返回"
    echo
    reading "请选择 [0-3]: " choice
    
    case "$choice" in
        1|2|3)
            reading "存储池名称 [pool1]: " pool_name
            pool_name=${pool_name:-pool1}
            
            reading "设备路径: " device
            if [ -z "$device" ]; then
                warn "设备路径不能为空"
                return
            fi
            
            warn "将使用 $device 创建存储池，数据将被清除！"
            reading "确认继续？(y/n) [n]: " confirm
            if [[ ! "$confirm" =~ ^[yY]$ ]]; then
                info "已取消"
                return
            fi
            
            case "$choice" in
                1) create_lvm_disk "$device" "$pool_name" ;;
                2) create_zfs_disk "$device" "$pool_name" ;;
                3) create_btrfs_disk "$device" "$pool_name" ;;
            esac
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
}

menu_list() {
    echo
    info "=== 存储池列表 ==="
    lxc storage list
}

menu_delete() {
    echo
    info "=== 删除存储池 ==="
    lxc storage list
    echo
    reading "输入要删除的存储池名称: " pool_name
    if [ -z "$pool_name" ]; then
        return
    fi
    
    warn "确认删除存储池 $pool_name？"
    reading "确认？(y/n) [n]: " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        delete_storage_pool "$pool_name"
    else
        info "已取消"
    fi
}

main_menu() {
    while true; do
        echo
        echo "================================"
        echo "    LXD 存储池管理脚本"
        echo "    LXDAPI by Github-xkatld"
        echo "================================"
        echo "1. 自定义路径 + 稀疏文件"
        echo "2. LXD 自动管理"
        echo "3. 指定磁盘/分区"
        echo "4. 查看存储池"
        echo "5. 删除存储池"
        echo "0. 退出"
        echo "================================"
        reading "请选择 [0-5]: " choice
        
        case "$choice" in
            1) menu_loop_file ;;
            2) menu_native ;;
            3) menu_disk ;;
            4) menu_list ;;
            5) menu_delete ;;
            0) ok "退出"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

check_root
check_lxd
main_menu
