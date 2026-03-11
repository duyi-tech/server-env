#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ -f "${PROJECT_ROOT}/.env" ]; then
    export $(cat "${PROJECT_ROOT}/.env" | grep -v '^#' | xargs)
fi

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_linux() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本只能在 Linux 系统上运行"
        log_error "当前系统: $OSTYPE"
        exit 1
    fi
    log_info "系统检查通过: Linux"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

setup_deploy_user() {
    local username="deploy"
    local home_dir="/home/$username"
    
    if id "$username" &>/dev/null; then
        log_warn "用户 $username 已存在，跳过创建"
    else
        log_info "创建用户: $username"
        useradd -m -s /bin/bash "$username"
        log_info "用户 $username 创建成功"
    fi
    
    local ssh_dir="$home_dir/.ssh"
    local private_key="$ssh_dir/id_rsa"
    local public_key="$ssh_dir/id_rsa.pub"
    
    if [ ! -d "$ssh_dir" ]; then
        log_info "创建 SSH 目录: $ssh_dir"
        mkdir -p "$ssh_dir"
    fi
    
    if [ -f "$private_key" ] && [ -f "$public_key" ]; then
        log_warn "SSH 密钥对已存在，跳过生成"
        log_info "公钥路径: $public_key"
    else
        log_info "生成 SSH 密钥对..."
        ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "deploy@$(hostname)"
        log_info "SSH 密钥对生成成功"
        log_info "私钥: $private_key"
        log_info "公钥: $public_key"
    fi
    
    chown -R "$username:$username" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$private_key"
    chmod 644 "$public_key"
    log_info "SSH 目录权限设置完成"
}

setup_products_dir() {
    local username="deploy"
    local products_dir="${PRODUCTS_DIR:-/opt/products}"
    
    if [ ! -d "$products_dir" ]; then
        log_info "创建目录: $products_dir"
        mkdir -p "$products_dir"
    else
        log_info "目录已存在: $products_dir"
    fi
    
    log_info "设置 $products_dir 的所有者为 $username"
    chown -R "$username:$username" "$products_dir"
    chmod 755 "$products_dir"
    log_info "权限设置完成"
}

main() {
    log_info "开始配置 deploy 用户..."
    
    check_linux
    check_root
    setup_deploy_user
    setup_products_dir
    
    log_info "deploy 用户配置完成"
    log_info "SSH 公钥位于: /home/deploy/.ssh/id_rsa.pub"
    log_info "PRODUCTS_DIR: ${PRODUCTS_DIR:-/opt/products}"
}

main
