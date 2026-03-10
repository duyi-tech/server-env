#!/bin/bash

# 该脚本仅支持 Alibaba Cloud Linux 3.2104
# Docker: 26.1.3

# 检查是否已安装 Docker
if command -v docker &> /dev/null; then
    echo "Docker 已安装，跳过安装步骤"
    docker --version
    exit 0
fi

# 安装并配置仓库
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo sed -i 's/$releasever/8/g' /etc/yum.repos.d/docker-ce.repo

# 安装 Docker
sudo yum clean all && sudo yum makecache
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动服务
sudo systemctl start docker && sudo systemctl enable docker