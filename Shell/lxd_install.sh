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

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; exit 1; }

reading() { read -rp "$(echo -e "${GREEN}$1${NC}")" "$2"; }

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
            systemctl restart apparmor
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
    
    if dpkg -l lxcfs 2>/dev/null | grep -q "^ii"; then
        warn "检测到 deb 版 lxcfs，正在移除..."
        systemctl stop lxcfs 2>/dev/null || true
        systemctl disable lxcfs 2>/dev/null || true
        apt-get remove -y lxcfs >/dev/null 2>&1
        ok "deb 版 lxcfs 已移除"
    fi
    
    lxd_version=$(lxd --version 2>/dev/null)
    info "LXD 版本: $lxd_version"
    if [[ ! "$lxd_version" =~ ^6\. ]]; then
        warn "当前 LXD 版本 $lxd_version 不兼容，推荐使用 6.x 版本"
        reading "是否继续？(y/n) [y]：" version_confirm
        version_confirm=${version_confirm:-y}
        if [[ ! "$version_confirm" =~ ^[yY]$ ]]; then
            err "已取消安装"
        fi
    else
        ok "LXD 版本兼容"
    fi
    
    info "配置 LXD..."
    snap set lxd lxcfs.flags="-l" 2>/dev/null
    snap set lxd daemon.debug=false 2>/dev/null
    snap restart lxd 2>/dev/null
    sleep 3
    ok "LXD 已配置"
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
                    bash <(curl -sL https://raw.githubusercontent.com/xkatld/lxdapi-web-server/refs/heads/v2.1.0-vpsm.link/Shell/debian_zfs.sh)
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

main() {
    echo
    echo "========================================"
    echo "        LXD 安装脚本"
    echo "        by Github-xkatld"
    echo "========================================"
    echo
    
    echo "======== 步骤 1/5: 检测系统 ========"
    info "系统: $SYSTEM $OS_VERSION"
    if [[ "$RECOMMENDED" == "true" ]]; then
        ok "系统版本符合推荐"
    else
        warn "建议使用 Debian 12/13 或 Ubuntu 24/25"
    fi
    
    if [[ "$SYSTEM" == "Debian" ]]; then
        echo
        warn "Debian 使用 ZFS 存储需要编译安装，耗时较长"
        warn "如需使用 ZFS，推荐使用 Ubuntu 系统"
        reading "是否继续使用 Debian？(y/n) [y]：" debian_confirm
        debian_confirm=${debian_confirm:-y}
        if [[ ! "$debian_confirm" =~ ^[yY]$ ]]; then
            info "已取消安装"
            exit 0
        fi
    fi
    echo
    
    echo "======== 步骤 2/5: 安装 LXD ========"
    reading "是否安装 LXD？(y/n) [y]：" step2_confirm
    step2_confirm=${step2_confirm:-y}
    if [[ "$step2_confirm" =~ ^[yY]$ ]]; then
        install_lxd
        ok "LXD 安装完成"
    else
        info "已跳过 LXD 安装"
    fi
    echo
    
    echo "======== 步骤 3/5: 网络配置 ========"
    reading "是否配置网络？(y/n) [y]：" step3_confirm
    step3_confirm=${step3_confirm:-y}
    if [[ "$step3_confirm" =~ ^[yY]$ ]]; then
        init_lxd_network
        reading "是否开启 IPv4 分配，分配NAT和独立IP需要开启 (y/n) [y]：" ipv4_dhcp
        ipv4_dhcp=${ipv4_dhcp:-y}
        if [[ ! "$ipv4_dhcp" =~ ^[yY]$ ]]; then
            /snap/bin/lxc network set lxdbr0 ipv4.dhcp false
            ok "IPv4 分配已关闭"
        else
            ok "IPv4 分配已开启"
        fi
        reading "是否开启 IPv6 分配，分配NAT和独立IP需要开启 (y/n) [y]：" ipv6_dhcp
        ipv6_dhcp=${ipv6_dhcp:-y}
        if [[ ! "$ipv6_dhcp" =~ ^[yY]$ ]]; then
            /snap/bin/lxc network set lxdbr0 ipv6.dhcp false
            /snap/bin/lxc network set lxdbr0 ipv6.address none
            ok "IPv6 分配已关闭"
        else
            ok "IPv6 分配已开启"
        fi
        ok "网络配置完成"
    else
        info "已跳过网络配置"
    fi
    echo
    
    echo "======== 步骤 4/5: 存储配置 ========"
    info "配置 default 存储池，首次安装推荐配置"
    reading "是否配置存储池？(y/n) [y]：" step4_confirm
    step4_confirm=${step4_confirm:-y}
    if [[ "$step4_confirm" =~ ^[yY]$ ]]; then
        setup_storage
        ok "存储配置完成"
    else
        info "已跳过存储配置"
    fi
    echo
    
    echo "======== 步骤 5/5: 完成 ========"
    echo
    echo "========================================"
    echo "        LXD 安装完成"
    echo "========================================"
    echo
    info "LXD 版本: $(lxd --version 2>/dev/null)"
    echo
    info "===== 网络配置 ====="
    lxc network list 2>/dev/null || warn "无法获取网络列表"
    echo
    info "===== 存储配置 ====="
    lxc storage list 2>/dev/null || warn "无法获取存储列表"
}

main
