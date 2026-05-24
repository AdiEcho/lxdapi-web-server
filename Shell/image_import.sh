#!/bin/bash
if ! command -v lxc >/dev/null 2>&1; then
    echo -e "\033[0;31m[ERROR]\033[0m 未检测到 lxc 命令，请关闭当前终端并重新打开，或者重新连接终端后，再次运行此脚本" >&2
    exit 1
fi

lxc() {
    command lxc "$@"
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LXC="lxc"

ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

reading() {
    read -rp "$(echo -e "${GREEN}[INPUT]${NC} $1")" "$2"
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

IMAGES_BASE_URL="https://github.com/xkatld/lxdapi-web-server/releases/download/image"

declare -a IMAGE_LIST=(
    "almalinux-8"
    "almalinux-9"
    "alpine-320"
    "alpine-321"
    "alpine-322"
    "archlinux-latest"
    "centos-9-Stream"
    "debian-11"
    "debian-12"
    "debian-13"
    "fedora-42"
    "fedora-43"
    "opensuse-156"
    "opensuse-tumbleweed"
    "rockylinux-8"
    "rockylinux-9"
    "ubuntu-2204"
    "ubuntu-2404"
)

download_and_import() {
    local image_name="$1"
    local image_type="$2"
    local image_url="${IMAGES_BASE_URL}/${image_name}-${ARCH}-${image_type}.tar.gz"
    
    info "下载: ${image_name}-${ARCH}-${image_type}.tar.gz"
    
    local temp_file=$(mktemp)
    if wget -q --show-progress -O "$temp_file" "$image_url" 2>&1; then
        info "导入到 LXD..."
        local alias="${image_name}-${image_type}"
        local import_err=$(mktemp)
        if $LXC image import "$temp_file" --alias "$alias" 2>"$import_err"; then
            ok "成功导入: $alias"
        else
            warn "导入失败: $alias"
            if [ -s "$import_err" ]; then
                err "详细报错信息："
                cat "$import_err" >&2
            fi
        fi
        rm -f "$temp_file"
        rm -f "$import_err"
    else
        warn "下载失败: ${image_name}-${ARCH}-${image_type}"
        rm -f "$temp_file"
    fi
}

show_image_list() {
    echo
    echo "============================================================================================================"
    echo " [1] almalinux-8       [2] almalinux-9      [3] alpine-320       [4] alpine-321       [5] alpine-322"
    echo " [6] archlinux-latest  [7] centos-9-Stream  [8] debian-11        [9] debian-12       [10] debian-13"
    echo "[11] fedora-42        [12] fedora-43       [13] opensuse-156    [14] opensuse-tumbleweed"
    echo "[15] rockylinux-8     [16] rockylinux-9    [17] ubuntu-2204     [18] ubuntu-2404"
    echo "============================================================================================================"
    echo
}

menu_import() {
    echo
    info "=== 导入镜像 ==="
    show_image_list
    
    reading "输入编号，多个用空格或逗号分隔，或输入 all 全部导入 [默认 8 9 17 18]：" image_choices
    image_choices=${image_choices:-"8 9 17 18"}
    
    local image_type="lxc"
    
    selected_images=()
    if [[ "$image_choices" == "all" ]]; then
        selected_images=("${IMAGE_LIST[@]}")
    else
        local cleaned_choices=$(echo "$image_choices" | tr -s ',; ' ' ')
        for choice in $cleaned_choices; do
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#IMAGE_LIST[@]} ]]; then
                    selected_images+=("${IMAGE_LIST[$idx]}")
                fi
            fi
        done
    fi
    
    if [[ ${#selected_images[@]} -eq 0 ]]; then
        warn "未选择任何镜像"
        return
    fi
    
    ok "已选择 ${#selected_images[@]} 个镜像"
    echo
    
    local current=0
    for img in "${selected_images[@]}"; do
        current=$((current + 1))
        echo "[$current/${#selected_images[@]}]"
        download_and_import "$img" "$image_type"
        echo
    done
}

menu_list() {
    echo
    info "=== 已有镜像 ==="
    $LXC image list
}

menu_delete() {
    echo
    info "=== 删除镜像 ==="
    $LXC image list
    echo
    reading "输入要删除的镜像别名或指纹：" image_id
    if [ -z "$image_id" ]; then
        return
    fi
    
    warn "确认删除镜像 $image_id？"
    reading "确认选择请输入 y，取消请输入 n，默认 n：" confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        if $LXC image delete "$image_id"; then
            ok "镜像已删除"
        else
            err "删除失败"
        fi
    else
        info "已取消删除"
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
        reading "请选择 [0-3]：" choice
        
        case "$choice" in
            1) menu_import ;;
            2) menu_list ;;
            3) menu_delete ;;
            0) ok "退出"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

detect_arch
main_menu
