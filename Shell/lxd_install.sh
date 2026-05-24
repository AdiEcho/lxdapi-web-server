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
    apt-get update >/dev/null 2>&1
    info "正在安装 snapd 服务..."
    apt-get install -y snapd
    
    info "正在升级 snapd 自身组件..."
    snap install snapd 2>/dev/null || snap install snapd
    
    info "正在检查并就绪 snap core 组件..."
    if ! snap list core >/dev/null 2>&1; then
        snap install core 2>/dev/null || snap install core
    fi
    
    info "开始安装 LXD..."
    snap install lxd --channel=latest/stable 2>/dev/null || snap install lxd --channel=latest/stable
    
    snap alias lxd.lxc lxc 2>/dev/null
    snap alias lxd.lxd lxd 2>/dev/null
    if [ ! -f /etc/profile.d/snap.sh ]; then
        echo 'export PATH=$PATH:/snap/bin' > /etc/profile.d/snap.sh
    fi
    export PATH=$PATH:/snap/bin
    
    if ! command -v lxc >/dev/null 2>&1; then
        err 'lxc 路径有问题，请检查 snap alias'
    fi
    
    lxd_lxc_detect=$(lxc list 2>/dev/null)
    if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]; then
        systemctl restart apparmor
        snap restart lxd
    fi
    
    ok "LXD 安装完成"
    
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
    info "初始化 LXD 网络..."
    reading "是否启用 IPv4？输入 y 或 n，默认 y：" enable_ipv4
    enable_ipv4=${enable_ipv4:-y}
    reading "是否启用 IPv6？输入 y 或 n，默认 y：" enable_ipv6
    enable_ipv6=${enable_ipv6:-y}
    ipv4_config="none"
    ipv6_config="none"
    ipv4_nat="false"
    ipv6_nat="false"
    if [[ "$enable_ipv4" =~ ^[yY]$ ]]; then
        ipv4_config="10.66.0.1/16"
        ipv4_nat="true"
    fi
    if [[ "$enable_ipv6" =~ ^[yY]$ ]]; then
        ipv6_config="fd66:6666::1/64"
        ipv6_nat="true"
    fi
    cat <<EOF | lxd init --preseed
config:
  images.auto_update_interval: "0"
networks:
- config:
    ipv4.address: $ipv4_config
    ipv4.nat: "$ipv4_nat"
    ipv6.address: $ipv6_config
    ipv6.nat: "$ipv6_nat"
  description: ""
  name: lxdbr0
  type: bridge
storage_pools: []
storage_volumes: []
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
  name: default
projects: []
cluster: null
EOF
    ok "LXD 网络初始化完成"
}

main() {
    echo
    echo "========================================"
    echo "        LXD 安装脚本"
    echo "        by Github-xkatld"
    echo "========================================"
    echo
    
    echo "======== 步骤 1/3: 检测系统 ========"
    info "系统: $SYSTEM $OS_VERSION"
    ok "系统检测通过"
    echo
    
    echo "======== 步骤 2/3: 安装 LXD ========"
    reading "是否安装 LXD？输入 y 或 n，默认 y：" step2_confirm
    step2_confirm=${step2_confirm:-y}
    if [[ "$step2_confirm" =~ ^[yY]$ ]]; then
        install_lxd
        ok "LXD 安装完成"
    else
        info "已跳过 LXD 安装"
    fi
    echo
    
    echo "======== 步骤 3/3: 配置网络 ========"
    reading "是否配置 LXD 默认网络？输入 y 或 n，默认 y：" step3_confirm
    step3_confirm=${step3_confirm:-y}
    if [[ "$step3_confirm" =~ ^[yY]$ ]]; then
        init_lxd_network
    else
        info "已跳过网络配置"
    fi
    echo
    
    echo "======== 安装完成 ========"
    echo
    echo "========================================"
    echo "        LXD 安装完成"
    echo "========================================"
    echo
    info "LXD 版本: $(lxd --version 2>/dev/null)"
    echo
    info "===== 网络配置 ====="
    lxc network list 2>/dev/null || warn "无法获取网络列表"
}

main
