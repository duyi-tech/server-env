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
    
    # 将公钥添加到 authorized_keys 以便其他机器可以通过公钥登录
    if [ ! -f "$ssh_dir/authorized_keys" ]; then
        log_info "创建 authorized_keys 文件..."
        cp "$public_key" "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown "$username:$username" "$ssh_dir/authorized_keys"
        log_info "authorized_keys 创建完成"
    else
        log_warn "authorized_keys 已存在，跳过复制"
    fi
    
    log_info "SSH 目录权限设置完成"
}

setup_docker_permissions() {
    local username="deploy"
    
    log_info "配置 Docker 权限..."
    
    # 检查 docker 组是否存在
    if getent group docker &>/dev/null; then
        log_info "docker 组已存在"
    else
        log_info "创建 docker 组..."
        groupadd docker
    fi
    
    # 将 deploy 用户添加到 docker 组
    if id -nG "$username" | grep -qw "docker"; then
        log_warn "用户 $username 已在 docker 组中"
    else
        log_info "将用户 $username 添加到 docker 组..."
        usermod -aG docker "$username"
        log_info "用户 $username 已添加到 docker 组"
    fi
    
    log_info "Docker 权限配置完成"
    log_warn "注意: 用户需要重新登录才能使 Docker 权限生效"
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
    setup_docker_permissions
    setup_products_dir
    
    log_info "deploy 用户配置完成"
    log_info "SSH 公钥位于: /home/deploy/.ssh/id_rsa.pub"
    log_info "authorized_keys 位于: /home/deploy/.ssh/authorized_keys"
    log_info "PRODUCTS_DIR: ${PRODUCTS_DIR:-/opt/products}"
    log_info "Docker 权限: deploy 用户已添加到 docker 组"
}

main
