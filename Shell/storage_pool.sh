#!/bin/bash
set -e
if ! command -v lxc >/dev/null 2>&1; then
    echo "错误：未检测到 lxc 命令，请关闭当前终端并重新打开，或者重新连接终端后，再次运行此脚本" >&2
    exit 1
fi

lxc() {
    command lxc "$@"
}

echo "==> LXD 存储池管理"
echo ""
echo "选择操作："
echo "[1] 创建存储池"
echo "[2] 删除存储池"
echo "[3] 列出存储池"
read -p "请选择 1-3，默认1: " action
action=${action:-1}

if [ "$action" = "3" ]; then
    echo ""
    echo "==> 存储池列表："
    lxc storage list
    exit 0
fi

if [ "$action" = "2" ]; then
    echo ""
    echo "现有存储池："
    lxc storage list
    echo ""
    read -p "输入要删除的存储池名称: " pool_name
    
    if [ -z "$pool_name" ]; then
        echo "错误：存储池名称不能为空"
        exit 1
    fi
    
    read -p "确认删除存储池 '$pool_name'？请确认输入 yes 或 no: " confirm
    if [ "$confirm" = "yes" ]; then
        echo "==> 删除存储池..."
        lxc storage delete "$pool_name"
        echo "==> 存储池已删除！"
    else
        echo "取消删除"
    fi
    exit 0
fi

echo "==> 选择存储驱动："
echo "[1] ZFS"
echo "[2] Btrfs"
read -p "请选择 1-2，默认1: " driver_choice
driver_choice=${driver_choice:-1}

if [ "$driver_choice" = "1" ]; then
    driver="zfs"
    echo "==> 检查 ZFS 支持..."
    if ! command -v zfs >/dev/null 2>&1; then
        os_id=""
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            os_id=`echo "$ID" | tr '[:upper:]' '[:lower:]'`
        fi

        if [ "$os_id" = "debian" ]; then
            echo "==> Debian: 启用 contrib 源..."
            if [ -f /etc/apt/sources.list.d/debian.sources ]; then
                if ! grep -q "contrib" /etc/apt/sources.list.d/debian.sources 2>/dev/null; then
                    sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
                fi
            else
                sed -i '/^deb/s/\bmain\b/main contrib non-free/g' /etc/apt/sources.list
            fi
            apt-get update >/dev/null 2>&1
            echo "==> Debian: 安装 ZFS..."
            current_kernel=`uname -r`
            apt-get install -y linux-headers-$current_kernel zfsutils-linux zfs-dkms || { echo "错误：ZFS 安装失败"; exit 1; }
            snap set lxd zfs.external=true 2>/dev/null || true
            snap restart lxd 2>/dev/null || true
        elif [ "$os_id" = "ubuntu" ]; then
            apt-get update >/dev/null 2>&1
            echo "==> Ubuntu: 安装 ZFS..."
            apt-get install -y zfsutils-linux || { echo "错误：ZFS 安装失败"; exit 1; }
            snap set lxd zfs.external=true 2>/dev/null || true
            snap restart lxd 2>/dev/null || true
        else
            echo "错误：当前系统不支持自动安装 ZFS: $os_id"
            exit 1
        fi
    fi
    echo "==> 启用 LXD 外部 ZFS 支持并重启服务..."
    snap set lxd zfs.external=true 2>/dev/null || true
    snap restart lxd 2>/dev/null || true
else
    driver="btrfs"
    echo "==> 检查 Btrfs 支持..."
    if ! command -v btrfs >/dev/null 2>&1; then
        echo "==> 安装 Btrfs..."
        apt-get install -y btrfs-progs || { echo "错误：Btrfs 安装失败"; exit 1; }
    fi
fi

echo "==> LXD 存储池配置"
echo ""

storage_list=$(lxc storage list -f csv)
if ! echo "$storage_list" | grep -q "default"; then
    default_name="default"
else
    i=1
    while echo "$storage_list" | grep -q "^pool$i,"; do
        i=$((i + 1))
        storage_list=$(lxc storage list -f csv)
    done
    default_name="pool$i"
fi

read -p "存储池名称 [$default_name]: " pool_name
pool_name=${pool_name:-$default_name}

echo ""
echo "选择存储方式："
echo "[1] 自动创建"
echo "[2] 使用独立磁盘"
storage_type=1
if [ -t 0 ]; then
    read -p "请选择 1-2，默认1: " storage_type_input
    storage_type=${storage_type_input:-1}
fi

if [ "$storage_type" = "2" ]; then
    echo ""
    echo "可用磁盘："
    lsblk -d -n -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -p "输入磁盘设备，例如 sdb: " device

    echo ""
    echo "==> 创建存储池..."
    lxc storage create "$pool_name" "$driver" source="/dev/$device" source.wipe=true
else
    available=`df /var/lib/lxd 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}'`
    if [ -z "$available" ]; then
        available=`df / 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}'`
    fi
    default_size=$((available - 5))
    if [ "$default_size" -lt 10 ]; then
        default_size=10
    fi
    
    read -p "存储池大小 GB [$default_size]: " size
    size=${size:-$default_size}
    
    echo ""
    echo "==> 创建存储池..."
    lxc storage create "$pool_name" "$driver" size="${size}GB"
fi

echo ""
echo "==> 存储池创建成功！"
lxc storage list
