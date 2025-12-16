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

detect_arch() {
    sys_arch=$(uname -m)
    case $sys_arch in
        x86_64) 
            ARCH="amd64"
            ;;
        aarch64|arm64) 
            ARCH="arm64"
            ;;
        *) 
            err "不支持的架构: $sys_arch"
            exit 1
            ;;
    esac
    ok "系统架构: $ARCH"
}

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

download_and_import() {
    local image_name="$1"
    local image_url="${IMAGES_BASE_URL}/${image_name}-${ARCH}.tar.gz"
    
    info "下载: ${image_name}-${ARCH}.tar.gz"
    
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

show_image_list() {
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
}

menu_import() {
    echo
    info "=== 导入镜像 ==="
    show_image_list
    
    reading "输入编号，多个用逗号分隔，或 all 全部导入 [2,5,13,26]: " image_choices
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
    
    ok "已选择 ${#selected_images[@]} 个镜像"
    echo
    
    current=0
    for img in "${selected_images[@]}"; do
        ((current++))
        echo "[$current/${#selected_images[@]}]"
        download_and_import "$img"
        echo
    done
}

menu_list() {
    echo
    info "=== 已有镜像 ==="
    lxc image list
}

menu_delete() {
    echo
    info "=== 删除镜像 ==="
    lxc image list
    echo
    reading "输入要删除的镜像别名或指纹: " image_id
    if [ -z "$image_id" ]; then
        return
    fi
    
    warn "确认删除镜像 $image_id？"
    reading "确认？(y/n) [n]: " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        if lxc image delete "$image_id"; then
            ok "镜像已删除"
        else
            err "删除失败"
        fi
    else
        info "已取消"
    fi
}

main_menu() {
    while true; do
        echo
        echo "================================"
        echo "      LXD 镜像管理脚本"
        echo "    LXDAPI by Github-xkatld"
        echo "================================"
        echo "1. 导入镜像"
        echo "2. 查看已有镜像"
        echo "3. 删除镜像"
        echo "0. 退出"
        echo "================================"
        reading "请选择 [0-3]: " choice
        
        case "$choice" in
            1) menu_import ;;
            2) menu_list ;;
            3) menu_delete ;;
            0) ok "退出"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

check_root
check_lxd
detect_arch
main_menu
