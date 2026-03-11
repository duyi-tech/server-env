#!/bin/bash

# 该脚本仅支持 Alibaba Cloud Linux 3.2104
# Docker: 26.1.3

# 检查是否已安装 Docker
if command -v docker &> /dev/null; then
    echo "Docker 已存在，当前版本：$(docker --version)"
    echo "跳过安装，继续配置..."
else
    # 安装并配置仓库
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    sudo sed -i 's/$releasever/8/g' /etc/yum.repos.d/docker-ce.repo

    # 安装 Docker
    sudo yum clean all && sudo yum makecache
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 启动服务
    sudo systemctl start docker && sudo systemctl enable docker
fi

# 确保 Docker 服务正在运行
if ! systemctl is-active --quiet docker; then
    echo "启动 Docker 服务..."
    sudo systemctl start docker
fi

# 配置 Docker 镜像加速（每次必做）
echo "配置 Docker 镜像加速..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "registry-mirrors": [
    "https://m.daocloud.io",
    "https://docker.aityp.com",
    "https://docker.1ms.run/"
  ]
}
EOF

# 重启 Docker 服务（每次必做）
echo "重启 Docker 服务..."
sudo systemctl restart docker

echo "Docker 配置完成"
