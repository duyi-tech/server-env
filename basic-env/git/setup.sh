#!/bin/bash

# 该脚本仅支持 Alibaba Cloud Linux 3.2104

set -e

# 1. 检查Git是否已安装，已安装则直接退出
if command -v git &> /dev/null; then
    echo "Git 已存在，当前版本：$(git --version)"
    exit 0
fi

# 2. 未安装则执行安装（阿里云Linux 3用dnf/yum均可，优先dnf）
echo "Git 未安装，开始安装..."
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用root权限运行（如 sudo ./install_git.sh）"
    exit 1
fi

# 阿里云Linux 3的官方源安装Git
dnf install git -y

# 3. 验证安装结果
echo "Git 安装完成，当前版本：$(git --version)"